import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/message.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';
import '../providers/feature_provider.dart';

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

class ToolCallService {
  ToolCallService(this._features);

  static const _channel = MethodChannel('lynai/native_tools');

  final FeatureProvider _features;

  static const systemPrompt = '''
你可以使用本地工具帮助用户管理日程、笔记、获取时间/位置、打开安卓应用和创建对话标题。
当需要调用工具且当前模型接口不支持原生 tool_calls 时，只返回一个 JSON 对象，不要包含 Markdown：
{"tool_calls":[{"name":"工具名","arguments":{...}}]}
收到工具结果后，再用自然语言给用户最终回复。
创建或修改数据前，应从用户输入中提取明确字段；缺少关键字段时先追问。
需要查看笔记内容时，先用 list_notes 查找笔记 id，再用 read_note 读取完整内容；如果用户给出明确标题，也可以直接用 read_note 按标题搜索。
日程时间使用带时区偏移的 ISO-8601 字符串；用户说“今天/明天”时必须先结合 get_current_time 的 iso 与 timezoneOffsetMinutes 换算成本地日期时间。
''';

  static String currentTimeContext() {
    final now = DateTime.now();
    return '当前设备本地时间: ${now.toIso8601String()}，时区: ${now.timeZoneName}，timezoneOffsetMinutes: ${now.timeZoneOffset.inMinutes}。';
  }

  static List<Map<String, dynamic>> openAITools() => [
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
        'name': 'get_location',
        'description': '获取设备当前位置。仅在平台允许并授权时可用。',
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
        'description': '查看用户日程列表，可用于规划日常安排。',
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
        'description': '创建新的日程。',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'start': {'type': 'string', 'description': 'ISO-8601 开始时间'},
            'end': {'type': 'string', 'description': 'ISO-8601 结束时间'},
            'note': {'type': 'string'},
          },
          'required': ['title', 'start', 'end'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'update_schedule',
        'description': '按 id 修改已有日程。',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
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
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'save_note',
        'description': '创建或修改并保存笔记，可整理用户与 AI 的对话内容。',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': '已有笔记 id；为空则创建'},
            'title': {'type': 'string'},
            'content': {'type': 'string'},
            'append': {'type': 'boolean', 'description': '是否追加到已有内容'},
          },
          'required': ['title', 'content'],
        },
      },
    },
  ];

  static List<ChatToolCall> parseFallbackToolCalls(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final data = jsonDecode(_stripCodeFence(trimmed));
      final rawCalls = data is Map<String, dynamic> ? data['tool_calls'] : null;
      if (rawCalls is! List) return const [];
      return rawCalls
          .whereType<Map<String, dynamic>>()
          .map((call) {
            final name = call['name'] as String? ?? '';
            final args = _decodeArguments(call['arguments']);
            return ChatToolCall(
              id: 'fallback_${DateTime.now().microsecondsSinceEpoch}_$name',
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
        case 'list_schedules':
          return _listSchedules(call.arguments);
        case 'create_schedule':
          return await _createSchedule(call.arguments);
        case 'update_schedule':
          return await _updateSchedule(call.arguments);
        case 'list_notes':
          return _listNotes(call.arguments);
        case 'read_note':
          return _readNote(call.arguments);
        case 'save_note':
          return await _saveNote(call.arguments);
        default:
          return _error('未知工具: ${call.name}');
      }
    } catch (e, st) {
      debugPrint('工具调用失败 ${call.name}: $e\n$st');
      return _error(e.toString());
    }
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
          if (from != null && !item.end.isAfter(from)) return false;
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
    final end = _dateArg(args, 'end');
    if (title.isEmpty || start == null || end == null) {
      return _error('创建日程需要 title、start、end');
    }
    if (!end.isAfter(start)) return _error('结束时间必须晚于开始时间');
    final id = await _features.addSchedule(
      title,
      start,
      end,
      note: args['note'] as String?,
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
    final updated = args.containsKey('note')
        ? current.copyWith(
            title: (args['title'] as String?)?.trim(),
            start: _dateArg(args, 'start'),
            end: _dateArg(args, 'end'),
            note: args['note'] as String?,
          )
        : current.copyWith(
            title: (args['title'] as String?)?.trim(),
            start: _dateArg(args, 'start'),
            end: _dateArg(args, 'end'),
          );
    if (!updated.end.isAfter(updated.start)) return _error('结束时间必须晚于开始时间');
    await _features.updateSchedule(updated);
    return {'ok': true, 'schedule': _scheduleJson(updated)};
  }

  Map<String, dynamic> _listNotes(Map<String, dynamic> args) {
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    final includeContent = args['includeContent'] as bool? ?? false;
    final notes = _features.notes.where((note) {
      if (query.isEmpty) return true;
      return note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);
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
          'summary': summary.length > 120
              ? '${summary.substring(0, 120)}...'
              : summary,
          if (includeContent) 'content': note.content,
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _readNote(Map<String, dynamic> args) {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    final query = (args['query'] as String? ?? '').trim().toLowerCase();

    Note? note;
    if (id.isNotEmpty) {
      note = _features.getNote(id);
    }
    if (note == null && title.isNotEmpty) {
      note =
          _bestNoteMatch((n) => n.title.toLowerCase() == title) ??
          _bestNoteMatch((n) => n.title.toLowerCase().contains(title));
    }
    if (note == null && query.isNotEmpty) {
      note =
          _bestNoteMatch((n) => n.title.toLowerCase().contains(query)) ??
          _bestNoteMatch((n) => n.content.toLowerCase().contains(query));
    }
    if (note == null) {
      return _error('未找到匹配的笔记，请先调用 list_notes 查看可用笔记');
    }
    return {'ok': true, 'note': note.toJson()};
  }

  Note? _bestNoteMatch(bool Function(Note note) test) {
    for (final note in _features.notes) {
      if (test(note)) return note;
    }
    return null;
  }

  Future<Map<String, dynamic>> _saveNote(Map<String, dynamic> args) async {
    final title = (args['title'] as String? ?? '').trim();
    final content = args['content'] as String? ?? '';
    if (title.isEmpty) return _error('笔记标题不能为空');
    final id = (args['id'] as String? ?? '').trim();
    final append = args['append'] as bool? ?? false;
    Note? note = id.isEmpty ? null : _features.getNote(id);
    if (note == null) {
      final newId = await _features.addNote(title);
      note = _features.getNote(newId);
    }
    if (note == null) return _error('创建笔记失败');
    final nextContent = append && note.content.trim().isNotEmpty
        ? '${note.content}\n\n$content'
        : content;
    final updated = note.copyWith(title: title, content: nextContent);
    await _features.updateNote(updated);
    return {'ok': true, 'note': updated.toJson()};
  }

  static DateTime? _dateArg(Map<String, dynamic> args, String key) {
    final raw = args[key] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toLocal();
  }

  static Map<String, dynamic> _scheduleJson(ScheduleItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'start': item.start.toLocal().toIso8601String(),
      'end': item.end.toLocal().toIso8601String(),
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
}
