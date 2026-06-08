package com.github.lynyugiri.lynai

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.ScrollCaptureCallback
import android.view.ScrollCaptureSession
import android.view.View
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel
import java.util.function.Consumer

fun installFlutterScrollCaptureIfSupported(
    activity: Activity,
    channel: MethodChannel
) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    FlutterScrollCaptureCallbackApi31(activity, channel).install(activity.window.decorView)
}

private data class ScrollCaptureMetrics(
    val bounds: Rect,
    val devicePixelRatio: Double,
    val maxOffset: Double
)

@RequiresApi(Build.VERSION_CODES.S)
private class FlutterScrollCaptureCallbackApi31(
    private val activity: Activity,
    private val channel: MethodChannel
) : ScrollCaptureCallback {
    private val handler = Handler(Looper.getMainLooper())
    private var metrics: ScrollCaptureMetrics? = null

    fun install(view: View) {
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
            copyVisibleBoundsToSession(session, current.bounds, captureArea, signal, onComplete)
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
        signal: android.os.CancellationSignal,
        onComplete: Consumer<Rect>
    ) {
        val bitmap = Bitmap.createBitmap(bounds.width(), bounds.height(), Bitmap.Config.ARGB_8888)
        PixelCopy.request(activity.window, bounds, bitmap, { copyResult ->
            if (copyResult != PixelCopy.SUCCESS || signal.isCanceled) {
                bitmap.recycle()
                onComplete.accept(Rect())
                return@request
            }
            val canvas = try {
                session.surface.lockCanvas(null)
            } catch (_: Exception) {
                bitmap.recycle()
                onComplete.accept(Rect())
                return@request
            }
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
