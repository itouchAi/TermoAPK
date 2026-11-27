package com.example.termostat_flow

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val widgetChannel = "termostat_flow/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        val payload = call.argument<String>("payload")
                        if (!payload.isNullOrBlank()) {
                            getSharedPreferences(
                                TermostatWidgetProvider.PREFS_NAME,
                                Context.MODE_PRIVATE
                            ).edit()
                                .putString(TermostatWidgetProvider.KEY_PAYLOAD, payload)
                                .apply()
                            TermostatWidgetProvider.refreshAllWidgets(applicationContext)
                        }
                        result.success(true)
                    }
                    "consumePendingTarget" -> {
                        val prefs = getSharedPreferences(
                            TermostatWidgetProvider.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        val rawTemp = prefs.getString(TermostatWidgetProvider.KEY_PENDING_TARGET, null)
                        val parsed = rawTemp?.toDoubleOrNull()
                        if (parsed != null) {
                            prefs.edit()
                                .remove(TermostatWidgetProvider.KEY_PENDING_TARGET)
                                .remove(TermostatWidgetProvider.KEY_PENDING_TS)
                                .apply()
                            result.success(parsed)
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
