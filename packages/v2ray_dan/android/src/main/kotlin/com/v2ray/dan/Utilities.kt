package com.v2ray.dan

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.ArrayList

object Utilities {
    fun copyAssets(context: Context) {
        val assetManager = context.assets
        val files = arrayOf("geosite.dat", "geoip.dat")
        for (filename in files) {
            var input: InputStream? = null
            var output: FileOutputStream? = null
            try {
                input = assetManager.open(filename)
                val outFile = File(context.filesDir, filename)
                output = FileOutputStream(outFile)
                copyFile(input, output)
            } catch (e: IOException) {
                // Ignore if asset missing
            } finally {
                input?.close()
                output?.close()
            }
        }
    }

    private fun copyFile(input: InputStream, output: FileOutputStream) {
        val buffer = ByteArray(1024)
        var read: Int
        while (input.read(buffer).also { read = it } != -1) {
            output.write(buffer, 0, read)
        }
    }
    
    fun parseV2rayJsonFile(
        remark: String,
        config: String,
        blockedApps: ArrayList<String>?,
        bypassSubnets: ArrayList<String>?
    ): V2rayConfig {
        return V2rayConfig(
            REMARK = remark,
            V2RAY_FULL_JSON_CONFIG = config,
            BLOCKED_APPS = blockedApps,
            BYPASS_SUBNETS = bypassSubnets
        )
    }

    fun broadcastLog(context: Context, message: String, level: String = "INFO") {
        // Also log to logcat for adb visibility
        android.util.Log.d("V2RayDAN", "[$level] $message")
        
        val intent = android.content.Intent("com.v2ray.dan.LOG")
        intent.putExtra("message", message)
        intent.putExtra("level", level)
        intent.setPackage(context.packageName)
        context.sendBroadcast(intent)
    }

    fun broadcastStatus(context: Context, status: String) {
        android.util.Log.d("V2RayDAN", "Status: $status")
        val intent = android.content.Intent("com.v2ray.dan.STATUS")
        intent.putExtra("status", status)
        intent.setPackage(context.packageName)
        context.sendBroadcast(intent)
    }

    fun getSystemDnsServers(context: Context): List<String> {
        val dnsServers = mutableListOf<String>()
        try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val activeNetwork = connectivityManager.activeNetwork
                val linkProperties = connectivityManager.getLinkProperties(activeNetwork)
                linkProperties?.dnsServers?.forEach { 
                    if (it is java.net.Inet4Address) { 
                        dnsServers.add(it.hostAddress ?: "")
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("V2RayDAN", "Error getting system DNS: ${e.message}")
        }
        return dnsServers.filter { it.isNotEmpty() }
    }
}
