package com.lmclient.lm_client

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "lmclient/termux"
        private const val TERMUX = "com.termux"
        private const val PERM = "com.termux.permission.RUN_COMMAND"
        private val reqCounter = AtomicInteger(1000)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstalled" -> result.success(isTermuxInstalled())
                "hasPermission" -> result.success(hasRunPermission())
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 23) requestPermissions(arrayOf(PERM), 7001)
                    result.success(true)
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
    }

    private fun isTermuxInstalled(): Boolean = try {
        packageManager.getPackageInfo(TERMUX, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun hasRunPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return checkSelfPermission(PERM) == PackageManager.PERMISSION_GRANTED
    }

    private fun runInTermux(command: String, workdir: String?, timeoutMs: Long, result: MethodChannel.Result) {
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
        val cb = Intent(this, TermuxResultReceiver::class.java).putExtra("lm_req", id)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        val pi = PendingIntent.getBroadcast(this, reqCounter.incrementAndGet(), cb, flags)
        val intent = Intent("com.termux.RUN_COMMAND").apply {
            setClassName(TERMUX, "com.termux.app.RunCommandService")
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", command))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", workdir ?: "/data/data/com.termux/files/home")
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pi)
        }
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
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
