package com.github.lynyugiri.lynai

import org.json.JSONObject
import java.io.File

/// 定位并预检设备上的 BlueLM MTK 模型目录。
///
/// SDK 需要普通文件系统路径，因此这里只做路径解析和 config JSON 引用文件
/// 检查；模型权重不会被复制或修改。
object BluelmModelLocator {
    const val DEFAULT_MODEL_PATH = "/sdcard/1225"
    const val CONFIG_FILE_NAME = "bluelm_mtk_llm_config.json"
    const val NESTED_MODEL_DIR = "1.7.0.4_1225_mtk9500"

    data class ValidationResult(
        val valid: Boolean,
        val configPath: String?,
        val modelVersion: String?,
        val missingFiles: List<String>,
        val error: String?,
    ) {
        companion object {
            fun failure(error: String) = ValidationResult(
                valid = false,
                configPath = null,
                modelVersion = null,
                missingFiles = emptyList(),
                error = error,
            )
        }
    }

    /// 归一化用户输入的模型路径。
    fun normalize(rawPath: String?): String {
        return rawPath?.trim()?.trim('"')?.trim('\'') ?: ""
    }

    /// 支持：
    /// - config 文件完整路径
    /// - 包含 config 的目录
    /// - 包含 `1.7.0.4_1225_mtk9500` 子目录的目录
    fun resolveConfigPath(rawPath: String): String? {
        val path = normalize(rawPath)
        if (path.isEmpty()) return null
        val file = File(path)
        if (file.isFile) return file.absolutePath
        if (file.isDirectory) {
            directConfig(file)?.let { return it }
            File(file, NESTED_MODEL_DIR).takeIf { it.isDirectory }
                ?.let { directConfig(it)?.let { config -> return config } }
        }
        // 用户可能输入了缺少文件名的嵌套目录；File.isDirectory 已覆盖。
        return null
    }

    private fun directConfig(dir: File): String? {
        val config = File(dir, CONFIG_FILE_NAME)
        return if (config.isFile) config.absolutePath else null
    }

    /// 预检 config 引用的模型文件是否都存在。只读，不加载权重。
    fun validate(configPath: String?): ValidationResult {
        if (configPath.isNullOrBlank()) {
            return ValidationResult.failure("模型路径为空")
        }
        val configFile = File(configPath)
        if (!configFile.isFile) {
            return ValidationResult.failure("模型配置不存在: ${configFile.absolutePath}")
        }
        val root = try {
            JSONObject(configFile.readText())
        } catch (error: Exception) {
            return ValidationResult.failure("模型配置解析失败: ${error.message}")
        }
        val baseDir = configFile.parentFile ?: return ValidationResult.failure(
            "无法确定模型目录",
        )
        val referenced = linkedSetOf<String>()
        var modelVersion: String? = null
        try {
            val llm = root.optJSONObject("llm_model")
            if (llm == null) return ValidationResult.failure("配置缺少 llm_model")
            modelVersion = llm.optString("version").takeIf { it.isNotBlank() }
            addString(llm, "vocab_bin", referenced)
            addString(llm, "embedding_bin", referenced)
            addStringArray(llm, "share_weights_bins", referenced)
            val baseParams = llm.optJSONArray("base_params") ?: return ValidationResult.failure(
                "配置缺少 base_params",
            )
            for (i in 0 until baseParams.length()) {
                val block = baseParams.optJSONObject(i) ?: continue
                addString(block, "overture_bin", referenced)
                addStringArray(block, "prompt_models", referenced)
                addStringArray(block, "decode_models", referenced)
                addStringArray(block, "fold_prompt_models", referenced)
                addStringArray(block, "fold_decode_models", referenced)
                addStringArray(block, "eagle_prompt_models", referenced)
                addStringArray(block, "eagle_decode_models", referenced)
                addStringArray(block, "pd_prompt_models", referenced)
                addStringArray(block, "pd_decode_models", referenced)
                val loras = block.optJSONArray("lora_dlas") ?: continue
                for (j in 0 until loras.length()) {
                    val lora = loras.optJSONObject(j) ?: continue
                    addStringArray(lora, "prompt_models", referenced)
                    addStringArray(lora, "decode_models", referenced)
                    addStringArray(lora, "fold_prompt_models", referenced)
                    addStringArray(lora, "fold_decode_models", referenced)
                    addStringArray(lora, "eagle_prompt_models", referenced)
                    addStringArray(lora, "eagle_decode_models", referenced)
                    addStringArray(lora, "pd_prompt_models", referenced)
                    addStringArray(lora, "pd_decode_models", referenced)
                }
            }
            val vit = root.optJSONObject("vit_model")
            if (vit != null) {
                addString(vit, "model_clip_path", referenced)
                addString(vit, "model_clip_multi_batch_path", referenced)
                addString(vit, "clip_sharedw_path", referenced)
                addString(vit, "model_class_path", referenced)
                addString(vit, "conv2d_weight_path", referenced)
            }
        } catch (error: Exception) {
            return ValidationResult.failure("模型配置解析失败: ${error.message}")
        }

        val missing = referenced.filter { name ->
            name.isBlank() || !File(baseDir, name).isFile
        }.sorted()
        return ValidationResult(
            valid = missing.isEmpty(),
            configPath = configFile.absolutePath,
            modelVersion = modelVersion,
            missingFiles = missing,
            error = if (missing.isEmpty()) null else "缺少 ${missing.size} 个模型文件",
        )
    }

    private fun addString(obj: JSONObject, key: String, target: MutableSet<String>) {
        val value = obj.optString(key).trim()
        if (value.isNotEmpty()) target.add(value)
    }

    private fun addStringArray(
        obj: JSONObject,
        key: String,
        target: MutableSet<String>,
    ) {
        val array = obj.optJSONArray(key) ?: return
        for (i in 0 until array.length()) {
            val value = array.optString(i).trim()
            if (value.isNotEmpty()) target.add(value)
        }
    }
}
