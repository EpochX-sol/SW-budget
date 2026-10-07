package com.swbudget.app

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

class FinancialNotificationListener : NotificationListenerService() {
    companion object {
        var listener: ((Map<String, Any>) -> Unit)? = null
        private const val PREFS_NAME = "sw_budget_buffer"
        private const val KEY_PENDING_NOTIFS = "pending_notifs_json"

        val TARGET_PACKAGES = setOf(
            "cn.tydic.ethiopay",
            "com.combanketh.cbe_mobile_banking",
            "et.com.abyssinia.mobile"
        )

        fun bufferNotification(context: Context, payload: Map<String, Any>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val currentSet = prefs.getStringSet(KEY_PENDING_NOTIFS, mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            val json = JSONObject(payload).toString()
            currentSet.add(json)
            prefs.edit().putStringSet(KEY_PENDING_NOTIFS, currentSet).apply()
        }

        fun flushPendingNotifications(context: Context): List<Map<String, Any>> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val set = prefs.getStringSet(KEY_PENDING_NOTIFS, emptySet()) ?: emptySet()
            if (set.isEmpty()) return emptyList()

            val list = mutableListOf<Map<String, Any>>()
            for (jsonStr in set) {
                try {
                    val obj = JSONObject(jsonStr)
                    val map = mutableMapOf<String, Any>()
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        map[key] = obj.get(key)
                    }
                    list.add(map)
                } catch (_: Exception) {}
            }
            prefs.edit().remove(KEY_PENDING_NOTIFS).apply()
            return list
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return

        if (!TARGET_PACKAGES.contains(packageName)) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        val payload = mapOf(
            "id" to "${sbn.id}_${sbn.postTime}",
            "package" to packageName,
            "title" to title,
            "text" to text,
            "timestamp" to sbn.postTime
        )

        val activeListener = listener
        if (activeListener != null) {
            activeListener.invoke(payload)
        } else {
            bufferNotification(applicationContext, payload)
        }
    }
}
