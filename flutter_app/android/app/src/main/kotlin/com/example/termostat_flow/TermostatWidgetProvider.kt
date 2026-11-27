package com.example.termostat_flow

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs
import kotlin.math.round

class TermostatWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS_NAME = "termostat_widget_prefs"
        const val KEY_PAYLOAD = "widget_payload"
        const val KEY_ROOM_INDEX = "widget_room_index"
        const val KEY_PENDING_TARGET = "pending_target_temp"
        const val KEY_PENDING_TS = "pending_target_ts"

        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_STATE_KEY = "flutter.termostat_flow_flutter_v2"

        const val ACTION_WIDGET_CMD = "com.example.termostat_flow.WIDGET_ACTION"
        const val EXTRA_CMD = "cmd"

        private const val CMD_TEMP_DOWN = "temp_down"
        private const val CMD_TEMP_UP = "temp_up"
        private const val CMD_PRESET_GECE = "preset_gece"
        private const val CMD_PRESET_EKO = "preset_eko"
        private const val CMD_PRESET_KONFOR = "preset_konfor"
        private const val CMD_PRESET_BOOST = "preset_boost"
        private const val CMD_ROOM_PREV = "room_prev"
        private const val CMD_ROOM_NEXT = "room_next"

        private const val MIN_TEMP = 10.0
        private const val MAX_TEMP = 30.0

        fun refreshAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TermostatWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                for (id in ids) {
                    updateAppWidget(context, manager, id)
                }
            }
        }

        private fun snapTemp(value: Double): Double {
            val clamped = value.coerceIn(MIN_TEMP, MAX_TEMP)
            return round(clamped * 2.0) / 2.0
        }

        private fun presetForTemp(temp: Double): String {
            return when {
                abs(temp - 18.5) < 0.05 -> "gece"
                abs(temp - 20.0) < 0.05 -> "eko"
                abs(temp - 22.5) < 0.05 -> "konfor"
                abs(temp - 25.0) < 0.05 -> "boost"
                else -> "custom"
            }
        }

        private fun loadPayload(context: Context): JSONObject {
            val widgetPrefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = widgetPrefs.getString(KEY_PAYLOAD, null)
            if (!raw.isNullOrBlank()) {
                try {
                    return JSONObject(raw)
                } catch (_: Exception) {
                }
            }

            // Fallback: read directly from Flutter SharedPreferences if widget_payload is not yet written
            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val flutterRaw = flutterPrefs.getString(FLUTTER_STATE_KEY, null)
            if (!flutterRaw.isNullOrBlank()) {
                try {
                    val state = JSONObject(flutterRaw)
                    val target = state.optDouble("targetTemp", 22.5)
                    val lang = state.optString("lang", "tr")
                    val roomsArr = JSONArray()
                    val floorPlan = state.optJSONObject("floorPlan")
                    val rawRooms = floorPlan?.optJSONArray("rooms")
                    if (rawRooms != null) {
                        for (i in 0 until rawRooms.length()) {
                            val r = rawRooms.optJSONObject(i) ?: continue
                            val item = JSONObject()
                            item.put("id", r.optString("id", "r_$i"))
                            item.put("name", r.optString("name", "Oda ${i + 1}"))
                            item.put("online", false)
                            roomsArr.put(item)
                        }
                    }
                    if (roomsArr.length() == 0) {
                        roomsArr.put(JSONObject().put("id", "living").put("name", if (lang == "en") "Living Room" else "Salon").put("online", false))
                    }
                    return JSONObject()
                        .put("targetTemp", target)
                        .put("presetId", presetForTemp(target))
                        .put("lang", lang)
                        .put("rooms", roomsArr)
                } catch (_: Exception) {
                }
            }

            // Fresh-install default before first app launch (zero fake temps)
            val defaults = JSONArray()
                .put(JSONObject().put("id", "living").put("name", "Salon").put("online", false))
                .put(JSONObject().put("id", "bedroom").put("name", "Yatak Odası").put("online", false))
                .put(JSONObject().put("id", "kitchen").put("name", "Mutfak").put("online", false))
            return JSONObject()
                .put("targetTemp", 22.5)
                .put("presetId", "konfor")
                .put("lang", "tr")
                .put("rooms", defaults)
        }

        private fun saveTargetChange(context: Context, nextTemp: Double) {
            val snapped = snapTemp(nextTemp)
            val preset = presetForTemp(snapped)
            val widgetPrefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val payload = loadPayload(context)
            payload.put("targetTemp", snapped)
            payload.put("presetId", preset)

            widgetPrefs.edit()
                .putString(KEY_PAYLOAD, payload.toString())
                .putString(KEY_PENDING_TARGET, snapped.toString())
                .putLong(KEY_PENDING_TS, System.currentTimeMillis())
                .apply()

            // Also sync into FlutterSharedPreferences so cold starts pick up the widget change immediately
            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val flutterRaw = flutterPrefs.getString(FLUTTER_STATE_KEY, null)
            if (!flutterRaw.isNullOrBlank()) {
                try {
                    val state = JSONObject(flutterRaw)
                    state.put("targetTemp", snapped)
                    val presetIdx = when (preset) {
                        "eko" -> 0
                        "konfor" -> 1
                        "gece" -> 2
                        "boost" -> 3
                        else -> -1
                    }
                    if (presetIdx >= 0) {
                        state.put("presetIndex", presetIdx)
                    } else {
                        state.remove("presetIndex")
                    }
                    flutterPrefs.edit().putString(FLUTTER_STATE_KEY, state.toString()).apply()
                } catch (_: Exception) {
                }
            }
        }

        private fun buildActionPendingIntent(context: Context, cmd: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, TermostatWidgetProvider::class.java).apply {
                action = ACTION_WIDGET_CMD
                putExtra(EXTRA_CMD, cmd)
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun buildLaunchAppPendingIntent(context: Context): PendingIntent {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                100,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.termostat_widget)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val payload = loadPayload(context)

            val targetTemp = snapTemp(payload.optDouble("targetTemp", 22.5))
            val preset = presetForTemp(targetTemp)
            val isEn = payload.optString("lang", "tr") == "en"

            // Format Target Temp
            views.setTextViewText(
                R.id.widget_target_temp,
                String.format(Locale.US, "%.1f°C", targetTemp)
            )

            // Active mode pill label
            val modeLabel = when (preset) {
                "gece" -> if (isEn) "NIGHT" else "GECE"
                "eko" -> if (isEn) "ECO" else "EKO"
                "konfor" -> if (isEn) "COMFORT" else "KONFOR"
                "boost" -> "BOOST"
                else -> if (isEn) "CUSTOM" else "ÖZEL"
            }
            views.setTextViewText(R.id.widget_mode_label, modeLabel)

            // Preset button labels & active highlighting
            views.setTextViewText(R.id.btn_mode_gece, if (isEn) "Night" else "Gece")
            views.setTextViewText(R.id.btn_mode_eko, if (isEn) "Eco" else "Eko")
            views.setTextViewText(R.id.btn_mode_konfor, if (isEn) "Comfort" else "Konfor")
            views.setTextViewText(R.id.btn_mode_boost, "Boost")

            val activeText = Color.parseColor("#FFFFFF")
            val inactiveText = Color.parseColor("#CBD5E1")

            views.setInt(R.id.btn_mode_gece, "setBackgroundResource", if (preset == "gece") R.drawable.widget_btn_active_bg else R.drawable.widget_btn_bg)
            views.setTextColor(R.id.btn_mode_gece, if (preset == "gece") activeText else inactiveText)

            views.setInt(R.id.btn_mode_eko, "setBackgroundResource", if (preset == "eko") R.drawable.widget_btn_active_bg else R.drawable.widget_btn_bg)
            views.setTextColor(R.id.btn_mode_eko, if (preset == "eko") activeText else inactiveText)

            views.setInt(R.id.btn_mode_konfor, "setBackgroundResource", if (preset == "konfor") R.drawable.widget_btn_active_bg else R.drawable.widget_btn_bg)
            views.setTextColor(R.id.btn_mode_konfor, if (preset == "konfor") activeText else inactiveText)

            views.setInt(R.id.btn_mode_boost, "setBackgroundResource", if (preset == "boost") R.drawable.widget_btn_active_bg else R.drawable.widget_btn_bg)
            views.setTextColor(R.id.btn_mode_boost, if (preset == "boost") activeText else inactiveText)

            // Room selector state
            val rooms = payload.optJSONArray("rooms") ?: JSONArray()
            val roomCount = rooms.length()
            if (roomCount > 0) {
                var idx = prefs.getInt(KEY_ROOM_INDEX, 0)
                idx = ((idx % roomCount) + roomCount) % roomCount
                val room = rooms.optJSONObject(idx) ?: JSONObject()
                val roomName = room.optString("name", if (isEn) "Room ${idx + 1}" else "Oda ${idx + 1}")
                val isOnline = room.optBoolean("online", false)
                val hasTemp = isOnline && room.has("tempC") && !room.isNull("tempC")
                val hasRad = isOnline && room.has("radiatorTempC") && !room.isNull("radiatorTempC")

                val roomsHeader = if (isEn) "ROOMS · ${idx + 1}/$roomCount" else "ODALAR · ${idx + 1}/$roomCount"
                views.setTextViewText(R.id.widget_rooms_counter, roomsHeader)
                views.setTextViewText(R.id.widget_room_name, roomName)
                views.setTextColor(
                    R.id.widget_room_status_dot,
                    if (isOnline) Color.parseColor("#10B981") else Color.parseColor("#64748B")
                )

                if (hasTemp) {
                    val tempC = room.optDouble("tempC")
                    views.setTextViewText(R.id.widget_room_temp, String.format(Locale.US, "%.1f°C", tempC))
                    views.setTextColor(R.id.widget_room_temp, Color.parseColor("#2ED6C7"))
                } else {
                    views.setTextViewText(R.id.widget_room_temp, "--")
                    views.setTextColor(R.id.widget_room_temp, Color.parseColor("#94A3B8"))
                }

                val radText = if (hasRad) {
                    val radC = room.optDouble("radiatorTempC")
                    if (isEn) String.format(Locale.US, "Rad: %.0f°C", radC)
                    else String.format(Locale.US, "Petek: %.0f°C", radC)
                } else {
                    if (isEn) "Rad: --" else "Petek: --"
                }
                views.setTextViewText(R.id.widget_room_radiator, radText)
            } else {
                views.setTextViewText(R.id.widget_rooms_counter, if (isEn) "ROOMS · 0" else "ODALAR · 0")
                views.setTextViewText(R.id.widget_room_name, if (isEn) "No Rooms" else "Oda Yok")
                views.setTextViewText(R.id.widget_room_temp, "--")
                views.setTextViewText(R.id.widget_room_radiator, if (isEn) "Rad: --" else "Petek: --")
            }

            // Wire click listeners
            val launchPi = buildLaunchAppPendingIntent(context)
            views.setOnClickPendingIntent(R.id.widget_thermostat_header, launchPi)
            views.setOnClickPendingIntent(R.id.widget_target_temp, launchPi)

            views.setOnClickPendingIntent(R.id.btn_temp_down, buildActionPendingIntent(context, CMD_TEMP_DOWN, 201))
            views.setOnClickPendingIntent(R.id.btn_temp_up, buildActionPendingIntent(context, CMD_TEMP_UP, 202))
            views.setOnClickPendingIntent(R.id.btn_mode_gece, buildActionPendingIntent(context, CMD_PRESET_GECE, 203))
            views.setOnClickPendingIntent(R.id.btn_mode_eko, buildActionPendingIntent(context, CMD_PRESET_EKO, 204))
            views.setOnClickPendingIntent(R.id.btn_mode_konfor, buildActionPendingIntent(context, CMD_PRESET_KONFOR, 205))
            views.setOnClickPendingIntent(R.id.btn_mode_boost, buildActionPendingIntent(context, CMD_PRESET_BOOST, 206))
            views.setOnClickPendingIntent(R.id.btn_room_prev, buildActionPendingIntent(context, CMD_ROOM_PREV, 207))
            views.setOnClickPendingIntent(R.id.btn_room_next, buildActionPendingIntent(context, CMD_ROOM_NEXT, 208))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_WIDGET_CMD) {
            val cmd = intent.getStringExtra(EXTRA_CMD) ?: return
            val payload = loadPayload(context)
            val currentTarget = payload.optDouble("targetTemp", 22.5)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val rooms = payload.optJSONArray("rooms") ?: JSONArray()
            val roomCount = rooms.length()

            when (cmd) {
                CMD_TEMP_DOWN -> saveTargetChange(context, currentTarget - 0.5)
                CMD_TEMP_UP -> saveTargetChange(context, currentTarget + 0.5)
                CMD_PRESET_GECE -> saveTargetChange(context, 18.5)
                CMD_PRESET_EKO -> saveTargetChange(context, 20.0)
                CMD_PRESET_KONFOR -> saveTargetChange(context, 22.5)
                CMD_PRESET_BOOST -> saveTargetChange(context, 25.0)
                CMD_ROOM_PREV -> {
                    if (roomCount > 0) {
                        val cur = prefs.getInt(KEY_ROOM_INDEX, 0)
                        val next = ((cur - 1) % roomCount + roomCount) % roomCount
                        prefs.edit().putInt(KEY_ROOM_INDEX, next).apply()
                    }
                }
                CMD_ROOM_NEXT -> {
                    if (roomCount > 0) {
                        val cur = prefs.getInt(KEY_ROOM_INDEX, 0)
                        val next = (cur + 1) % roomCount
                        prefs.edit().putInt(KEY_ROOM_INDEX, next).apply()
                    }
                }
            }
            refreshAllWidgets(context)
        }
    }
}
