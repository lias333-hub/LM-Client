package com.lmclient.termux

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** Holds callbacks waiting for a Termux command result, keyed by request id. */
object TermuxBridgeRegistry {
    private val pending = ConcurrentHashMap<String, (Bundle?) -> Unit>()
    fun register(id: String, cb: (Bundle?) -> Unit) { pending[id] = cb }
    fun deliver(id: String, b: Bundle?) { pending.remove(id)?.invoke(b) }
    fun cancel(id: String) { pending.remove(id) }
}

/** Receives the PendingIntent result that Termux fires when a command finishes. */
class TermuxResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("lm_req") ?: return
        TermuxBridgeRegistry.deliver(id, intent.getBundleExtra("result"))
    }
}

class LmTermuxPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        private const val CHANNEL = "lmclient/termux"
        private const val TERMUX = "com.termux"
        private const val PERM = "com.termux.permission.RUN_COMMAND"
        private val reqCounter = AtomicInteger(1000)
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
        when (call.method) {
            "isInstalled" -> result.success(isTermuxInstalled())
            "hasPermission" -> result.success(hasRunPermission())
            "requestPermission" -> {
                val a = activity
                if (a != null && Build.VERSION.SDK_INT >= 23) {
                    a.requestPermissions(arrayOf(PERM), 7001)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "run" -> {
                val cmd = call.argument<String>("command") ?: ""
                val dir = call.argument<String>("workdir")
                val timeout = call.argument<Number>("timeoutMs")?.toLong() ?: 60000L
                runInTermux(cmd, dir, timeout, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun isTermuxInstalled(): Boolean {
        val ctx = context ?: return false
        return try {
            ctx.packageManager.getPackageInfo(TERMUX, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun hasRunPermission(): Boolean {
        val ctx = context ?: return false
        return ctx.checkCallingOrSelfPermission(PERM) == PackageManager.PERMISSION_GRANTED
    }

    private fun runInTermux(command: String, workdir: String?, timeoutMs: Long, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.success(mapOf("ok" to false, "error" to "no_context"))
            return
        }
        if (!isTermuxInstalled()) {
            result.success(mapOf("ok" to false, "error" to "termux_not_installed"))
            return
        }
        if (!hasRunPermission()) {
            result.success(mapOf("ok" to false, "error" to "permission_denied"))
            return
        }
        val id = UUID.randomUUID().toString()
        var done = false
        val handler = Handler(Looper.getMainLooper())
        fun finish(payload: Map<String, Any?>) {
            if (done) return
            done = true
            TermuxBridgeRegistry.cancel(id)
            result.success(payload)
        }
        TermuxBridgeRegistry.register(id) { b ->
            if (b == null) {
                finish(mapOf("ok" to false, "error" to "no_result"))
            } else {
                finish(
                    mapOf(
                        "ok" to true,
                        "stdout" to (b.getString("stdout") ?: ""),
                        "stderr" to (b.getString("stderr") ?: ""),
                        "exitCode" to b.getInt("exitCode", -1),
                        "err" to b.getInt("err", 0),
                        "errmsg" to (b.getString("errmsg") ?: "")
                    )
                )
            }
        }
        val cb = Intent(ctx, TermuxResultReceiver::class.java).putExtra("lm_req", id)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        val pi = PendingIntent.getBroadcast(ctx, reqCounter.incrementAndGet(), cb, flags)
        val intent = Intent("com.termux.RUN_COMMAND").apply {
            setClassName(TERMUX, "com.termux.app.RunCommandService")
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", command))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", workdir ?: "/data/data/com.termux/files/home")
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pi)
        }
        try {
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(intent) else ctx.startService(intent)
        } catch (e: SecurityException) {
            finish(mapOf("ok" to false, "error" to "permission_denied"))
            return
        } catch (e: Exception) {
            finish(mapOf("ok" to false, "error" to (e.message ?: e.javaClass.simpleName)))
            return
        }
        handler.postDelayed({ finish(mapOf("ok" to false, "error" to "timeout")) }, timeoutMs)
    }
}
