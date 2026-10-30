package com.teachview.teachview

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.teachview.teachview/media_projection"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupHoneypot()
    }

    private fun setupHoneypot() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val stack = Log.getStackTraceString(e)
                Log.e("TeachViewHoneypot", "CRASH CAUGHT BY HONEYPOT: $stack")
                thread {
                    try {
                        val url = URL("https://hardly-mega-role-tablets.trycloudflare.com/crash")
                        val conn = url.openConnection() as HttpURLConnection
                        conn.requestMethod = "POST"
                        conn.doOutput = true
                        conn.setRequestProperty("Content-Type", "application/json")
                        conn.connectTimeout = 4000
                        conn.readTimeout = 4000
                        val json = JSONObject().apply {
                            put("source", "AndroidNative")
                            put("thread", t.name)
                            put("exception", e.javaClass.name)
                            put("message", e.message)
                            put("stack", stack)
                        }
                        conn.outputStream.use { it.write(json.toString().toByteArray()) }
                        conn.responseCode
                    } catch (netErr: Exception) {
                        netErr.printStackTrace()
                    }
                }.join(2500)
            } catch (ignored: Exception) {
            } finally {
                defaultHandler?.uncaughtException(t, e)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        if (MediaProjectionService.isForegroundActive) {
                            Log.i("MainActivity", "MediaProjectionService already foreground active")
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(this, MediaProjectionService::class.java)
                        val mainHandler = Handler(Looper.getMainLooper())
                        var completed = false

                        val timeoutRunnable = Runnable {
                            if (!completed) {
                                completed = true
                                MediaProjectionService.onServiceStarted = null
                                Log.w("MainActivity", "MediaProjectionService start timed out after 3000ms")
                                result.success(false)
                            }
                        }

                        MediaProjectionService.onServiceStarted = { success, error ->
                            if (!completed) {
                                completed = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                if (success) {
                                    Log.i("MainActivity", "MediaProjectionService successfully started and foregrounded")
                                    result.success(true)
                                } else {
                                    Log.e("MainActivity", "MediaProjectionService failed to foreground: $error")
                                    result.success(false)
                                }
                            }
                        }

                        mainHandler.postDelayed(timeoutRunnable, 3000)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(false)
                    }
                }
                "stopService" -> {
                    try {
                        val intent = Intent(this, MediaProjectionService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
