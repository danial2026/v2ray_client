package com.v2ray.v2ray

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
    private val VPN_PERMISSION_CHANNEL = "com.v2ray.v2ray/vpn_permission"
    private val LOG_CHANNEL = "com.v2ray.v2ray/logs"
    private val VPN_REQUEST_CODE = 1001
    
    private var vpnMethodChannel: MethodChannel? = null
    private var logChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        sendLog("INFO", "Configuring Flutter engine...")
        
        // Setup VPN permission channel
        vpnMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VPN_PERMISSION_CHANNEL
        )
        
        vpnMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestVpnPermission" -> {
                    sendLog("INFO", "VPN permission requested from Flutter")
                    requestVpnPermission(result)
                }
                else -> {
                    sendLog("WARN", "Unknown VPN method called: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        // Setup logging bridge channel
        logChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOG_CHANNEL
        )
        
        sendLog("INFO", "✓ Flutter engine configured successfully")
        sendLog("INFO", "✓ VPN permission channel: $VPN_PERMISSION_CHANNEL")
        sendLog("INFO", "✓ Logging bridge channel: $LOG_CHANNEL")
        sendLog("INFO", "Android version: ${Build.VERSION.SDK_INT} (${Build.VERSION.RELEASE})")
        sendLog("INFO", "Device: ${Build.MANUFACTURER} ${Build.MODEL}")
    }
    
    // Send log message to Flutter via MethodChannel
    private fun sendLog(level: String, message: String) {
        val fullMessage = "[Android] $message"
        
        // Log to Android logcat
        when (level) {
            "ERROR" -> Log.e(TAG, fullMessage)
            "WARN" -> Log.w(TAG, fullMessage)
            "DEBUG" -> Log.d(TAG, fullMessage)
            else -> Log.i(TAG, fullMessage)
        }
        
        // Send to Flutter
        try {
            logChannel?.invokeMethod("log", mapOf(
                "level" to level,
                "message" to fullMessage
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send log to Flutter: ${e.message}")
        }
    }
    
    private fun requestVpnPermission(result: MethodChannel.Result) {
        try {
            sendLog("INFO", "========== VPN Permission Request ==========")
            sendLog("INFO", "Checking VPN permission status...")
            
            val intent = VpnService.prepare(this)
            
            if (intent != null) {
                //Permission not granted
                sendLog("WARN", "VPN permission NOT granted - requesting user approval")
                sendLog("INFO", "Launching VPN permission dialog...")
                pendingResult = result
                startActivityForResult(intent, VPN_REQUEST_CODE)
            } else {
                // Already granted
                sendLog("INFO", "✓ VPN permission ALREADY granted")
                sendLog("INFO", "========== VPN Permission: GRANTED ==========")
                result.success(true)
            }
        } catch (e: Exception) {
            sendLog("ERROR", "========== VPN Permission: FAILED ==========")
            sendLog("ERROR", "Exception requesting VPN permission: ${e.message}")
            sendLog("ERROR", "Stack trace: ${e.stackTraceToString()}")
            result.error("VPN_PERMISSION_ERROR", e.message, e.toString())
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        sendLog("DEBUG", "onActivityResult: requestCode=$requestCode, resultCode=$resultCode")
        
        if (requestCode == VPN_REQUEST_CODE) {
            val granted = resultCode == Activity.RESULT_OK
            
            sendLog("INFO", "========== VPN Permission Result ==========")
            if (granted) {
                sendLog("INFO", "✓ VPN permission GRANTED by user")
            } else {
                sendLog("WARN", "✗ VPN permission DENIED by user")
            }
            sendLog("INFO", "=========================================")
            
            pendingResult?.let { result ->
                try {
                    result.success(granted)
                    sendLog("DEBUG", "Permission result sent to Flutter: $granted")
                } catch (e: Exception) {
                    sendLog("ERROR", "Error sending permission result to Flutter: ${e.message}")
                }
                pendingResult = null
            } ?: run {
                sendLog("WARN", "No pending result found for VPN permission")
            }
        }
    }
    
    override fun onDestroy() {
        sendLog("INFO", "MainActivity destroying - cleaning up channels")
        super.onDestroy()
        vpnMethodChannel?.setMethodCallHandler(null)
        logChannel?.setMethodCallHandler(null)
        vpnMethodChannel = null
        logChannel = null
        pendingResult = null
        sendLog("INFO", "MainActivity destroyed")
    }
}
