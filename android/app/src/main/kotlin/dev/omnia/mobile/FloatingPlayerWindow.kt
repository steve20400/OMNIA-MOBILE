package dev.omnia.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
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
// restait donc désespérément noire. Ces contenus arrivent maintenant sous
// forme d'image fixe ou de texte.
//
// Tout ce qui s'affiche ici est construit en code, sans fichier de mise en
// page ni ressource : une fenêtre superposée vit hors de l'activité, et moins
// elle dépend du reste, moins elle peut casser.
class FloatingPlayerWindow(private val context: Context) {

    companion object {
        const val MODE_VIDEO = "video"
        const val MODE_STILL = "still"
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
    }

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private var root: FrameLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var listener: Listener? = null
    private var still: ImageView? = null
    private var label: TextView? = null

    val isShowing: Boolean
        get() = root != null

    @SuppressLint("ClickableViewAccessibility")
    fun show(widthPx: Int, heightPx: Int, mode: String, listener: Listener): Boolean {
        if (isShowing) return true
        this.listener = listener

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
                    this@FloatingPlayerWindow.listener?.onSurfaceReady(
                        holder.surface,
                        widthPx,
                        heightPx
                    )
                }

                override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
                    this@FloatingPlayerWindow.listener?.onSurfaceReady(holder.surface, w, h)
                }

                override fun surfaceDestroyed(holder: SurfaceHolder) {
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
            val pad = (10 * context.resources.displayMetrics.density).toInt()
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

        container.addView(
            buildControls(),
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.END
            )
        )

        attachDrag(container, lp)

        return try {
            windowManager.addView(container, lp)
            root = container
            true
        } catch (e: Exception) {
            // Autorisation révoquée entre-temps, ou constructeur récalcitrant :
            // l'appelant doit pouvoir le dire à l'utilisateur.
            Log.w("OMNIA", "Fenetre flottante refusee : " + e)
            this.listener = null
            params = null
            still = null
            label = null
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

    fun hide() {
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
    }

    fun resize(widthPx: Int, heightPx: Int) {
        val current = root ?: return
        val lp = params ?: return
        lp.width = widthPx
        lp.height = heightPx
        try {
            windowManager.updateViewLayout(current, lp)
        } catch (e: Exception) {
            Log.w("OMNIA", "Redimensionnement de la fenetre flottante : " + e)
        }
    }

    // Deux commandes seulement : revenir à l'application, et fermer. Une
    // fenêtre de cette taille ne supporte pas davantage sans devenir illisible.
    private fun buildControls(): View {
        val row = LinearLayout(context)
        row.orientation = LinearLayout.HORIZONTAL
        row.setBackgroundColor(Color.argb(140, 0, 0, 0))
        row.addView(buildButton("⤢") { listener?.onExpandRequested() })
        row.addView(buildButton("✕") { listener?.onCloseRequested() })
        return row
    }

    private fun buildButton(text: String, onClick: () -> Unit): TextView {
        val button = TextView(context)
        button.text = text
        button.setTextColor(Color.WHITE)
        button.textSize = 16f
        button.gravity = Gravity.CENTER
        val pad = (12 * context.resources.displayMetrics.density).toInt()
        button.setPadding(pad, pad, pad, pad)
        button.setOnClickListener { onClick() }
        return button
    }

    // Déplacement au doigt : une fenêtre flottante qui ne se déplace pas finit
    // toujours par masquer ce qu'on voulait voir.
    @SuppressLint("ClickableViewAccessibility")
    private fun attachDrag(view: View, lp: WindowManager.LayoutParams) {
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x
                    startY = lp.y
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = startX + (event.rawX - touchX).toInt()
                    lp.y = startY + (event.rawY - touchY).toInt()
                    try {
                        windowManager.updateViewLayout(view, lp)
                    } catch (e: Exception) {
                        Log.w("OMNIA", "Deplacement de la fenetre flottante : " + e)
                    }
                    true
                }
                else -> false
            }
        }
    }
}
