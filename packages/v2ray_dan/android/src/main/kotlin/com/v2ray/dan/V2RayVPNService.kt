package com.v2ray.dan

import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.util.Log
import java.io.File
import java.io.FileDescriptor
import java.util.ArrayList
import java.util.Arrays
import android.app.Notification
import android.content.Context
import android.os.PowerManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import androidx.core.app.NotificationCompat
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import java.net.InetAddress
import java.net.Inet4Address

class V2RayVPNService : VpnService(), V2RayServicesListener {
    private val TAG = "V2RayVPNService"
    private var mInterface: ParcelFileDescriptor? = null
    private var process: Process? = null
    @Volatile
    private var isRunning = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var setupTimeoutHandler: android.os.Handler? = null
    private var setupTimeoutRunnable: Runnable? = null

    companion object {
        const val ACTION_STOP_VPN = "com.v2ray.dan.action.STOP_VPN"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val command = intent?.getIntExtra("COMMAND", 0)
        Log.i(TAG, "onStartCommand: command=$command action=${intent?.action}")
        Utilities.broadcastLog(this, "Service: onStartCommand (cmd: $command)", "INFO")
        
        if (intent?.action == ACTION_STOP_VPN || command == AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE) {
            Utilities.broadcastLog(this, "Service: Stopping service command received", "INFO")
            Utilities.broadcastStatus(this, "disconnecting")
            isRunning = false // Stop supervisor loops first
            stopAllProcess()
            Utilities.broadcastStatus(this, "disconnected")
            stopSelf()
            return Service.START_NOT_STICKY
        }
        if (command == AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE) {
            Utilities.copyAssets(this)
            V2RayCoreManager.setUpListener(this)
            val config = AppConfigs.V2RAY_CONFIG
            if (config != null) {
                Utilities.broadcastStatus(this, "connecting")
                Utilities.broadcastLog(this, "Service: Starting V2Ray Core", "INFO")
                
                // Log parameters for verification
                android.util.Log.d("V2RayDAN", "Service: Start core - Remark: ${config.REMARK}, Config Length: ${config.V2RAY_FULL_JSON_CONFIG.length}")
                Utilities.broadcastLog(this, "Service: Using config for server '${config.REMARK}'", "DEBUG")
                
                V2RayCoreManager.startCore(config)
                
                // FALLBACK: If core doesn't call startup() within 5 seconds, try to setup anyway
                // This ensures VPN interface is established even if core lifecycle is weird
                // CRITICAL: Store handler reference so we can cancel it on disconnect
                setupTimeoutRunnable = Runnable {
                    if (!isRunning) {
                        Utilities.broadcastLog(this, "Service: Core callback timeout - triggering setup fallback", "WARN")
                        setup()
                    }
                }
                setupTimeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
                setupTimeoutHandler?.postDelayed(setupTimeoutRunnable!!, 5000)
                
            } else {
                Utilities.broadcastLog(this, "Service: Config is null, cannot start", "ERROR")
            }
        }
        return Service.START_STICKY
    }
    
    // V2RayServicesListener implementation
    override fun onProtect(socket: Int): Boolean {
        return protect(socket)
    }
    
    override fun getService(): Service {
        return this
    }
    
    override fun startService() {
        setup()
    }
    
    override fun stopService() {
        stopAllProcess()
    }

