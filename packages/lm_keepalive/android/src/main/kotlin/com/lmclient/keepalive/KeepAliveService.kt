package com.lmclient.keepalive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app process alive (foreground service + partial wake lock) while an agent run is in progress,
 * so the run is not frozen when the user switches apps or turns the screen off.
 */
class KeepAliveService : Service() {
    companion object {
        const val CHANNEL_ID = "lmclient_work"
        const val NOTIF_ID = 4271
        const val ACTION_STOP = "com.lmclient.keepalive.STOP"
        @Volatile var running: Boolean = false
        // Safety net: a wake lock is never held longer than this, even if the app forgets to stop the service.
        private const val WAKE_TIMEOUT_MS = 3L * 60L * 60L * 1000L
    }

    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val stop = intent?.action == ACTION_STOP
        val title = intent?.getStringExtra("title") ?: "LMClient"
        val text = intent?.getStringExtra("text") ?: ""
        // EVERY start command must reach startForeground(), the stop command included: while a
        // startForegroundService() request is still waiting for it, stopping the service makes Android kill the
        // app with ForegroundServiceDidNotStartInTimeException (seen in CI when runs started and ended quickly).
        val foreground = enterForeground(title, text)
        if (stop) {
            // stopSelfResult(startId) refuses to stop when a newer start request is already queued, so a quick
            // stop-then-start keeps the service alive instead of dropping the newer request.
            if (stopSelfResult(startId)) {
                releaseWake()
                running = false
                leaveForeground()
            }
            return START_NOT_STICKY
        }
        if (!foreground) {
            // Android refused the foreground state; do not linger as a background service.
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        acquireWake()
        return START_NOT_STICKY
    }

    private fun enterForeground(title: String, text: String): Boolean {
        return try {
            ensureChannel()
            val n = buildNotification(title, text)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIF_ID, n)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun leaveForeground() {
        try {
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
        }
    }

    override fun onDestroy() {
        releaseWake()
        running = false
        super.onDestroy()
    }

    private fun acquireWake() {
        try {
            if (wake == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "lmclient:work").also { it.setReferenceCounted(false) }
            }
            wake?.acquire(WAKE_TIMEOUT_MS)
        } catch (e: Exception) {
            // The foreground service alone still helps; do not crash for a wake lock.
        }
    }

    private fun releaseWake() {
        try {
            val w = wake
            if (w != null && w.isHeld) w.release()
        } catch (e: Exception) {
        }
        wake = null
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(CHANNEL_ID, "LMClient work", NotificationManager.IMPORTANCE_LOW)
                ch.description = "Shown while the agent is working so Android does not pause it"
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        val b: Notification.Builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        b.setContentTitle(title)
        b.setContentText(text)
        b.setSmallIcon(android.R.drawable.stat_notify_sync)
        b.setOngoing(true)
        b.setOnlyAlertOnce(true)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            val flags = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
            b.setContentIntent(PendingIntent.getActivity(this, 0, launch, flags))
        }
        return b.build()
    }
}
