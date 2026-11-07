package com.sinred.sinred

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Looper
import android.provider.Settings
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        /** Extra con el id del nodo que debe abrirse al tocar la notificación. */
        const val EXTRA_PEER_ID = "sinred.peerId"

        /** Id de conversación del canal abierto "Todos". */
        const val CHANNEL_CONVERSATION_ID = "todos"
    }

    private val channelName = "sinred/power"
    private val locationChannelName = "sinred/location"
    private val sensorChannelName = "sinred/sensors"
    private val shareChannelName = "sinred/share"
    private val rescueChannelName = "sinred/rescue"
    private val permissionRequestCode = 71
    private val locationPermissionRequestCode = 72
    private val contactChannelId = "sinred_contacts"

    private var powerChannel: MethodChannel? = null
    private var locationChannel: MethodChannel? = null
    private var sensorChannel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private var rescueChannel: MethodChannel? = null
    private var rescueSignals: RescueSignals? = null
    private var compassListener: SensorEventListener? = null
    private var lastHeadingAt = 0L
    private var lastHeading = -1f

    /** Chat pedido desde una notificación, pendiente de que Dart lo recoja. */
    private var pendingChatPeerId: String? = null

    /** Resultados pendientes de Dart mientras el usuario responde al diálogo. */
    private val pendingPermissionResults = mutableListOf<MethodChannel.Result>()
    private val pendingLocationPermissionResults =
        mutableListOf<MethodChannel.Result>()

    private var locationListener: LocationListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // La app se abrió tocando una notificación: se guarda para que Dart lo
        // consuma en cuanto termine de arrancar.
        pendingChatPeerId = intent?.getStringExtra(EXTRA_PEER_ID)
        intent?.removeExtra(EXTRA_PEER_ID)

        powerChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        powerChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    val wanted = mutableListOf<String>()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        wanted.add(Manifest.permission.BLUETOOTH_SCAN)
                        wanted.add(Manifest.permission.BLUETOOTH_ADVERTISE)
                        wanted.add(Manifest.permission.BLUETOOTH_CONNECT)
                    } else {
                        // Antes de Android 12 el escaneo BLE exige ubicación.
                        wanted.add(Manifest.permission.ACCESS_FINE_LOCATION)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        wanted.add(Manifest.permission.POST_NOTIFICATIONS)
                    }
                    val missing = wanted.filter {
                        checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                    }
                    if (missing.isEmpty()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    // Se responde cuando el usuario contesta: si se responde
                    // ya, Dart arranca la radio sin permisos y en Android 14
                    // el servicio en primer plano lanza SecurityException.
                    pendingPermissionResults.add(result)
                    // Un solo diálogo: las demás peticiones esperan a este.
                    if (pendingPermissionResults.size == 1) {
                        requestPermissions(
                            missing.toTypedArray(),
                            permissionRequestCode
                        )
                    }
                }
                "startForeground", "updateText" -> {
                    if (!hasBluetoothPermission()) {
                        // Sin permiso de Bluetooth el servicio de tipo
                        // connectedDevice no puede arrancar (Android 14+).
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val text = call.argument<String>("text") ?: "Escuchando la malla"
                    val intent = Intent(this, MeshForegroundService::class.java)
                        .putExtra(MeshForegroundService.EXTRA_TEXT, text)
                    if (call.method == "updateText") {
                        intent.setAction(MeshForegroundService.ACTION_UPDATE)
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        // Android 12+ prohíbe arrancar un servicio en primer
                        // plano desde segundo plano; mejor seguir sin él.
                        result.success(false)
                    }
                }
                "hasPermissions" -> {
                    result.success(hasBluetoothPermission())
                }
                "notifyChannel" -> {
                    notifyChannel(
                        title = call.argument<String>("title") ?: "Canal Todos",
                        body = call.argument<String>("body") ?: "",
                        sos = call.argument<Boolean>("sos") ?: false
                    )
                    result.success(true)
                }
                "notifyContact" -> {
                    notifyContact(
                        peerId = call.argument<String>("peerId") ?: "",
                        name = call.argument<String>("name") ?: "Un contacto",
                        body = call.argument<String>("body") ?: ""
                    )
                    result.success(true)
                }
                "consumePendingChat" -> {
                    val peerId = pendingChatPeerId
                    pendingChatPeerId = null
                    result.success(peerId)
                }
                "stopForeground" -> {
                    stopService(Intent(this, MeshForegroundService::class.java))
                    result.success(true)
                }
                "openBatterySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(true)
                        } catch (fallback: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        locationChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannelName)
        locationChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasLocationPermission())
                "requestPermission" -> requestLocationPermission(result)
                "start" -> startLocationUpdates(result)
                "stop" -> {
                    stopLocationUpdates()
                    result.success(true)
                }
                "current" -> {
                    val manager = getSystemService(LOCATION_SERVICE) as? LocationManager
                    val location = manager?.let { lastKnown(it) }
                    result.success(location?.let { locationToMap(it) })
                }
                "openSettings" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(true)
                    } catch (error: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        sensorChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sensorChannelName)
        sensorChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(startCompass())
                "stop" -> {
                    stopCompass()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        shareChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
        shareChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "shareApk" -> result.success(shareApk())
                else -> result.notImplemented()
            }
        }

        // Panel de señales: linterna, sirena y pantalla encendida. No usa la
        // radio, así que puede estar activo sin tocar la malla.
        val signals = RescueSignals(this, window)
        rescueSignals = signals
        rescueChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, rescueChannelName)
        rescueChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasTorch" -> result.success(signals.hasTorch())
                "torch" ->
                    result.success(signals.setTorch(call.argument<Boolean>("on") ?: false))
                "siren" ->
                    result.success(signals.setSiren(call.argument<Boolean>("on") ?: false))
                "keepAwake" -> {
                    signals.keepAwake(call.argument<Boolean>("on") ?: false)
                    result.success(true)
                }
                "release" -> {
                    signals.stopSignals()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** La app ya estaba viva y el usuario tocó otra notificación. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val peerId = intent.getStringExtra(EXTRA_PEER_ID) ?: return
        intent.removeExtra(EXTRA_PEER_ID)
        pendingChatPeerId = peerId
        powerChannel?.invokeMethod("openChat", peerId)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            permissionRequestCode -> {
                // Se responde lo que el usuario decidió de verdad: antes se
                // contestaba "concedido" aunque hubiera denegado los permisos.
                val granted = permissions.isNotEmpty() &&
                    grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                replyPendingPermissions(granted)
            }
            locationPermissionRequestCode ->
                replyLocationPermissions(hasLocationPermission())
        }
    }

    override fun onStop() {
        // El panel de señales solo tiene sentido con la pantalla delante: si la
        // app pasa a segundo plano se apagan linterna y sirena. La radio sigue
        // con su servicio en primer plano, como siempre.
        rescueSignals?.stopSignals()
        super.onStop()
    }

    override fun onDestroy() {
        // Si la Activity muere con el diálogo abierto, se libera el canal para
        // que el Future de Dart no quede colgado para siempre.
        rescueSignals?.stopSignals()
        rescueSignals = null
        replyPendingPermissions(false)
        replyLocationPermissions(false)
        stopLocationUpdates()
        stopCompass()
        super.onDestroy()
    }

    private fun replyPendingPermissions(granted: Boolean) {
        if (pendingPermissionResults.isEmpty()) return
        // clear() antes de responder: responder puede reentrar en el canal.
        val pending = pendingPermissionResults.toList()
        pendingPermissionResults.clear()
        for (result in pending) {
            result.success(granted)
        }
    }

    private fun replyLocationPermissions(granted: Boolean) {
        if (pendingLocationPermissionResults.isEmpty()) return
        val pending = pendingLocationPermissionResults.toList()
        pendingLocationPermissionResults.clear()
        for (result in pending) {
            result.success(granted)
        }
    }

    // ------------------------------------------------------------------ GPS

    private fun hasLocationPermission(): Boolean {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (hasLocationPermission()) {
            result.success(true)
            return
        }
        pendingLocationPermissionResults.add(result)
        if (pendingLocationPermissionResults.size == 1) {
            requestPermissions(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                locationPermissionRequestCode
            )
        }
    }

    /**
     * Ubicación del chip, sin internet. Se piden las dos fuentes: GPS para
     * precisión y red (torres conocidas) para un primer dato rápido.
     */
    private fun startLocationUpdates(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.success(false)
            return
        }
        val manager = getSystemService(LOCATION_SERVICE) as? LocationManager
        if (manager == null) {
            result.success(false)
            return
        }
        if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER) &&
            !manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        ) {
            result.success(false)
            return
        }
        val listener = locationListener ?: object : LocationListener {
            override fun onLocationChanged(location: Location) {
                locationChannel?.invokeMethod("update", locationToMap(location))
            }

            // Aunque en las APIs nuevas tienen implementación por defecto, se
            // declaran para que en Android 7/8 el sistema no llame a un método
            // que nuestra clase no tiene.
            override fun onProviderEnabled(provider: String) {}

            override fun onProviderDisabled(provider: String) {}

            override fun onStatusChanged(
                provider: String?,
                status: Int,
                extras: android.os.Bundle?
            ) {}
        }.also { locationListener = it }
        try {
            // 15 s y 10 m: alcanza para "está a 30 m" sin drenar la batería.
            if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                manager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    15000L,
                    10f,
                    listener,
                    Looper.getMainLooper()
                )
            }
            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                manager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    15000L,
                    10f,
                    listener,
                    Looper.getMainLooper()
                )
            }
            // Última conocida: así hay dato sin esperar al primer fix.
            lastKnown(manager)?.let {
                locationChannel?.invokeMethod("update", locationToMap(it))
            }
            result.success(true)
        } catch (error: SecurityException) {
            result.success(false)
        } catch (error: IllegalArgumentException) {
            // El proveedor existe pero está deshabilitado en el sistema.
            result.success(false)
        }
    }

    private fun stopLocationUpdates() {
        val listener = locationListener ?: return
        try {
            val manager = getSystemService(LOCATION_SERVICE) as? LocationManager
            manager?.removeUpdates(listener)
        } catch (error: Exception) {
            // Sin permiso o proveedor caído: no hay nada que quitar.
        }
        locationListener = null
    }

    private fun lastKnown(manager: LocationManager): Location? {
        if (!hasLocationPermission()) return null
        var best: Location? = null
        for (provider in listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )) {
            val candidate = try {
                manager.getLastKnownLocation(provider)
            } catch (error: Exception) {
                null
            } ?: continue
            val current = best
            if (current == null || candidate.time > current.time) best = candidate
        }
        return best
    }

    private fun locationToMap(location: Location): Map<String, Any> = mapOf(
        "lat" to location.latitude,
        "lon" to location.longitude,
        "acc" to if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0,
        "ts" to location.time
    )

    // -------------------------------------------------------- notificaciones

    /**
     * Aviso local de que un contacto de la libreta está al alcance. No es el
     * servicio en primer plano: es una notificación aparte que se puede
     * descartar y que no mantiene nada vivo. Tocarla abre su chat.
     */
    private fun notifyContact(peerId: String, name: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            // Sin permiso de notificaciones no hay aviso, pero la app sigue igual.
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                contactChannelId,
                "Contactos al alcance",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description =
                "Avisa cuando un contacto guardado está lo bastante cerca para escribirle."
            manager.createNotificationChannel(channel)
        }
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (peerId.isNotEmpty()) putExtra(EXTRA_PEER_ID, peerId)
        }
        // Un requestCode por contacto: si no, Android reutiliza el PendingIntent
        // anterior y el toque abriría el chat equivocado.
        val open = PendingIntent.getActivity(
            this,
            if (peerId.isEmpty()) 0 else peerId.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, contactChannelId)
        } else {
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("$name está al alcance")
            .setContentText(
                body.ifEmpty {
                    if (peerId.isNotEmpty()) "Toca para abrir el chat."
                    else "Está en la malla."
                }
            )
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            // Mismo id por contacto: si vuelve a aparecer, se actualiza el aviso
            // en vez de apilar uno nuevo.
            manager.notify(name.hashCode(), notification)
        } catch (error: SecurityException) {
            // Carrera con la revocación del permiso: se ignora.
        }
    }

    // ---------------------------------------------------------------- brújula

    /**
     * Rumbo del teléfono con el sensor de rotación, en grados (0 = norte).
     * Sin sensor devuelve false y la UI sigue mostrando la sigla calculada a
     * partir de las coordenadas: la flecha es un extra, no la única forma.
     */
    private fun startCompass(): Boolean {
        if (compassListener != null) return true
        val manager = getSystemService(SENSOR_SERVICE) as? SensorManager ?: return false
        val sensor = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: manager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
            ?: return false
        val rotation = FloatArray(9)
        val orientation = FloatArray(3)
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                SensorManager.getOrientation(rotation, orientation)
                var degrees = Math.toDegrees(orientation[0].toDouble()).toFloat()
                if (degrees < 0f) degrees += 360f
                val now = System.currentTimeMillis()
                // 200 ms alcanza para mover una flecha sin saturar el canal.
                if (now - lastHeadingAt < 200L) return
                if (lastHeading >= 0f && Math.abs(degrees - lastHeading) < 2f) return
                lastHeadingAt = now
                lastHeading = degrees
                sensorChannel?.invokeMethod("heading", degrees.toDouble())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        return try {
            val registered =
                manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
            if (registered) {
                compassListener = listener
                lastHeading = -1f
            }
            registered
        } catch (error: Exception) {
            false
        }
    }

    private fun stopCompass() {
        val listener = compassListener ?: return
        try {
            val manager = getSystemService(SENSOR_SERVICE) as? SensorManager
            manager?.unregisterListener(listener)
        } catch (error: Exception) {
            // Sensor ya desregistrado o servicio caído: nada que hacer.
        }
        compassListener = null
        lastHeading = -1f
    }

    // --------------------------------------------------------- compartir app

    /**
     * Abre la hoja de compartir con el APK adjunto. Quick Share o Bluetooth lo
     * llevan a otro teléfono sin internet y sin Play Store.
     */
    private fun shareApk(): Boolean {
        return try {
            val apk = File(applicationInfo.sourceDir)
            val uri = try {
                FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
            } catch (error: IllegalArgumentException) {
                // Si el proveedor no cubre la ruta del APK, se copia a caché.
                val cached = File(cacheDir, "SinRed.apk")
                if (!cached.exists() || cached.length() != apk.length()) {
                    apk.copyTo(cached, overwrite = true)
                }
                FileProvider.getUriForFile(this, "$packageName.fileprovider", cached)
            }
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.android.package-archive"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, "SinRed: chat sin internet")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, "Compartir SinRed"))
            true
        } catch (error: Exception) {
            false
        }
    }

    // ------------------------------------------------------- avisos del canal

    /** Aviso de estado o SOS del canal abierto. Tocarlo abre "Todos". */
    private fun notifyChannel(title: String, body: String, sos: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channelId = if (sos) "sinred_sos" else "sinred_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationChannel = NotificationChannel(
                channelId,
                if (sos) "SOS de la malla" else "Canal Todos",
                if (sos) NotificationManager.IMPORTANCE_HIGH
                else NotificationManager.IMPORTANCE_DEFAULT
            )
            notificationChannel.description = if (sos) {
                "Peticiones de auxilio recibidas por la malla."
            } else {
                "Avisos y estados del canal abierto."
            }
            if (sos) {
                notificationChannel.enableVibration(true)
                notificationChannel.vibrationPattern = longArrayOf(0, 400, 200, 400)
            }
            manager.createNotificationChannel(notificationChannel)
        }
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_PEER_ID, CHANNEL_CONVERSATION_ID)
        }
        val open = PendingIntent.getActivity(
            this,
            if (sos) 9101 else 9102,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(
                if (sos) android.R.drawable.stat_notify_error
                else android.R.drawable.stat_notify_chat
            )
            .setContentTitle(title)
            .setContentText(body.ifEmpty { "Toca para abrir el canal." })
            .setAutoCancel(true)
            .setContentIntent(open)
            .setPriority(
                if (sos) Notification.PRIORITY_MAX else Notification.PRIORITY_DEFAULT
            )
        if (sos) {
            builder.setDefaults(Notification.DEFAULT_VIBRATE)
        }
        try {
            manager.notify(if (sos) 9101 else 9102, builder.build())
        } catch (error: SecurityException) {
            // Carrera con la revocación del permiso: se ignora.
        }
    }

    /** En Android 12+ basta con uno de los permisos BLE para el servicio. */
    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return listOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT
        ).any { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }
}
