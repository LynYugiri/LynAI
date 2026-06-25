package com.github.lynyugiri.lynai

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.util.Base64
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min

object OnDeviceOcrRecognizer {
    private val recognizer by lazy {
        TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    }

    fun recognize(imageBase64: String, result: MethodChannel.Result) {
        try {
            val decoded = Base64.decode(imageBase64, Base64.NO_WRAP)
            val bitmap = BitmapFactory.decodeByteArray(decoded, 0, decoded.size)
            if (bitmap == null) {
                result.success(error("decode_failed", "无法解码截图"))
                return
            }
            val image = InputImage.fromBitmap(bitmap, 0)
            recognizer.process(image)
                .addOnSuccessListener { text ->
                    val blocks = mutableListOf<Map<String, Any?>>()
                    for (block in text.textBlocks) {
                        val blockText = block.text.trim()
                        if (blockText.isEmpty()) continue
                        val bounds = block.boundingBox
                        if (bounds != null) {
                            blocks.add(mapOf(
                                "id" to "ocr_${blocks.size}",
                                "text" to blockText,
                                "bounds" to mapOf(
                                    "left" to bounds.left,
                                    "top" to bounds.top,
                                    "right" to bounds.right,
                                    "bottom" to bounds.bottom
                                ),
                                "lines" to block.lines.map { line ->
                                    val lb = line.boundingBox ?: Rect()
                                    mapOf(
                                        "text" to line.text,
                                        "bounds" to mapOf(
                                            "left" to lb.left,
                                            "top" to lb.top,
                                            "right" to lb.right,
                                            "bottom" to lb.bottom
                                        )
                                    )
                                }
                            ))
                        }
                    }
                    result.success(mapOf(
                        "ok" to true,
                        "result" to blocks
                    ))
                    bitmap.recycle()
                }
                .addOnFailureListener { e ->
                    result.success(error("ocr_failed", "OCR 识别失败: ${e.message}"))
                    bitmap.recycle()
                }
        } catch (e: Exception) {
            result.success(error("ocr_exception", "OCR 异常: ${e.message}"))
        }
    }

    private fun error(code: String, message: String): Map<String, Any?> {
        return mapOf("ok" to false, "error" to mapOf("code" to code, "message" to message))
    }
}
