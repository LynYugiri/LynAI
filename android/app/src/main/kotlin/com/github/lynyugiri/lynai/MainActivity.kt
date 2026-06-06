package com.github.lynyugiri.lynai

import android.Manifest
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.Rect
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.PixelCopy
import android.view.ScrollCaptureCallback
import android.view.ScrollCaptureSession
import android.view.View
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.function.Consumer

class MainActivity : FlutterActivity() {
    private var pendingLocationResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            window.decorView.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lynai/background_service"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startGeneration" -> {
                    startGenerationService()
                    result.success(null)
                }
                "stopGeneration" -> {
                    stopService(Intent(this, GenerationForegroundService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lynai/schedule_widget"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    ScheduleWidgetProvider.refresh(this)
                    result.success(null)
                }
                "rescheduleNotifications" -> {
                    requestNotificationPermissionIfNeeded()
                    result.success(ScheduleNotificationReceiver.reschedule(this))
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            FlutterScrollCaptureCallback(
                this,
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lynai/scroll_capture")
            ).install(window.decorView)
        }
    }

    private fun startGenerationService() {
        val intent = Intent(this, GenerationForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
        }
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
            ?: return mapOf("ok" to false, "error" to "未找到可打开的应用: $packageName")
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(launchIntent)
        return mapOf("ok" to true, "packageName" to packageName)
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

private data class ScrollCaptureMetrics(
    val bounds: Rect,
    val devicePixelRatio: Double,
    val maxOffset: Double
)

private class FlutterScrollCaptureCallback(
    private val activity: Activity,
    private val channel: MethodChannel
) : ScrollCaptureCallback {
    private val handler = Handler(Looper.getMainLooper())
    private var metrics: ScrollCaptureMetrics? = null

    fun install(view: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        view.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
        view.setScrollCaptureCallback(this)
    }

    override fun onScrollCaptureSearch(
        signal: android.os.CancellationSignal,
        onReady: Consumer<Rect>
    ) {
        requestMetrics { next ->
            metrics = next
            onReady.accept(next?.bounds ?: Rect())
        }
    }

    override fun onScrollCaptureStart(
        session: ScrollCaptureSession,
        signal: android.os.CancellationSignal,
        onReady: Runnable
    ) {
        invokeMap("begin", null) {
            onReady.run()
        }
    }

    override fun onScrollCaptureImageRequest(
        session: ScrollCaptureSession,
        signal: android.os.CancellationSignal,
        captureArea: Rect,
        onComplete: Consumer<Rect>
    ) {
        val current = metrics
        if (current == null || signal.isCanceled) {
            onComplete.accept(Rect())
            return
        }
        val targetOffset = (captureArea.top / current.devicePixelRatio)
            .coerceIn(0.0, current.maxOffset)
        invokeMap("scrollTo", targetOffset) { result ->
            if (result?.get("ok") != true || signal.isCanceled) {
                onComplete.accept(Rect())
                return@invokeMap
            }
            copyVisibleBoundsToSession(session, current.bounds, captureArea, onComplete)
        }
    }

    override fun onScrollCaptureEnd(onReady: Runnable) {
        invokeMap("restore", null) {
            metrics = null
            onReady.run()
        }
    }

    private fun requestMetrics(onResult: (ScrollCaptureMetrics?) -> Unit) {
        invokeMap("getMetrics", null) { result ->
            if (result?.get("ok") != true) {
                onResult(null)
                return@invokeMap
            }
            val ratio = result.doubleValue("devicePixelRatio") ?: 1.0
            val bounds = Rect(
                result.pixelValue("left", ratio),
                result.pixelValue("top", ratio),
                result.pixelValue("right", ratio),
                result.pixelValue("bottom", ratio)
            )
            if (bounds.isEmpty) {
                onResult(null)
                return@invokeMap
            }
            onResult(
                ScrollCaptureMetrics(
                    bounds = bounds,
                    devicePixelRatio = ratio,
                    maxOffset = result.doubleValue("maxOffset") ?: 0.0
                )
            )
        }
    }

    private fun copyVisibleBoundsToSession(
        session: ScrollCaptureSession,
        bounds: Rect,
        captureArea: Rect,
        onComplete: Consumer<Rect>
    ) {
        val bitmap = Bitmap.createBitmap(bounds.width(), bounds.height(), Bitmap.Config.ARGB_8888)
        PixelCopy.request(activity.window, bounds, bitmap, { copyResult ->
            if (copyResult != PixelCopy.SUCCESS) {
                onComplete.accept(Rect())
                return@request
            }
            val canvas = session.surface.lockCanvas(null)
            try {
                clearCanvas(canvas)
                canvas.drawBitmap(bitmap, 0f, 0f, null)
            } finally {
                session.surface.unlockCanvasAndPost(canvas)
                bitmap.recycle()
            }
            onComplete.accept(
                Rect(
                    captureArea.left,
                    captureArea.top,
                    captureArea.left + bounds.width(),
                    captureArea.top + bounds.height()
                )
            )
        }, handler)
    }

    private fun clearCanvas(canvas: Canvas) {
        if (canvas.isOpaque) {
            canvas.drawColor(Color.WHITE)
        } else {
            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        }
    }

    private fun invokeMap(
        method: String,
        arguments: Any?,
        onResult: (Map<String, Any?>?) -> Unit
    ) {
        handler.post {
            channel.invokeMethod(method, arguments, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    @Suppress("UNCHECKED_CAST")
                    onResult(result as? Map<String, Any?>)
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    onResult(null)
                }

                override fun notImplemented() {
                    onResult(null)
                }
            })
        }
    }
}

private fun Map<String, Any?>.doubleValue(key: String): Double? {
    return (this[key] as? Number)?.toDouble()
}

private fun Map<String, Any?>.pixelValue(key: String, devicePixelRatio: Double): Int {
    return ((doubleValue(key) ?: 0.0) * devicePixelRatio).toInt()
}
