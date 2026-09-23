package dev.omnia.mobile

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val PIP_CHANNEL = "dev.omnia.mobile/pip"
    private val INTENT_CHANNEL = "dev.omnia.mobile/intent"

    private var initialFilePath: String? = null
    private var intentMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = handleIntent(intent)
        if (path != null) {
            intentMethodChannel?.invokeMethod("onFileOpened", path)
        }
    }

    private fun handleIntent(intent: Intent?): String? {
        if (intent == null) return null
        val action = intent.action
        val data: Uri? = intent.data

        if ((Intent.ACTION_VIEW == action || Intent.ACTION_EDIT == action || Intent.ACTION_SEND == action) && data != null) {
            val resolvedPath = resolveUriToPath(data)
            if (resolvedPath != null) {
                initialFilePath = resolvedPath
                return resolvedPath
            }
        }
        return null
    }

    private fun resolveUriToPath(uri: Uri): String? {
        val scheme = uri.scheme
        if (scheme == null || scheme == "file") {
            return uri.path
        }
        if (scheme == "content") {
            try {
                var fileName = "opened_file"
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1) {
                            val name = cursor.getString(nameIndex)
                            if (!name.isNullOrBlank()) {
                                fileName = name
                            }
                        }
                    }
                }

                val cacheFolder = File(cacheDir, "opened_media")
                if (!cacheFolder.exists()) {
                    cacheFolder.mkdirs()
                }
                val outputFile = File(cacheFolder, fileName)

                contentResolver.openInputStream(uri)?.use { inputStream ->
                    FileOutputStream(outputFile).use { outputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }

                return outputFile.absolutePath
            } catch (e: Exception) {
                Log.e("OMNIA", "Failed to resolve content URI: $uri", e)
                return uri.path
            }
        }
        return uri.toString()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Configuration PiP
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).setMethodCallHandler { call, result ->
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

        // Configuration Intent "Ouvrir avec"
        intentMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        val path = initialFilePath
                        initialFilePath = null
                        result.success(path)
                    }
                    else -> result.notImplemented()
                }
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
            MethodChannel(it, PIP_CHANNEL).invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        }
    }
}
