# vivo BlueLM 端侧 LLM SDK 的 JNI 层通过 GetMethodID 按名称查找
# LlmManager 的回调方法；R8 重命名或移除这些方法会导致
# NoSuchMethodError 并触发 native abort。
-keep class com.vivo.llmsdk.** { *; }
