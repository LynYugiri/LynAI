import 'dart:convert';

/// 新建插件时可选的脚手架模板类型。
enum PluginScaffoldKind {
  /// 空 Lua 入口，适合从零开始写工具或函数。
  blank,

  /// 带一个示例 tool 的 Lua 插件，演示 lynai.json / lynai.call 与异步续延。
  luaTool,

  /// 只声明一个可编辑 Skill 的插件，入口保留空实现。
  skill,

  /// 带 WebView 功能页的插件，包含 HTML/CSS/JS 可编辑文件。
  featurePage,
}

extension PluginScaffoldKindLabel on PluginScaffoldKind {
  String get label => switch (this) {
    PluginScaffoldKind.blank => '空白 Lua 插件',
    PluginScaffoldKind.luaTool => 'Lua 工具插件',
    PluginScaffoldKind.skill => 'Skill 插件',
    PluginScaffoldKind.featurePage => 'WebView 功能页插件',
  };

  String get description => switch (this) {
    PluginScaffoldKind.blank => '只生成 plugin.json 和 main.lua，适合熟悉插件结构的作者。',
    PluginScaffoldKind.luaTool => '生成一个可被模型调用的 hello 工具，演示 Lua 沙箱 API。',
    PluginScaffoldKind.skill => '生成一个可编辑的 Skill 工作流说明，适合沉淀方法论。',
    PluginScaffoldKind.featurePage => '生成 WebView 功能页入口及 HTML/CSS/JS 文件。',
  };
}

/// 生成新插件的初始文件集合。
///
/// 只负责产出合法的 manifest 和模板内容，不直接写文件。目录安装与原子替换
/// 由 [PluginRepository.importDirectory] 承担。
class PluginScaffoldService {
  PluginScaffoldService._();

  /// 生成插件脚手架文件，返回「相对路径 -> 文件内容」的映射。
  static Map<String, String> buildScaffold({
    required String id,
    required String name,
    required String version,
    required String author,
    required String description,
    required PluginScaffoldKind kind,
  }) {
    final manifest = _manifestFor(
      id: id,
      name: name,
      version: version,
      author: author,
      description: description,
      kind: kind,
    );
    final files = <String, String>{
      'plugin.json': const JsonEncoder.withIndent('  ').convert(manifest),
    };
    switch (kind) {
      case PluginScaffoldKind.blank:
        files['main.lua'] = _blankLua(id, name);
      case PluginScaffoldKind.luaTool:
        files['main.lua'] = _luaToolScript();
        files['README.md'] = _luaToolReadme(id, name);
      case PluginScaffoldKind.skill:
        files['main.lua'] = _blankLua(id, name);
        files['skills/example_workflow.md'] = _skillBody(id, name);
        files['defaults/skills/example_workflow.md'] = _skillBody(id, name);
        files['README.md'] = _skillReadme(id, name);
      case PluginScaffoldKind.featurePage:
        files['main.lua'] = _blankLua(id, name);
        files['index.html'] = _featureHtml(name);
        files['index.css'] = _featureCss();
        files['index.js'] = _featureJs();
        files['README.md'] = _featurePageReadme(id, name);
    }
    return Map.unmodifiable(files);
  }

