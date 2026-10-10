package com.swbudget.app

import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.provider.Telephony
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val SMS_METHOD_CHANNEL = "com.swbudget/sms"
    private val SMS_EVENT_CHANNEL = "com.swbudget/sms_stream"
    private val NOTIF_EVENT_CHANNEL = "com.swbudget/notification_stream"
    private val BATTERY_METHOD_CHANNEL = "com.swbudget/battery"

    private var smsEventSink: EventChannel.EventSink? = null
    private var notifEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method Channel for Inbox historical queries
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "queryInbox") {
                val sinceTimestamp = call.argument<Long>("sinceTimestamp") ?: 0L
                val senders = call.argument<List<String>>("senders") ?: emptyList()
                val list = querySmsInbox(sinceTimestamp, senders)
                result.success(list)
            } else {
                result.notImplemented()
            }
        }

        // Method Channel for OEM Battery Optimization & Foreground Sync
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryOptimizationIgnored" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val isIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(isIgnored)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback to general battery settings
                            val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(fallbackIntent)
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER.uppercase())
                }
                "startForegroundSync" -> {
                    val count = call.argument<Int>("totalCount") ?: 0
                    SyncForegroundService.startService(this, count)
                    result.success(true)
                }
                "stopForegroundSync" -> {
                    SyncForegroundService.stopService(this)
                    result.success(true)
                }
                "openNotificationAccessSettings" -> {
                    try {
                        val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Event Channel for incoming SMS stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    smsEventSink = events
                    SmsBroadcastReceiver.listener = { payload ->
                        runOnUiThread { smsEventSink?.success(payload) }
                    }
                    // Flush any messages buffered while the app was in the background
                    val buffered = SmsBroadcastReceiver.flushPendingMessages(this@MainActivity)
                    for (msg in buffered) {
                        runOnUiThread { smsEventSink?.success(msg) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    smsEventSink = null
                    SmsBroadcastReceiver.listener = null
                }
            }
        )

        // Event Channel for incoming notifications stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notifEventSink = events
                    FinancialNotificationListener.listener = { payload ->
                        runOnUiThread { notifEventSink?.success(payload) }
                    }
                    // Flush any notifications buffered while the app was in the background
                    val buffered = FinancialNotificationListener.flushPendingNotifications(this@MainActivity)
                    for (notif in buffered) {
                        runOnUiThread { notifEventSink?.success(notif) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    notifEventSink = null
                    FinancialNotificationListener.listener = null
                }
            }
        )
    }

    private fun querySmsInbox(sinceTimestamp: Long, whitelistSenders: List<String>): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val uri: Uri = Telephony.Sms.Inbox.CONTENT_URI
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val selection = "${Telephony.Sms.DATE} >= ?"
        val selectionArgs = arrayOf(sinceTimestamp.toString())
        val sortOrder = "${Telephony.Sms.DATE} ASC"

        try {
            contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
                val addressCol = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyCol = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateCol = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)

                while (cursor.moveToNext()) {
                    val address = cursor.getString(addressCol) ?: ""
                    val matchesSender = whitelistSenders.isEmpty() || whitelistSenders.any { sender ->
                        address.contains(sender, ignoreCase = true)
                    }

                    if (matchesSender) {
                        results.add(
                            mapOf(
                                "id" to cursor.getString(idCol),
                                "sender" to address,
                                "body" to cursor.getString(bodyCol),
                                "timestamp" to cursor.getLong(dateCol)
                            )
                        )
                        if (results.size >= 1000) break
                    }
                }
            }
        } catch (_: Exception) {
            // Permission or security exception
        }
        return results
    }
}
