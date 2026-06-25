cmake_minimum_required(VERSION 3.14)

project(lynai_ocr LANGUAGES C CXX)

# ncnn prebuilt (CPU-only static, fetched by scripts/fetch-ncnn-deps.sh)
set(ncnn_DIR ${CMAKE_CURRENT_LIST_DIR}/../../android/app/src/main/jni/ncnn-android/${ANDROID_ABI}/lib/cmake/ncnn)
find_package(ncnn REQUIRED)

# opencv-mobile prebuilt (static, fetched by scripts/fetch-ncnn-deps.sh)
set(OpenCV_DIR ${CMAKE_CURRENT_LIST_DIR}/../../android/app/src/main/jni/opencv-mobile/sdk/native/jni)
find_package(OpenCV REQUIRED core imgproc)

add_library(lynai_ocr SHARED
    ocr_jni.cpp
    ppocrv5.cpp
    omp_compat.cpp
)

target_include_directories(lynai_ocr PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# ncnn's cmake config already adds -fopenmp -static-openmp to INTERFACE_LINK_LIBRARIES.
# Do NOT use find_package(OpenMP) / OpenMP::OpenMP_CXX — it forces libomp.so (dynamic),
# which is missing __kmpc_dispatch_deinit in this NDK.  -static-openmp selects libomp.a.
target_link_libraries(lynai_ocr
    ncnn
    ${OpenCV_LIBS}
    jnigraphics
    log
    android
)

target_compile_options(lynai_ocr PRIVATE
    -Wall -Wextra -Wno-unused-parameter
    -fopenmp
)
