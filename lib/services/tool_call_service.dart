// ignore_for_file: unused_element

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_trace.dart';
import '../models/message.dart';
import '../models/note.dart';
import '../models/agent_plan.dart';
import '../models/plugin.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/conversation_provider.dart';
import 'agent_lua_script_service.dart';
import 'agent_runtime_service.dart';
import 'lynai_call_identity.dart';
import 'lynai_function_service.dart';
import 'lynai_permission_service.dart';
import 'plugin_lua_runtime_service.dart';
import 'storage_v2_service.dart';

/// 模型请求执行本地工具的标准化描述。
///
/// OpenAI 原生 tool call 和 JSON fallback 都会被转换为这个结构，再交给
/// [ToolCallService] 统一校验和执行。
class ChatToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ChatToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

class _NoteLineEdit {
  final int startLine;
  final int deleteCount;
  final List<String> insertLines;
  final List<String>? expectedLines;

  const _NoteLineEdit({
    required this.startLine,
    required this.deleteCount,
    required this.insertLines,
    this.expectedLines,
  });

  static _NoteLineEdit? fromRaw(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final startLine = _intArg(json['startLine']);
    final deleteCount = _intArg(json['deleteCount']);
    if (startLine == null || deleteCount == null || deleteCount < 0) {
      return null;
    }
    final rawLines = json['insertLines'];
    final insertLines = rawLines is List
        ? rawLines.map((line) => line?.toString() ?? '').toList()
        : const <String>[];
    final rawExpectedLines = json['expectedLines'];
    final expectedLines = rawExpectedLines is List
        ? rawExpectedLines.map((line) => line?.toString() ?? '').toList()
        : null;
    return _NoteLineEdit(
      startLine: startLine,
      deleteCount: deleteCount,
      insertLines: insertLines,
      expectedLines: expectedLines,
    );
  }

  static int? _intArg(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }
}

class _ParsedNoteEdit {
  final Note? note;
  final List<_NoteLineEdit> edits;
  final String? baseRevisionId;
  final String? error;

  const _ParsedNoteEdit({
    required this.note,
    required this.edits,
    required this.baseRevisionId,
  }) : error = null;

  const _ParsedNoteEdit.error(this.error)
    : note = null,
      edits = const [],
      baseRevisionId = null;
}

class _SelectedNote {
  final Note? note;
  final String? error;

  const _SelectedNote({required this.note}) : error = null;
  const _SelectedNote.error(this.error) : note = null;
}

class _AppliedLineEdits {
  final String? content;
  final String? error;

  const _AppliedLineEdits.success(this.content) : error = null;
  const _AppliedLineEdits.error(this.error) : content = null;
}

class _TextMatcher {
  final String query;
  final RegExp? _regex;

  const _TextMatcher._(this.query, this._regex);

  factory _TextMatcher(String query) {
    final trimmed = query.trim();
    final parsed = _parseRegexSearch(trimmed);
    if (parsed == null) return _TextMatcher._(trimmed.toLowerCase(), null);
    try {
      return _TextMatcher._(
        trimmed,
        RegExp(parsed.pattern, caseSensitive: parsed.caseSensitive),
      );
    } catch (_) {
      return _TextMatcher._('', RegExp(r'a^'));
    }
  }

  bool get isEmpty => query.isEmpty;
  bool get isRegex => _regex != null;

  bool matches(String text) {
    final regex = _regex;
    if (query.isEmpty) return true;
    if (regex != null) return regex.hasMatch(text);
    return text.toLowerCase().contains(query);
  }
}

class _ParsedRegexSearch {
  final String pattern;
  final bool caseSensitive;

  const _ParsedRegexSearch(this.pattern, {required this.caseSensitive});
}

_ParsedRegexSearch? _parseRegexSearch(String query) {
  if (query.startsWith('re:')) {
    final pattern = query.substring(3).trim();
    return pattern.isEmpty
        ? null
        : _ParsedRegexSearch(pattern, caseSensitive: false);
  }
  if (!query.startsWith('/') || query.length < 2) return null;
  final lastSlash = query.lastIndexOf('/');
  if (lastSlash <= 0) return null;
  final pattern = query.substring(1, lastSlash);
  if (pattern.isEmpty) return null;
  final flags = query.substring(lastSlash + 1);
  return _ParsedRegexSearch(pattern, caseSensitive: !flags.contains('i'));
}

/// 工具执行后的统一返回格式。
///
/// 将工具调用 ID、工具名和执行结果打包，供对话 Provider 拼装
/// `tool` 角色消息回传给模型。
class ToolExecutionResult {
  final String toolCallId;
  final String name;
  final Map<String, dynamic> result;

  const ToolExecutionResult({
    required this.toolCallId,
    required this.name,
    required this.result,
  });
}

/// 执行模型可调用的本地工具。
///
/// 工具只通过 Provider 或平台通道访问本地能力。所有结果都返回结构化 JSON，
/// 让模型可以继续生成自然语言回复，也让失败原因不会被吞掉。
class ToolCallService {
  ToolCallService(
    this._features, {
    PluginProvider? plugins,
    ModelConfigProvider? modelConfigs,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
  }) : _plugins = plugins,
       _modelConfigs = modelConfigs,
       _settings = settings,
       _conversations = conversations,
       _conversationId = conversationId;

  static const _channel = MethodChannel('lynai/native_tools');
  static const _uuid = Uuid();

  final FeatureProvider _features;
  final PluginProvider? _plugins;
  final ModelConfigProvider? _modelConfigs;
  final SettingsProvider? _settings;
  final ConversationProvider? _conversations;
  final String? _conversationId;
  final _lynaiFunctions = LynAIFunctionService();
  final _permissionService = const LynAIPermissionService();
  final _agentRuntime = const AgentRuntimeService();

  /// 非原生 tool_calls 接口使用的系统提示词。
  ///
  /// 当模型接口不支持 OpenAI 原生 tool_calls 时（如部分兼容接口），
  /// 系统提示词教模型以 JSON fallback 格式发起工具调用：
  /// `{"tool_calls":[{"name":"工具名","arguments":{...}}]}`。
  /// 返回的 JSON 由 [parseFallbackToolCalls] 解析。
  static const systemPrompt = '''
你可以使用本地工具帮助用户管理日程、笔记、待办清单、获取时间/位置、打开安卓应用和创建对话标题。
当需要调用工具且当前模型接口不支持原生 tool_calls 时，只返回一个 JSON 对象，不要包含 Markdown：
{"tool_calls":[{"name":"工具名","arguments":{...}}]}
收到工具结果后，再用自然语言给用户最终回复。
创建或修改数据前，应从用户输入中提取明确字段；缺少关键字段时先追问。
需要查看笔记内容时，先用 list_notes 查找笔记 id，再用 read_note 读取完整内容；多分页笔记先用 list_note_pages 查看分页，read_note/save_note/edit_note/propose_note_edit 可用 pageId 或 pageTitle 指定分页。小范围修改笔记时，先 read_note，再用 propose_note_edit 按行提交 edits 让用户逐行确认；用户明确要求直接修改时才用 edit_note。创建、追加或整篇替换时用 save_note。笔记可通过 list_note_folders/save_note_folder 管理文件夹，通过 save_note_page 创建、重命名、删除或上移/下移分页。
需要查看待办清单内容时，先用 list_todo_lists 查找清单 id，再用 read_todo_list 读取完整内容；创建或修改待办项用 save_todo_item，完成/未完成待办项时设置 done。
日程时间使用带时区偏移的 ISO-8601 字符串；用户说“今天/明天”时必须先结合 get_current_time 的 iso 与 timezoneOffsetMinutes 换算成本地日期时间。
''';

  /// 支持原生 tool_calls 接口使用的系统提示词。
  ///
  /// 与 [systemPrompt] 的区别是不包含 JSON fallback 格式说明，
  /// 因为原生 tool_calls 接口会自行处理工具调用的序列化和反序列化。
  static const nativeSystemPrompt = '''
你可以使用本地工具帮助用户管理日程、笔记、待办清单、获取时间/位置、打开安卓应用和创建对话标题。
需要调用工具时使用接口提供的 tool_calls；不需要工具时直接正常回答，不要提及工具。
收到工具结果后，再用自然语言给用户最终回复。
创建或修改数据前，应从用户输入中提取明确字段；缺少关键字段时先追问。
需要查看笔记内容时，先用 list_notes 查找笔记 id，再用 read_note 读取完整内容；多分页笔记先用 list_note_pages 查看分页，read_note/save_note/edit_note/propose_note_edit 可用 pageId 或 pageTitle 指定分页。小范围修改笔记时，先 read_note，再用 propose_note_edit 按行提交 edits 让用户逐行确认；用户明确要求直接修改时才用 edit_note。创建、追加或整篇替换时用 save_note。笔记可通过 list_note_folders/save_note_folder 管理文件夹，通过 save_note_page 创建、重命名、删除或上移/下移分页。
需要查看待办清单内容时，先用 list_todo_lists 查找清单 id，再用 read_todo_list 读取完整内容；创建或修改待办项用 save_todo_item，完成/未完成待办项时设置 done。
日程时间使用带时区偏移的 ISO-8601 字符串；用户说“今天/明天”时必须先结合 get_current_time 的 iso 与 timezoneOffsetMinutes 换算成本地日期时间。
''';

  static const agentSystemPrompt = '''
你处于 LynAI Agent 模式。
复杂任务应先调用 create_plan 创建计划，再按计划调用工具执行。
执行过程中使用 update_plan 更新步骤状态；不要在自然语言中伪造计划状态。
Plan 创建和更新不需要权限，只用于当前对话的可视化状态。
如果需要了解可用插件函数，先调用 list_plugin_functions。
如果需要调用插件函数，先调用 list_plugin_functions 查看可用函数，再用 call_plugin_function。该能力需要 plugins.callFunction 权限。
如果需要了解可用插件 Skill，先调用 list_plugin_skills；Skill 摘要不是完整说明，执行相关流程前调用 load_plugin_skill 加载正文。加载 Skill 不需要额外权限。
如果需要运行 Lua，调用 execute_lua。Lua 运行在受限沙箱中：禁用 os/io/package/require/dofile/loadfile，不能访问文件系统或系统命令；所有 LynAI 能力必须通过 lynai.call(name, args) 调用；脚本最后必须 return 一个 JSON 可序列化 table。Agent Lua 支持同步读取函数、plugins.functions.list、plugins.callFunction、agent.plan.update、agent.note.add、model.chat、model.ocr、model.recognizeFile、model.generateImage、device.app.open 和 device.* 设备函数；插件函数调用需要 plugins.callFunction 权限。打开已安装 Android 应用时在 Lua 中调用 lynai.call("device.app.open", { packageName = "目标包名" })。复杂屏幕操控应优先在 Lua 中线性编排多步 device.*：读取 screen.context 或 waitForNode，优先用 node.action，必要时才用坐标 tap/swipe。关键调用后检查 ok，失败时返回结构化 error。
Agent 专用工具成功时返回 {ok:true,result:{...}}，失败时返回 {ok:false,error:{code,message,details?}}；读取数据时优先看 result。
可以输出简短的中间说明，但不要把工具 JSON 原样展示给用户；最终回复应汇总执行结果。
''';

