package com.v2ray.dan

import java.util.ArrayList

object AppConfigs {
    const val V2RAY_CONFIG_TAG = "V2RAY_CONFIG"
    var APPLICATION_ICON = 0
    var APPLICATION_NAME = ""
    var V2RAY_STATE = V2RAY_STATES.V2RAY_DISCONNECTED
    var V2RAY_CONFIG: V2rayConfig? = null
    var V2RAY_CONNECTION_MODE = V2RAY_CONNECTION_MODES.VPN_TUN
    
    // Default ports
    const val PORT_HTTP = 10809
    const val PORT_SOCKS = 10808
    
    const val NOTIFICATION_DISCONNECT_BUTTON_NAME = "DISCONNECT"
    
    // Command Constants
    object V2RAY_SERVICE_COMMANDS {
        const val START_SERVICE = 1
        const val STOP_SERVICE = 2
        const val MEASURE_DELAY = 3
    }

    enum class V2RAY_STATES {
        V2RAY_CONNECTED,
        V2RAY_DISCONNECTED,
        V2RAY_CONNECTING
    }
    
    enum class V2RAY_CONNECTION_MODES {
        VPN_TUN,
        PROXY_ONLY
    }
}

data class V2rayConfig(
    var REMARK: String = "",
    var V2RAY_FULL_JSON_CONFIG: String = "",
    var BYPASS_SUBNETS: ArrayList<String>? = null,
    var BLOCKED_APPS: ArrayList<String>? = null,
    var APPLICATION_ICON: Int = 0,
    var APPLICATION_NAME: String = "",
    var LOCAL_SOCKS5_PORT: Int = 10808,
    var LOCAL_HTTP_PORT: Int = 10809,
    var NOTIFICATION_DISCONNECT_BUTTON_NAME: String = "DISCONNECT",
    var USE_SYSTEM_DNS: Boolean = true
)