  static Map<String, dynamic> _manifestFor({
    required String id,
    required String name,
    required String version,
    required String author,
    required String description,
    required PluginScaffoldKind kind,
  }) {
    final manifest = <String, dynamic>{
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'entry': 'main.lua',
      'permissions': <String>[],
    };

    switch (kind) {
      case PluginScaffoldKind.blank:
        break;
      case PluginScaffoldKind.luaTool:
        manifest['permissions'] = ['network:public'];
        manifest['tools'] = [
          {
            'name': 'hello',
            'description': '向指定对象打招呼，并可选地通过 HTTP 获取一条示例问候语。',
            'handler': 'hello',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {
                  'type': 'string',
                  'description': '要打招呼的对象，例如 世界、LynAI。',
                },
              },
            },
          },
        ];
      case PluginScaffoldKind.skill:
        manifest['skills'] = [
          {
            'name': 'example_workflow',
            'title': '示例工作流',
            'description': '描述一个可复用的工作流，模型按需加载正文。',
            'whenToUse': '当用户要求执行示例任务或演示 Skill 机制时使用。',
            'tags': ['example'],
          },
        ];
        manifest['editableFiles'] = [
          {
            'path': 'skills/example_workflow.md',
            'title': '示例工作流 Skill',
            'type': 'markdown',
            'defaultPath': 'defaults/skills/example_workflow.md',
          },
        ];
      case PluginScaffoldKind.featurePage:
        manifest['permissions'] = ['webview:bridge'];
        manifest['featurePages'] = [
          {'id': 'main', 'title': name, 'icon': '', 'entry': 'index.html'},
        ];
        manifest['editableFiles'] = [
          {'path': 'index.html', 'title': '功能页入口', 'type': 'html'},
          {'path': 'index.css', 'title': '功能页样式', 'type': 'css'},
          {'path': 'index.js', 'title': '功能页脚本', 'type': 'javascript'},
        ];
    }
    return manifest;
  }

  static String _blankLua(String id, String name) =>
      '''
-- $name ($id)
--
-- 这是插件入口脚本。plugin.json 中声明的 tool/function/command handler
-- 都需要在本文件或本文件加载的全局环境中定义。
-- 可用的沙箱 API 见 README 或应用内插件文档；异步能力通过返回
-- { __lynai_function = "...", __lynai_next = "..." } 续延完成。
''';

  static String _luaToolScript() => r'''
-- Lua 工具插件示例。
--
-- 模型调用 hello 工具时，ToolCallService 会执行这里的 hello(args)。
-- 返回普通 table 即为最终工具结果；返回包含 __lynai_function 的 table
-- 则会先由 Dart 执行对应宿主能力，再通过 __lynai_next 回到 Lua 整理结果。

local function hello(args)
  args = args or {}
  local name = tostring(args.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    name = "世界"
  end

  -- 示例 1：直接返回结构化结果。
  -- return { ok = true, message = "你好，" .. name }

  -- 示例 2：通过 http.fetchPublic 发起异步请求，再回到 parse_hello 处理。
  return {
    __lynai_function = "http.fetchPublic",
    __lynai_next = "parse_hello",
    args = {
      url = "https://httpbin.org/get?name=" .. name,
      method = "GET",
    },
  }
end

function parse_hello(response, original_args, request_args)
  if type(response) ~= "table" or response.ok ~= true then
    return { ok = false, error = "请求失败", detail = response and response.error or nil }
  end

  local data, decode_error = lynai.json.decode(response.body or "")
  if type(data) ~= "table" then
    return { ok = false, error = "响应解析失败", detail = decode_error }
  end

  return {
    ok = true,
    message = "你好，" .. tostring(original_args.name or "世界"),
    source = "httpbin.org",
    url = request_args.url,
  }
end
''';

  static String _skillBody(String id, String name) =>
      '''
# 示例工作流

<!-- 这是插件 $id（$name）的 Skill 正文。模型只会在需要时加载本文件。 -->

## 适用场景

当用户要求执行示例任务或演示 Skill 机制时使用。

## 步骤

1. 明确用户目标，确认输入和期望输出。
2. 检查是否需要调用插件工具或宿主能力（如 `lynai.call('notes.list', {})`）。
3. 执行任务并整理为简洁结果。
4. 如有可复用经验，写回本 Skill。

## 注意

- 正文支持 Markdown。
- 用户或模型修改后保存在 `skills/example_workflow.md`，不会覆盖 `defaults/` 出厂模板。
''';

  static String _featureHtml(String name) =>
      '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$name</title>
  <link rel="stylesheet" href="index.css" />
</head>
<body>
  <main class="card">
    <h1>$name</h1>
    <p id="message">这是一个 WebView 功能页示例。</p>
    <button id="hello">调用插件函数</button>
  </main>
  <script src="index.js"></script>
</body>
</html>
''';

  static String _featureCss() => '''
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: #f6f7f9;
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
}
.card {
  background: white;
  padding: 32px;
  border-radius: 16px;
  box-shadow: 0 8px 24px rgb(0 0 0 / 0.08);
  text-align: center;
}
button {
  padding: 10px 18px;
  border: none;
  border-radius: 8px;
  background: #3f6ae0;
  color: white;
  cursor: pointer;
}
''';

  static String _featureJs() => '''
// WebView 功能页脚本示例。
// 在应用内嵌功能页中，LynAI 会注入全局 bridge 对象；请以实际宿主注入的
// window.LynAI / webkit.messageHandlers 桥接 API 为准。
const button = document.getElementById('hello');
const message = document.getElementById('message');
button.addEventListener('click', () => {
  message.textContent = '你好，来自插件功能页！';
});
''';

  static String _luaToolReadme(String id, String name) =>
      '''
# $name

插件 ID：`$id`

## 结构

- `plugin.json`：清单，声明一个名为 `hello` 的工具。
- `main.lua`：工具 handler 示例，演示同步返回与 `http.fetchPublic` 异步续延。

## 开发提示

- 修改 `main.lua` 后在插件详情页「重新加载插件」。
- 工具参数由 `plugin.json` 中的 JSON Schema 校验。
''';

  static String _skillReadme(String id, String name) =>
      '''
# $name

插件 ID：`$id`

## 结构

- `plugin.json`：清单，声明一个名为 `example_workflow` 的可编辑 Skill。
- `skills/example_workflow.md`：用户或模型可编辑的 Skill 正文。
- `defaults/skills/example_workflow.md`：出厂模板，删除 `skills/` 下的文件可回退。
''';

  static String _featurePageReadme(String id, String name) =>
      '''
# $name

插件 ID：`$id`

## 结构

- `plugin.json`：清单，声明功能页 `main`。
- `index.html` / `index.css` / `index.js`：WebView 功能页。
- `main.lua`：Lua 入口，功能页无需处理时保持为空。

## 开发提示

功能页通过 `PluginFeatureWebView` 渲染；在应用内编辑并保存 `index.*` 后重新打开功能页即可生效。
''';
}
