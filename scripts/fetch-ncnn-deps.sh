#!/usr/bin/env bash
#
# Fetch ncnn + opencv-mobile prebuilt Android libraries.
# These are large binary packages excluded from git; run this script
# before building the Android OCR native layer.
#
# Usage:  scripts/fetch-ncnn-deps.sh
#
set -euo pipefail

JNI_DIR="$(cd "$(dirname "$0")/../android/app/src/main/jni" && pwd)"
ASSETS_DIR="$(dirname "$0")/../android/app/src/main/assets/ocr_models"
NCNN_VERSION="20260526"
OPENCV_MOBILE_VERSION="4.13.0"
OPENCV_MOBILE_RELEASE="v35"
PPOCRV5_REPO_BASE="https://github.com/nihui/ncnn-android-ppocrv5/raw/master/app/src/main/assets"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "== Fetching ncnn $NCNN_VERSION (CPU-only, static) =="
NCNN_ZIP="$TMP_DIR/ncnn-android.zip"
curl -L -o "$NCNN_ZIP" \
  "https://github.com/Tencent/ncnn/releases/download/${NCNN_VERSION}/ncnn-${NCNN_VERSION}-android.zip"
unzip -q -o "$NCNN_ZIP" -d "$TMP_DIR/ncnn-extracted"
rm -rf "$JNI_DIR/ncnn-android"
mv "$TMP_DIR/ncnn-extracted/ncnn-${NCNN_VERSION}-android" "$JNI_DIR/ncnn-android"
echo "  -> $JNI_DIR/ncnn-android"

echo "== Fetching opencv-mobile $OPENCV_MOBILE_VERSION =="
OPENCV_ZIP="$TMP_DIR/opencv-mobile-android.zip"
curl -L -o "$OPENCV_ZIP" \
  "https://github.com/nihui/opencv-mobile/releases/download/${OPENCV_MOBILE_RELEASE}/opencv-mobile-${OPENCV_MOBILE_VERSION}-android.zip"
unzip -q -o "$OPENCV_ZIP" -d "$TMP_DIR/opencv-extracted"
rm -rf "$JNI_DIR/opencv-mobile"
mv "$TMP_DIR/opencv-extracted/opencv-mobile-${OPENCV_MOBILE_VERSION}-android" "$JNI_DIR/opencv-mobile"
echo "  -> $JNI_DIR/opencv-mobile"

echo "== Fetching PPOCRv5 mobile models =="
mkdir -p "$ASSETS_DIR"
for f in PP_OCRv5_mobile_det.ncnn.bin PP_OCRv5_mobile_det.ncnn.param \
         PP_OCRv5_mobile_rec.ncnn.bin PP_OCRv5_mobile_rec.ncnn.param; do
  curl -L -o "$ASSETS_DIR/$f" "$PPOCRV5_REPO_BASE/$f"
  echo "  -> $ASSETS_DIR/$f"
done

echo "== Done =="
