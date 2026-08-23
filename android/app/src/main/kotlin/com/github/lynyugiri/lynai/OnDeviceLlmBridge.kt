package com.github.lynyugiri.lynai

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.vivo.llmsdk.LlmConfig
import com.vivo.llmsdk.LlmManager
import com.vivo.llmsdk.TokenCallback
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/// BlueLM 端侧模型的 Flutter 平台桥。
///
/// 模型文件位于设备普通文件系统路径（默认 /sdcard/1225，与 Demo 一致），
/// 由 [BluelmModelLocator] 解析并预检，再由 com.vivo.llmsdk.LlmManager 加载。
object OnDeviceLlmBridge : EventChannel.StreamHandler {
    private const val METHOD_CHANNEL = "lynai/on_device_llm"
    private const val EVENT_CHANNEL = "lynai/on_device_llm/events"
    private const val PREFS_NAME = "lynai.local_bluelm"
    private const val KEY_MODEL_PATH = "model_path"

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "bluelm-llm-bridge")
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var activity: Activity? = null

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var manager: LlmManager? = null

    @Volatile
    private var state: String = STATE_NOT_CONFIGURED

    @Volatile
    private var busy = false

    @Volatile
    private var generationId: String? = null

    @Volatile
    private var lastErrorCode: Int? = null

    @Volatile
    private var lastError: String? = null

    @Volatile
    private var lastValidation: BluelmModelLocator.ValidationResult? = null

    fun install(activity: Activity, methodChannel: MethodChannel, eventChannel: EventChannel) {
        this.activity = activity
        appContext = activity.applicationContext
        eventChannel.setStreamHandler(this)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(statusSnapshot())
                "refreshStatus" -> refreshStatus(result)
                "setModelPath" -> {
                    val path = BluelmModelLocator.normalize(
                        call.argument<String>("path"),
                    )
                    setModelPath(path, result)
                }
                "requestStoragePermission" -> result.success(
                    requestStoragePermission(),
                )
                "validateModel" -> validateModel(result)
                "init" -> initModel(call.argument<Map<*, *>>("params"), result)
                "generate" -> generate(
                    call.argument<String>("requestId").orEmpty(),
                    call.argument<String>("prompt").orEmpty(),
                    result,
                )
                "interrupt" -> {
                    interrupt()
                    result.success(null)
                }
                "release" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun uninstall() {
        eventSink = null
        activity = null
        release()
    }

    private fun refreshStatus(result: MethodChannel.Result) {
        executor.execute {
            val snapshot = recomputeStatus()
            mainHandler.post { result.success(snapshot) }
        }
    }

    private fun setModelPath(path: String, result: MethodChannel.Result) {
        executor.execute {
            val context = appContext
            if (context != null) {
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_MODEL_PATH, path)
                    .apply()
            }
            releaseManagerOnExecutor()
            lastErrorCode = null
            lastError = null
            lastValidation = null
            val snapshot = recomputeStatus()
            mainHandler.post { result.success(snapshot) }
        }
    }

    private fun validateModel(result: MethodChannel.Result) {
        executor.execute {
            val snapshot = recomputeStatus()
            mainHandler.post { result.success(snapshot) }
        }
    }

    private fun initModel(rawParams: Map<*, *>?, result: MethodChannel.Result) {
        executor.execute {
            val snapshot = initOnExecutor(rawParams ?: emptyMap<Any, Any>())
            mainHandler.post { result.success(snapshot) }
        }
    }

    private fun initOnExecutor(rawParams: Map<*, *>): Map<String, Any?> {
        if (!isSupportedAbi()) {
            lastValidation = null
            updateState(STATE_UNSUPPORTED, "仅支持 arm64-v8a 设备", null, null)
            return statusSnapshot()
        }
        if (!hasStoragePermission()) {
            lastValidation = null
            updateState(STATE_PERMISSION_REQUIRED, "需要所有文件访问权限", null, null)
            return statusSnapshot()
        }
        val configuredPath = configuredPath()
        val validation = BluelmModelLocator.validate(
            BluelmModelLocator.resolveConfigPath(configuredPath),
        )
        lastValidation = validation
        if (!validation.valid || validation.configPath == null) {
            updateState(
                STATE_INVALID_MODEL,
                validation.error ?: "模型文件校验失败",
                null,
                null,
            )
            return statusSnapshot()
        }

        releaseManagerOnExecutor()
        updateState(STATE_INITIALIZING, validation.error, null, null)
        val params = paramsFrom(rawParams)
        val candidates = initCandidates(validation.configPath)
        var lastCode: Int? = null
        var lastMessage: String? = null
        var created: LlmManager? = null
        for (candidate in candidates) {
            var candidateManager: LlmManager? = null
            try {
                candidateManager = LlmManager()
                val config = LlmConfig().apply {
                    modelPath = candidate
                    nPredict = params.nPredict
                    nCtx = params.nCtx
                    nThreads = params.nThreads
                    topK = params.topK
                    topP = params.topP
                    temperature = params.temperature
                    npuPower = params.npuPower
                    multimodal = params.multimodal
                }
                val code = candidateManager.init(config)
                if (code == 0) {
                    created = candidateManager
                    lastCode = null
                    lastMessage = null
                    break
                }
                lastCode = code
                lastMessage = "LlmManager.init 返回 $code"
            } catch (error: Throwable) {
                lastCode = CODE_NATIVE_LOAD_FAILED
                lastMessage = error.message ?: error.toString()
            }
            if (candidateManager != null && created !== candidateManager) {
                releaseQuietly(candidateManager)
            }
        }

        if (created == null) {
            updateState(
                STATE_ERROR,
                lastMessage ?: "模型初始化失败",
                lastCode,
                null,
            )
            return statusSnapshot()
        }
        synchronized(lock) {
            manager = created
            state = STATE_READY
            busy = false
            generationId = null
            lastErrorCode = null
            lastError = null
        }
        return statusSnapshot()
    }

    private fun generate(
        requestId: String,
        prompt: String,
        result: MethodChannel.Result,
    ) {
        if (!isSupportedAbi()) {
            result.success(errorResult("unsupported", "当前设备不支持 BlueLM APU"))
            return
        }
        if (requestId.isEmpty() || prompt.isEmpty()) {
            result.success(errorResult("invalid_arguments", "缺少 requestId 或 prompt"))
            return
        }
        val current: LlmManager
        synchronized(lock) {
            if (busy) {
                result.success(errorResult("busy", "本地模型正在生成中"))
                return
            }
            val loaded = manager
            if (loaded == null || state != STATE_READY) {
                result.success(
                    errorResult("not_initialized", "本地模型未初始化"),
                )
                return
            }
            current = loaded
            busy = true
            generationId = requestId
        }
        result.success(mapOf("ok" to true, "started" to true))
        try {
            current.generate(prompt, callbackFor(requestId))
        } catch (error: Throwable) {
            finishGeneration(
                requestId,
                success = false,
                code = CODE_GENERATE_FAILED,
                message = error.message ?: error.toString(),
            )
        }
    }

    private fun callbackFor(requestId: String): TokenCallback {
        return object : TokenCallback {
            override fun onToken(token: String) {
                emit(
                    mapOf(
                        "type" to "token",
                        "requestId" to requestId,
                        "token" to token,
                    ),
                )
            }

            override fun onComplete() {
                finishGeneration(requestId, success = true, code = 0, message = null)
            }

            override fun onError(code: Int, msg: String) {
                finishGeneration(requestId, success = false, code = code, message = msg)
            }
        }
    }

    private fun finishGeneration(
        requestId: String,
        success: Boolean,
        code: Int,
        message: String?,
    ) {
        val shouldFinish: Boolean
        synchronized(lock) {
            shouldFinish = generationId == requestId
            if (shouldFinish) {
                busy = false
                generationId = null
                if (state == STATE_READY) {
                    lastErrorCode = if (success) null else code
                    lastError = if (success) null else message
                }
            }
        }
        if (!shouldFinish) return
        emit(
            mapOf(
                "type" to if (success) "completed" else "error",
                "requestId" to requestId,
                "code" to code,
                "message" to (message ?: ""),
            ),
        )
    }

    private fun interrupt() {
        synchronized(lock) {
            val current = manager ?: return
            try {
                current.interrupt()
            } catch (_: Throwable) {
                // 释放或未生成时忽略
            }
        }
    }

    private fun release() {
        executor.execute { releaseManagerOnExecutor() }
    }

    private fun releaseManagerOnExecutor() {
        val current = synchronized(lock) {
            val existing = manager
            manager = null
            busy = false
            generationId = null
            state = STATE_NOT_CONFIGURED
            existing
        }
        if (current != null) releaseQuietly(current)
    }

    private fun releaseQuietly(target: LlmManager) {
        try {
            target.release()
        } catch (_: Throwable) {
            // 已释放
        }
    }

    private fun recomputeStatus(): Map<String, Any?> {
        if (!isSupportedAbi()) {
            lastValidation = null
            updateState(STATE_UNSUPPORTED, "仅支持 arm64-v8a 设备", null, null)
            return statusSnapshot()
        }
        val configuredPath = configuredPath()
        if (configuredPath.isEmpty()) {
            lastValidation = null
            updateState(STATE_NOT_CONFIGURED, "尚未设置模型路径", null, null)
            return statusSnapshot()
        }
        if (!hasStoragePermission()) {
            lastValidation = null
            updateState(STATE_PERMISSION_REQUIRED, "需要所有文件访问权限", null, null)
            return statusSnapshot()
        }
        val resolved = BluelmModelLocator.resolveConfigPath(configuredPath)
        if (resolved == null) {
            lastValidation = null
            updateState(STATE_MODEL_NOT_FOUND, "未找到模型配置", null, null)
            return statusSnapshot()
        }
        val validation = BluelmModelLocator.validate(resolved)
        lastValidation = validation
        if (!validation.valid) {
            updateState(
                STATE_INVALID_MODEL,
                validation.error ?: "模型文件校验失败",
                null,
                null,
            )
            return statusSnapshot()
        }
        val alreadyReady = synchronized(lock) { state == STATE_READY && manager != null }
        val currentlyInitializing = synchronized(lock) { state == STATE_INITIALIZING }
        if (!alreadyReady && currentlyInitializing) return statusSnapshot()
        if (!alreadyReady) {
            synchronized(lock) {
                state = STATE_VALIDATED
                lastErrorCode = null
                lastError = null
            }
        }
        return statusSnapshot()
    }

    private fun statusSnapshot(): Map<String, Any?> {
        val validation = lastValidation
        val configured = configuredPath()
        return mapOf(
            "ok" to true,
            "state" to state,
            "busy" to busy,
            "supportedAbi" to isSupportedAbi(),
            "apiLevel" to Build.VERSION.SDK_INT,
            "storagePermission" to hasStoragePermission(),
            "modelPath" to configured,
            "resolvedConfigPath" to validation?.configPath,
            "modelVersion" to validation?.modelVersion,
            "missingFiles" to (validation?.missingFiles ?: emptyList<String>()),
            "lastErrorCode" to lastErrorCode,
            "lastError" to lastError,
        )
    }

    private fun requestStoragePermission(): Map<String, Any?> {
        if (hasStoragePermission()) {
            return mapOf("ok" to true, "granted" to true)
        }
        val currentActivity = activity
        if (currentActivity == null) {
            return errorResult("activity_unavailable", "Activity 不可用")
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                currentActivity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:${currentActivity.packageName}"),
                    ),
                )
                mapOf("ok" to true, "granted" to false, "requested" to true)
            } catch (error: Throwable) {
                errorResult(
                    "permission_error",
                    error.message ?: error.toString(),
                )
            }
        } else {
            ActivityCompat.requestPermissions(
                currentActivity,
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST_CODE,
            )
            mapOf("ok" to true, "granted" to false, "requested" to true)
        }
    }

    private fun hasStoragePermission(): Boolean {
        val context = appContext ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun isSupportedAbi(): Boolean {
        return Build.SUPPORTED_ABIS.any { it == "arm64-v8a" }
    }

    private fun configuredPath(): String {
        val context = appContext ?: return BluelmModelLocator.DEFAULT_MODEL_PATH
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_MODEL_PATH, BluelmModelLocator.DEFAULT_MODEL_PATH)
            ?: BluelmModelLocator.DEFAULT_MODEL_PATH
    }

    private fun initCandidates(configPath: String): List<String> {
        val candidates = linkedSetOf<String>()
        val configFile = java.io.File(configPath)
        candidates.add(configFile.absolutePath)
        val directParent = configFile.parentFile
        directParent?.let { candidates.add(it.absolutePath) }
        if (directParent?.name == BluelmModelLocator.NESTED_MODEL_DIR) {
            directParent.parentFile?.let { candidates.add(it.absolutePath) }
        }
        return candidates.toList()
    }

    private data class LlmParams(
        val nPredict: Int,
        val nCtx: Int,
        val nThreads: Int,
        val topK: Int,
        val topP: Float,
        val temperature: Float,
        val npuPower: Int,
        val multimodal: Boolean,
    )

    private fun paramsFrom(raw: Map<*, *>): LlmParams {
        return LlmParams(
            nPredict = (raw["nPredict"] as? Number)?.toInt() ?: DEFAULT_N_PREDICT,
            nCtx = (raw["nCtx"] as? Number)?.toInt() ?: DEFAULT_N_CTX,
            nThreads = (raw["nThreads"] as? Number)?.toInt() ?: DEFAULT_N_THREADS,
            topK = (raw["topK"] as? Number)?.toInt() ?: DEFAULT_TOP_K,
            topP = (raw["topP"] as? Number)?.toFloat() ?: DEFAULT_TOP_P,
            temperature = (raw["temperature"] as? Number)?.toFloat()
                ?: DEFAULT_TEMPERATURE,
            npuPower = (raw["npuPower"] as? Number)?.toInt() ?: DEFAULT_NPU_POWER,
            multimodal = raw["multimodal"] == true,
        )
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun updateState(
        nextState: String,
        message: String?,
        code: Int?,
        validation: BluelmModelLocator.ValidationResult?,
    ) {
        synchronized(lock) {
            state = nextState
            lastError = message
            lastErrorCode = code
            if (validation != null) lastValidation = validation
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun errorResult(code: String, message: String): Map<String, Any?> {
        return mapOf(
            "ok" to false,
            "error" to mapOf("code" to code, "message" to message),
        )
    }

    private const val STORAGE_PERMISSION_REQUEST_CODE = 7813
    private const val CODE_NATIVE_LOAD_FAILED = -10000
    private const val CODE_GENERATE_FAILED = -10001

    private const val DEFAULT_N_PREDICT = 200
    private const val DEFAULT_N_CTX = 4096
    private const val DEFAULT_N_THREADS = 4
    private const val DEFAULT_TOP_K = 1
    private const val DEFAULT_TOP_P = 1.0f
    private const val DEFAULT_TEMPERATURE = 0.0f
    private const val DEFAULT_NPU_POWER = 100

    const val STATE_NOT_CONFIGURED = "not_configured"
    const val STATE_UNSUPPORTED = "unsupported"
    const val STATE_PERMISSION_REQUIRED = "permission_required"
    const val STATE_MODEL_NOT_FOUND = "model_not_found"
    const val STATE_INVALID_MODEL = "invalid_model"
    const val STATE_VALIDATED = "validated"
    const val STATE_INITIALIZING = "initializing"
    const val STATE_READY = "ready"
    const val STATE_ERROR = "error"
}
