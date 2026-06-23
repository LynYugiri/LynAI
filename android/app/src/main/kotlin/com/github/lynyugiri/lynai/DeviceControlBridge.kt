package com.github.lynyugiri.lynai

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object DeviceControlBridge : EventChannel.StreamHandler {
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    fun install(activity: Activity, methodChannel: MethodChannel, eventChannel: EventChannel) {
        this.activity = activity
        eventChannel.setStreamHandler(this)
        methodChannel.setMethodCallHandler { call, result ->
            val service = LynAIAccessibilityService.instance
            when (call.method) {
                "snapshot" -> result.success(service?.snapshot() ?: unavailable())
                "context" -> result.success(service?.screenContext() ?: unavailable())
                "screenshot" -> service?.screenshot(result) ?: result.success(unavailable())
                "tap" -> service?.tap(arguments(call.arguments), result) ?: result.success(unavailable())
                "tapRepeat" -> service?.tapRepeat(arguments(call.arguments), result) ?: result.success(unavailable())
                "swipe" -> service?.swipe(arguments(call.arguments), result) ?: result.success(unavailable())
                "pressBack" -> result.success(service?.pressBack() ?: unavailable())
                "inputText" -> result.success(service?.inputText(arguments(call.arguments)) ?: unavailable())
                "nodeAction" -> result.success(service?.nodeAction(arguments(call.arguments)) ?: unavailable())
                "openSettings" -> result.success(openSettings(arguments(call.arguments)))
                else -> result.notImplemented()
            }
        }
    }

    fun emit(event: Map<String, Any?>) {
        activity?.runOnUiThread { eventSink?.success(event) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun openSettings(args: Map<String, Any?>): Map<String, Any?> {
        val target = args["target"]?.toString().orEmpty()
        val ctx = activity ?: return error("activity_unavailable", "Activity 不可用")
        val intent = if (target == "overlay") {
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                data = Uri.parse("package:${ctx.packageName}")
            }
        } else {
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(intent)
        return mapOf("ok" to true, "target" to if (target == "overlay") "overlay" else "accessibility")
    }

    private fun arguments(raw: Any?): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return raw as? Map<String, Any?> ?: emptyMap()
    }

    private fun unavailable(): Map<String, Any?> {
        return error("accessibility_unavailable", "LynAI 无障碍服务未启用")
    }

    private fun error(code: String, message: String): Map<String, Any?> {
        return mapOf("ok" to false, "error" to mapOf("code" to code, "message" to message))
    }
}
