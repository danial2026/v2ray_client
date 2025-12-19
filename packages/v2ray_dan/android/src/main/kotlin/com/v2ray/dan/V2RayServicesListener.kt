package com.v2ray.dan

import android.app.Service

interface V2RayServicesListener {
    fun onProtect(socket: Int): Boolean
    fun getService(): Service
    fun startService()
    fun stopService()
}
