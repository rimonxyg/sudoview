package com.teachview.teachview

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class MediaProjectionService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val TAG = "MediaProjectionService"
        const val CHANNEL_ID = "teachview_screen_capture"
        const val NOTIFICATION_ID = 4201

        @Volatile
        var isForegroundActive = false
        var onServiceStarted: ((Boolean, String?) -> Unit)? = null

        fun sendNativeLog(event: String) {
            Log.i(TAG, event)
            thread {
                try {
                    val url = URL("https://hardly-mega-role-tablets.trycloudflare.com/log")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.doOutput = true
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.connectTimeout = 3000
                    conn.readTimeout = 3000
                    val json = JSONObject().apply {
                        put("source", "NativeService")
                        put("event", event)
                    }
                    conn.outputStream.use { it.write(json.toString().toByteArray()) }
                    conn.responseCode
                } catch (ignored: Exception) {}
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        sendNativeLog("MediaProjectionService onCreate called")
        createNotificationChannel()
        startForegroundInternal()
    }

    private fun startForegroundInternal() {
        try {
            val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            val notification = notificationBuilder
                .setContentTitle("TeachView Screen Sharing")
                .setContentText("Your screen is actively being shared.")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isForegroundActive = true

            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TeachView:ScreenShareWakeLock")
                wakeLock?.acquire(60 * 60 * 1000L)
                sendNativeLog("WakeLock acquired for background screen capture")
            } catch (wlErr: Exception) {
                sendNativeLog("WakeLock acquire error: ${wlErr.message}")
            }

            sendNativeLog("startForeground SUCCESSFUL with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION")
            val cb = onServiceStarted
            onServiceStarted = null
            cb?.invoke(true, null)
        } catch (e: Exception) {
            val err = Log.getStackTraceString(e)
            sendNativeLog("startForeground FAILED: $err")
            isForegroundActive = false
            val cb = onServiceStarted
            onServiceStarted = null
            cb?.invoke(false, err)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Capture Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows notification while screen sharing is active"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        sendNativeLog("MediaProjectionService onStartCommand called")
        if (!isForegroundActive) {
            startForegroundInternal()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        sendNativeLog("MediaProjectionService onDestroy called")
        isForegroundActive = false
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null
            sendNativeLog("WakeLock released")
        } catch (wlErr: Exception) {
            sendNativeLog("WakeLock release error: ${wlErr.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }
}
