package com.lmclient.keepalive

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class LmKeepalivePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        private const val CHANNEL = "lmclient/keepalive"
        // True from the moment a start request is accepted until a stop is sent. `KeepAliveService.running` only turns
        // true once the service has actually reached startForeground(), so a stop sent in between must not be skipped.
        @Volatile private var wanted = false
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("no_context", "plugin is not attached", null)
            return
        }
        when (call.method) {
            "start", "update" -> {
                val i = Intent(ctx, KeepAliveService::class.java)
                i.putExtra("title", call.argument<String>("title") ?: "LMClient")
                i.putExtra("text", call.argument<String>("text") ?: "")
                try {
                    if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
                    wanted = true
                    result.success(true)
                } catch (e: Exception) {
                    // Android 12+ refuses to start a foreground service while the app is in the background.
                    result.success(false)
                }
            }
            "stop" -> {
                try {
                    if (wanted || KeepAliveService.running) {
                        wanted = false
                        val i = Intent(ctx, KeepAliveService::class.java)
                        i.action = KeepAliveService.ACTION_STOP
                        // Sent as a foreground start too: the service answers every command with startForeground()
                        // before it stops, so this can never leave an unanswered foreground request behind.
                        if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "isRunning" -> result.success(KeepAliveService.running)
            "notificationsAllowed" -> result.success(notificationsAllowed(ctx))
            "requestNotifications" -> {
                val a = activity
                if (a != null && Build.VERSION.SDK_INT >= 33) {
                    a.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7002)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun notificationsAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            return ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.areNotificationsEnabled()
    }
}
