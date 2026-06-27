package com.github.lynyugiri.lynai

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

object NcnnOcrRecognizer {
    private external fun nativeInit(assetManager: android.content.res.AssetManager): Boolean
    private external fun nativeRecognize(bitmap: Bitmap): String
    private external fun nativeRelease()

    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var loaded = false
    private val initLock = Object()

    init {
        System.loadLibrary("lynai_ocr")
    }

    fun ensureLoaded(context: Context) {
        if (loaded) return
        synchronized(initLock) {
            if (loaded) return
            loaded = nativeInit(context.assets)
        }
    }

    fun recognize(imageBase64: String, result: MethodChannel.Result) {
        executor.execute {
            try {
                val decoded = Base64.decode(imageBase64, Base64.NO_WRAP)
                val bitmap = BitmapFactory.decodeByteArray(decoded, 0, decoded.size)
                if (bitmap == null) {
                    result.success(error("decode_failed", "无法解码截图"))
                    return@execute
                }

                if (!loaded) {
                    result.success(error("not_loaded", "OCR 引擎未初始化"))
                    bitmap.recycle()
                    return@execute
                }

                val json = nativeRecognize(bitmap)
                bitmap.recycle()

                val blocks = parseJson(json)
                result.success(mapOf("ok" to true, "result" to blocks))
            } catch (e: Exception) {
                result.success(error("ocr_exception", "OCR 异常: ${e.message}"))
            }
        }
    }

    private fun parseJson(json: String): List<Map<String, Any?>> {
        val errorObj: JSONObject
        try {
            errorObj = JSONObject(json)
            if (errorObj.has("error")) {
                return emptyList()
            }
        } catch (e: org.json.JSONException) {
            // Not a single object — might be an array, fall through
        }

        val array: JSONArray
        try {
            array = JSONArray(json)
        } catch (e: org.json.JSONException) {
            return emptyList()
        }

        val blocks = mutableListOf<Map<String, Any?>>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            val text = obj.optString("text", "").trim()
            if (text.isEmpty()) continue

            val bounds = obj.optJSONObject("bounds")
            val orientation = obj.optInt("orientation", 0)
            val boxW = obj.optInt("boxW", 0)
            val boxH = obj.optInt("boxH", 0)
            val fontSize = obj.optInt("fontSize", 0)
            val angle = obj.optInt("angle", 0)

            val boundsMap = mutableMapOf<String, Any>(
                "left" to (bounds?.optInt("left", 0) ?: 0),
                "top" to (bounds?.optInt("top", 0) ?: 0),
                "right" to (bounds?.optInt("right", 0) ?: 0),
                "bottom" to (bounds?.optInt("bottom", 0) ?: 0),
            )

            val block = mutableMapOf<String, Any?>(
                // G1: do not emit positional id ("ocr_$i") here; the positional
                // scheme collides across OCR calls once content scrolls and lets
                // the Dart cache silently reuse a stale translation for a brand
                // new block. Empty forces Dart to derive a stable id from
                // text + bounds.
                "id" to "",
                "text" to text,
                "bounds" to boundsMap,
                "orientation" to orientation,
                "boxW" to boxW,
                "boxH" to boxH,
                "fontSize" to fontSize,
                "angle" to angle,
            )
            blocks.add(block)
        }
        return blocks
    }

    private fun error(code: String, message: String): Map<String, Any?> {
        return mapOf("ok" to false, "error" to mapOf("code" to code, "message" to message))
    }
}