  /// 生成 Agent 模式系统提示词，并在末尾追加启用插件 Skill 的摘要。
  static String agentSystemPromptWithSkills(
    Iterable<InstalledPlugin> plugins, {
    int maxSkills = 30,
  }) {
    final lines = <String>[];
    var total = 0;
    for (final plugin in plugins) {
      if (!plugin.enabled || plugin.hasError) continue;
      for (final skill in plugin.manifest.skills) {
        if (!skill.modelInvocable ||
            !plugin.enabledSkills.contains(skill.name)) {
          continue;
        }
        total++;
        if (lines.length >= maxSkills) continue;
        final title = skill.title.isNotEmpty ? skill.title : skill.name;
        final parts = [
          if (skill.description.isNotEmpty) skill.description,
          if (skill.whenToUse.isNotEmpty) '使用场景：${skill.whenToUse}',
          if (skill.tags.isNotEmpty) '标签：${skill.tags.join(', ')}',
        ];
        lines.add(
          '- ${_qualifiedName(plugin.id, skill.name)}：$title${parts.isEmpty ? '' : '。${parts.join('；')}'}',
        );
      }
    }
    if (lines.isEmpty) return agentSystemPrompt;
    final more = total > lines.length
        ? '\n还有 ${total - lines.length} 个 Skill，可调用 list_plugin_skills 查询。'
        : '';
    return '''$agentSystemPrompt

可用插件 Skills：
以下是当前启用插件提供的可按需加载 Skill 摘要。不要把摘要当成完整说明；需要执行相关流程时，先调用 load_plugin_skill 加载正文。
${lines.join('\n')}$more''';
  }

  /// 生成当前设备时间的上下文字符串。
  ///
  /// 返回带时区信息的 ISO-8601 时间戳，帮助模型将用户的相对时间表达
  /// （如"今天""明天"）转换为准确的绝对时间。
  static String currentTimeContext() {
    final now = DateTime.now();
    return '当前设备本地时间: ${now.toIso8601String()}，时区: ${now.timeZoneName}，timezoneOffsetMinutes: ${now.timeZoneOffset.inMinutes}。';
  }

