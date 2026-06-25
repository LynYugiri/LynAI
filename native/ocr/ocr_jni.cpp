// LynAI JNI bridge for PPOCRv5 ncnn OCR.
//
// Copyright (C) 2025 THL A29 Limited, a Tencent company. All rights reserved.
// (ncnn BSD-3-Clause portion)
//
// The JNI interface in this file is licensed under GPL-3.0-or-later (LynAI).
//
// Inputs:  Android Bitmap + AssetManager
// Output:  JSON string [{text, bounds, orientation, prob}, ...]

#include <android/bitmap.h>
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <android/log.h>

#include <jni.h>

#include <string>
#include <vector>
#include <sstream>
#include <mutex>

#include <opencv2/core/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>

#include "ppocrv5.h"
#include "ppocrv5_dict.h"

#define TAG "lynai_ocr"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static PPOCRv5* g_ocr = nullptr;
static std::mutex g_ocr_lock;
static bool g_loaded = false;

static std::string build_text(const Object& obj)
{
    std::string text;
    for (size_t j = 0; j < obj.text.size(); j++)
    {
        const Character& ch = obj.text[j];
        if (ch.id < 0 || ch.id >= character_dict_size)
        {
            if (!text.empty() && text.back() != ' ')
                text += ' ';
            continue;
        }

        text += character_dict[ch.id];

        if (obj.orientation == 1 && j + 1 < obj.text.size())
            text += '\n';
    }
    return text;
}

static std::string escape_json(const std::string& s)
{
    std::string out;
    out.reserve(s.size() + 16);
    for (size_t i = 0; i < s.size(); i++)
    {
        char c = s[i];
        switch (c)
        {
        case '"':  out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b";  break;
        case '\f': out += "\\f";  break;
        case '\n': out += "\\n";  break;
        case '\r': out += "\\r";  break;
        case '\t': out += "\\t";  break;
        default:
            if (static_cast<unsigned char>(c) < 0x20)
            {
                char buf[8];
                snprintf(buf, sizeof(buf), "\\u%04x", c);
                out += buf;
            }
            else
            {
                out += c;
            }
            break;
        }
    }
    return out;
}

static std::string objects_to_json(const std::vector<Object>& objects)
{
    std::ostringstream oss;
    oss << '[';

    bool first = true;
    for (size_t i = 0; i < objects.size(); i++)
    {
        const Object& obj = objects[i];

        std::string text = build_text(obj);
        if (text.empty())
            continue;

        // Compute axis-aligned bounding box from rotated rect corners
        cv::Point2f corners[4];
        obj.rrect.points(corners);

        float min_x = corners[0].x, max_x = corners[0].x;
        float min_y = corners[0].y, max_y = corners[0].y;
        for (int j = 1; j < 4; j++)
        {
            min_x = std::min(min_x, corners[j].x);
            max_x = std::max(max_x, corners[j].x);
            min_y = std::min(min_y, corners[j].y);
            max_y = std::max(max_y, corners[j].y);
        }

        int left   = (int)(min_x + 0.5f);
        int top    = (int)(min_y + 0.5f);
        int right  = (int)(max_x + 0.5f);
        int bottom = (int)(max_y + 0.5f);

        if (right <= left || bottom <= top)
            continue;

        if (!first)
            oss << ',';
        first = false;

        oss << '{';
        oss << "\"id\":\"ocr_" << i << "\",";
        oss << "\"text\":\"" << escape_json(text) << "\",";
        oss << "\"bounds\":{";
        oss << "\"left\":"   << left   << ',';
        oss << "\"top\":"    << top    << ',';
        oss << "\"right\":"  << right  << ',';
        oss << "\"bottom\":" << bottom;
        oss << "},";
        oss << "\"orientation\":" << obj.orientation << ',';
        oss << "\"prob\":" << obj.prob;
        oss << '}';
    }

    oss << ']';
    return oss.str();
}

static bool bitmap_to_mat(JNIEnv* env, jobject bitmap, cv::Mat& mat)
{
    AndroidBitmapInfo info;
    if (AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS)
    {
        LOGE("AndroidBitmap_getInfo failed");
        return false;
    }

    if (info.format != ANDROID_BITMAP_FORMAT_RGBA_8888)
    {
        LOGE("bitmap format is not RGBA_8888 (got %d)", info.format);
        return false;
    }

    void* pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels) != ANDROID_BITMAP_RESULT_SUCCESS)
    {
        LOGE("AndroidBitmap_lockPixels failed");
        return false;
    }

    cv::Mat rgba((int)info.height, (int)info.width, CV_8UC4, pixels);
    cv::cvtColor(rgba, mat, cv::COLOR_RGBA2RGB);

    AndroidBitmap_unlockPixels(env, bitmap);
    return true;
}

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_github_lynyugiri_lynai_NcnnOcrRecognizer_nativeInit(
    JNIEnv* env, jobject thiz, jobject assetManager)
{
    std::lock_guard<std::mutex> g(g_ocr_lock);

    if (g_loaded && g_ocr)
        return JNI_TRUE;

    AAssetManager* mgr = AAssetManager_fromJava(env, assetManager);
    if (!mgr)
    {
        LOGE("AAssetManager_fromJava failed");
        return JNI_FALSE;
    }

    delete g_ocr;
    g_ocr = new PPOCRv5;

    g_ocr->set_target_size(640);

    bool use_fp16 = true;
    bool use_gpu = false;

    int ret = g_ocr->load(mgr,
        "ocr_models/PP_OCRv5_mobile_det.ncnn.param",
        "ocr_models/PP_OCRv5_mobile_det.ncnn.bin",
        "ocr_models/PP_OCRv5_mobile_rec.ncnn.param",
        "ocr_models/PP_OCRv5_mobile_rec.ncnn.bin",
        use_fp16, use_gpu);

    if (ret != 0)
    {
        LOGE("PPOCRv5 load failed: %d", ret);
        delete g_ocr;
        g_ocr = nullptr;
        g_loaded = false;
        return JNI_FALSE;
    }

    g_loaded = true;
    LOGD("PPOCRv5 models loaded successfully");
    return JNI_TRUE;
}

JNIEXPORT jstring JNICALL
Java_com_github_lynyugiri_lynai_NcnnOcrRecognizer_nativeRecognize(
    JNIEnv* env, jobject thiz, jobject bitmap)
{
    std::lock_guard<std::mutex> g(g_ocr_lock);

    if (!g_loaded || !g_ocr)
    {
        return env->NewStringUTF("{\"error\":\"not_loaded\"}");
    }

    cv::Mat rgb;
    if (!bitmap_to_mat(env, bitmap, rgb))
    {
        return env->NewStringUTF("{\"error\":\"bitmap_failed\"}");
    }

    std::vector<Object> objects;
    g_ocr->detect_and_recognize(rgb, objects);

    std::string json = objects_to_json(objects);
    return env->NewStringUTF(json.c_str());
}

JNIEXPORT void JNICALL
Java_com_github_lynyugiri_lynai_NcnnOcrRecognizer_nativeRelease(
    JNIEnv* env, jobject thiz)
{
    std::lock_guard<std::mutex> g(g_ocr_lock);
    delete g_ocr;
    g_ocr = nullptr;
    g_loaded = false;
    LOGD("PPOCRv5 models released");
}

} // extern "C"
