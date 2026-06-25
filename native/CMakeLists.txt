cmake_minimum_required(VERSION 3.14)

project(lynai_native LANGUAGES C CXX)

# Unified native build entry point.
# AGP's externalNativeBuild.cmake.path points here so both tree_sitter
# and ocr libraries are built from a single CMake invocation.

add_subdirectory(tree_sitter)
add_subdirectory(ocr)
