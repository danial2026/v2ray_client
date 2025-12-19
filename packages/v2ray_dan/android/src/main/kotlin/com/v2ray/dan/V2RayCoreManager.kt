package com.v2ray.dan

import android.app.Service
import android.util.Log
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import libv2ray.V2RayProtector

object V2RayCoreManager {
    private const val TAG = "V2RayCoreManager"
    private var coreController: CoreController? = null
    var listener: V2RayServicesListener? = null
    var isInitialized = false
    var isCoreRunning = false

    fun setUpListener(service: Service) {
        if (service is V2RayServicesListener) {
            listener = service as V2RayServicesListener
            
            // Initialize Core Env
            Libv2ray.initCoreEnv(service.applicationContext.filesDir.absolutePath, "")
            
            // Register Protector
            Libv2ray.useProtector(object : V2RayProtector {
                override fun protect(fd: Long): Boolean {
                    return listener?.onProtect(fd.toInt()) ?: true
                }
            })
            
            // Initialize Controller
            coreController = Libv2ray.newCoreController(object : CoreCallbackHandler {
                override fun onEmitStatus(p0: Long, p1: String?): Long {
                    if (p1 != null) {
                        Utilities.broadcastLog(service.applicationContext, p1, "INFO")
                    }
                    return 0
                }
                
                override fun shutdown(): Long {
                    Utilities.broadcastLog(service.applicationContext, "Core: shutdown() callback received", "INFO")
                    if (listener is Service) {
                        try {
                           (listener as Service).stopSelf()
                        } catch (e: Exception) {}
                    }
                    listener?.stopService()
                    return 0
                }
                
                override fun startup(): Long {
                    Utilities.broadcastLog(service.applicationContext, "Core: startup() callback received", "INFO")
                    listener?.startService()
                    return 0
                }
            })
            
            isInitialized = true
        }
    }

    fun startCore(config: V2rayConfig): Boolean {
        if (isCoreRunning) {
            Log.w(TAG, "Core already running")
            return true
        }
        
        if (!isInitialized || coreController == null) {
            Log.e(TAG, "Core not initialized")
            return false
        }
        
        try {
            // Set protector server if possible (optional)
            // Libv2ray.setProtectorServer(...) 
            
            coreController?.startLoop(config.V2RAY_FULL_JSON_CONFIG)
            isCoreRunning = true
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start core: ${e.message}")
            return false
        }
    }

    fun stopCore() {
        try {
            coreController?.stopLoop()
            isCoreRunning = false
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop core: ${e.message}")
        }
    }
}
