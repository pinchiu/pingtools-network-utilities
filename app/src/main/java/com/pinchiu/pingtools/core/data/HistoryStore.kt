package com.pinchiu.pingtools.core.data

import android.content.Context
import com.pinchiu.pingtools.core.model.WolDevice
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lightweight persistence for recent tool inputs and saved Wake-on-LAN
 * devices. Backed by SharedPreferences so the app needs no database setup.
 */
object HistoryStore {

    private const val PREFS = "pingtools_history"
    private const val DEVICES_KEY = "wol_devices"
    private const val MAX_RECENT = 8

    fun recent(context: Context, tool: String, limit: Int = 5): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString("recent_$tool", null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) add(array.getString(i))
            }.take(limit)
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun add(context: Context, tool: String, value: String) {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return
        val updated = (listOf(trimmed) + recent(context, tool, MAX_RECENT))
            .distinct()
            .take(MAX_RECENT)
        val array = JSONArray().apply { updated.forEach { put(it) } }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("recent_$tool", array.toString())
            .apply()
    }

    fun clear(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        prefs.all.keys.filter { it.startsWith("recent_") }.forEach(editor::remove)
        editor.apply()
    }

    fun savedDevices(context: Context): List<WolDevice> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(DEVICES_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    add(
                        WolDevice(
                            name = obj.optString("name", "Device"),
                            mac = obj.optString("mac"),
                            broadcast = obj.optString("broadcast", "255.255.255.255"),
                            port = obj.optInt("port", 9)
                        )
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveDevice(context: Context, device: WolDevice) {
        val devices = savedDevices(context).filterNot { it.mac.equals(device.mac, true) } + device
        val array = JSONArray()
        devices.forEach {
            array.put(
                JSONObject()
                    .put("name", it.name)
                    .put("mac", it.mac)
                    .put("broadcast", it.broadcast)
                    .put("port", it.port)
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(DEVICES_KEY, array.toString())
            .apply()
    }

    fun removeDevice(context: Context, mac: String) {
        val devices = savedDevices(context).filterNot { it.mac.equals(mac, true) }
        val array = JSONArray()
        devices.forEach {
            array.put(
                JSONObject()
                    .put("name", it.name)
                    .put("mac", it.mac)
                    .put("broadcast", it.broadcast)
                    .put("port", it.port)
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(DEVICES_KEY, array.toString())
            .apply()
    }
}
