package dev.omnia.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

// Une fenêtre flottante posée au-dessus des autres applications.
//
// C'est le seul mini-lecteur possible sur un appareil dépourvu d'image dans
// l'image : cette fonction d'Android est optionnelle, et manque sur beaucoup
// de téléphones d'entrée de gamme.
//
// Elle sait montrer deux choses, et c'est la raison d'être de [Mode]. Une
// vidéo se dessine dans une surface que le moteur vise directement. Tout le
// reste — une image, une page de document, un titre de musique — n'a jamais
// rien à voir avec ce moteur : Flutter le dessine de son côté, et la surface
// resterait désespérément noire. Ces contenus arrivent en image fixe.
//
// Tout ce qui s'affiche ici est construit en code, sans fichier de mise en
// page ni ressource : une fenêtre superposée vit hors de l'activité, et moins
// elle dépend du reste, moins elle peut casser.
class FloatingPlayerWindow(private val context: Context) {

    companion object {
        const val MODE_VIDEO = "video"
        const val MODE_STILL = "still"

        // Au-delà, le doigt déplace la fenêtre ; en deçà, il la touche.
        private const val TAP_SLOP = 12f

        // Les commandes s'effacent seules : une fenêtre de cette taille est
        // d'abord là pour montrer l'image, pas des boutons.
        private const val CONTROLS_DELAY = 2600L

        // Maintenir avant de glisser déplace la fenêtre ; glisser tout de
        // suite fait défiler le document. Sans cette distinction, l'un des
        // deux gestes serait impossible sur un document.
        private const val HOLD_TO_MOVE = 400L
    }

    interface Listener {
        // La surface est prête : le moteur peut y dessiner. Mode vidéo seul.
        fun onSurfaceReady(surface: Surface, width: Int, height: Int)

        // La fenêtre disparaît : le moteur doit cesser d'y dessiner.
        fun onSurfaceLost()

        // L'utilisateur veut revenir dans l'application.
        fun onExpandRequested()

        // L'utilisateur ferme le mini-lecteur.
        fun onCloseRequested()

        // Un toucher sur l'image : lecture ou pause, décidé côté Dart par le
        // bus de commandes — la fenêtre ne connaît pas l'état de la lecture.
        fun onTapped()

