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
 * Circle Widget - A circular variant of the connection widget
 */
class CircleWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_WIDGET_CONNECT = "com.flaming.cherubim.action.CIRCLE_WIDGET_CONNECT"
        const val ACTION_WIDGET_DISCONNECT = "com.flaming.cherubim.action.CIRCLE_WIDGET_DISCONNECT"
        const val ACTION_UPDATE_WIDGET_STATE = "com.flaming.cherubim.action.UPDATE_WIDGET_STATE"
        const val PREFS_NAME = "CircleWidgetPrefs"
        const val PREF_IS_CONNECTED = "is_connected"
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
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
            val appIntent = Intent(context, MainActivity::class.java)
            appIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            context.startActivity(appIntent)
        } else if (intent.action == ACTION_WIDGET_DISCONNECT) {
            // Stop Service directly
            val stopIntent = Intent(context, V2RayVPNService::class.java)
            stopIntent.action = V2RayVPNService.ACTION_STOP_VPN
            context.startService(stopIntent)
            
            // Update state locally
            setConnectedState(context, false)
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, CircleWidgetProvider::class.java))
            for (id in ids) {
                updateAppWidget(context, appWidgetManager, id)
            }
        } else if (intent.action == ACTION_UPDATE_WIDGET_STATE) {
            val isConnected = intent.getBooleanExtra("is_connected", false)
            setConnectedState(context, isConnected)
            
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, CircleWidgetProvider::class.java))
            for (id in ids) {
                updateAppWidget(context, appWidgetManager, id)
            }
        }
    }
}

private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
    val isConnected = getConnectedState(context)

    val views = RemoteViews(context.packageName, R.layout.widget_circle)
    
    if (isConnected) {
        views.setTextViewText(R.id.widget_text, "DISCONNECT")
        views.setTextColor(R.id.widget_text, 0xFFFFFFFF.toInt()) // White text
        views.setImageViewResource(R.id.widget_circle_bg, R.drawable.widget_background_circle_connected)
        
        // Action: Disconnect
        val intent = Intent(context, CircleWidgetProvider::class.java)
        intent.action = CircleWidgetProvider.ACTION_WIDGET_DISCONNECT
        val pendingIntent = PendingIntent.getBroadcast(context, 1, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
    } else {
        views.setTextViewText(R.id.widget_text, "CONNECT")
        views.setTextColor(R.id.widget_text, 0xFF000000.toInt()) // Black text
        views.setImageViewResource(R.id.widget_circle_bg, R.drawable.widget_background_circle)
        
        // Action: Connect (Open App)
        val intent = Intent(context, CircleWidgetProvider::class.java)
        intent.action = CircleWidgetProvider.ACTION_WIDGET_CONNECT
        val pendingIntent = PendingIntent.getBroadcast(context, 1, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
    }

    appWidgetManager.updateAppWidget(appWidgetId, views)
}

private fun setConnectedState(context: Context, isConnected: Boolean) {
    val prefs = context.getSharedPreferences(CircleWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
    prefs.edit().putBoolean(CircleWidgetProvider.PREF_IS_CONNECTED, isConnected).apply()
}

private fun getConnectedState(context: Context): Boolean {
    val prefs = context.getSharedPreferences(CircleWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
    return prefs.getBoolean(CircleWidgetProvider.PREF_IS_CONNECTED, false)
}
