package dev.omnia.mobile

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "dev.omnia.mobile/pip"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    val width = call.argument<Int>("aspectRatioWidth") ?: 16
                    val height = call.argument<Int>("aspectRatioHeight") ?: 9
                    val success = enterPipMode(width, height)
                    result.success(success)
                }
                "isPipSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    result.success(supported)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPipMode(width: Int, height: Int): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val clampedWidth = width.coerceIn(1, 1000)
                val clampedHeight = height.coerceIn(1, 1000)
                val rational = Rational(clampedWidth, clampedHeight)
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(rational)
                    .build()
                return enterPictureInPictureMode(params)
            } catch (e: Exception) {
                try {
                    @Suppress("DEPRECATION")
                    enterPictureInPictureMode()
                    return true
                } catch (e2: Exception) {
                    return false
                }
            }
        }
        return false
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, CHANNEL).invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        }
    }
}
