package com.github.lynyugiri.lynai

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingLocationResult: MethodChannel.Result? = null
    private var backgroundServiceChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        if (isFinishing) stopGenerationService()
        // 释放悬浮窗持有的广播接收器和 Activity 引用，避免内存泄漏。
        FloatingAssistantOverlay.uninstall(this)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backgroundServiceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lynai/background_service"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startGeneration" -> {
                        startGenerationService()
                        result.success(null)
                    }
                    "stopGeneration" -> {
                        stopGenerationService()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lynai/calendar_platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncProjection" -> {
                    val projection = call.argument<Map<*, *>>("projection")
                    if (projection == null) {
                        result.error("invalid_projection", "缺少日历平台投影", null)
                        return@setMethodCallHandler
                    }
                    if (!CalendarProjectionStore.write(this, projection)) {
                        result.error("projection_write_failed", "无法持久化日历平台投影", null)
                        return@setMethodCallHandler
                    }
                    ScheduleNotificationReceiver.reschedule(this)
                    ScheduleWidgetProvider.refresh(this)
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    // 权限请求只响应 Dart 的显式用户操作；同步投影不会自动弹窗。
                    requestNotificationPermissionIfNeeded()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lynai/native_tools"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openApp" -> {
                    val packageName = call.argument<String>("packageName").orEmpty()
                    result.success(openApp(packageName))
                }
                "getLocation" -> getLocation(result)
                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName").orEmpty()
                    result.success(saveImageToGallery(bytes, fileName))
                }
                else -> result.notImplemented()
            }
        }
        installFlutterScrollCaptureIfSupported(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lynai/scroll_capture")
        )
        DeviceControlBridge.install(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lynai/device_control"),
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, "lynai/device_events")
        )
        FloatingAssistantOverlay.install(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lynai/floating_assistant")
        )
        NcnnOcrRecognizer.ensureLoaded(applicationContext)
        val screenTranslation = ScreenTranslationPipeline(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lynai/screen_translation"
        ).setMethodCallHandler(screenTranslation::handle)
    }

    private fun startGenerationService() {
        val intent = Intent(this, GenerationForegroundService::class.java).apply {
            action = GenerationForegroundService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
        }
    }

    private fun stopGenerationService() {
        val intent = Intent(this, GenerationForegroundService::class.java).apply {
            action = GenerationForegroundService.ACTION_STOP
        }
        try {
            startService(intent)
        } catch (_: IllegalStateException) {
            stopService(intent)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backgroundServiceChannel?.setMethodCallHandler(null)
        backgroundServiceChannel = null
        stopGenerationService()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < 33) return
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_REQUEST_CODE
        )
    }

    private fun openApp(packageName: String): Map<String, Any> {
        if (packageName.isBlank()) {
            return mapOf("ok" to false, "error" to "缺少包名")
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(packageName)
            }
        return try {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launchIntent)
            mapOf("ok" to true, "packageName" to packageName)
        } catch (e: ActivityNotFoundException) {
            mapOf("ok" to false, "error" to "未找到可打开的应用: $packageName")
        } catch (e: SecurityException) {
            mapOf("ok" to false, "error" to "无权打开应用: $packageName")
        }
    }

    private fun getLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            pendingLocationResult?.success(mapOf("ok" to false, "error" to "已有位置请求未完成"))
            pendingLocationResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                LOCATION_REQUEST_CODE
            )
            return
        }
        result.success(readLastLocation())
    }

    private fun saveImageToGallery(bytes: ByteArray?, fileName: String): Map<String, Any> {
        if (bytes == null || bytes.isEmpty()) {
            return mapOf("ok" to false, "error" to "图片数据为空")
        }
        val safeName = if (fileName.isBlank()) {
            "lynai_${System.currentTimeMillis()}.png"
        } else {
            fileName
        }
        var uri: android.net.Uri? = null
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, safeName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/LynAI")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                } else {
                    val directory = File(
                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                        "LynAI"
                    )
                    if (!directory.exists()) directory.mkdirs()
                    put(MediaStore.Images.Media.DATA, File(directory, safeName).absolutePath)
                }
            }
            val resolver = contentResolver
            uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: return mapOf("ok" to false, "error" to "无法创建图库文件")
            val imageUri = uri ?: return mapOf("ok" to false, "error" to "无法创建图库文件")
            resolver.openOutputStream(imageUri)?.use { output ->
                output.write(bytes)
            } ?: return mapOf("ok" to false, "error" to "无法写入图库文件")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(imageUri, values, null, null)
            }
            mapOf("ok" to true, "uri" to imageUri.toString())
        } catch (e: Exception) {
            uri?.let { contentResolver.delete(it, null, null) }
            mapOf("ok" to false, "error" to (e.message ?: e.toString()))
        }
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun readLastLocation(): Map<String, Any> {
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = manager.getProviders(true)
        val location = providers.mapNotNull { provider ->
            try {
                manager.getLastKnownLocation(provider)
            } catch (_: SecurityException) {
                null
            }
        }.maxByOrNull { it.time }
        return location?.toMap() ?: mapOf(
            "ok" to false,
            "error" to "没有可用的最近位置，请确认定位服务已开启"
        )
    }

    private fun Location.toMap(): Map<String, Any> {
        return mapOf(
            "ok" to true,
            "latitude" to latitude,
            "longitude" to longitude,
            "accuracy" to accuracy.toDouble(),
            "provider" to provider.orEmpty(),
            "time" to time
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCATION_REQUEST_CODE) return
        val result = pendingLocationResult ?: return
        pendingLocationResult = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            result.success(readLastLocation())
        } else {
            result.success(mapOf("ok" to false, "error" to "位置权限被拒绝"))
        }
    }

    companion object {
        private const val LOCATION_REQUEST_CODE = 7811
        private const val NOTIFICATION_REQUEST_CODE = 7812
    }
}
