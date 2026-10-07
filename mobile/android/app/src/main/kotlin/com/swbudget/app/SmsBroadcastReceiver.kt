package com.swbudget.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SmsMessage
import org.json.JSONObject

class SmsBroadcastReceiver : BroadcastReceiver() {
    companion object {
        var listener: ((Map<String, Any>) -> Unit)? = null
        private const val PREFS_NAME = "sw_budget_buffer"
        private const val KEY_PENDING_SMS = "pending_sms_json"

        fun bufferMessage(context: Context, payload: Map<String, Any>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val currentSet = prefs.getStringSet(KEY_PENDING_SMS, mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            val json = JSONObject(payload).toString()
            currentSet.add(json)
            prefs.edit().putStringSet(KEY_PENDING_SMS, currentSet).apply()
        }

        fun flushPendingMessages(context: Context): List<Map<String, Any>> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val set = prefs.getStringSet(KEY_PENDING_SMS, emptySet()) ?: emptySet()
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
            prefs.edit().remove(KEY_PENDING_SMS).apply()
            return list
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages: Array<SmsMessage> = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
            if (messages.isEmpty()) return

            val sender = messages[0].displayOriginatingAddress ?: ""
            val fullBody = StringBuilder()
            var timestamp = System.currentTimeMillis()

            for (msg in messages) {
                fullBody.append(msg.displayMessageBody)
                timestamp = msg.timestampMillis
            }

            val payload = mapOf(
                "id" to "${sender}_${timestamp}",
                "sender" to sender,
                "body" to fullBody.toString(),
                "timestamp" to timestamp
            )

            val activeListener = listener
            if (activeListener != null) {
                activeListener.invoke(payload)
            } else {
                bufferMessage(context, payload)
            }
        }
    }
}
