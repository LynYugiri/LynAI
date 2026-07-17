package_path = Dir[
  File.join(
    Dir.home,
    '.pub-cache/hosted/pub.dev/speech_to_text-*/darwin/speech_to_text/Package.swift',
  ),
].first
abort('speech_to_text Package.swift not found') unless package_path

package_source = File.read(package_path)
package_patched = package_source.sub('.macOS("10.14")', '.macOS("10.15")')
if package_patched != package_source
  File.write(package_path, package_patched)
elsif !package_source.include?('.macOS("10.15")')
  abort('speech_to_text Package.swift patch did not match')
end

swift_path = Dir[
  File.join(
    Dir.home,
    '.pub-cache/hosted/pub.dev/speech_to_text-*/darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift',
  ),
].first
abort('speech_to_text Swift source not found') unless swift_path

source = File.read(swift_path)
patched = source.sub(
  /var\s+localeStr:\s*String\?\s*=\s*nil\s*\n\s*if\s+let\s+localeParam\s*=\s*argsArr\["localeId"\]\s+as\?\s+String\s*\{\s*\n\s*localeStr\s*=\s*localeParam\s*\n\s*\}/,
  'let localeStr = argsArr["localeId"] as? String',
)
if patched != source
  File.write(swift_path, patched)
elsif !source.include?('let localeStr = argsArr["localeId"] as? String')
  abort('speech_to_text Swift source patch did not match')
end
