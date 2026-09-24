/*
 * 字节视图与 ArrayBuffer 之间的安全转换。
 *
 * 鸿蒙的文件与图像 API 接受的是 `ArrayBuffer`，而 Dart 侧传来的是 `Uint8Array`
 * 视图。如果直接把 `bytes.buffer` 传下去，一旦该视图只是底层大 buffer 的一段
 * （带 byteOffset/byteLength），就会把多余字节一起写入或解码——这类错误在设备上
 * 表现为「文件损坏」而不会报错，因此这里统一折算成精确长度的 buffer。
 *
 * 纯逻辑，无 ArkTS 依赖，由 Node 单元测试覆盖（scripts/ohos-arkts-tests/）。
 */
export function exactBuffer(bytes: Uint8Array): ArrayBuffer {
  if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
    return bytes.buffer as ArrayBuffer;
  }
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer as ArrayBuffer;
}
