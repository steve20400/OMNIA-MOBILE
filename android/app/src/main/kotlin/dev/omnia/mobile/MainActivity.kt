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
import android.webkit.MimeTypeMap
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
        val uri = getUriFromIntent(intent) ?: return null
        val resolvedPath = resolveUriToPath(uri, intent)
        if (resolvedPath != null) {
            initialFilePath = resolvedPath
            return resolvedPath
        }
        return null
    }

    private fun getUriFromIntent(intent: Intent): Uri? {
        // 1. Données directes de l'intent
        if (intent.data != null) return intent.data

        // 2. ClipData (utilisé par de nombreux gestionnaires de fichiers et applications de partage)
        val clipData = intent.clipData
        if (clipData != null && clipData.itemCount > 0) {
            val itemUri = clipData.getItemAt(0)?.uri
            if (itemUri != null) return itemUri
        }

        // 3. Extra stream (ACTION_SEND / partages)
        val extraStream = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
        if (extraStream != null) return extraStream

        return null
    }

    private fun resolveUriToPath(uri: Uri, intent: Intent): String? {
        val scheme = uri.scheme

        // Cas d'un chemin de fichier direct
        if (scheme == null || scheme == "file") {
            val decodedPath = Uri.decode(uri.path ?: "")
            if (decodedPath.isNotEmpty()) {
                val f = File(decodedPath)
                if (f.exists() && f.canRead()) {
                    return f.absolutePath
                }
            }
        }

        // Schéma "content" ou fichier nécessitant une copie en cache pour accès garanti
        try {
            var fileName = "opened_file"
            var extension = ""

            // 1. Détection du type MIME pour garantir l'extension exacte
            val mimeType = try {
                contentResolver.getType(uri) ?: intent.type
            } catch (_: Exception) {
                intent.type
            }

            if (!mimeType.isNullOrBlank()) {
                val mappedExt = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
                if (!mappedExt.isNullOrBlank()) {
                    extension = mappedExt.lowercase()
                } else if (mimeType.startsWith("image/")) {
                    val sub = mimeType.substringAfter("image/").lowercase()
                    extension = if (sub == "jpeg") "jpg" else sub
                } else if (mimeType.startsWith("video/")) {
                    extension = "mp4"
                } else if (mimeType.startsWith("audio/")) {
                    extension = "mp3"
                } else if (mimeType == "application/pdf") {
                    extension = "pdf"
                }
            }

            // 2. Extraction du nom d'origine
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
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
            } catch (e: Exception) {
                Log.w("OMNIA", "Could not query display name for $uri: ${e.message}")
            }

            // 3. S'assurer de la présence d'une extension valide pour OMNIA
            val dotIndex = fileName.lastIndexOf('.')
            if (dotIndex == -1 || fileName.substring(dotIndex + 1).length > 5) {
                if (extension.isNotEmpty()) {
                    fileName = "$fileName.$extension"
                } else {
                    // Fallback intelligent selon le type d'intent
                    if (intent.type?.startsWith("image/") == true) {
                        fileName = "$fileName.jpg"
                    } else if (intent.type?.startsWith("video/") == true) {
                        fileName = "$fileName.mp4"
                    } else if (intent.type?.startsWith("audio/") == true) {
                        fileName = "$fileName.mp3"
                    } else {
                        fileName = "$fileName.jpg"
                    }
                }
            }

            val cacheFolder = File(cacheDir, "opened_media")
            if (!cacheFolder.exists()) {
                cacheFolder.mkdirs()
            }

            // Nom de fichier assaini
            val cleanName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val outputFile = File(cacheFolder, "${System.currentTimeMillis()}_$cleanName")

            val inputStream = contentResolver.openInputStream(uri)
            if (inputStream != null) {
                inputStream.use { input ->
                    FileOutputStream(outputFile).use { output ->
                        input.copyTo(output)
                    }
                }
                if (outputFile.exists() && outputFile.length() > 0) {
                    return outputFile.absolutePath
                }
            }
        } catch (e: Exception) {
            Log.e("OMNIA", "Failed to resolve content URI: $uri", e)
        }

        return uri.path
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