  /// 生成符合 OpenAI function-calling 规范的工具定义列表。
  ///
  /// 合并两类工具：
  /// 1. **内置工具**——get_current_time、get_location、open_app 及所有笔记/待办/日程
  ///    CRUD 操作。每个工具都有完整的 JSON Schema 供模型精确匹配参数。
  /// 2. **插件工具**——遍历已启用且权限已满足的插件，将其 [PluginToolDefinition]
  ///    转换为 OpenAI 工具格式追加到列表末尾。
  ///
  /// 去重策略：插件工具名若与内置工具名冲突则跳过该插件工具（内置工具优先）。
  /// 仅当插件 enabled、无错误且全部权限已授予时，其工具才会暴露给模型。
  static List<Map<String, dynamic>> openAITools([
    Iterable<InstalledPlugin> plugins = const [],
    bool agentEnabled = false,
    Iterable<String> agentGrantedPermissions = const [],
    bool imageGenerationEnabled = false,
  ]) {
    final tools = <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': 'get_current_time',
          'description': '获取设备当前时间、时区和 ISO-8601 时间戳。',
          'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'propose_note_edit',
          'description': '按行提交笔记修改建议，不直接保存；用户会在笔记页逐行接受或拒绝。调用前必须先 read_note。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '已有笔记 id'},
              'pageId': {'type': 'string', 'description': '可选，目标分页 id'},
              'pageTitle': {'type': 'string', 'description': '可选，目标分页标题'},
              'baseRevisionId': {
                'type': 'string',
                'description': 'read_note 返回的 currentRevisionId，可选',
              },
              'expectedContentHash': {
                'type': 'string',
                'description': 'read_note 返回的 contentHash，用于避免基于过期内容提案',
              },
              'edits': {
                'type': 'array',
                'description':
                    '逐行修改建议。行号从 1 开始，使用 read_note 返回的 numberedLines；startLine=lineCount+1 可在末尾追加；多个 edit 不可重叠。强烈建议填写 expectedLines 校验被替换/删除的原文，避免行号偏移误改。',
                'items': {
                  'type': 'object',
                  'properties': {
                    'startLine': {'type': 'integer'},
                    'deleteCount': {'type': 'integer'},
                    'insertLines': {
                      'type': 'array',
                      'items': {'type': 'string'},
                    },
                    'expectedLines': {
                      'type': 'array',
                      'description': '可选。预期被 deleteCount 覆盖的原文行；不匹配时拒绝修改。',
                      'items': {'type': 'string'},
                    },
                  },
                  'required': ['startLine', 'deleteCount'],
                },
              },
            },
            'required': ['id', 'edits'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'get_location',
          'description': '获取设备当前位置。',
          'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'open_app',
          'description': '在安卓端通过包名打开已安装应用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'packageName': {'type': 'string', 'description': '安卓应用包名'},
            },
            'required': ['packageName'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'list_schedules',
          'description': '查看用户日程表事项列表，包含日程和只需要开始时间的任务。',
          'parameters': {
            'type': 'object',
            'properties': {
              'from': {'type': 'string', 'description': '可选起始 ISO 时间'},
              'to': {'type': 'string', 'description': '可选结束 ISO 时间'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'create_schedule',
          'description':
              '创建新的日程或任务。kind=task 表示任务，只需要 title/start；默认 kind=schedule 表示日程，需要 title/start/end。',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'kind': {
                'type': 'string',
                'description': 'schedule 或 task；task 只需要开始时间',
              },
              'start': {'type': 'string', 'description': 'ISO-8601 开始时间'},
              'end': {'type': 'string', 'description': 'ISO-8601 结束时间；任务可省略'},
              'note': {'type': 'string'},
            },
            'required': ['title', 'start'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'update_schedule',
          'description': '按 id 修改已有日程或任务。任务只使用 start，忽略 end。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'kind': {'type': 'string', 'description': 'schedule 或 task'},
              'title': {'type': 'string'},
              'start': {'type': 'string'},
              'end': {'type': 'string'},
              'note': {'type': 'string'},
            },
            'required': ['id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'list_notes',
          'description': '查看用户笔记列表，可按标题或内容关键字搜索。默认只返回摘要。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '可选搜索关键字'},
              'folderId': {'type': 'string', 'description': '可选笔记文件夹 id'},
              'includeContent': {
                'type': 'boolean',
                'description': '是否在列表中返回完整正文；大量笔记时优先使用 read_note',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'read_note',
          'description': '读取单篇笔记的完整内容。可按 id 精确读取，或按标题/关键字搜索最匹配的一篇。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '笔记 id'},
              'title': {'type': 'string', 'description': '笔记标题'},
              'query': {'type': 'string', 'description': '标题或正文搜索关键字'},
              'pageId': {'type': 'string', 'description': '可选，指定分页 id'},
              'pageTitle': {'type': 'string', 'description': '可选，指定分页标题'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'save_note',
          'description':
              '创建或修改并保存笔记。传 id 时修改已有笔记；不传 id 时创建新笔记。小范围逐行修改优先使用 propose_note_edit 让用户确认。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '已有笔记 id；为空则创建'},
              'title': {'type': 'string'},
              'content': {'type': 'string'},
              'pageId': {'type': 'string', 'description': '可选，目标分页 id'},
              'pageTitle': {'type': 'string', 'description': '可选，目标分页标题'},
              'folderId': {
                'type': 'string',
                'description': '目标笔记文件夹 id；传空字符串表示移出文件夹',
              },
              'append': {'type': 'boolean', 'description': '是否追加到已有内容'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'edit_note',
          'description':
              '按行修改已有笔记并保存到时间线。调用前必须先 read_note 获取 contentHash/currentRevisionId；edits 使用 read_note 返回内容的行号。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '已有笔记 id'},
              'pageId': {'type': 'string', 'description': '可选，目标分页 id'},
              'pageTitle': {'type': 'string', 'description': '可选，目标分页标题'},
              'baseRevisionId': {
                'type': 'string',
                'description': 'read_note 返回的 currentRevisionId，可选',
              },
              'expectedContentHash': {
                'type': 'string',
                'description': 'read_note 返回的 contentHash，用于避免覆盖用户新改动',
              },
              'edits': {
                'type': 'array',
                'description':
                    '逐行修改列表。行号从 1 开始，使用 read_note 返回的 numberedLines；startLine=lineCount+1 可在末尾追加；多个 edit 不可重叠。强烈建议填写 expectedLines 校验被替换/删除的原文，避免行号偏移误改。',
                'items': {
                  'type': 'object',
                  'properties': {
                    'startLine': {'type': 'integer'},
                    'deleteCount': {'type': 'integer'},
                    'insertLines': {
                      'type': 'array',
                      'items': {'type': 'string'},
                    },
                    'expectedLines': {
                      'type': 'array',
                      'description': '可选。预期被 deleteCount 覆盖的原文行；不匹配时拒绝修改。',
                      'items': {'type': 'string'},
                    },
                  },
                  'required': ['startLine', 'deleteCount'],
                },
              },
            },
            'required': ['id', 'edits'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'list_note_folders',
          'description': '查看笔记文件夹及每个文件夹的笔记数量。',
          'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'list_note_pages',
          'description': '列出某篇笔记的分页，并返回当前激活分页 id。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '笔记 id'},
            },
            'required': ['id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'save_note_page',
          'description':
              '创建、重命名、删除或移动笔记分页。传 delete=true 时删除分页；move=up/down 时上移/下移分页；至少保留一个分页。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '笔记 id'},
              'pageId': {'type': 'string', 'description': '已有分页 id；为空则创建'},
              'title': {'type': 'string', 'description': '分页标题'},
              'delete': {'type': 'boolean'},
              'move': {
                'type': 'string',
                'description': '可选，up 表示上移分页，down 表示下移分页',
                'enum': ['up', 'down'],
              },
            },
            'required': ['id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'save_note_folder',
          'description': '创建、重命名或删除笔记文件夹。传 delete=true 时删除文件夹，文件夹内笔记会移出文件夹。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '已有文件夹 id；为空则创建'},
              'title': {'type': 'string'},
              'delete': {'type': 'boolean'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'list_todo_lists',
          'description': '查看用户待办清单列表，可按标题或待办内容搜索。默认返回清单摘要。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '可选搜索关键字'},
              'includeItems': {
                'type': 'boolean',
                'description': '是否在列表中返回待办项；大量清单时优先使用 read_todo_list',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'read_todo_list',
          'description': '读取单个待办清单的完整内容。可按 id 精确读取，或按标题/关键字搜索最匹配的一份。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '待办清单 id'},
              'title': {'type': 'string', 'description': '待办清单标题'},
              'query': {'type': 'string', 'description': '标题或待办内容搜索关键字'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'save_todo_list',
          'description':
              '创建或修改待办清单。传 id 时修改已有清单；不传 id 时创建新清单。items 会替换整份清单的待办项。',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '已有待办清单 id；为空则创建'},
              'title': {'type': 'string'},
              'items': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'text': {'type': 'string'},
                    'done': {'type': 'boolean'},
                  },
                  'required': ['text'],
                },
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'save_todo_item',
          'description':
              '创建、修改、完成或未完成一个待办项。不传 itemId 时创建新待办项；传 delete=true 时删除。',
          'parameters': {
            'type': 'object',
            'properties': {
              'listId': {'type': 'string', 'description': '待办清单 id'},
              'itemId': {'type': 'string', 'description': '待办项 id；为空则创建'},
              'text': {'type': 'string', 'description': '待办内容'},
              'done': {
                'type': 'boolean',
                'description': 'true 表示完成，false 表示未完成',
              },
              'delete': {'type': 'boolean', 'description': '是否删除该待办项'},
            },
            'required': ['listId'],
          },
        },
      },
    ];
    final names = tools
        .map((tool) => tool['function']?['name']?.toString())
        .whereType<String>()
        .toSet();
    if (agentEnabled) {
      _appendAgentTools(tools, names, agentGrantedPermissions.toSet());
    }
    for (final plugin in plugins) {
      if (!plugin.enabled ||
          plugin.hasError ||
          !plugin.hasAllPermissionsGranted) {
        continue;
      }
      for (final tool in plugin.manifest.tools) {
        if (tool.name.isEmpty ||
            tool.handler.isEmpty ||
            !plugin.enabledTools.contains(tool.name) ||
            names.contains(tool.name)) {
          continue;
        }
        names.add(tool.name);
        tools.add({
          'type': 'function',
          'function': {
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.parameters,
          },
        });
      }
    }
    if (imageGenerationEnabled) _appendImageGenerationTool(tools, names);
    return tools;
  }

  static void _appendImageGenerationTool(
    List<Map<String, dynamic>> tools,
    Set<String> names,
  ) {
    if (!names.add('generate_image')) return;
    tools.add({
      'type': 'function',
      'function': {
        'name': 'generate_image',
        'description':
            '使用当前对话选择的图片生成模型生成图片。仅当用户明确要求画图、生成图片、出图、绘制视觉内容时调用。调用后图片会自动保存并显示在对话中。',
        'parameters': {
          'type': 'object',
          'properties': {
            'prompt': {
              'type': 'string',
              'description': '图片生成提示词，尽量包含主体、风格、构图、光照和色彩要求。',
            },
            'count': {'type': 'integer', 'description': '生成数量，默认 1，建议 1-4。'},
            'size': {
              'type': 'string',
              'description': '图片尺寸，例如 1024x1024、1024x1792、1792x1024。',
            },
            'quality': {
              'type': 'string',
              'description': '可选质量参数，例如 standard 或 hd。',
            },
            'style': {
              'type': 'string',
              'description': '可选风格参数，例如 vivid 或 natural。',
            },
          },
          'required': ['prompt'],
        },
      },
    });
  }

  static void _appendAgentTools(
    List<Map<String, dynamic>> tools,
    Set<String> names,
    Set<String> permissions,
  ) {
    void add(String name, String description, Map<String, dynamic> parameters) {
      if (!names.add(name)) return;
      tools.add({
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      });
    }

    add('create_plan', '创建当前对话的 Agent Plan。Plan 只用于展示和跟踪步骤，不需要权限。', {
      'type': 'object',
      'properties': {
        'title': {'type': 'string', 'description': '计划标题，简短描述本次任务'},
        'items': {
          'type': 'array',
          'description': '计划步骤列表。每步只描述一个可验证动作。',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '稳定步骤 ID，例如 step_1'},
              'title': {'type': 'string', 'description': '步骤标题'},
            },
            'required': ['id', 'title'],
          },
        },
      },
      'required': ['title', 'items'],
    });
    add('update_plan', '更新当前 Agent Plan 中一个或多个步骤的状态。', {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'status': {
                'type': 'string',
                'enum': AgentPlanItem.statuses.toList(growable: false),
              },
              'summary': {'type': 'string', 'description': '可选，简短说明结果或失败原因'},
              'resultSummary': {
                'type': 'string',
                'description': '可选，步骤完成后的结果摘要',
              },
              'error': {'type': 'string', 'description': '可选，步骤失败原因'},
            },
            'required': ['id', 'status'],
          },
        },
      },
      'required': ['items'],
    });
    add('list_plugin_functions', '列出当前启用插件提供且已启用的函数，供 Agent 判断是否可调用。', {
      'type': 'object',
      'properties': <String, dynamic>{},
    });
    add(
      'list_plugin_skills',
      '列出当前启用插件提供且已启用的 Skills。Skill 只返回摘要，需要正文时调用 load_plugin_skill。',
      {
        'type': 'object',
        'properties': {
          'pluginId': {'type': 'string', 'description': '可选，按插件 ID 筛选'},
          'query': {'type': 'string', 'description': '可选，按标题、描述、使用场景或标签搜索'},
        },
      },
    );
    add(
      'load_plugin_skill',
      '加载插件 Skill 正文。调用前应先用 list_plugin_skills 查看 pluginId 和 skillName。加载 Skill 不需要额外权限。',
      {
        'type': 'object',
        'properties': {
          'pluginId': {'type': 'string', 'description': '插件 ID'},
          'skillName': {'type': 'string', 'description': '插件 Skill 名'},
          'qualifiedName': {
            'type': 'string',
            'description': '可选，形如 pluginId__skillName；解析时只切第一个 __',
          },
        },
      },
    );
    add(
      'add_agent_note',
      '向当前 assistant 消息追加一条简短的用户可见 Agent 中间说明。不需要权限，不要用于最终回答或输出工具 JSON。',
      {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'description': '简短说明，最多 500 字。'},
        },
        'required': ['content'],
      },
    );
    if (permissions.contains(LynAICapabilities.pluginCallFunction)) {
      add(
        'call_plugin_function',
        '调用当前启用插件提供的函数。调用前应先用 list_plugin_functions 查看 pluginId、functionName 和参数 schema。需要 plugins.callFunction 权限。',
        {
          'type': 'object',
          'properties': {
            'pluginId': {'type': 'string', 'description': '插件 ID'},
            'functionName': {'type': 'string', 'description': '插件函数名'},
            'arguments': {
              'type': 'object',
              'description': '传给插件函数的参数',
              'additionalProperties': true,
            },
          },
          'required': ['pluginId', 'functionName', 'arguments'],
        },
      );
    }
    if (permissions.contains(LynAICapabilities.luaExecute)) {
      add(
        'execute_lua',
        '执行 LynAI Agent Lua 脚本。脚本运行在受限 lua_dardo 沙箱中：禁用 os、io、package、require、dofile、loadfile；不能访问本地文件系统或执行系统命令；所有 LynAI 能力必须通过 lynai.call(name, args) 调用；lynai.call 返回 JSON 风格 table，通常包含 ok 字段；脚本最后必须 return 一个 JSON 可序列化 table。支持同步读取函数（如 todos.list、notes.read、schedules.list）、plugins.functions.list、plugins.callFunction、agent.plan.update、agent.note.add、model.chat、model.ocr、model.recognizeFile、model.generateImage、device.app.open 和 device.*。打开已安装 Android 应用时调用 lynai.call("device.app.open", { packageName = "目标包名" })；device.* 支持异步线性执行，可在 Lua 中写循环、等待和多步流程；复杂屏幕操控优先使用 device.screen.context、device.waitForNode、device.node.action，必要时再用 device.screen.screenshot 配合 model.ocr/model.recognizeFile，最后才用 device.tap/device.swipe 坐标操作。关键调用应检查 ok，失败时 return { ok = false, error = result.error }。示例：local opened = lynai.call("device.app.open", { packageName = "com.example.app" }); if not opened.ok then return opened end; local n = lynai.call("device.waitForNode", { text = "发送", timeoutMs = 5000 }); if not n.ok then return n end; return lynai.call("device.node.action", { nodeId = n.result.id, action = "click" })',
        {
          'type': 'object',
          'properties': {
            'purpose': {'type': 'string', 'description': '脚本目的，展示给用户和日志'},
            'code': {'type': 'string', 'description': 'Lua 源码'},
          },
          'required': ['purpose', 'code'],
        },
      );
    }
  }

  static Map<String, dynamic> listPluginFunctions(
    Iterable<InstalledPlugin> plugins,
  ) {
    final functions = <Map<String, dynamic>>[];
    for (final plugin in plugins) {
      if (!plugin.enabled || plugin.hasError) continue;
      for (final function in plugin.manifest.functions) {
        if (!plugin.enabledFunctions.contains(function.name)) continue;
        functions.add({
          'pluginId': plugin.id,
          'pluginName': plugin.displayName,
          'name': function.name,
          'qualifiedName': _qualifiedName(plugin.id, function.name),
          'title': function.title,
          'description': function.description,
          'parameters': function.parameters,
        });
      }
    }
    return {'ok': true, 'functions': functions};
  }

  static Map<String, dynamic> listPluginSkills(
    Iterable<InstalledPlugin> plugins, {
    String pluginId = '',
    String query = '',
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final skills = <Map<String, dynamic>>[];
    for (final plugin in plugins) {
      if (!plugin.enabled || plugin.hasError) continue;
      if (pluginId.isNotEmpty && plugin.id != pluginId) continue;
      for (final skill in plugin.manifest.skills) {
        if (!plugin.enabledSkills.contains(skill.name)) continue;
        final item = _skillSummaryJson(plugin, skill);
        if (normalizedQuery.isNotEmpty &&
            !_skillMatchesQuery(skill, normalizedQuery)) {
          continue;
        }
        skills.add(item);
      }
    }
    return {'ok': true, 'skills': skills};
  }

  static Map<String, dynamic> _skillSummaryJson(
    InstalledPlugin plugin,
    PluginSkillDefinition skill,
  ) {
    return {
      'pluginId': plugin.id,
      'pluginName': plugin.displayName,
      'name': skill.name,
      'qualifiedName': _qualifiedName(plugin.id, skill.name),
      'title': skill.title,
      'description': skill.description,
      'whenToUse': skill.whenToUse,
      'tags': skill.tags,
      'modelInvocable': skill.modelInvocable,
      'userInvocable': skill.userInvocable,
      'path': 'skills/${skill.name}.md',
    };
  }

  static bool _skillMatchesQuery(
    PluginSkillDefinition skill,
    String normalizedQuery,
  ) {
    return skill.name.toLowerCase().contains(normalizedQuery) ||
        skill.title.toLowerCase().contains(normalizedQuery) ||
        skill.description.toLowerCase().contains(normalizedQuery) ||
        skill.whenToUse.toLowerCase().contains(normalizedQuery) ||
        skill.tags.any((tag) => tag.toLowerCase().contains(normalizedQuery));
  }

  /// 解析 JSON fallback 格式的工具调用。
  ///
  /// 当模型不支持原生 tool_calls 时，它在 `content` 中返回 JSON 文本：
  /// `{"tool_calls": [{"name": "...", "arguments": {...}}]}`。
  /// 此方法从文本中提取并转换为 [ChatToolCall] 列表。
  /// 支持被 Markdown 代码块包裹的 JSON（即 ```json ... ``` 格式）。
  /// 解析失败时不抛异常，返回空列表。
  static List<ChatToolCall> parseFallbackToolCalls(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final data = jsonDecode(_stripCodeFence(trimmed));
      final rawCalls = data is Map<String, dynamic> ? data['tool_calls'] : null;
      if (rawCalls is! List) return const [];
      return rawCalls
          .whereType<Map<String, dynamic>>()
          .indexed
          .map((entry) {
            final index = entry.$1;
            final call = entry.$2;
            final name = call['name'] as String? ?? '';
            final args = _decodeArguments(call['arguments']);
            return ChatToolCall(
              id: 'fallback_${DateTime.now().microsecondsSinceEpoch}_${index}_$name',
              name: name,
              arguments: args,
            );
          })
          .where((call) => call.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _stripCodeFence(String value) {
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    ).firstMatch(value);
    return match?.group(1) ?? value;
  }

  static Map<String, dynamic> _decodeArguments(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// 批量执行一组工具调用。
  ///
  /// 按顺序逐个执行，每个调用返回一个 [ToolExecutionResult]。
  /// [conversationMessages] 作为上下文传入，供需要对话历史的工具使用。
  Future<List<ToolExecutionResult>> executeAll(
    List<ChatToolCall> calls,
    List<Message> conversationMessages,
  ) async {
    final results = <ToolExecutionResult>[];
    for (final call in calls) {
      results.add(
        ToolExecutionResult(
          toolCallId: call.id,
          name: call.name,
          result: await execute(call, conversationMessages),
        ),
      );
    }
    return results;
  }

  /// 执行单个工具调用并返回结构化结果。
  ///
  /// 工具分发顺序：
  /// 1. 内置硬编码工具（get_current_time / get_location / open_app）
  /// 2. [LynAIFunctionService.aiToolAliases] 映射的工具（统一由 LynAI 函数引擎执行）
  /// 3. 插件 Lua 工具（由 [PluginLuaRuntimeService.executeTool] 在沙箱中运行）
  ///
  /// 结果总是返回 `{'ok': true/false, ...}` 结构，
  /// 确保模型能区分成功和失败并据此生成合适的用户回复。
  Future<Map<String, dynamic>> execute(
    ChatToolCall call,
    List<Message> conversationMessages,
  ) async {
    try {
      switch (call.name) {
        case 'get_current_time':
          final now = DateTime.now();
          return {
            'ok': true,
            'iso': now.toIso8601String(),
            'localIso': now.toLocal().toIso8601String(),
            'timezone': now.timeZoneName,
            'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
          };
        case 'get_location':
          final result = await _invokeNative('getLocation');
          return {'ok': true, ...result};
        case 'open_app':
          final packageName = _stringArg(call, 'packageName');
          if (packageName.isEmpty) return _error('缺少 packageName');
          final result = await _invokeNative('openApp', {
            'packageName': packageName,
          });
          return {'ok': true, ...result};
        case 'create_plan':
          return _createPlan(call.arguments);
        case 'update_plan':
          return _updatePlan(call.arguments);
        case 'list_plugin_functions':
          if (!_agentEnabled) {
            return _agentError('agent_disabled', '当前对话未启用 Agent 模式');
          }
          return _listPluginFunctionsForAgent();
        case 'list_plugin_skills':
          return _listPluginSkillsForAgent(call.arguments);
        case 'load_plugin_skill':
          return _loadPluginSkill(call.arguments);
        case 'add_agent_note':
          return _addAgentNote(call.arguments);
        case 'call_plugin_function':
          return _callPluginFunction(call.arguments);
        case 'execute_lua':
          final result = await _executeAgentLua(call.arguments);
          _appendGeneratedImagesToConversation(result);
          return result;
        default:
          final functionName = LynAIFunctionService.aiToolAliases[call.name];
          if (functionName != null) {
            final result = await _lynaiFunctions.execute(
              LynAIFunctionCall(name: functionName, arguments: call.arguments),
              LynAIFunctionContext(
                identity: LynAICallIdentity(
                  type: LynAICallerType.system,
                  conversationId: _conversationId,
                ),
                features: _features,
                modelConfigs: _modelConfigs,
                settings: _settings,
                plugins: _plugins,
                conversations: _conversations,
              ),
            );
            if (functionName == 'model.generateImage') {
              _appendGeneratedImagesToConversation(result);
            }
            return result;
          }
          final pluginResult = await _executePluginTool(call);
          if (pluginResult != null) return pluginResult;
          return _error('未知工具: ${call.name}');
      }
    } on Exception catch (e, st) {
      debugPrint('工具调用失败 ${call.name}: $e\n$st');
      return _error(e.toString());
    }
  }

  void _appendGeneratedImagesToConversation(Map<String, dynamic> result) {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null || result['ok'] != true) return;
    final rawImages = _generatedImageList(result);
    if (rawImages is! List) return;
    final images = <MessageImage>[];
    for (final raw in rawImages.whereType<Map>()) {
      final json = Map<String, dynamic>.from(raw);
      final path = (json['path'] as String? ?? '').trim();
      if (path.isEmpty) continue;
      images.add(
        MessageImage(
          path: path,
          name: (json['name'] as String? ?? 'generated_image.png').trim(),
          size: (json['size'] as num?)?.toInt() ?? 0,
          mimeType: (json['mimeType'] as String? ?? 'image/png').trim(),
        ),
      );
    }
    conversations.appendImagesToLastAssistantMessage(cid, images);
  }

  Object? _generatedImageList(Map<String, dynamic> result) {
    final direct = result['images'];
    if (direct is List) return direct;
    final generated = result['generatedImages'];
    if (generated is List) return generated;
    return null;
  }

  Map<String, dynamic> _addAgentNote(Map<String, dynamic> args) {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) {
      return _agentError('missing_context', '缺少对话上下文');
    }
    return _agentRuntime.addNote(conversations, cid, args);
  }

  Map<String, dynamic> _listPluginFunctionsForAgent() {
    _appendAgentTrace(AgentTraceEvent.toolCall, '查看插件函数');
    final result = listPluginFunctions(_plugins?.plugins ?? const []);
    final count = (result['functions'] as List?)?.length ?? 0;
    _appendAgentTrace(
      AgentTraceEvent.toolResult,
      '插件函数列表已读取',
      content: '$count 个可用函数',
      metadata: {'count': count},
    );
    return _agentOk(result);
  }

  Map<String, dynamic> _listPluginSkillsForAgent(Map<String, dynamic> args) {
    if (!_agentEnabled) {
      return _agentError('agent_disabled', '当前对话未启用 Agent 模式');
    }
    final pluginId = (args['pluginId'] as String? ?? '').trim();
    final query = (args['query'] as String? ?? '').trim();
    _appendAgentTrace(
      AgentTraceEvent.toolCall,
      '查看插件 Skills',
      metadata: {
        if (pluginId.isNotEmpty) 'pluginId': pluginId,
        if (query.isNotEmpty) 'query': query,
      },
    );
    final result = listPluginSkills(
      _plugins?.plugins ?? const [],
      pluginId: pluginId,
      query: query,
    );
    final count = (result['skills'] as List?)?.length ?? 0;
    _appendAgentTrace(
      AgentTraceEvent.toolResult,
      '插件 Skill 列表已读取',
      content: '$count 个可用 Skill',
      metadata: {'count': count},
    );
    return _agentOk(result);
  }

  Future<Map<String, dynamic>> _loadPluginSkill(
    Map<String, dynamic> args,
  ) async {
    if (!_agentEnabled) {
      return _agentError('agent_disabled', '当前对话未启用 Agent 模式');
    }
    final plugins = _plugins;
    if (plugins == null) {
      return _agentError('plugin_system_unavailable', '插件系统不可用');
    }
    final parsed = _parseQualifiedName(args['qualifiedName'] as String? ?? '');
    final pluginId = (args['pluginId'] as String? ?? parsed?.$1 ?? '').trim();
    final skillName = (args['skillName'] as String? ?? parsed?.$2 ?? '').trim();
    if (pluginId.isEmpty || skillName.isEmpty) {
      return _agentError(
        'invalid_arguments',
        'load_plugin_skill 缺少 pluginId 或 skillName',
      );
    }
    InstalledPlugin? plugin;
    for (final item in plugins.plugins) {
      if (item.id == pluginId) {
        plugin = item;
        break;
      }
    }
    if (plugin == null || !plugin.enabled || plugin.hasError) {
      return _agentError('plugin_not_found', '插件不可用: $pluginId');
    }
    PluginSkillDefinition? skill;
    for (final item in plugin.manifest.skills) {
      if (item.name == skillName) {
        skill = item;
        break;
      }
    }
    if (skill == null || !plugin.enabledSkills.contains(skill.name)) {
      return _agentError(
        'plugin_skill_not_found',
        '插件 Skill 不可用: $pluginId.$skillName',
      );
    }
    final path = 'skills/${skill.name}.md';
    _appendAgentTrace(
      AgentTraceEvent.toolCall,
      '加载插件 Skill',
      content: '${plugin.displayName}.${skill.name}',
      metadata: {'pluginId': plugin.id, 'skillName': skill.name},
    );
    try {
      final content = await plugins.readFile(plugin.id, path);
      final result = {..._skillSummaryJson(plugin, skill), 'content': content};
      _appendAgentTrace(
        AgentTraceEvent.toolResult,
        '插件 Skill 已加载',
        content: '${plugin.displayName}.${skill.name}',
        metadata: {
          'pluginId': plugin.id,
          'skillName': skill.name,
          'length': content.length,
        },
      );
      return _agentOk(result);
    } catch (e) {
      final result = _agentError(
        'plugin_skill_load_failed',
        '加载插件 Skill 失败: $e',
        details: {'pluginId': plugin.id, 'skillName': skill.name, 'path': path},
      );
      _appendAgentTrace(
        AgentTraceEvent.error,
        '插件 Skill 加载失败',
        content: _errorMessage(result),
        metadata: {'pluginId': plugin.id, 'skillName': skill.name},
      );
      return result;
    }
  }

  bool get _agentEnabled {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) return false;
    return conversations.getConversation(cid)?.settings.agentEnabled == true;
  }

  LynAICallIdentity get _agentIdentity => LynAICallIdentity(
    type: LynAICallerType.agent,
    conversationId: _conversationId,
  );

  bool _hasAgentCapability(String capability) {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) return false;
    final settings = conversations.getConversation(cid)?.settings;
    if (settings == null || !settings.agentEnabled) return false;
    return _permissionService.canUseCapability(
      identity: _agentIdentity,
      capability: capability,
      appSettings: _settings?.settings,
    );
  }

  void _appendAgentTrace(
    String type,
    String title, {
    String? content,
    Map<String, dynamic>? metadata,
  }) {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) return;
    _agentRuntime.appendTrace(
      conversations,
      cid,
      type,
      title,
      content: content,
      metadata: metadata,
    );
  }

  static Map<String, dynamic> _agentError(
    String code,
    String message, {
    Map<String, dynamic>? details,
  }) => AgentRuntimeService.error(code, message, details: details);

  static Map<String, dynamic> _agentOk([Map<String, dynamic>? result]) {
    return AgentRuntimeService.ok(result);
  }

  static String? _errorMessage(Map<String, dynamic> result) {
    final error = result['error'];
    if (error is Map) return error['message']?.toString();
    return error?.toString();
  }

  Map<String, dynamic> _createPlan(Map<String, dynamic> args) {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) {
      return _agentError('missing_context', '缺少对话上下文');
    }
    return _agentRuntime.createPlan(conversations, cid, args);
  }

  Map<String, dynamic> _updatePlan(Map<String, dynamic> args) {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) {
      return _agentError('missing_context', '缺少对话上下文');
    }
    return _agentRuntime.updatePlan(conversations, cid, args);
  }

  Future<Map<String, dynamic>> _callPluginFunction(
    Map<String, dynamic> args,
  ) async {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) {
      return _agentError('missing_context', '缺少对话上下文');
    }
    final conv = conversations.getConversation(cid);
    if (conv?.settings.agentEnabled != true) {
      return _agentError('agent_disabled', '当前对话未启用 Agent 模式');
    }
    if (!_hasAgentCapability(LynAICapabilities.pluginCallFunction)) {
      final result = _agentError(
        'permission_denied',
        'Agent 未授权 plugins.callFunction。请请求用户在 Agent 设置中开启“调用插件函数”。',
      );
      _appendAgentTrace(
        AgentTraceEvent.error,
        '插件函数调用被拒绝',
        content: _errorMessage(result),
      );
      return result;
    }
    final plugins = _plugins;
    if (plugins == null) {
      return _agentError('plugin_system_unavailable', '插件系统不可用');
    }
    final pluginId = (args['pluginId'] as String? ?? '').trim();
    final functionName = (args['functionName'] as String? ?? '').trim();
    final functionArgs = args['arguments'] is Map
        ? Map<String, dynamic>.from(args['arguments'] as Map)
        : <String, dynamic>{};
    if (pluginId.isEmpty || functionName.isEmpty) {
      return _agentError(
        'invalid_arguments',
        'call_plugin_function 缺少 pluginId 或 functionName',
      );
    }
    InstalledPlugin? plugin;
    for (final item in plugins.plugins) {
      if (item.id == pluginId) {
        plugin = item;
        break;
      }
    }
    if (plugin == null || !plugin.enabled || plugin.hasError) {
      return _agentError('plugin_not_found', '插件不可用: $pluginId');
    }
    PluginFunctionDefinition? function;
    for (final item in plugin.manifest.functions) {
      if (item.name == functionName) {
        function = item;
        break;
      }
    }
    if (function == null || !plugin.enabledFunctions.contains(function.name)) {
      return _agentError(
        'plugin_function_not_found',
        '插件函数不可用: $pluginId.$functionName',
      );
    }
    if (!plugin.hasAllPermissionsGranted) {
      return _agentError(
        'plugin_permissions_missing',
        '插件 ${plugin.displayName} 权限不足，无法执行 $functionName',
      );
    }
    _appendAgentTrace(
      AgentTraceEvent.toolCall,
      '调用插件函数',
      content: '${plugin.displayName}.${function.name}',
      metadata: {'pluginId': plugin.id, 'functionName': function.name},
    );
    final result = await PluginLuaRuntimeService().executeFunction(
      plugin: plugin,
      function: function,
      arguments: functionArgs,
      features: _features,
      modelConfigs: _modelConfigs,
      plugins: _plugins,
      settings: _settings,
    );
    _appendAgentTrace(
      result['ok'] == false
          ? AgentTraceEvent.error
          : AgentTraceEvent.toolResult,
      result['ok'] == false ? '插件函数调用失败' : '插件函数调用完成',
      content: '${plugin.displayName}.${function.name}',
      metadata: {
        'pluginId': plugin.id,
        'functionName': function.name,
        'ok': result['ok'] != false,
        if (_errorMessage(result) != null) 'error': _errorMessage(result),
      },
    );
    if (result['ok'] == false) {
      return _agentError(
        'plugin_function_failed',
        _errorMessage(result) ?? '插件函数执行失败',
        details: result,
      );
    }
    final flattened = Map<String, dynamic>.from(result)..remove('ok');
    return {
      'ok': true,
      'result': {
        'pluginId': plugin.id,
        'functionName': function.name,
        'value': flattened.isEmpty ? result['result'] : flattened,
      },
    };
  }

  Future<Map<String, dynamic>> _executeAgentLua(
    Map<String, dynamic> args,
  ) async {
    final cid = _conversationId;
    final conversations = _conversations;
    if (cid == null || conversations == null) {
      return _agentError('missing_context', '缺少对话上下文');
    }
    final conv = conversations.getConversation(cid);
    if (conv?.settings.agentEnabled != true) {
      return _agentError('agent_disabled', '当前对话未启用 Agent 模式');
    }
    if (!_hasAgentCapability(LynAICapabilities.luaExecute)) {
      final result = _agentError(
        'permission_denied',
        'Agent 未授权 lua.execute。请请求用户在 Agent 设置中开启“执行 Lua 脚本”。',
      );
      _appendAgentTrace(
        AgentTraceEvent.error,
        'Agent Lua 被拒绝',
        content: _errorMessage(result),
      );
      return result;
    }
    _appendAgentTrace(
      AgentTraceEvent.toolCall,
      '执行 Agent Lua',
      content: (args['purpose'] as String? ?? '').trim(),
    );
    final result = await AgentLuaScriptService().execute(
      code: (args['code'] as String? ?? '').trim(),
      purpose: (args['purpose'] as String? ?? '').trim(),
      features: _features,
      modelConfigs: _modelConfigs,
      plugins: _plugins,
      settings: _settings,
      conversations: _conversations,
      conversationId: _conversationId,
      identity: _agentIdentity.child(
        type: LynAICallerType.agentLua,
        toolName: 'execute_lua',
      ),
    );
    _appendAgentTrace(
      result['ok'] == false
          ? AgentTraceEvent.error
          : AgentTraceEvent.toolResult,
      result['ok'] == false ? 'Agent Lua 执行失败' : 'Agent Lua 执行完成',
      content: (args['purpose'] as String? ?? '').trim(),
      metadata: {
        'ok': result['ok'] != false,
        'calls': result['calls'],
        if (_errorMessage(result) != null) 'error': _errorMessage(result),
      },
    );
    return result;
  }

  Future<Map<String, dynamic>?> _executePluginTool(ChatToolCall call) async {
    final plugins = _plugins;
    if (plugins == null) return null;
    for (final plugin in plugins.plugins) {
      if (!plugin.enabled || plugin.hasError) continue;
      for (final tool in plugin.manifest.tools) {
        if (tool.name != call.name) continue;
        if (!plugin.enabledTools.contains(tool.name)) continue;
        if (!plugin.hasAllPermissionsGranted) {
          return _error('插件 ${plugin.manifest.name} 权限不足，无法执行 ${call.name}');
        }
        return PluginLuaRuntimeService().executeTool(
          plugin: plugin,
          tool: tool,
          arguments: call.arguments,
          features: _features,
          modelConfigs: _modelConfigs,
          plugins: _plugins,
          settings: _settings,
        );
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _invokeNative(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      method,
      arguments,
    );
    return result ?? {'ok': false, 'message': '平台无返回'};
  }

  Map<String, dynamic> _listSchedules(Map<String, dynamic> args) {
    final from = _dateArg(args, 'from');
    final to = _dateArg(args, 'to');
    final items = _features.schedules
        .where((item) {
          if (from != null && !_scheduleVisibleEnd(item).isAfter(from)) {
            return false;
          }
          if (to != null && !item.start.isBefore(to)) return false;
          return true;
        })
        .map(_scheduleJson)
        .toList();
    return {
      'ok': true,
      'timezone': DateTime.now().timeZoneName,
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'schedules': items,
    };
  }

  Future<Map<String, dynamic>> _createSchedule(
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    final start = _dateArg(args, 'start');
    final kind = _scheduleKindArg(args);
    final end = kind == ScheduleItem.kindTask
        ? start?.add(const Duration(minutes: 1))
        : _dateArg(args, 'end');
    if (title.isEmpty || start == null || end == null) {
      return _error(
        kind == ScheduleItem.kindTask
            ? '创建任务需要 title、start'
            : '创建日程需要 title、start、end',
      );
    }
    if (kind != ScheduleItem.kindTask && !end.isAfter(start)) {
      return _error('结束时间必须晚于开始时间');
    }
    final id = await _features.addSchedule(
      title,
      start,
      end,
      note: args['note'] as String?,
      kind: kind,
    );
    final schedule = _features.getSchedule(id);
    return {
      'ok': true,
      'schedule': schedule == null ? null : _scheduleJson(schedule),
    };
  }

  Future<Map<String, dynamic>> _updateSchedule(
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final current = _features.getSchedule(id);
    if (current == null) return _error('未找到日程: $id');
    final nextKind = args.containsKey('kind')
        ? _scheduleKindArg(args)
        : current.kind;
    final nextStart = _dateArg(args, 'start') ?? current.start;
    final parsedEnd = _dateArg(args, 'end');
    final nextEnd = nextKind == ScheduleItem.kindTask
        ? nextStart.add(const Duration(minutes: 1))
        : parsedEnd ?? current.end;
    final updated = args.containsKey('note')
        ? current.copyWith(
            title: (args['title'] as String?)?.trim(),
            start: nextStart,
            end: nextEnd,
            note: args['note'] as String?,
            kind: nextKind,
          )
        : current.copyWith(
            title: (args['title'] as String?)?.trim(),
            start: nextStart,
            end: nextEnd,
            kind: nextKind,
          );
    if (!updated.isTask && !updated.end.isAfter(updated.start)) {
      return _error('结束时间必须晚于开始时间');
    }
    await _features.updateSchedule(updated);
    return {'ok': true, 'schedule': _scheduleJson(updated)};
  }

  Map<String, dynamic> _listNotes(Map<String, dynamic> args) {
    final query = (args['query'] as String? ?? '').trim();
    final matcher = _TextMatcher(query);
    final folderId = (args['folderId'] as String? ?? '').trim();
    final includeContent = args['includeContent'] as bool? ?? false;
    if (includeContent && query.isEmpty) {
      return _error('includeContent 需要提供 query，避免一次读取全部笔记正文');
    }
    final notes = _features.notes.where((note) {
      if (folderId.isNotEmpty && note.folderId != folderId) return false;
      if (matcher.isEmpty) return true;
      return matcher.matches(note.title) || matcher.matches(note.content);
    });
    return {
      'ok': true,
      'notes': notes.map((note) {
        final summary = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
        return {
          'id': note.id,
          'title': note.title,
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
          if (note.folderId != null) 'folderId': note.folderId,
          'summary': summary.length > 120
              ? '${summary.substring(0, 120)}...'
              : summary,
          if (includeContent) 'content': note.content,
        };
      }).toList(),
    };
  }

  Future<Map<String, dynamic>> _readNote(Map<String, dynamic> args) async {
    final selected = await _selectNoteForTool(args);
    if (selected.error != null) return _error(selected.error!);
    final note = selected.note!;
    return _noteReadResult(note);
  }

  Future<_SelectedNote> _selectNoteForTool(Map<String, dynamic> args) async {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    final query = (args['query'] as String? ?? '').trim();
    final pageId = (args['pageId'] as String? ?? '').trim();
    final pageTitle = (args['pageTitle'] as String? ?? '').trim();
    final matcher = _TextMatcher(query);

    Note? note;
    if (id.isNotEmpty) {
      note = _features.getNote(id);
    }
    if (note == null && title.isNotEmpty) {
      note = _findNote(
        (candidate) =>
            _scoreNoteMatch(candidate, query: title, preferTitle: true),
      );
    }
    if (note == null && !matcher.isEmpty) {
      note = _findNote(
        (candidate) => _scoreNoteMatch(candidate, matcher: matcher),
      );
    }
    if (note == null) {
      return const _SelectedNote.error('未找到匹配的笔记，请先调用 list_notes 查看可用笔记');
    }
    if (pageId.isNotEmpty || pageTitle.isNotEmpty) {
      final page = _findNotePage(note.id, pageId: pageId, pageTitle: pageTitle);
      if (page == null) {
        return _SelectedNote.error(
          '未找到笔记分页: ${pageId.isNotEmpty ? pageId : pageTitle}',
        );
      }
      await _features.selectNotePage(note.id, page.id);
      note = _features.getNote(note.id);
      if (note == null) return const _SelectedNote.error('切换分页后未找到笔记');
    }
    return _SelectedNote(note: note);
  }

  Map<String, dynamic> _noteReadResult(Note note) {
    final activePage = _features.activeNotePage(note.id);
    final pages = _features.notePages(note.id);
    return {
      'ok': true,
      'note': {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        if (activePage != null) 'pageId': activePage.id,
        if (activePage != null) 'pageTitle': activePage.title,
        if (note.folderId != null) 'folderId': note.folderId,
        'createdAt': note.createdAt.toIso8601String(),
        'updatedAt': note.updatedAt.toIso8601String(),
        'wrap': note.wrap,
      },
      if (activePage != null) 'activePage': _notePageJson(activePage),
      if (pages.isNotEmpty) 'pages': pages.map(_notePageJson).toList(),
      'outline': _noteOutline(note.content),
      'contentHash': _contentHash(note.content),
      'currentRevisionId': note.currentRevisionId,
      'lineCount': _splitNoteLines(note.content).length,
      'lineNumberBase': 1,
      'appendStartLine': _splitNoteLines(note.content).length + 1,
      'lineEditHint':
          'edit_note/propose_note_edit 的 startLine 从 1 开始，对应 numberedLines.line；替换/删除时建议带 expectedLines 校验原文；startLine=lineCount+1 且 deleteCount=0 表示追加到末尾。',
      'numberedLines': _numberedNoteLines(note.content),
    };
  }

  StorageV2NotePage? _findNotePage(
    String noteId, {
    required String pageId,
    required String pageTitle,
  }) {
    final pages = _features.notePages(noteId);
    if (pages.isEmpty) return null;
    if (pageId.isNotEmpty) {
      for (final page in pages) {
        if (page.id == pageId) return page;
      }
      return null;
    }
    final normalized = pageTitle.toLowerCase();
    for (final page in pages) {
      if (page.title.toLowerCase() == normalized ||
          page.fileName.toLowerCase() == normalized) {
        return page;
      }
    }
    for (final page in pages) {
      if (page.title.toLowerCase().contains(normalized) ||
          page.fileName.toLowerCase().contains(normalized)) {
        return page;
      }
    }
    return null;
  }

  Note? _findNote(int Function(Note note) score) {
    Note? best;
    var bestScore = 0;
    for (final note in _features.notes) {
      final currentScore = score(note);
      if (currentScore <= 0) continue;
      if (best == null ||
          currentScore > bestScore ||
          (currentScore == bestScore &&
              note.updatedAt.isAfter(best.updatedAt))) {
        best = note;
        bestScore = currentScore;
      }
    }
    return best;
  }

  int _scoreNoteMatch(
    Note note, {
    String? query,
    _TextMatcher? matcher,
    bool preferTitle = false,
  }) {
    if (matcher != null && matcher.isRegex) {
      if (matcher.matches(note.title)) return 250;
      if (!preferTitle && matcher.matches(note.content)) return 100;
      return 0;
    }
    final normalizedQuery = (query ?? matcher?.query ?? '').toLowerCase();
    if (normalizedQuery.isEmpty) return 0;
    final normalizedTitle = note.title.toLowerCase();
    final normalizedContent = note.content.toLowerCase();
    if (normalizedTitle == normalizedQuery) return preferTitle ? 600 : 500;
    if (normalizedTitle.startsWith(normalizedQuery)) {
      return preferTitle ? 450 : 350;
    }
    if (normalizedTitle.contains(normalizedQuery)) {
      return preferTitle ? 300 : 250;
    }
    if (!preferTitle && normalizedContent.contains(normalizedQuery)) return 100;
    return 0;
  }

  Future<Map<String, dynamic>> _saveNote(Map<String, dynamic> args) async {
    final title = (args['title'] as String? ?? '').trim();
    final content = args['content'] as String? ?? '';
    final id = (args['id'] as String? ?? '').trim();
    final append = args['append'] as bool? ?? false;
    final hasContent = args.containsKey('content');
    final hasFolderId = args.containsKey('folderId');
    final folderId = (args['folderId'] as String? ?? '').trim();
    if (hasFolderId &&
        folderId.isNotEmpty &&
        _features.getNoteFolder(folderId) == null) {
      return _error('未找到笔记文件夹: $folderId');
    }
    if (id.isEmpty) {
      if (title.isEmpty) return _error('创建笔记需要 title');
      if (!hasContent) return _error('创建笔记需要 content');
      final newId = await _features.addNoteWithContent(
        title,
        content,
        folderId: hasFolderId && folderId.isNotEmpty ? folderId : null,
      );
      final note = _features.getNote(newId);
      if (note == null) return _error('创建笔记失败');
      return {
        'ok': true,
        'note': note.toJson(),
        'contentHash': _contentHash(note.content),
        'lineCount': _splitNoteLines(note.content).length,
        'currentRevisionId': note.currentRevisionId,
        'timelineSaved': note.currentRevisionId != null,
        'revisionId': note.currentRevisionId,
        'contentChanged': content.isNotEmpty,
        'diff': _lineDiff('', note.content),
        'diffSummary': _diffSummary('', note.content),
        'lineDiffSummary': _lineDiffSummary('', note.content),
      };
    }
    final selected = await _selectNoteForTool(args);
    if (selected.error != null) return _error(selected.error!);
    final note = selected.note!;
    if (title.isEmpty && !hasContent && !hasFolderId) {
      return _error('修改笔记需要 title、content 或 folderId');
    }
    final nextContent = !hasContent
        ? note.content
        : append && note.content.trim().isNotEmpty
        ? '${note.content}\n\n$content'
        : content;
    final updated = note.copyWith(
      title: title.isEmpty ? null : title,
      folderId: hasFolderId
          ? (folderId.isEmpty ? null : folderId)
          : note.folderId,
    );
    if (updated.title != note.title || updated.folderId != note.folderId) {
      await _features.updateNote(updated);
    }
    NoteRevision? revision;
    if (hasContent) {
      revision = await _features.saveNoteContent(note.id, nextContent);
    }
    final savedNote = _features.getNote(note.id) ?? updated;
    final contentChanged = hasContent && note.content != savedNote.content;
    return {
      'ok': true,
      'note': savedNote.toJson(),
      'contentHash': _contentHash(savedNote.content),
      'lineCount': _splitNoteLines(savedNote.content).length,
      'currentRevisionId': savedNote.currentRevisionId,
      'timelineSaved': revision != null && contentChanged,
      'revisionId': contentChanged ? revision?.id : null,
      'contentChanged': contentChanged,
      if (hasContent) 'diff': _lineDiff(note.content, savedNote.content),
      if (hasContent)
        'diffSummary': _diffSummary(note.content, savedNote.content),
      if (hasContent)
        'lineDiffSummary': _lineDiffSummary(note.content, savedNote.content),
    };
  }

  Future<Map<String, dynamic>> _editNote(Map<String, dynamic> args) async {
    final parsed = await _parseNoteEditArgs(
      args,
      emptyMessage: 'edit_note 需要 edits',
    );
    if (parsed.error != null) return _error(parsed.error!);
    final note = parsed.note!;
    final edits = parsed.edits;
    final editResult = _applyLineEdits(note.content, edits);
    if (editResult.error != null) return _error(editResult.error!);
    final nextContent = editResult.content!;
    final baseRevisionId = (args['baseRevisionId'] as String? ?? '').trim();
    final revision = nextContent == note.content
        ? null
        : await _features.saveNoteContent(
            note.id,
            nextContent,
            baseRevisionId: baseRevisionId.isEmpty ? null : baseRevisionId,
          );
    final savedNote = _features.getNote(note.id) ?? note;
    return {
      'ok': true,
      'note': savedNote.toJson(),
      'contentHash': _contentHash(savedNote.content),
      'lineCount': _splitNoteLines(savedNote.content).length,
      'currentRevisionId': savedNote.currentRevisionId,
      'timelineSaved': revision != null,
      'revisionId': revision?.id,
      'contentChanged': nextContent != note.content,
      'diff': _lineDiff(note.content, savedNote.content),
      'diffSummary': _diffSummary(note.content, savedNote.content),
      'lineDiffSummary': _lineDiffSummary(note.content, savedNote.content),
    };
  }

  Future<Map<String, dynamic>> _proposeNoteEdit(
    Map<String, dynamic> args,
  ) async {
    final parsed = await _parseNoteEditArgs(
      args,
      emptyMessage: 'propose_note_edit 需要 edits',
    );
    if (parsed.error != null) return _error(parsed.error!);
    final note = parsed.note!;
    final editResult = _applyLineEdits(note.content, parsed.edits);
    if (editResult.error != null) return _error(editResult.error!);
    final nextContent = editResult.content!;
    if (nextContent == note.content) return _error('修改建议没有产生内容变化');
    final proposal = _proposalFromEdits(
      note: note,
      pageId: _features.activeNotePage(note.id)?.id,
      edits: parsed.edits,
      baseRevisionId: parsed.baseRevisionId,
    );
    await _features.setNoteEditProposal(proposal);
    return {
      'ok': true,
      'proposal': proposal.toJson(),
      'note': note.toJson(),
      'contentHash': _contentHash(note.content),
      'lineCount': _splitNoteLines(note.content).length,
      'currentRevisionId': note.currentRevisionId,
      'contentChanged': true,
      'timelineSaved': false,
      'diff': _lineDiff(note.content, nextContent),
      'diffSummary': _diffSummary(note.content, nextContent),
      'lineDiffSummary': _lineDiffSummary(note.content, nextContent),
    };
  }

  Map<String, dynamic> _listNotePages(Map<String, dynamic> args) {
    final id = (args['id'] as String? ?? '').trim();
    final note = _features.getNote(id);
    if (note == null) return _error('未找到笔记: $id');
    final activePage = _features.activeNotePage(id);
    return {
      'ok': true,
      'noteId': id,
      'activePageId': activePage?.id,
      'pages': _features.notePages(id).map(_notePageJson).toList(),
    };
  }

  Future<Map<String, dynamic>> _saveNotePage(Map<String, dynamic> args) async {
    final noteId = (args['id'] as String? ?? '').trim();
    final note = _features.getNote(noteId);
    if (note == null) return _error('未找到笔记: $noteId');
    final pageId = (args['pageId'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final delete = args['delete'] == true;
    final move = (args['move'] as String? ?? '').trim().toLowerCase();
    if (delete) {
      if (pageId.isEmpty) return _error('删除分页需要 pageId');
      final deleted = await _features.deleteNotePage(noteId, pageId);
      if (!deleted) return _error('删除分页失败，至少保留一个分页');
      return _listNotePages({'id': noteId});
    }
    if (move.isNotEmpty) {
      if (pageId.isEmpty) return _error('移动分页需要 pageId');
      final delta = switch (move) {
        'up' => -1,
        'down' => 1,
        _ => 0,
      };
      if (delta == 0) return _error('move 只支持 up 或 down');
      final moved = await _features.moveNotePage(noteId, pageId, delta);
      if (!moved) return _error('分页无法继续移动');
      return _listNotePages({'id': noteId});
    }
    if (pageId.isEmpty) {
      final newPageId = await _features.addNotePage(noteId, title);
      if (newPageId == null) return _error('当前存储不支持分页');
      return _noteReadResult(_features.getNote(noteId) ?? note);
    }
    if (title.isEmpty) return _error('重命名分页需要 title');
    await _features.renameNotePage(noteId, pageId, title);
    final page = _findNotePage(noteId, pageId: pageId, pageTitle: '');
    return {'ok': true, 'page': page == null ? null : _notePageJson(page)};
  }

  Map<String, dynamic> _notePageJson(StorageV2NotePage page) {
    return {
      'id': page.id,
      'noteId': page.noteId,
      'title': page.title,
      'fileName': page.fileName,
      'currentRevisionId': page.currentRevisionId,
      'updatedAt': page.updatedAt.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _noteOutline(String content) {
    final headings = <Map<String, dynamic>>[];
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final match = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(lines[i]);
      if (match == null) continue;
      headings.add({
        'line': i + 1,
        'level': match.group(1)!.length,
        'title': match.group(2)!,
      });
    }
    return headings;
  }

  Future<_ParsedNoteEdit> _parseNoteEditArgs(
    Map<String, dynamic> args, {
    required String emptyMessage,
  }) async {
    final selected = await _selectNoteForTool(args);
    if (selected.error != null) return _ParsedNoteEdit.error(selected.error!);
    final note = selected.note!;
    final expectedHash = (args['expectedContentHash'] as String? ?? '').trim();
    final currentHash = _contentHash(note.content);
    if (expectedHash.isNotEmpty && expectedHash != currentHash) {
      return _ParsedNoteEdit.error('笔记内容已变化，请重新 read_note 后再编辑');
    }
    final rawEdits = args['edits'];
    if (rawEdits is! List || rawEdits.isEmpty) {
      return _ParsedNoteEdit.error(emptyMessage);
    }
    final edits = <_NoteLineEdit>[];
    for (final raw in rawEdits) {
      final edit = _NoteLineEdit.fromRaw(raw);
      if (edit == null) return _ParsedNoteEdit.error('edits 格式错误');
      edits.add(edit);
    }
    final baseRevisionId = (args['baseRevisionId'] as String? ?? '').trim();
    return _ParsedNoteEdit(
      note: note,
      edits: edits,
      baseRevisionId: baseRevisionId.isEmpty ? null : baseRevisionId,
    );
  }

  Map<String, dynamic> _listNoteFolders() {
    final counts = <String, int>{};
    for (final note in _features.notes) {
      final fid = note.folderId;
      if (fid != null) counts[fid] = (counts[fid] ?? 0) + 1;
    }
    return {
      'ok': true,
      'folders': _features.noteFolders.map((folder) {
        return {
          'id': folder.id,
          'title': folder.title,
          'createdAt': folder.createdAt.toIso8601String(),
          'updatedAt': folder.updatedAt.toIso8601String(),
          'noteCount': counts[folder.id] ?? 0,
        };
      }).toList(),
    };
  }

  Future<Map<String, dynamic>> _saveNoteFolder(
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final delete = _boolArg(args, 'delete') ?? false;
    if (id.isEmpty) {
      if (delete) return _error('删除文件夹需要 id');
      if (title.isEmpty) return _error('创建笔记文件夹需要 title');
      final newId = await _features.addNoteFolder(title);
      final folder = _features.getNoteFolder(newId);
      return {'ok': true, 'folder': folder?.toJson()};
    }
    final folder = _features.getNoteFolder(id);
    if (folder == null) return _error('未找到笔记文件夹: $id');
    if (delete) {
      await _features.deleteNoteFolder(id);
      return {'ok': true, 'deleted': true};
    }
    if (title.isEmpty) return _error('重命名笔记文件夹需要 title');
    final updated = folder.copyWith(title: title);
    await _features.updateNoteFolder(updated);
    return {'ok': true, 'folder': updated.toJson()};
  }

  Map<String, dynamic> _listTodoLists(Map<String, dynamic> args) {
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    final includeItems = _boolArg(args, 'includeItems') ?? false;
    final lists = _features.todoLists.where((list) {
      if (query.isEmpty) return true;
      return list.title.toLowerCase().contains(query) ||
          list.items.any((item) => item.text.toLowerCase().contains(query));
    });
    return {
      'ok': true,
      'todoLists': lists.map((list) {
        final done = list.items.where((item) => item.done).length;
        return {
          'id': list.id,
          'title': list.title,
          'createdAt': list.createdAt.toIso8601String(),
          'updatedAt': list.updatedAt.toIso8601String(),
          'totalItems': list.items.length,
          'doneItems': done,
          if (includeItems) 'items': list.items.map(_todoItemJson).toList(),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _readTodoList(Map<String, dynamic> args) {
    final list = _findTodoList(args);
    if (list == null) {
      return _error('未找到匹配的待办清单，请先调用 list_todo_lists 查看可用清单');
    }
    return {'ok': true, 'todoList': _todoListJson(list)};
  }

  Future<Map<String, dynamic>> _saveTodoList(Map<String, dynamic> args) async {
    final title = (args['title'] as String? ?? '').trim();
    final id = (args['id'] as String? ?? '').trim();
    final rawItems = args['items'];
    final items = rawItems is List
        ? rawItems.map(_todoItemFromRaw).whereType<TodoItem>().toList()
        : <TodoItem>[];
    if (id.isEmpty) {
      if (title.isEmpty) return _error('创建待办清单需要 title');
      final newId = await _features.addTodoListWithItems(title, items);
      final list = _features.getTodoList(newId);
      return {
        'ok': true,
        'todoList': list == null ? null : _todoListJson(list),
      };
    }
    final current = _features.getTodoList(id);
    if (current == null) return _error('未找到待办清单: $id');
    if (title.isEmpty && rawItems is! List) {
      return _error('修改待办清单需要 title 或 items');
    }
    final updated = rawItems is List
        ? current.copyWith(title: title.isEmpty ? null : title, items: items)
        : current.copyWith(title: title);
    await _features.updateTodoList(updated);
    return {'ok': true, 'todoList': _todoListJson(updated)};
  }

  Future<Map<String, dynamic>> _saveTodoItem(Map<String, dynamic> args) async {
    final listId = (args['listId'] as String? ?? '').trim();
    if (listId.isEmpty) return _error('缺少 listId');
    final list = _features.getTodoList(listId);
    if (list == null) return _error('未找到待办清单: $listId');
    final itemId = (args['itemId'] as String? ?? '').trim();
    final delete = _boolArg(args, 'delete') ?? false;
    if (itemId.isEmpty) {
      if (delete) return _error('删除待办项需要 itemId');
      final text = (args['text'] as String? ?? '').trim();
      if (text.isEmpty) return _error('创建待办项需要 text');
      final item = TodoItem(
        id: _uuid.v4(),
        text: text,
        done: _boolArg(args, 'done') ?? false,
      );
      final updated = list.copyWith(items: [item, ...list.items]);
      await _features.updateTodoList(updated);
      return {
        'ok': true,
        'todoList': _todoListJson(updated),
        'item': _todoItemJson(item),
      };
    }
    final index = list.items.indexWhere((item) => item.id == itemId);
    if (index == -1) return _error('未找到待办项: $itemId');
    if (delete) {
      final updated = list.copyWith(
        items: list.items.where((item) => item.id != itemId).toList(),
      );
      await _features.updateTodoList(updated);
      return {'ok': true, 'todoList': _todoListJson(updated)};
    }
    final current = list.items[index];
    final text = (args['text'] as String?)?.trim();
    final done = _boolArg(args, 'done');
    final item = current.copyWith(
      text: text == null || text.isEmpty ? null : text,
      done: done,
    );
    final items = List<TodoItem>.from(list.items)..[index] = item;
    final updated = list.copyWith(items: items);
    await _features.updateTodoList(updated);
    return {
      'ok': true,
      'todoList': _todoListJson(updated),
      'item': _todoItemJson(item),
    };
  }

  TodoList? _findTodoList(Map<String, dynamic> args) {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    final query = (args['query'] as String? ?? '').trim().toLowerCase();

    if (id.isNotEmpty) return _features.getTodoList(id);
    if (title.isNotEmpty) {
      return _bestTodoListMatch((list) => list.title.toLowerCase() == title) ??
          _bestTodoListMatch(
            (list) => list.title.toLowerCase().contains(title),
          );
    }
    if (query.isNotEmpty) {
      return _bestTodoListMatch(
            (list) => list.title.toLowerCase().contains(query),
          ) ??
          _bestTodoListMatch(
            (list) => list.items.any(
              (item) => item.text.toLowerCase().contains(query),
            ),
          );
    }
    return null;
  }

  TodoList? _bestTodoListMatch(bool Function(TodoList list) test) {
    for (final list in _features.todoLists) {
      if (test(list)) return list;
    }
    return null;
  }

  static TodoItem? _todoItemFromRaw(Object? raw) {
    if (raw is! Map) return null;
    final item = _todoItemFromJson(Map<String, dynamic>.from(raw));
    return item.text.isEmpty ? null : item;
  }

  static TodoItem _todoItemFromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    return TodoItem(
      id: id.isEmpty ? _uuid.v4() : id,
      text: (json['text'] as String? ?? '').trim(),
      done: _boolArg(json, 'done') ?? false,
    );
  }

  static String _contentHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  static List<String> _splitNoteLines(String content) {
    if (content.isEmpty) return const [''];
    return content.split('\n');
  }

  static List<Map<String, dynamic>> _numberedNoteLines(String content) {
    final lines = _splitNoteLines(content);
    return [
      for (var i = 0; i < lines.length; i++) {'line': i + 1, 'text': lines[i]},
    ];
  }

  static String _joinNoteLines(List<String> lines) {
    return lines.join('\n');
  }

  static _AppliedLineEdits _applyLineEdits(
    String content,
    List<_NoteLineEdit> edits,
  ) {
    final lines = _splitNoteLines(content);
    final sorted = [...edits]
      ..sort((a, b) => b.startLine.compareTo(a.startLine));
    var previousStart = lines.length + 1;
    for (final edit in sorted) {
      final startIndex = edit.startLine - 1;
      final endIndex = startIndex + edit.deleteCount;
      if (edit.startLine < 1 || startIndex > lines.length) {
        return _AppliedLineEdits.error(
          'edits 行号越界：startLine 必须在 1 到 ${lines.length + 1} 之间，${lines.length + 1} 仅用于 deleteCount=0 的末尾追加',
        );
      }
      if (startIndex == lines.length && edit.deleteCount != 0) {
        return _AppliedLineEdits.error('末尾追加时 deleteCount 必须为 0');
      }
      if (endIndex > lines.length) {
        return _AppliedLineEdits.error('edits 删除范围越界：deleteCount 超过可用行数');
      }
      if (endIndex > previousStart - 1) {
        return _AppliedLineEdits.error('edits 存在重叠或顺序冲突，请合并相邻修改');
      }
      final expectedLines = edit.expectedLines;
      if (expectedLines != null) {
        if (expectedLines.length != edit.deleteCount) {
          return _AppliedLineEdits.error(
            'expectedLines 数量必须等于 deleteCount，用于校验被替换/删除的原文',
          );
        }
        final actualLines = lines.sublist(startIndex, endIndex);
        for (var i = 0; i < expectedLines.length; i++) {
          if (expectedLines[i] != actualLines[i]) {
            return _AppliedLineEdits.error(
              '第 ${edit.startLine + i} 行原文不匹配，请重新 read_note 后按 numberedLines 行号编辑',
            );
          }
        }
      }
      lines.replaceRange(startIndex, endIndex, edit.insertLines);
      previousStart = edit.startLine;
    }
    return _AppliedLineEdits.success(_joinNoteLines(lines));
  }

  static NoteEditProposal _proposalFromEdits({
    required Note note,
    required String? pageId,
    required List<_NoteLineEdit> edits,
    required String? baseRevisionId,
  }) {
    final lines = _splitNoteLines(note.content);
    return NoteEditProposal(
      id: _uuid.v4(),
      noteId: note.id,
      pageId: pageId,
      baseRevisionId: baseRevisionId,
      baseContentHash: _contentHash(note.content),
      createdAt: DateTime.now(),
      blocks: edits.map((edit) {
        final start = edit.startLine - 1;
        final end = (start + edit.deleteCount).clamp(0, lines.length);
        return NoteEditBlock(
          id: _uuid.v4(),
          startLine: edit.startLine,
          deleteCount: edit.deleteCount,
          deletedLines: start >= 0 && start <= end
              ? lines.sublist(start, end)
              : const [],
          insertLines: edit.insertLines,
        );
      }).toList(),
    );
  }

  static List<Map<String, dynamic>> _lineDiff(String before, String after) {
    final beforeLines = _splitNoteLines(before);
    final afterLines = _splitNoteLines(after);
    var prefix = 0;
    final maxPrefix = beforeLines.length < afterLines.length
        ? beforeLines.length
        : afterLines.length;
    while (prefix < maxPrefix && beforeLines[prefix] == afterLines[prefix]) {
      prefix++;
    }
    var beforeSuffix = beforeLines.length;
    var afterSuffix = afterLines.length;
    while (beforeSuffix > prefix &&
        afterSuffix > prefix &&
        beforeLines[beforeSuffix - 1] == afterLines[afterSuffix - 1]) {
      beforeSuffix--;
      afterSuffix--;
    }
    final diff = <Map<String, dynamic>>[];
    for (var i = prefix; i < beforeSuffix; i++) {
      diff.add({'line': i + 1, 'type': 'remove', 'text': beforeLines[i]});
    }
    for (var i = prefix; i < afterSuffix; i++) {
      diff.add({'line': i + 1, 'type': 'add', 'text': afterLines[i]});
    }
    return diff;
  }

  static String _diffSummary(String before, String after) {
    final delta = NoteTextDelta.between(before, after);
    final added = delta.insertedText.length;
    final removed = delta.deletedText.length;
    if (added == 0 && removed == 0) return '无内容变化';
    if (added > 0 && removed > 0) return '+$added / -$removed 字符';
    if (added > 0) return '+$added 字符';
    return '-$removed 字符';
  }

  static String _lineDiffSummary(String before, String after) {
    final diff = _lineDiff(before, after);
    final added = diff.where((line) => line['type'] == 'add').length;
    final removed = diff.where((line) => line['type'] == 'remove').length;
    if (added == 0 && removed == 0) return '行无变化';
    if (added > 0 && removed > 0) return '+$added / -$removed 行';
    if (added > 0) return '+$added 行';
    return '-$removed 行';
  }

  static bool? _boolArg(Map<String, dynamic> args, String key) {
    final raw = args[key];
    if (raw is bool) return raw;
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }

  static Map<String, dynamic> _todoListJson(TodoList list) {
    return {
      'id': list.id,
      'title': list.title,
      'createdAt': list.createdAt.toIso8601String(),
      'updatedAt': list.updatedAt.toIso8601String(),
      'items': list.items.map(_todoItemJson).toList(),
    };
  }

  static Map<String, dynamic> _todoItemJson(TodoItem item) {
    return {'id': item.id, 'text': item.text, 'done': item.done};
  }

  static DateTime? _dateArg(Map<String, dynamic> args, String key) {
    final raw = args[key] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toLocal();
  }

  static String _scheduleKindArg(Map<String, dynamic> args) {
    final raw = (args['kind'] as String? ?? '').trim().toLowerCase();
    if (raw == ScheduleItem.kindTask || raw == '任务') {
      return ScheduleItem.kindTask;
    }
    return ScheduleItem.kindSchedule;
  }

  static DateTime _scheduleVisibleEnd(ScheduleItem item) {
    return item.isTask ? item.start.add(const Duration(minutes: 1)) : item.end;
  }

  static Map<String, dynamic> _scheduleJson(ScheduleItem item) {
    return {
      'id': item.id,
      'kind': item.kind,
      'title': item.title,
      'start': item.start.toLocal().toIso8601String(),
      if (!item.isTask) 'end': item.end.toLocal().toIso8601String(),
      'timezone': item.start.toLocal().timeZoneName,
      'timezoneOffsetMinutes': item.start.toLocal().timeZoneOffset.inMinutes,
      if (item.note != null) 'note': item.note,
    };
  }

  static String _stringArg(ChatToolCall call, String key) {
    return (call.arguments[key] as String? ?? '').trim();
  }

  static Map<String, dynamic> _error(String message) => {
    'ok': false,
    'error': message,
  };

  static String _qualifiedName(String pluginId, String name) =>
      '${pluginId}__$name';

  static (String, String)? _parseQualifiedName(String value) {
    final index = value.indexOf('__');
    if (index <= 0 || index + 2 >= value.length) return null;
    return (value.substring(0, index), value.substring(index + 2));
  }
}
