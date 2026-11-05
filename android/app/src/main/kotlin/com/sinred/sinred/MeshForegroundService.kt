package com.sinred.sinred

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Servicio en primer plano de tipo `connectedDevice`.
 *
 * Su único trabajo es mantener vivo el proceso mientras la app está en
 * segundo plano: no despierta la CPU ni mantiene wakelocks.
 *
 * No es START_STICKY a propósito: si el sistema mata el proceso, el motor
 * Flutter muere con él y el servicio recreado solo mostraría una notificación
 * de "malla activa" sin malla. El estado sí queda en disco y la app lo retoma
 * al abrirse.
 */
class MeshForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "sinred_mesh"
        const val NOTIFICATION_ID = 4711
        const val EXTRA_TEXT = "text"
        const val ACTION_UPDATE = "com.sinred.sinred.ACTION_UPDATE"
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Escuchando la malla"
        val notification = buildNotification(text)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: Exception) {
            // Android 14+ lanza SecurityException si el permiso de Bluetooth
            // no está concedido. Sin servicio la app sigue funcionando en
            // primer plano, así que no tiene sentido tumbar el proceso.
            stopSelf()
            return START_NOT_STICKY
        }

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("SinRed")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setOngoing(true)
            .setContentIntent(openAppIntent())
            .build()
    }

    private fun openAppIntent(): PendingIntent? {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(this, 0, intent, pendingFlags)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Malla SinRed",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Mantiene la malla activa con la pantalla apagada"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
