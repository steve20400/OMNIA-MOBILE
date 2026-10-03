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
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val PIP_CHANNEL = "dev.omnia.mobile/pip"
    private val INTENT_CHANNEL = "dev.omnia.mobile/intent"
    private val PERMISSION_CHANNEL = "dev.omnia.mobile/permissions"
    private val UPDATE_CHANNEL = "dev.omnia.mobile/update"

    private var intentMethodChannel: MethodChannel? = null

    /// Résolution du fichier reçu : requêtes au fournisseur, et copie de
    /// secours quand elle est inévitable. Ce sont des appels entre processus,
    /// qui n'ont rien à faire sur le fil principal.
    private val intentWorker = Executors.newSingleThreadExecutor()

    /// Descripteurs et chemins réels, sur leur propre fil : une copie de
    /// secours en cours ne doit pas retenir l'ouverture d'un autre média.
    private val providerWorker = Executors.newSingleThreadExecutor()

    private val mainHandler = Handler(Looper.getMainLooper())

    /// Fichier résolu mais pas encore réclamé par Flutter, au format attendu
    /// par « getInitialFile ». Consommé une seule fois.
    private var pendingFile: Map<String, Any?>? = null

    /// Une résolution est en cours : l'écran d'accueil patiente au lieu de
    /// démarrer à vide puis de sauter sur le fichier.
    @Volatile private var resolving = false

    /// Vrai une fois que le lecteur a posé son écouteur. Avant cela le canal
    /// existe déjà — `configureFlutterEngine` s'exécute pendant `onCreate` —
    /// mais personne ne recevrait l'événement : le résultat est mis de côté.
    private var dartListening = false

    /// Avancement de la copie de secours, de 0 à 1 ; -1 quand rien n'est copié.
    @Volatile private var copyProgress = -1.0

    /// Descripteurs ouverts pour mpv, par numéro. Le lecteur les referme
    /// explicitement en changeant de média : un descripteur oublié reste ouvert
    /// jusqu'à la mort du processus.
    private val openDescriptors = HashMap<Int, ParcelFileDescriptor>()

    /// Extensions audio/vidéo reconnues quand le fournisseur annonce un type
    /// générique (« application/octet-stream »), ce que font plusieurs
    /// messageries pour les fichiers qu'elles ne savent pas classer.
    private val avExtensions = setOf(
        "mp4", "m4v", "mkv", "webm", "avi", "mov", "wmv", "asf", "flv", "ogv",
        "3gp", "divx", "xvid", "mpg", "mpeg", "vob", "ts", "m2ts", "mts", "rm",
        "rmvb", "mp3", "aac", "m4a", "m4b", "flac", "wav", "ogg", "opus", "wma",
        "aiff", "ape", "dts", "ac3", "mka", "mp2", "amr", "spx"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Rien de lourd ici. La résolution du fichier reçu était faite sur ce
        // fil, copie intégrale comprise : un film d'un gigaoctet et demi
        // bloquait l'affichage du premier écran pendant dix à vingt secondes,
        // et frôlait le « l'application ne répond pas » d'Android.
        startResolvingIntent(intent)
        requestStartupPermissions()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        startResolvingIntent(intent)
    }

    override fun onDestroy() {
        // Descripteurs encore ouverts : ils appartiennent au processus, pas à
        // mpv, et personne d'autre ne les refermerait.
        synchronized(openDescriptors) {
            for (pfd in openDescriptors.values) {
                try { pfd.close() } catch (_: Exception) {}
            }
            openDescriptors.clear()
        }
        intentWorker.shutdownNow()
        providerWorker.shutdownNow()
        super.onDestroy()
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

    // --- Ouverture depuis une autre application ---------------------------------

    /**
     * Lance la résolution de l'URI reçu sur le fil de fond et rend la main
     * tout de suite. L'interface s'affiche pendant ce temps ; elle réclame le
     * résultat par « getInitialFile », ou le reçoit par « onFileOpened » si
     * l'application tournait déjà.
     */
    private fun startResolvingIntent(intent: Intent?) {
        if (intent == null) return
        val uri = getUriFromIntent(intent) ?: return
        val intentType = intent.type

        val intentFlags = intent.flags
        resolving = true
        copyProgress = -1.0

        intentWorker.execute {
            // La permission de lecture donnée par l'expéditeur ne dure que le
            // temps de la tâche. Rendue durable quand le fournisseur
            // l'autorise, le fichier reste ouvrable depuis les récents.
            takePersistablePermission(intentFlags, uri)
            val outcome = try {
                resolveUri(uri, intentType)
            } catch (e: Throwable) {
                Log.e("OMNIA", "Résolution impossible pour $uri", e)
                null
            }
            mainHandler.post {
                resolving = false
                copyProgress = -1.0
                if (outcome == null) {
                    pendingFile = null
                    return@post
                }
                // Application déjà à l'écran : l'événement suffit, son
                // destinataire est en place. Au démarrage à froid il n'y a
                // encore aucun auditeur, donc on garde le résultat sous la main.
                if (dartListening) {
                    intentMethodChannel?.invokeMethod("onFileOpened", outcome)
                } else {
                    pendingFile = outcome
                }
            }
        }
    }

    private fun takePersistablePermission(intentFlags: Int, uri: Uri) {
        if (uri.scheme != "content") return
        if ((intentFlags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) == 0) return
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
            // Fournisseur qui ne sait pas rendre la permission durable : la
            // lecture immédiate fonctionne quand même.
        }
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
     * Donne au lecteur de quoi ouvrir l'URI reçu, en évitant toute recopie du
     * média.
     *
     * Dans l'ordre : le vrai chemin physique quand il existe (il permet en plus
     * de lister les fichiers voisins), puis l'URI « content:// » tel quel pour
     * l'audio et la vidéo (mpv le lit par descripteur, sans rien copier), et
     * seulement en dernier recours une copie en cache — réservée aux documents
     * et aux images, dont la taille se compte en mégaoctets.
     *
     * S'exécute sur le fil de fond.
     */
    private fun resolveUri(uri: Uri, intentType: String?): Map<String, Any?>? {
        // 1. Schéma « file » ou chemin nu : rien à demander à un fournisseur.
        val scheme = uri.scheme
        if (scheme == null || scheme == "file") {
            val decodedPath = Uri.decode(uri.path ?: "")
            if (decodedPath.isNotEmpty()) {
                val f = File(decodedPath)
                if (f.exists() && f.canRead()) return resolved(f.absolutePath, f.name)
            }
        }

        val mimeType = try {
            contentResolver.getType(uri) ?: intentType
        } catch (_: Exception) {
            intentType
        }
        val name = fileNameFor(uri, mimeType, intentType)

        // 2. Chemin physique réel derrière un « content:// ». Le meilleur cas :
        // pas de descripteur à gérer, et le panneau peut scanner le dossier.
        val directPath = resolveContentUriToFilePath(uri)
        if (directPath != null) {
            val f = File(directPath)
            if (f.exists() && f.canRead()) {
                Log.i("OMNIA", "Chemin physique résolu : $directPath")
                return resolved(f.absolutePath, f.name)
            }
        }

        // 3. Audio ou vidéo derrière un fournisseur qui n'expose pas « _data »
        // (Google Files, Telegram, Drive… le cas courant depuis Android 11) :
        // on rend l'URI, que le lecteur ouvre en descripteur. Zéro octet copié.
        if (isSeekableAvUri(uri, name, mimeType)) {
            return resolved(uri.toString(), name)
        }

        // 4. Dernier recours : copie. Elle a lieu ici, sur le fil de fond, et
        // son avancement est visible à l'écran.
        return copyToCache(uri, name)
    }

    /**
     * Vrai si l'URI désigne un média audio/vidéo que mpv pourra lire ET
     * parcourir par son descripteur.
     *
     * Un descripteur dont la taille est connue vient d'un vrai fichier : mpv
     * peut s'y déplacer. Un fournisseur distant rend un tuyau, de taille -1 :
     * la recherche y serait impossible et la lecture hachée, donc on copie.
     */
    private fun isSeekableAvUri(uri: Uri, name: String, mimeType: String?): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase()
        val isAv = mimeType?.startsWith("video/") == true ||
            mimeType?.startsWith("audio/") == true ||
            avExtensions.contains(extension) ||
            mimeType == "application/octet-stream"
        if (!isAv) return false
        return try {
            contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false
        } catch (e: Exception) {
            Log.w("OMNIA", "Descripteur refusé pour $uri : ${e.message}")
            false
        }
    }

    /** Nom réel du fichier, extension comprise : c'est lui qui donne le type. */
    private fun fileNameFor(uri: Uri, mimeType: String?, intentType: String?): String {
        var fileName = "fichier_ouvert"
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1) {
                        val name = cursor.getString(nameIndex)
                        if (!name.isNullOrBlank()) fileName = name
                    }
                }
            }
        } catch (e: Exception) {
            Log.w("OMNIA", "Nom introuvable pour $uri : ${e.message}")
        }

        val dotIndex = fileName.lastIndexOf('.')
        if (dotIndex != -1 && fileName.length - dotIndex - 1 in 1..5) return fileName

        // Sans extension, le type se déduit du type MIME annoncé.
        var extension = ""
        val type = mimeType ?: intentType
        if (!type.isNullOrBlank()) {
            val mappedExt = MimeTypeMap.getSingleton().getExtensionFromMimeType(type)
            extension = when {
                !mappedExt.isNullOrBlank() -> mappedExt.lowercase()
                type.startsWith("image/") -> type.substringAfter("image/").lowercase().let {
                    if (it == "jpeg") "jpg" else it
                }
                type.startsWith("video/") -> "mp4"
                type.startsWith("audio/") -> "mp3"
                type == "application/pdf" -> "pdf"
                else -> ""
            }
        }
        return if (extension.isEmpty()) fileName else "$fileName.$extension"
    }

    /** Copie en cache, par tampon d'un mégaoctet, avec avancement publié. */
    private fun copyToCache(uri: Uri, name: String): Map<String, Any?>? {
        val cacheFolder = File(cacheDir, "opened_media")
        if (!cacheFolder.exists()) cacheFolder.mkdirs()

        val cleanName = name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val outputFile = File(cacheFolder, "${System.currentTimeMillis()}_$cleanName")

        val total = try {
            contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: -1L
        } catch (_: Exception) {
            -1L
        }

        copyProgress = 0.0
        var copied = 0L
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outputFile).use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val bytesRead = input.read(buffer)
                        if (bytesRead == -1) break
                        output.write(buffer, 0, bytesRead)
                        copied += bytesRead
                        if (total > 0) copyProgress = copied.toDouble() / total
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("OMNIA", "Copie impossible pour $uri", e)
            return null
        } finally {
            copyProgress = -1.0
        }

        if (outputFile.exists() && outputFile.length() > 0) {
            return resolved(outputFile.absolutePath, name)
        }
        return null
    }

    private fun resolved(path: String, name: String): Map<String, Any?> =
        mapOf("status" to "ready", "path" to path, "name" to name)

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
            Log.w("OMNIA", "Chemin physique introuvable pour cet URI : $e")
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
            Log.w("OMNIA", "Chemin réel introuvable pour $cachedPath", e)
        }
        return cachedPath
    }

    /**
     * Liste les fichiers voisins d'un URI « content:// » via MediaStore.
     *
     * Un URI reçu de « Ouvrir avec » n'a pas de dossier parent dans le système
     * de fichiers : on ne peut pas le scanner. MediaStore, lui, connaît le
     * « bucket » (le dossier) de chaque média : on renvoie tous les médias du
     * même bucket pour que le panneau latéral affiche les frères, comme le fait
     * un scan de dossier pour un chemin réel.
     */
    private fun listSiblings(uriText: String): Map<String, Any?> {
        val uri = Uri.parse(uriText)
        if (uri.scheme != "content") return mapOf("folder" to null, "files" to emptyList<Map<String, Any?>>())

        val mime = try { contentResolver.getType(uri) } catch (_: Exception) { null }
        val collection = when {
            mime?.startsWith("video/") == true -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            mime?.startsWith("audio/") == true -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            mime?.startsWith("image/") == true -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Files.getContentUri("external")
        }

        var bucket: String? = null
        var folderName: String? = null
        try {
            contentResolver.query(
                uri, arrayOf("bucket_id", "bucket_display_name"), null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    bucket = c.getString(0)
                    folderName = c.getString(1)
                }
            }
        } catch (_: Exception) {}
        if (bucket == null) return mapOf("folder" to null, "files" to emptyList<Map<String, Any?>>())

        val files = mutableListOf<Map<String, Any?>>()
        try {
            contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME),
                "bucket_id=?",
                arrayOf(bucket),
                "${MediaStore.MediaColumns.DISPLAY_NAME} ASC"
            )?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    val name = c.getString(1) ?: continue
                    val itemUri = ContentUris.withAppendedId(collection, id)
                    files.add(mapOf("name" to name, "uri" to itemUri.toString()))
                }
            }
        } catch (_: Exception) {}

        return mapOf("folder" to folderName, "files" to files)
    }

    // --- Descripteurs de fichier pour mpv ---------------------------------------

    /**
     * Ouvre un descripteur en lecture sur un URI « content:// » et rend son
     * numéro, que le lecteur passe à mpv sous la forme « fd://<n> ».
     *
     * Le [ParcelFileDescriptor] est conservé ici : c'est lui le propriétaire.
     * mpv ne referme pas les descripteurs de « fd:// » — seul
     * « closeDescriptor » le fait, une fois et une seule.
     */
    private fun openDescriptor(uriText: String): Int {
        return try {
            val pfd = contentResolver.openFileDescriptor(Uri.parse(uriText), "r") ?: return -1
            val fd = pfd.fd
            synchronized(openDescriptors) { openDescriptors[fd] = pfd }
            fd
        } catch (e: Exception) {
            Log.w("OMNIA", "Descripteur impossible pour $uriText : ${e.message}")
            -1
        }
    }

    private fun closeDescriptor(fd: Int): Boolean {
        val pfd = synchronized(openDescriptors) { openDescriptors.remove(fd) } ?: return false
        return try {
            pfd.close()
            true
        } catch (e: Exception) {
            Log.w("OMNIA", "Fermeture du descripteur $fd impossible : ${e.message}")
            false
        }
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

        // Configuration Intent « Ouvrir avec », chemins réels et descripteurs
        intentMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "beginListening" -> {
                        dartListening = true
                        result.success(true)
                    }
                    "getInitialFile" -> {
                        val ready = pendingFile
                        when {
                            // Consommé une seule fois : l'écran d'accueil et le
                            // lecteur le réclament tous les deux.
                            ready != null -> {
                                pendingFile = null
                                result.success(ready)
                            }
                            resolving -> result.success(
                                mapOf("status" to "pending", "progress" to copyProgress)
                            )
                            else -> result.success(null)
                        }
                    }
                    "resolveRealStoragePath" -> {
                        val path = call.argument<String>("path") ?: ""
                        // Requêtes MediaStore : hors du fil principal.
                        providerWorker.execute {
                            val resolvedPath = resolveRealStoragePath(path)
                            mainHandler.post { result.success(resolvedPath) }
                        }
                    }
                    "openDescriptor" -> {
                        val uriText = call.argument<String>("uri") ?: ""
                        providerWorker.execute {
                            val fd = openDescriptor(uriText)
                            mainHandler.post { result.success(fd) }
                        }
                    }
                    "closeDescriptor" -> {
                        val fd = call.argument<Int>("fd") ?: -1
                        result.success(closeDescriptor(fd))
                    }
                    "listSiblings" -> {
                        val uriText = call.argument<String>("uri") ?: ""
                        // Requêtes MediaStore : hors du fil principal.
                        providerWorker.execute {
                            val siblings = listSiblings(uriText)
                            mainHandler.post { result.success(siblings) }
                        }
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

        // Installation de la mise à jour téléchargée par l'application
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallUnknownSources" -> result.success(canInstallUnknownSources())
                "openUnknownSourcesSettings" -> result.success(openUnknownSourcesSettings())
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("chemin_manquant", "Chemin de l'APK manquant", null)
                    } else {
                        result.success(installApk(path))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Android 8 et plus exigent que l'utilisateur autorise cette application à
    // installer des paquets « inconnus ». Sans ce réglage, l'installeur refuse
    // en silence et l'utilisateur ne comprend pas pourquoi rien ne se passe.
    private fun canInstallUnknownSources(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openUnknownSourcesSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
            true
        } catch (e: Exception) {
            Log.w("OMNIA", "Réglage des sources inconnues inaccessible : ${e.message}")
            false
        }
    }

    // Confie l'APK à l'installeur du système. Ni file:// — rejeté depuis
    // Android 7 par FileUriExposedException — ni la commande shell `am`, qui
    // n'existe pas dans un processus d'application : l'URI passe par
    // FileProvider et le lancement par startActivity.
    private fun installApk(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) {
            Log.w("OMNIA", "APK introuvable pour l'installation : $path")
            return false
        }
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w("OMNIA", "Installation de l'APK impossible : ${e.message}")
            false
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
                Log.w("OMNIA", "Passage en PiP refusé avec ces paramètres : $e")
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