        // Un glissement vertical sur un document : il faut le faire défiler.
        fun onScrolled(dy: Float)
    }

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())

    private var root: FrameLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var listener: Listener? = null
    private var still: ImageView? = null
    private var label: TextView? = null
    private var controls: View? = null
    private var lockButton: TextView? = null
    private var progress: View? = null
    private var progressTrack: FrameLayout? = null

    // Verrouillée, la fenêtre ne répond plus au toucher : ni lecture, ni
    // pause, ni déplacement involontaire pendant qu'on regarde.
    private var locked = false

    // Vrai pour un document : le glissement y fait défiler au lieu de déplacer.
    private var scrollable = false

    // Effacement des commandes, nommé pour pouvoir l'annuler seul : annuler
    // tout annulerait aussi l'attente du maintien.
    private val hideControls = Runnable { controls?.visibility = View.GONE }

    // La surface vivante de la fenêtre, et sa taille.
    //
    // Gardées pour pouvoir reposer la redirection vidéo : quand l'activité
    // passe en arrière-plan, Flutter détruit sa propre surface et le moteur
    // remet sa sortie à zéro, ce qui efface la nôtre.
    private var videoSurface: Surface? = null
    var widthPx: Int = 0
        private set
    var heightPx: Int = 0
        private set

    fun currentVideoSurface(): Surface? = videoSurface

    val isShowing: Boolean
        get() = root != null

    @SuppressLint("ClickableViewAccessibility")
    fun show(
        widthPx: Int,
        heightPx: Int,
        mode: String,
        scrollable: Boolean,
        listener: Listener
    ): Boolean {
        if (isShowing) return true
        this.listener = listener
        this.widthPx = widthPx
        this.heightPx = heightPx
        this.scrollable = scrollable
        locked = false

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val lp = WindowManager.LayoutParams(
            widthPx,
            heightPx,
            layoutType,
            // Non focalisable : la fenêtre ne prend pas le clavier à
            // l'application du dessous, mais reçoit quand même les touchers.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = 32
        lp.y = 160
        params = lp

        val container = FrameLayout(context)
        container.setBackgroundColor(Color.BLACK)

        val fill = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )

        // La surface vidéo n'existe qu'en mode vidéo : la créer en mode image
        // reviendrait à offrir au moteur une surface qu'il ne remplira pas.
        if (mode == MODE_VIDEO) {
            val video = SurfaceView(context)
            video.holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) {
                    videoSurface = holder.surface
                    this@FloatingPlayerWindow.listener?.onSurfaceReady(
                        holder.surface,
                        this@FloatingPlayerWindow.widthPx,
                        this@FloatingPlayerWindow.heightPx
                    )
                }

                override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
                    videoSurface = holder.surface
                    this@FloatingPlayerWindow.widthPx = w
                    this@FloatingPlayerWindow.heightPx = h
                    this@FloatingPlayerWindow.listener?.onSurfaceReady(holder.surface, w, h)
                }

                override fun surfaceDestroyed(holder: SurfaceHolder) {
                    videoSurface = null
                    this@FloatingPlayerWindow.listener?.onSurfaceLost()
                }
            })
            container.addView(video, fill)
        } else {
            val image = ImageView(context)
            image.scaleType = ImageView.ScaleType.FIT_CENTER
            container.addView(image, fill)
            still = image

            val text = TextView(context)
            text.setTextColor(Color.WHITE)
            text.textSize = 13f
            text.gravity = Gravity.CENTER
            text.maxLines = 3
            val pad = (10 * density()).toInt()
            text.setPadding(pad, pad, pad, pad)
            container.addView(
                text,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER
                )
            )
            label = text
        }

        val row = buildControls()
        container.addView(
            row,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.END
            )
        )
        controls = row

        container.addView(buildProgress())

        attachTouch(container, lp)

        return try {
            windowManager.addView(container, lp)
            root = container
            scheduleHideControls()
            true
        } catch (e: Exception) {
            // Autorisation révoquée entre-temps, ou constructeur récalcitrant :
            // l'appelant doit pouvoir le dire à l'utilisateur.
            Log.w("OMNIA", "Fenetre flottante refusee : " + e)
            this.listener = null
            params = null
            still = null
            label = null
            controls = null
            false
        }
    }

    // Affiche une image lue sur le disque : c'est le cas d'une photo ouverte
    // dans l'application, dont le chemin est connu.
    fun setImagePath(path: String): Boolean {
        val view = still ?: return false
        return try {
            val bitmap = BitmapFactory.decodeFile(path) ?: return false
            view.setImageBitmap(bitmap)
            label?.text = ""
            true
        } catch (e: Throwable) {
            Log.w("OMNIA", "Image flottante illisible : " + e)
            false
        }
    }

    // Affiche une image fournie par Flutter : c'est le cas d'une page de
    // document, que seule l'application sait dessiner.
    fun setImageBytes(bytes: ByteArray): Boolean {
        val view = still ?: return false
        return try {
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return false
            view.setImageBitmap(bitmap)
            label?.text = ""
            true
        } catch (e: Throwable) {
            Log.w("OMNIA", "Image flottante illisible : " + e)
            false
        }
    }

    // Un titre, quand il n'y a rien à montrer : une musique n'a pas d'image.
    fun setLabel(text: String) {
        label?.text = text
    }

    // L'avancement de la lecture, de 0 à 1. Hors de cet intervalle, la barre
    // disparaît : une image ou un document n'ont pas de durée.
    fun setProgress(fraction: Double) {
        val track = progressTrack ?: return
        val bar = progress ?: return
        if (fraction < 0) {
            track.visibility = View.GONE
            return
        }
        track.visibility = View.VISIBLE
        val width = (widthPx * fraction.coerceIn(0.0, 1.0)).toInt()
        val lp = bar.layoutParams
        lp.width = width
        bar.layoutParams = lp
    }

    fun hide() {
        handler.removeCallbacksAndMessages(null)
        scrollable = false
        val current = root ?: return
        try {
            windowManager.removeView(current)
        } catch (e: Exception) {
            Log.w("OMNIA", "Retrait de la fenetre flottante : " + e)
        }
        root = null
        params = null
        listener = null
        still = null
        label = null
        controls = null
        lockButton = null
        progress = null
        progressTrack = null
        videoSurface = null
    }

    fun resize(widthPx: Int, heightPx: Int) {
        val current = root ?: return
        val lp = params ?: return
        lp.width = widthPx
        lp.height = heightPx
        this.widthPx = widthPx
        this.heightPx = heightPx
        try {
            windowManager.updateViewLayout(current, lp)
        } catch (e: Exception) {
            Log.w("OMNIA", "Redimensionnement de la fenetre flottante : " + e)
        }
    }

    private fun density(): Float = context.resources.displayMetrics.density

    // Trois commandes : revenir à l'application, verrouiller, fermer. Elles
    // s'effacent d'elles-mêmes et reviennent au premier toucher.
    private fun buildControls(): View {
        val row = LinearLayout(context)
        row.orientation = LinearLayout.HORIZONTAL
        row.setBackgroundColor(Color.argb(150, 0, 0, 0))
        row.addView(buildButton("⤢") { listener?.onExpandRequested() })
        val lock = buildButton("⚿") { toggleLock() }
        row.addView(lock)
        lockButton = lock
        row.addView(buildButton("✕") { listener?.onCloseRequested() })
        return row
    }

    private fun buildProgress(): View {
        val track = FrameLayout(context)
        track.setBackgroundColor(Color.argb(90, 255, 255, 255))
        val bar = View(context)
        bar.setBackgroundColor(Color.rgb(0xF2, 0xB4, 0x41))
        track.addView(
            bar,
            FrameLayout.LayoutParams(0, FrameLayout.LayoutParams.MATCH_PARENT)
        )
        progress = bar
        progressTrack = track
        track.visibility = View.GONE
        track.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            (3 * density()).toInt(),
            Gravity.BOTTOM
        )
        return track
    }

    private fun buildButton(text: String, onClick: () -> Unit): TextView {
        val button = TextView(context)
        button.text = text
        button.setTextColor(Color.WHITE)
        button.textSize = 16f
        button.gravity = Gravity.CENTER
        val pad = (12 * density()).toInt()
        button.setPadding(pad, pad, pad, pad)
        button.setOnClickListener {
            onClick()
            showControls()
        }
        return button
    }

    private fun toggleLock() {
        locked = !locked
        // Le verrou se lit à la couleur : le même glyphe teinté d'ambre, pour
        // ne dépendre d'aucune police exotique sur un téléphone d'entrée de
        // gamme — certaines n'ont tout simplement pas le cadenas ouvert.
        lockButton?.setTextColor(
            if (locked) Color.rgb(0xF2, 0xB4, 0x41) else Color.WHITE
        )
    }

    private fun showControls() {
        controls?.visibility = View.VISIBLE
        scheduleHideControls()
    }

    private fun scheduleHideControls() {
        handler.removeCallbacks(hideControls)
        handler.postDelayed(hideControls, CONTROLS_DELAY)
    }

    // Un seul écouteur pour le déplacement et le toucher : séparer les deux
    // ferait se disputer deux gestionnaires pour la même pression.
    //
    // Au-delà d'un court déplacement, le doigt déplace la fenêtre — sans quoi
    // elle finirait toujours par masquer ce qu'on voulait voir. En deçà, c'est
    // un toucher : il réveille les commandes et bascule lecture ou pause.
    @SuppressLint("ClickableViewAccessibility")
    private fun attachTouch(view: View, lp: WindowManager.LayoutParams) {
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var lastY = 0f
        var moved = false
        // Sur un document, le glissement fait défiler ; il ne déplace la
        // fenêtre qu'après un maintien. Ailleurs, il n'y a rien à faire
        // défiler, et le déplacement est immédiat.
        var moveMode = !scrollable
        val startMove = Runnable { moveMode = true }

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x
                    startY = lp.y
                    touchX = event.rawX
                    touchY = event.rawY
                    lastY = event.rawY
                    moved = false
                    moveMode = !scrollable
                    if (scrollable) handler.postDelayed(startMove, HOLD_TO_MOVE)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (locked) return@setOnTouchListener true
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (!moved && kotlin.math.hypot(dx, dy) < TAP_SLOP) {
                        return@setOnTouchListener true
                    }
                    if (!moved) {
                        moved = true
                        // Le doigt est parti avant la fin du maintien : c'est
                        // un défilement, la fenêtre ne doit pas suivre.
                        if (scrollable && !moveMode) handler.removeCallbacks(startMove)
                    }
                    if (moveMode) {
                        lp.x = startX + dx.toInt()
                        lp.y = startY + dy.toInt()
                        try {
                            windowManager.updateViewLayout(view, lp)
                        } catch (e: Exception) {
                            Log.w("OMNIA", "Deplacement de la fenetre flottante : " + e)
                        }
                    } else {
                        // Le delta depuis la dernière image, et non depuis le
                        // départ : le document suivrait sinon par bonds.
                        listener?.onScrolled(lastY - event.rawY)
                    }
                    lastY = event.rawY
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(startMove)
                    if (!moved) {
                        showControls()
                        // Verrouillée, la fenêtre se contente de montrer ses
                        // commandes : c'est à cela que sert le verrou.
                        if (!locked) listener?.onTapped()
                    }
                    true
                }
                else -> false
            }
        }
    }
}
