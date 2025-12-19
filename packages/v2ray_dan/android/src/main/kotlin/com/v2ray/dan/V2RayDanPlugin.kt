package com.v2ray.dan

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import java.util.ArrayList
import android.net.VpnService
import android.app.Activity
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

class V2RayDanPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
  private lateinit var channel : MethodChannel
  private lateinit var logChannel : MethodChannel
  private lateinit var eventChannel: EventChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  private var pendingPermissionResult: Result? = null
  private var eventSink: EventChannel.EventSink? = null
  
  private val REQUEST_CODE_VPN_PERMISSION = 24

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "v2ray_dan")
    channel.setMethodCallHandler(this)
    
    // Log channel
    logChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.v2ray.v2ray/logs")
    
    // Register BroadcastReceiver for logs and status
    val filter = android.content.IntentFilter()
    filter.addAction("com.v2ray.dan.LOG")
    filter.addAction("com.v2ray.dan.STATUS")
    
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
        context.registerReceiver(broadcastReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
        context.registerReceiver(broadcastReceiver, filter)
    }
    
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "v2ray_dan/status")
    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            // Send current status immediately
            val currentStatus = if (V2RayCoreManager.isCoreRunning) "connected" else "disconnected"
            eventSink?.success(currentStatus)
        }
        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    })
  }

  private val broadcastReceiver = object : android.content.BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
          when (intent?.action) {
              "com.v2ray.dan.LOG" -> {
                  val message = intent.getStringExtra("message")
                  val level = intent.getStringExtra("level") ?: "INFO"
                  if (message != null) {
                      val args = mapOf("message" to message, "level" to level)
                      android.os.Handler(android.os.Looper.getMainLooper()).post {
                          logChannel.invokeMethod("log", args)
                      }
                  }
              }
              "com.v2ray.dan.STATUS" -> {
                  val status = intent.getStringExtra("status")
                  if (status != null) {
                      android.os.Handler(android.os.Looper.getMainLooper()).post {
                          eventSink?.success(status)
                      }
                  }
              }
          }
      }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "initialize") {
        // Handle initialization
        val iconName = call.argument<String>("iconName")
        // Resolve icon resource ID
        val resId = context.resources.getIdentifier(iconName, "drawable", context.packageName)
        AppConfigs.APPLICATION_ICON = if (resId != 0) resId else android.R.drawable.sym_def_app_icon
        result.success(context.filesDir.absolutePath)
        
    } else if (call.method == "startV2Ray") {
        val config = call.argument<String>("config")
        val remark = call.argument<String>("remark")
        val proxyOnly = call.argument<Boolean>("proxyOnly") ?: false
        val useSystemDns = call.argument<Boolean>("useSystemDns") ?: true
        val bypassSubnets = call.argument<ArrayList<String>>("bypassSubnets")
        val blockedApps = call.argument<ArrayList<String>>("blockedApps")
                
        AppConfigs.V2RAY_CONFIG = V2rayConfig(
            REMARK = remark ?: "",
            V2RAY_FULL_JSON_CONFIG = config ?: "",
            BYPASS_SUBNETS = bypassSubnets,
            BLOCKED_APPS = blockedApps,
            LOCAL_SOCKS5_PORT = AppConfigs.PORT_SOCKS,
            LOCAL_HTTP_PORT = AppConfigs.PORT_HTTP,
            USE_SYSTEM_DNS = useSystemDns
        )

        // Log the received configuration for verification
        android.util.Log.d("V2RayDAN", "Plugin: Received Config - Remark: $remark, ProxyOnly: $proxyOnly")
        android.util.Log.d("V2RayDAN", "Plugin: Config JSON: $config")
        Utilities.broadcastLog(context, "Plugin: Received config for server '$remark' (proxyOnly: $proxyOnly)", "DEBUG")
        Utilities.broadcastLog(context, "Plugin: Config JSON (first 500 chars): ${config?.take(500)}...", "DEBUG")
        AppConfigs.V2RAY_CONNECTION_MODE = if (proxyOnly) AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY else AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN
        
        // Clear log files before starting
        try {
            java.io.File(context.filesDir, "access.log").delete()
            java.io.File(context.filesDir, "error.log").delete()
        } catch (e: Exception) {}

        Utilities.broadcastLog(context, "Plugin: startV2Ray called (mode: ${AppConfigs.V2RAY_CONNECTION_MODE})", "INFO")
        
        val intent = Intent(context, if (proxyOnly) V2RayProxyOnlyService::class.java else V2RayVPNService::class.java)
        intent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        result.success(true)
        
    } else if (call.method == "stopV2Ray") {
         Utilities.broadcastLog(context, "Plugin: stopV2Ray called", "INFO")
         val intent = Intent(context, if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY) V2RayProxyOnlyService::class.java else V2RayVPNService::class.java)
         intent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE)
         context.startService(intent)
         result.success(null)
         
    } else if (call.method == "requestPermission") {
        val intent = VpnService.prepare(context)
        if (intent != null) {
            activity?.startActivityForResult(intent, REQUEST_CODE_VPN_PERMISSION)
            pendingPermissionResult = result
        } else {
            result.success(true)
        }
        
    } else if (call.method == "getCoreVersion") {
        result.success("Custom V2Ray Core")
        
    } else if (call.method == "getLogs") {
        val logs = mutableListOf<String>()
        try {
            val accessLog = java.io.File(context.filesDir, "access.log")
            if (accessLog.exists()) {
                logs.add("--- Access Logs ---")
                logs.addAll(accessLog.readLines().takeLast(100))
            }
            val errorLog = java.io.File(context.filesDir, "error.log")
            if (errorLog.exists()) {
                logs.add("--- Error Logs ---")
                logs.addAll(errorLog.readLines().takeLast(100))
            }
        } catch (e: Exception) {
            logs.add("Error reading log files: ${e.message}")
        }
        result.success(logs)
        
    } else if (call.method == "getSystemDns") {
        result.success(Utilities.getSystemDnsServers(context))
        
    } else if (call.method == "isIgnoringBatteryOptimizations") {
        val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
        
    } else if (call.method == "requestIgnoreBatteryOptimizations") {
        try {
            val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = android.net.Uri.parse("package:${context.packageName}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
        
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context.unregisterReceiver(broadcastReceiver)
    channel.setMethodCallHandler(null)
  }
  
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addActivityResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() { activity = null }
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
  override fun onDetachedFromActivity() { activity = null }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode == REQUEST_CODE_VPN_PERMISSION) {
        if (resultCode == Activity.RESULT_OK) {
            pendingPermissionResult?.success(true)
        } else {
            pendingPermissionResult?.success(false)
        }
        pendingPermissionResult = null
        return true
    }
    return false
  }
}