    private fun createNotification(): Notification {
        val channelId = "V2RAY_VPN_CHANNEL"
        val channelName = "V2Ray VPN Service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_LOW)
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
        
        val disconnectIntent = Intent(this, V2RayVPNService::class.java)
        disconnectIntent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getService(this, 0, disconnectIntent, flags)

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Flaming Cherubim: ${AppConfigs.V2RAY_CONFIG?.REMARK ?: "Connected"}")
            .setContentText("Connected to ${AppConfigs.V2RAY_CONFIG?.REMARK ?: "secure server"}")
            .setSmallIcon(AppConfigs.APPLICATION_ICON)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "DISCONNECT", pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun setup() {
        Utilities.broadcastLog(this, "Service: setup() starting", "INFO")
        val config = AppConfigs.V2RAY_CONFIG
        if (config == null) {
            Utilities.broadcastLog(this, "Service: setup failed - config is null", "ERROR")
            stopSelf()
            return
        }

        // CRITICAL: Must be called within 5 seconds of startForegroundService
        try {
            startForeground(1, createNotification())
            Utilities.broadcastLog(this, "Service: startForeground called", "INFO")
            broadcastWidgetState(true) // Notify widget
        } catch (e: Exception) {
            Utilities.broadcastLog(this, "Service: startForeground failed: ${e.message}", "ERROR")
        }

        // Prepare VPN
        Utilities.broadcastLog(this, "Service: Establishing VPN Interface...", "INFO")
        val builder = Builder()
        builder.setSession(config.REMARK)
        builder.setMtu(1500)
        builder.addAddress("172.19.0.1", 30)
        builder.addRoute("0.0.0.0", 0)
        
        /* IPv6 disabled to prevent leaks/resets on dual-stack networks for now */
        // builder.addAddress("fd00:1::1", 128)
        // builder.addRoute("::", 0)

        
        // DNS
        if (config.USE_SYSTEM_DNS) {
            val systemDnsChannels = Utilities.getSystemDnsServers(this)
            if (systemDnsChannels.isNotEmpty()) {
                systemDnsChannels.forEach { dns ->
                    try {
                        builder.addDnsServer(dns)
                        Utilities.broadcastLog(this, "Service: Added System DNS: $dns", "DEBUG")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to add system DNS: $dns")
                    }
                }
            } else {
                // Fallback if no system DNS found
                builder.addDnsServer("1.1.1.1")
                builder.addDnsServer("8.8.8.8")
                Utilities.broadcastLog(this, "Service: No System DNS found, using Fallback (Cloudflare/Google)", "WARN")
            }
        } else {
            try {
                builder.addDnsServer("1.1.1.1")
                builder.addDnsServer("8.8.8.8")
                Utilities.broadcastLog(this, "Service: Custom DNS servers added", "DEBUG")
            } catch (e: Exception) {
                Utilities.broadcastLog(this, "Service: addDnsServer error: ${e.message}", "WARN")
            }
        }

        // Bypassed Subnets - NOTE: In VpnService, addRoute INCLUDES the subnet. 
        // To bypass, we should NOT add the route, but since we have 0.0.0.0/0, everything is covered.
        // True bypass requires excluded routes (API 33+) or complex route math.
        // For now, we log that bypass subnets are being ignored as they are covered by 0.0.0.0/0
        if (!config.BYPASS_SUBNETS.isNullOrEmpty()) {
            Utilities.broadcastLog(this, "Service: Bypass subnets requested (Note: fully bypassing requires complex routing)", "WARN")
        }

        // Blocked / Disallowed Apps
        config.BLOCKED_APPS?.forEach { appPackage ->
            try {
                if (appPackage != packageName) {
                    builder.addDisallowedApplication(appPackage)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to disallow app: $appPackage")
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        try {
            mInterface = builder.establish()
            if (mInterface == null) {
                val msg = "FATAL: VPN Interface establishment failed (returns null). Possible reasons: Missing VpnService.prepare() or config conflict."
                Log.e(TAG, msg)
                Utilities.broadcastLog(this, msg, "ERROR")
                stopAllProcess()
                return
            }
            isRunning = true
            
            // Acquire WakeLock to keep CPU alive in background
            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$TAG::WakeLock")
                wakeLock?.acquire()
                Utilities.broadcastLog(this, "WakeLock acquired", "DEBUG")
            } catch (e: Exception) {
                Utilities.broadcastLog(this, "Failed to acquire WakeLock: ${e.message}", "WARN")
            }
            
            Utilities.broadcastLog(this, "✓ VPN Interface established (FD: ${mInterface?.fd}). Starting Tun2Socks...", "INFO")
            Utilities.broadcastStatus(this, "connected")
            runTun2socks()
            
        } catch (e: Exception) {
            val msg = "FATAL: Failed to establish VPN interface: ${e.message}"
            Log.e(TAG, msg, e)
            Utilities.broadcastLog(this, msg, "ERROR")
            stopAllProcess()
        }
    }

    private fun runTun2socks() {
        if (!isRunning) return
        
        val config = AppConfigs.V2RAY_CONFIG ?: return
        val nativeDir = applicationInfo.nativeLibraryDir
        
        // Try multiple possible locations for tun2socks
        val possiblePaths = arrayOf(
            File(nativeDir, "libtun2socks.so"),
            File(nativeDir, "arm64-v8a/libtun2socks.so"),
            File(nativeDir, "arm64/libtun2socks.so"),
            File(nativeDir, "armeabi-v7a/libtun2socks.so"),
            File(filesDir, "libtun2socks.so")
        )
        
        var tun2socksFile: File? = null
        for (path in possiblePaths) {
            if (path.exists()) {
                tun2socksFile = path
                break
            }
        }
        
        if (tun2socksFile == null) {
             Utilities.broadcastLog(this, "FATAL: libtun2socks.so not found", "ERROR")
             return
        }
        
        val tun2socksPath = tun2socksFile.absolutePath
        val socksPort = config.LOCAL_SOCKS5_PORT
        val socketFile = File(filesDir, "sock_path")
        
        // CRITICAL: Cleanup old socket file to prevent "address already in use" errors
        if (socketFile.exists()) {
            socketFile.delete()
        }
        
        val cmd = ArrayList(Arrays.asList(
            tun2socksPath,
            "--netif-ipaddr", "172.19.0.2",
            "--netif-netmask", "255.255.255.252",
            "--socks-server-addr", "127.0.0.1:$socksPort",
            "--tunmtu", "1500",
            "--sock-path", socketFile.absolutePath,
            "--enable-udprelay",
            "--loglevel", "debug"
        ))

        Thread {
            while (isRunning) {
                try {
                    Utilities.broadcastLog(this, "Supervisor: Starting Tun2Socks...", "INFO")
                    val currentProcess = ProcessBuilder(cmd)
                        .redirectErrorStream(true)
                        .directory(filesDir)
                        .start()
                    
                    process = currentProcess
                    
                    // Start FD sender after a short delay to let tun2socks create the socket
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        if (isRunning) sendFileDescriptor()
                    }, 500)

                    // Monitor process output
                    try {
                        val reader = java.io.BufferedReader(java.io.InputStreamReader(currentProcess.inputStream))
                        var line: String?
                        while (true) {
                            line = reader.readLine()
                            if (line == null) break
                            Log.d("Tun2Socks", line)
                            Utilities.broadcastLog(this, "[Tun2Socks] $line", "INFO")
                        }
                    } catch (e: Exception) {
                        if (isRunning) {
                            Utilities.broadcastLog(this, "Tun2Socks read error: ${e.message}", "WARN")
                        }
                    }
                    
                    val exitCode = currentProcess.waitFor()
                    if (isRunning) {
                        val level = if (exitCode == 0) "INFO" else "ERROR"
                        Utilities.broadcastLog(this, "Supervisor: Tun2Socks exited with code $exitCode", level)
                    }
                    
                    if (!isRunning) break
                    
                    // Wait before restarting
                    Thread.sleep(3000)
                } catch (e: Exception) {
                    if (isRunning) {
                        Utilities.broadcastLog(this, "Supervisor error: ${e.message}", "ERROR")
                        Thread.sleep(5000)
                    } else {
                        break
                    }
                }
            }
            Utilities.broadcastLog(this, "Supervisor: Thread exiting", "INFO")
        }.start()
    }

    private fun sendFileDescriptor() {
        val fd = mInterface?.fileDescriptor ?: run {
            Utilities.broadcastLog(this, "sendFd: interface is null", "ERROR")
            return
        }
        val socketFile = File(filesDir, "sock_path").absolutePath
        Utilities.broadcastLog(this, "sendFd: Connecting to LocalSocket at $socketFile", "INFO")
        
        Thread {
            var tries = 0
            while (tries < 20) {
                try {
                    Thread.sleep(100L)
                    val clientSocket = LocalSocket()
                    clientSocket.connect(LocalSocketAddress(socketFile, LocalSocketAddress.Namespace.FILESYSTEM))
                    
                    if (clientSocket.isConnected) {
                        Utilities.broadcastLog(this, "sendFd: LocalSocket connected. Sending FD...", "INFO")
                        val outputStream = clientSocket.outputStream
                        clientSocket.setFileDescriptorsForSend(arrayOf(fd))
                        outputStream.write(32)
                        clientSocket.setFileDescriptorsForSend(null)
                        clientSocket.shutdownOutput()
                        clientSocket.close()
                        Utilities.broadcastLog(this, "✓ sendFd: FD sent successfully", "INFO")
                        break
                    }
                    clientSocket.close()
                } catch (e: Exception) {
                    if (tries % 5 == 0) {
                        Log.e(TAG, "sendFd attempt $tries failed: ${e.message}")
                        Utilities.broadcastLog(this, "sendFd attempt $tries: ${e.message}", "DEBUG")
                    }
                }
                tries++
            }
            if (tries >= 20) {
                Utilities.broadcastLog(this, "FATAL: sendFd failed after 20 attempts. Tun2Socks will not route traffic.", "ERROR")
            }
        }.start()
    }

    private fun stopAllProcess() {
        Utilities.broadcastLog(this, "Service: Cleanup started", "INFO")
        isRunning = false
        broadcastWidgetState(false) // Notify widget
        
        // CRITICAL: Cancel timeout handler to prevent spurious setup() after disconnect
        setupTimeoutRunnable?.let { runnable ->
            setupTimeoutHandler?.removeCallbacks(runnable)
            Utilities.broadcastLog(this, "Service: Cleanup - Cancelled timeout handler", "DEBUG")
        }
        setupTimeoutHandler = null
        setupTimeoutRunnable = null
        
        V2RayCoreManager.stopCore()
        
        try {
            if (process != null) {
                Utilities.broadcastLog(this, "Service: Cleanup - Killing Tun2Socks...", "DEBUG")
                process?.destroy()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    process?.destroyForcibly()
                }
            }
        } catch (e: Exception) {
            Utilities.broadcastLog(this, "Service: Cleanup - Failed to kill Tun2Socks: ${e.message}", "WARN")
        }
        process = null
        
        try {
            if (mInterface != null) {
                Utilities.broadcastLog(this, "Service: Cleanup - Closing VPN interface...", "INFO")
                mInterface?.close()
                Utilities.broadcastLog(this, "Service: Cleanup - VPN interface closed", "INFO")
            } else {
                Utilities.broadcastLog(this, "Service: Cleanup - VPN interface was already null", "DEBUG")
            }
        } catch (e: Exception) {
            Utilities.broadcastLog(this, "Service: Cleanup - Failed to close VPN interface: ${e.message}", "ERROR")
        }
        mInterface = null

        val socketFile = File(filesDir, "sock_path")
        if (socketFile.exists()) {
            socketFile.delete()
        }

        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Utilities.broadcastLog(this, "WakeLock released", "DEBUG")
            }
        } catch (e: Exception) {}
        wakeLock = null

        // CRITICAL: Remove foreground notification to signal system that VPN is done
        try {
            stopForeground(true)
            Utilities.broadcastLog(this, "Service: Foreground state removed", "INFO")
        } catch (e: Exception) {
             Utilities.broadcastLog(this, "Service: Failed to stopForeground: ${e.message}", "WARN")
        }
    }

    override fun onDestroy() {
        stopAllProcess()
        super.onDestroy()
    }

    private fun broadcastWidgetState(isConnected: Boolean) {
        try {
            val intent = Intent("com.v2ray.v2ray.action.UPDATE_WIDGET_STATE")
            intent.`package` = "com.v2ray.v2ray" // Target the app package specifically
            intent.putExtra("is_connected", isConnected)
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to broadcast widget state: ${e.message}")
        }
    }
}
