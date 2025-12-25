package com.flaming.cherubim

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.v2ray.dan.V2RayVPNService

/**
 * Implementation of App Widget functionality.
 */
class ConnectWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_WIDGET_CONNECT = "com.flaming.cherubim.action.WIDGET_CONNECT"
        const val ACTION_WIDGET_DISCONNECT = "com.flaming.cherubim.action.WIDGET_DISCONNECT"
        const val ACTION_UPDATE_WIDGET_STATE = "com.flaming.cherubim.action.UPDATE_WIDGET_STATE"
        const val PREFS_NAME = "WidgetPrefs"
        const val PREF_IS_CONNECTED = "is_connected"
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        // There may be multiple widgets active, so update all of them
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        // Enter relevant functionality for when the first widget is created
    }

    override fun onDisabled(context: Context) {
        // Enter relevant functionality for when the last widget is disabled
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == ACTION_WIDGET_CONNECT) {
            // Open App to Connect
            // We open the app because the connection logic (config generation, etc.) is complex and handled in Flutter
            val appIntent = Intent(context, MainActivity::class.java)
            appIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            // Optionally add an extra to tell Flutter to auto-connect if we wanted to be fancy, 
            // but for now just opening the app is safer as per plan.
            context.startActivity(appIntent)
        } else if (intent.action == ACTION_WIDGET_DISCONNECT) {
            // Stop Service directly
            val stopIntent = Intent(context, V2RayVPNService::class.java)
            stopIntent.action = V2RayVPNService.ACTION_STOP_VPN
            context.startService(stopIntent)
            
            // Also update state locally immediately for better responsiveness
            setConnectedState(context, false)
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, ConnectWidgetProvider::class.java))
            for (id in ids) {
                updateAppWidget(context, appWidgetManager, id)
            }
        } else if (intent.action == ACTION_UPDATE_WIDGET_STATE) {
            val isConnected = intent.getBooleanExtra("is_connected", false)
            setConnectedState(context, isConnected)
            
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, ConnectWidgetProvider::class.java))
            for (id in ids) {
                updateAppWidget(context, appWidgetManager, id)
            }
        }
    }
}

private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
    val isConnected = getConnectedState(context)

    val views = RemoteViews(context.packageName, R.layout.widget_connect)
    
    if (isConnected) {
        views.setTextViewText(R.id.widget_text, "DISCONNECT")
        views.setTextColor(R.id.widget_text, 0xFFFFFFFF.toInt()) // White text
        views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_background_connected) // Red bg
        
        // Action: Disconnect
        val intent = Intent(context, ConnectWidgetProvider::class.java)
        intent.action = ConnectWidgetProvider.ACTION_WIDGET_DISCONNECT
        val pendingIntent = PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
    } else {
        views.setTextViewText(R.id.widget_text, "CONNECT")
        views.setTextColor(R.id.widget_text, 0xFF000000.toInt()) // Black text
        views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_background) // White bg
        
        // Action: Connect (Open App)
        val intent = Intent(context, ConnectWidgetProvider::class.java)
        intent.action = ConnectWidgetProvider.ACTION_WIDGET_CONNECT
        val pendingIntent = PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
    }

    // Instruct the widget manager to update the widget
    appWidgetManager.updateAppWidget(appWidgetId, views)
}

private fun setConnectedState(context: Context, isConnected: Boolean) {
    val prefs = context.getSharedPreferences(ConnectWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
    prefs.edit().putBoolean(ConnectWidgetProvider.PREF_IS_CONNECTED, isConnected).apply()
}

private fun getConnectedState(context: Context): Boolean {
    val prefs = context.getSharedPreferences(ConnectWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
    return prefs.getBoolean(ConnectWidgetProvider.PREF_IS_CONNECTED, false)
}
