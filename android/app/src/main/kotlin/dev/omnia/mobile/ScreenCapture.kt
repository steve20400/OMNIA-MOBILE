package dev.omnia.mobile

import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.util.Log
import android.view.Surface

// Le relais entre le service qui encode et l'activité qui transmet au Dart.
//
// Les deux vivent dans le même processus : un objet partagé suffit, et évite
// d'écrire une communication entre processus pour rien.
object ScreenCaptureBridge {
    // L'autorisation de capture, donnée par l'utilisateur dans une boîte du
    // système. Elle ne se demande qu'une fois par session, et le service en a
    // besoin pour ouvrir la projection.
    @Volatile
    var consentData: Intent? = null

    @Volatile
    var consentResult: Int = 0

    // Chaque morceau encodé part vers le Dart, qui le sert sur le réseau.
    @Volatile
    var onChunk: ((ByteArray, Boolean) -> Unit)? = null

    // La capture s'est arrêtée, d'elle-même ou parce qu'on l'a demandé.
    @Volatile
    var onStopped: (() -> Unit)? = null

    val hasConsent: Boolean
        get() = consentData != null
}

// Encode l'écran en H.264 et rend les morceaux au fur et à mesure.
//
// L'image ne transite jamais par la mémoire de l'application : la projection
// dessine dans la surface d'entrée du codec, qui sort directement du flux
// compressé. C'est ce qui rend la chose tenable sur un téléphone modeste.
class ScreenEncoder(
    private val width: Int,
    private val height: Int,
    private val density: Int,
    private val bitRate: Int,
    private val onChunk: (ByteArray, Boolean) -> Unit
) {
    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var display: VirtualDisplay? = null
    private var drain: Thread? = null

    @Volatile
    private var running = false

    // Les paramètres de décodage, émis une seule fois par le codec. Ils sont
    // gardés pour être renvoyés en tête à chaque nouveau spectateur : sans
    // eux, un lecteur qui arrive en cours de route ne décode rien.
    @Volatile
    var header: ByteArray? = null
        private set

    fun start(projection: MediaProjection): Boolean {
        return try {
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                width,
                height
            ).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                // Une image clé par seconde : un spectateur qui arrive en
                // cours de route voit quelque chose sans attendre.
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }

            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val input = encoder.createInputSurface()
            encoder.start()

            codec = encoder
            surface = input
            display = projection.createVirtualDisplay(
                "omnia-screen",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                input,
                null,
                null
            )

            running = true
            drain = Thread({ drainLoop(encoder) }, "omnia-screen-encoder").also { it.start() }
            true
        } catch (e: Throwable) {
            Log.w("OMNIA", "Encodeur d'ecran indisponible : " + e)
            stop()
            false
        }
    }

    private fun drainLoop(encoder: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        while (running) {
            try {
                val index = encoder.dequeueOutputBuffer(info, 10_000)
                if (index < 0) continue
                val buffer = encoder.getOutputBuffer(index)
                if (buffer != null && info.size > 0) {
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val bytes = ByteArray(info.size)
                    buffer.get(bytes)
                    val isHeader =
                        (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                    if (isHeader) header = bytes
                    onChunk(bytes, isHeader)
                }
                encoder.releaseOutputBuffer(index, false)
            } catch (e: Throwable) {
                Log.w("OMNIA", "Encodage d'ecran interrompu : " + e)
                break
            }
        }
    }

    fun stop() {
        running = false
        try {
            drain?.join(500)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        drain = null
        try {
            display?.release()
        } catch (e: Throwable) {
            Log.w("OMNIA", "Ecran virtuel : " + e)
        }
        display = null
        try {
            codec?.stop()
            codec?.release()
        } catch (e: Throwable) {
            Log.w("OMNIA", "Codec d'ecran : " + e)
        }
        codec = null
        try {
            surface?.release()
        } catch (e: Throwable) {
            Log.w("OMNIA", "Surface d'encodage : " + e)
        }
        surface = null
        header = null
    }
}
