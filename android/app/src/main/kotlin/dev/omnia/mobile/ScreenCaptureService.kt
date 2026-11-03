package dev.omnia.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager

// Le service qui tient la capture d'écran.
//
// Android exige qu'une projection d'écran vive dans un service de premier
// plan, avec une notification visible : c'est une garantie pour l'utilisateur,
// qui doit toujours savoir que son écran est partagé. Depuis Android 14, le
// service doit en outre déclarer explicitement ce type.
class ScreenCaptureService : Service() {

    companion object {
        const val ACTION_START = "dev.omnia.mobile.SCREEN_START"
        const val ACTION_STOP = "dev.omnia.mobile.SCREEN_STOP"

        private const val CHANNEL_ID = "omnia_screen"
        private const val NOTIFICATION_ID = 4201

        // Assez pour un écran de téléphone lisible, assez peu pour tenir sur
        // un réseau local sans saturer un encodeur d'entrée de gamme.
        private const val BIT_RATE = 4_000_000

        fun start(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, ScreenCaptureService::class.java).setAction(ACTION_STOP)
            )
        }
    }

    private var projection: MediaProjection? = null
    private var encoder: ScreenEncoder? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopCapture()
            stopSelf()
            return START_NOT_STICKY
        }

        // La notification d'abord : le système tue un service de premier plan
        // qui tarde à en montrer une.
        startForeground(NOTIFICATION_ID, buildNotification())

        if (!beginCapture()) {
            stopCapture()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun beginCapture(): Boolean {
        val data = ScreenCaptureBridge.consentData ?: return false
        return try {
            val manager =
                getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val media = manager.getMediaProjection(ScreenCaptureBridge.consentResult, data)
                ?: return false
            projection = media

            // L'utilisateur peut révoquer le partage depuis la notification du
            // système : il faut alors s'arrêter proprement, et le dire.
            media.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    stopCapture()
                    stopSelf()
                }
            }, null)

            val metrics = screenMetrics()
            val encode = ScreenEncoder(
                width = metrics.first,
                height = metrics.second,
                density = metrics.third,
                bitRate = BIT_RATE,
                onChunk = { bytes, header ->
                    ScreenCaptureBridge.onChunk?.invoke(bytes, header)
                }
            )
            encoder = encode
            encode.start(media)
        } catch (e: Throwable) {
            Log.w("OMNIA", "Capture d'ecran impossible : " + e)
            false
        }
    }

    // Les dimensions de l'écran, ramenées à des nombres pairs : un encodeur
    // H.264 refuse souvent une largeur ou une hauteur impaire.
    private fun screenMetrics(): Triple<Int, Int, Int> {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(Context.WINDOW_SERVICE) as WindowManager)
            .defaultDisplay.getRealMetrics(metrics)
        val width = (metrics.widthPixels / 2) * 2
        val height = (metrics.heightPixels / 2) * 2
        return Triple(width, height, metrics.densityDpi)
    }

    private fun stopCapture() {
        encoder?.stop()
        encoder = null
        try {
            projection?.stop()
        } catch (e: Throwable) {
            Log.w("OMNIA", "Arret de la projection : " + e)
        }
        projection = null
        ScreenCaptureBridge.onStopped?.invoke()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Partage d'ecran",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Indique qu'OMNIA partage l'ecran de cet appareil."
            manager?.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("OMNIA partage votre ecran")
            .setContentText("Le partage s'arrete en fermant la projection.")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .build()
    }
}
