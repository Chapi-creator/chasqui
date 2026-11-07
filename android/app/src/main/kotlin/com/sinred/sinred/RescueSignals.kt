package com.sinred.sinred

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.view.Window
import android.view.WindowManager
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Señales de rescate que viven fuera de Flutter: linterna, sirena y pantalla
 * despierta a brillo máximo.
 *
 * Se resuelven con tres APIs del sistema en lugar de meter un paquete más al
 * APK. Ninguna toca la radio: la malla sigue escuchando y enviando mientras el
 * panel está abierto.
 */
class RescueSignals(context: Context, private val window: Window) {

    private val cameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager

    private var torchCameraId: String? = null
    private var torchOn = false
    private var siren: AudioTrack? = null
    private var tone: AudioTrack? = null

    /** Id de la cámara trasera con flash; null si el equipo no tiene ninguna. */
    private fun torchCamera(): String? {
        torchCameraId?.let { return it }
        val manager = cameraManager ?: return null
        return try {
            val ids = manager.cameraIdList
            fun hasFlash(id: String): Boolean =
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true

            fun facesBack(id: String): Boolean =
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK

            val id = ids.firstOrNull { hasFlash(it) && facesBack(it) }
                ?: ids.firstOrNull { hasFlash(it) }
            id?.also { torchCameraId = it }
        } catch (error: Exception) {
            // Un fabricante con la cámara rota no debe tirar la app: el panel
            // sigue funcionando con la pantalla.
            null
        }
    }

    fun hasTorch(): Boolean = torchCamera() != null

    /** Devuelve true si la linterna quedó como se pidió. */
    fun setTorch(on: Boolean): Boolean {
        val id = torchCamera() ?: return false
        if (on == torchOn) return true
        return try {
            cameraManager?.setTorchMode(id, on)
            torchOn = on
            true
        } catch (error: CameraAccessException) {
            // Otra app tiene la cámara abierta (videollamada, cámara, escáner).
            false
        } catch (error: SecurityException) {
            false
        } catch (error: IllegalArgumentException) {
            false
        } catch (error: RuntimeException) {
            false
        }
    }

    fun setSiren(on: Boolean): Boolean {
        if (!on) {
            stopSiren()
            return true
        }
        if (siren != null) return true
        return try {
            siren = buildSiren()?.also { it.play() }
            siren != null
        } catch (error: Exception) {
            stopSiren()
            false
        }
    }

    /**
     * Dos tonos alternos de 600 ms. Las frecuencias se eligen para que cada
     * tramo dure un número entero de ciclos (880 Hz son 528 ciclos, 1180 Hz
     * son 708), así el final del bucle empalma con el principio sin chasquido.
     */
    private fun buildSiren(): AudioTrack? {
        val sampleRate = 22050
        val framesPerTone = sampleRate * 600 / 1000
        val samples = ShortArray(framesPerTone * 2)
        fillTone(samples, 0, framesPerTone, 880.0, sampleRate)
        fillTone(samples, framesPerTone, framesPerTone, 1180.0, sampleRate)
        return buildLoop(samples, sampleRate)
    }

    /**
     * Pitido continuo para el morse escrito: cada punto y cada raya lo encienden
     * y lo apagan, así el oído sigue el mismo ritmo que la luz. Un segundo son
     * 700 ciclos exactos, de modo que el bucle empalma sin chasquido.
     */
    private fun buildTone(): AudioTrack? {
        val sampleRate = 22050
        val frames = sampleRate
        val samples = ShortArray(frames)
        fillTone(samples, 0, frames, 700.0, sampleRate)
        return buildLoop(samples, sampleRate)
    }

    /** Reproductor en bucle infinito para un buffer ya sintetizado. */
    private fun buildLoop(samples: ShortArray, sampleRate: Int): AudioTrack? {
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(sampleRate)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()
        // Volumen de alarma: suena aunque el teléfono esté en silencio.
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val track = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(samples.size * 2)
            .build()
        val written = track.write(samples, 0, samples.size)
        if (written <= 0) {
            track.release()
            return null
        }
        // -1 = en bucle hasta que se pare.
        track.setLoopPoints(0, samples.size, -1)
        track.setVolume(1f)
        return track
    }

    private fun fillTone(
        buffer: ShortArray,
        offset: Int,
        frames: Int,
        hertz: Double,
        sampleRate: Int
    ) {
        for (i in 0 until frames) {
            val value = sin(2.0 * PI * hertz * i / sampleRate) * 0.5 * Short.MAX_VALUE
            buffer[offset + i] = value.roundToInt().toShort()
        }
    }

    fun setMorseTone(on: Boolean): Boolean {
        if (!on) {
            stopTone()
            return true
        }
        if (tone != null) return true
        return try {
            tone = buildTone()?.also { it.play() }
            tone != null
        } catch (error: Exception) {
            stopTone()
            false
        }
    }

    private fun stopTone() {
        val track = tone ?: return
        tone = null
        try {
            track.stop()
        } catch (error: Exception) {
            // Ya estaba parado.
        }
        try {
            track.release()
        } catch (error: Exception) {
            // Nada que liberar.
        }
    }

    private fun stopSiren() {
        val track = siren ?: return
        siren = null
        try {
            track.stop()
        } catch (error: Exception) {
            // Ya estaba parada.
        }
        try {
            track.release()
        } catch (error: Exception) {
            // Nada que liberar.
        }
    }

    /**
     * Pantalla despierta y a brillo máximo mientras hay un patrón que mostrar.
     * Al apagarlo se devuelve el brillo al que tenía el sistema, no al mínimo.
     */
    fun keepAwake(on: Boolean) {
        try {
            val attributes = window.attributes
            if (on) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                attributes.screenBrightness =
                    WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                attributes.screenBrightness =
                    WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            }
            window.attributes = attributes
        } catch (error: Exception) {
            // Ventana ya cerrada: no hay nada que ajustar.
        }
    }

    /** Corta las señales: la app pasó a segundo plano o se cerró. */
    fun stopSignals() {
        setTorch(false)
        stopSiren()
        stopTone()
        keepAwake(false)
    }
}
