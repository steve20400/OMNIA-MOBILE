package dev.omnia.mobile

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val PIP_CHANNEL = "dev.omnia.mobile/pip"
    private val INTENT_CHANNEL = "dev.omnia.mobile/intent"
    private val PERMISSION_CHANNEL = "dev.omnia.mobile/permissions"

    private var initialFilePath: String? = null
    private var intentMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        requestStartupPermissions()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = handleIntent(intent)
        if (path != null) {
            intentMethodChannel?.invokeMethod("onFileOpened", path)
        }
    }

    private fun requestStartupPermissions() {
        val permissionsToRequest = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // Android 13+
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.READ_MEDIA_VIDEO)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.READ_MEDIA_AUDIO)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.READ_MEDIA_IMAGES)
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.CAMERA)
        }

        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissionsToRequest.toTypedArray(), 1001)
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
        if (intent.data != null) return intent.data

        val clipData = intent.clipData
        if (clipData != null && clipData.itemCount > 0) {
            val itemUri = clipData.getItemAt(0)?.uri
            if (itemUri != null) return itemUri
        }

        val extraStream = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
        if (extraStream != null) return extraStream

        return null
    }

    /**
     * Résout un URI en chemin absolu de fichier.
     * Tente TOUJOURS d'accéder au vrai chemin physique (/storage/emulated/0/...)
     * pour éliminer toute copie lente et permettre la découverte immédiate des fichiers voisins.
     */
    private fun resolveUriToPath(uri: Uri, intent: Intent): String? {
        val scheme = uri.scheme

        // 1. Schéma "file"
        if (scheme == null || scheme == "file") {
            val decodedPath = Uri.decode(uri.path ?: "")
            if (decodedPath.isNotEmpty()) {
                val f = File(decodedPath)
                if (f.exists() && f.canRead()) {
                    return f.absolutePath
                }
            }
        }

        // 2. Schéma "content" : Tenter d'abord la résolution directe du chemin MediaStore / DocumentsContract
        val directPath = resolveContentUriToFilePath(uri)
        if (directPath != null) {
            val f = File(directPath)
            if (f.exists() && f.canRead()) {
                Log.i("OMNIA", "Resolved direct physical path: $directPath")
                return f.absolutePath
            }
        }

        // 3. Fallback : Flux content:// avec copie en cache rapide
        try {
            var fileName = "opened_file"
            var extension = ""

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
                Log.w("OMNIA", "Could not query DISPLAY_NAME for $uri: ${e.message}")
            }

            val dotIndex = fileName.lastIndexOf('.')
            if (dotIndex == -1 || fileName.substring(dotIndex + 1).length > 5) {
                if (extension.isNotEmpty()) {
                    fileName = "$fileName.$extension"
                } else {
                    fileName = if (intent.type?.startsWith("video/") == true) "$fileName.mp4" else "$fileName.jpg"
                }
            }

            val cacheFolder = File(cacheDir, "opened_media")
            if (!cacheFolder.exists()) {
                cacheFolder.mkdirs()
            }

            val cleanName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val outputFile = File(cacheFolder, "${System.currentTimeMillis()}_$cleanName")

            // Copie par tampon efficace de 1 Mo
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outputFile).use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                    }
                }
            }

            if (outputFile.exists() && outputFile.length() > 0) {
                return outputFile.absolutePath
            }
        } catch (e: Exception) {
            Log.e("OMNIA", "Failed to copy content URI: $uri", e)
        }

        return uri.path
    }

    private fun resolveContentUriToFilePath(uri: Uri): String? {
        val authority = uri.authority ?: return null

        try {
            // DocumentsContract: ExternalStorageProvider
            if ("com.android.externalstorage.documents" == authority) {
                val docId = DocumentsContract.getDocumentId(uri)
                val split = docId.split(":")
                val type = split[0]
                if ("primary".equals(type, ignoreCase = true)) {
                    val candidate = Environment.getExternalStorageDirectory().path + "/" + split[1]
                    if (File(candidate).exists()) return candidate
                } else {
                    val candidate = "/storage/$type/${split[1]}"
                    if (File(candidate).exists()) return candidate
                }
            }

            // DocumentsContract: MediaDocumentsProvider
            if ("com.android.providers.media.documents" == authority) {
                val docId = DocumentsContract.getDocumentId(uri)
                val split = docId.split(":")
                val type = split[0]
                val id = split[1]
                val contentUri: Uri = when (type) {
                    "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                    else -> MediaStore.Files.getContentUri("external")
                }
                val selection = "_id=?"
                val selectionArgs = arrayOf(id)
                val path = getDataColumn(contentUri, selection, selectionArgs)
                if (path != null && File(path).exists()) return path
            }

            // Direct MediaStore query
            if ("media" == authority || uri.toString().startsWith("content://media/")) {
                val path = getDataColumn(uri, null, null)
                if (path != null && File(path).exists()) return path
            }

            // DownloadsProvider
            if ("com.android.providers.downloads.documents" == authority) {
                val id = DocumentsContract.getDocumentId(uri)
                if (id.startsWith("raw:")) {
                    val rawPath = id.replaceFirst("raw:", "")
                    if (File(rawPath).exists()) return rawPath
                }
                val contentUri = ContentUris.withAppendedId(
                    Uri.parse("content://downloads/public_downloads"),
                    id.toLongOrNull() ?: 0L
                )
                val path = getDataColumn(contentUri, null, null)
                if (path != null && File(path).exists()) return path
            }
        } catch (e: Exception) {
            Log.w("OMNIA", "Failed resolving content URI to file path: $e")
        }

        return null
    }

    private fun getDataColumn(uri: Uri, selection: String?, selectionArgs: Array<String>?): String? {
        val column = "_data"
        val projection = arrayOf(column)
        try {
            contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val columnIndex = cursor.getColumnIndex(column)
                    if (columnIndex != -1) {
                        return cursor.getString(columnIndex)
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun resolveRealStoragePath(cachedPath: String): String {
        try {
            val file = File(cachedPath)
            if (!cachedPath.contains("/cache/")) return cachedPath

            val fileName = file.name
            val projection = arrayOf(MediaStore.MediaColumns.DATA)
            val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
            val selectionArgs = arrayOf(fileName)

            val uris = arrayOf(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Files.getContentUri("external")
            )

            for (contentUri in uris) {
                contentResolver.query(contentUri, projection, selection, selectionArgs, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val realPath = cursor.getString(0)
                        if (!realPath.isNullOrBlank() && File(realPath).exists()) {
                            return realPath
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w("OMNIA", "Error resolving real path for $cachedPath", e)
        }
        return cachedPath
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

        // Configuration Intent "Ouvrir avec" et Résolution de chemins réels
        intentMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        val path = initialFilePath
                        initialFilePath = null
                        result.success(path)
                    }
                    "resolveRealStoragePath" -> {
                        val path = call.argument<String>("path") ?: ""
                        val resolved = resolveRealStoragePath(path)
                        result.success(resolved)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Configuration Permissions Système
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    requestStartupPermissions()
                    result.success(true)
                }
                "openOverlaySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "openAllFilesSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "checkStatus" -> {
                    val hasCamera = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                    val canOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true
                    val isAllFilesManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else true
                    result.success(mapOf(
                        "hasCamera" to hasCamera,
                        "canOverlay" to canOverlay,
                        "isAllFilesManager" to isAllFilesManager
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPipMode(width: Int, height: Int): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // Bornage strict du ratio [1:2.39 à 2.39:1] imposé par le framework Android
                val ratio = (width.toDouble() / height.toDouble()).coerceIn(0.42, 2.38)
                val clampedW = (ratio * 100).toInt().coerceIn(42, 238)
                val clampedH = 100
                val rational = Rational(clampedW, clampedH)
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(rational)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(true)
                }
                return enterPictureInPictureMode(builder.build())
            } catch (e: Exception) {
                Log.w("OMNIA", "Failed entering PiP with params: $e")
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
