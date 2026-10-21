package dev.omnia.mobile

import android.annotation.SuppressLint
import android.content.Context
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
import android.widget.LinearLayout
import android.widget.TextView

// Une fenêtre flottante posée au-dessus des autres applications.
//
// C'est le seul mini-lecteur possible sur un appareil dépourvu d'image dans
// l'image : cette fonction d'Android est optionnelle, et manque sur beaucoup
// de téléphones d'entrée de gamme. La vidéo y sera dessinée par le moteur,
// qui visera la surface de cette fenêtre au lieu de celle de Flutter.
//
// Tout ce qui s'affiche ici est construit en code, sans fichier de mise en
// page ni ressource graphique : une fenêtre superposée vit hors de l'activité,
// et moins elle dépend du reste, moins elle peut casser.
class FloatingPlayerWindow(private val context: Context) {

    interface Listener {
        // La surface est prête : le moteur peut y dessiner.
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

    val isShowing: Boolean
        get() = root != null

    @SuppressLint("ClickableViewAccessibility")
    fun show(widthPx: Int, heightPx: Int, listener: Listener): Boolean {
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
        container.addView(
            video,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

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
            false
        }
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

    private fun buildButton(label: String, onClick: () -> Unit): TextView {
        val button = TextView(context)
        button.text = label
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
