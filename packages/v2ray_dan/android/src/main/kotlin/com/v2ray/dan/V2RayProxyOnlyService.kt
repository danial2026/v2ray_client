package com.v2ray.dan

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.core.app.NotificationCompat
import android.app.PendingIntent

class V2RayProxyOnlyService : Service(), V2RayServicesListener {
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val command = intent?.getIntExtra("COMMAND", 0)
        Utilities.broadcastLog(this, "ProxyService: onStartCommand (cmd: $command)", "INFO")
        
        if (command == AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE) {
            Utilities.copyAssets(this)
            V2RayCoreManager.setUpListener(this)
            val config = AppConfigs.V2RAY_CONFIG
            if (config != null) {
                Utilities.broadcastStatus(this, "connecting")
                Utilities.broadcastLog(this, "ProxyService: Starting V2Ray Core", "INFO")
                startV2Ray()
            }
        } else if (command == AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE) {
            Utilities.broadcastLog(this, "ProxyService: Stopping service command received", "INFO")
            Utilities.broadcastStatus(this, "disconnecting")
            stopV2Ray()
            Utilities.broadcastStatus(this, "disconnected")
        }
        return START_STICKY
    }

    private fun startV2Ray() {
        startForeground(1, createNotification())
        val config = AppConfigs.V2RAY_CONFIG ?: return
        
        // Log parameters for verification
        android.util.Log.d("V2RayDAN", "ProxyService: Start core - Remark: ${config.REMARK}, Config Length: ${config.V2RAY_FULL_JSON_CONFIG.length}")
        Utilities.broadcastLog(this, "ProxyService: Using config for server '${config.REMARK}'", "DEBUG")
        
        V2RayCoreManager.startCore(config)
        Utilities.broadcastStatus(this, "connected")
    }

    private fun stopV2Ray() {
        V2RayCoreManager.stopCore()
        stopForeground(true)
        stopSelf()
    }

    private fun createNotification(): Notification {
        val channelId = "V2RAY_PROXY_CHANNEL"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "V2Ray Proxy Service", NotificationManager.IMPORTANCE_LOW)
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
        
        val disconnectIntent = Intent(this, V2RayProxyOnlyService::class.java)
        disconnectIntent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getService(this, 0, disconnectIntent, flags)
        
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Flaming Cherubim: Proxy Mode")
            .setContentText("SOCKS: 10808 | HTTP: 10809")
            .setSmallIcon(AppConfigs.APPLICATION_ICON)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "DISCONNECT", pendingIntent)
            .setOngoing(true)
            .build()
    }
    
    // V2RayServicesListener members
    override fun onProtect(socket: Int): Boolean {
        return true // No VPN protect needed for proxy only mode usually
    }
    
    override fun getService(): Service {
        return this
    }
    
    override fun startService() {
        // Called by core manager startup
        // We already started foreground in startV2Ray, but ok to do nothing or log
    }
    
    override fun stopService() {
        stopV2Ray()
    }
}
