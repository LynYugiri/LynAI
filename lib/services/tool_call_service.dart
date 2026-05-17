import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
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

class _NoteLineEdit {
  final int startLine;
  final int deleteCount;
  final List<String> insertLines;

  const _NoteLineEdit({
    required this.startLine,
    required this.deleteCount,
    required this.insertLines,
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
    return _NoteLineEdit(
      startLine: startLine,
      deleteCount: deleteCount,
      insertLines: insertLines,
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
  static const _uuid = Uuid();

  final FeatureProvider _features;

  static const systemPrompt = '''
你可以使用本地工具帮助用户管理日程、笔记、待办清单、获取时间/位置、打开安卓应用和创建对话标题。
当需要调用工具且当前模型接口不支持原生 tool_calls 时，只返回一个 JSON 对象，不要包含 Markdown：
{"tool_calls":[{"name":"工具名","arguments":{...}}]}
收到工具结果后，再用自然语言给用户最终回复。
创建或修改数据前，应从用户输入中提取明确字段；缺少关键字段时先追问。
需要查看笔记内容时，先用 list_notes 查找笔记 id，再用 read_note 读取完整内容；如果用户给出明确标题，也可以直接用 read_note 按标题搜索。小范围修改笔记时，先 read_note，再用 propose_note_edit 按行提交 edits 让用户逐行确认；用户明确要求直接修改时才用 edit_note。创建、追加或整篇替换时用 save_note。笔记可通过 list_note_folders/save_note_folder 管理文件夹，save_note 可用 folderId 移动笔记。
需要查看待办清单内容时，先用 list_todo_lists 查找清单 id，再用 read_todo_list 读取完整内容；创建或修改待办项用 save_todo_item，完成/未完成待办项时设置 done。
日程时间使用带时区偏移的 ISO-8601 字符串；用户说“今天/明天”时必须先结合 get_current_time 的 iso 与 timezoneOffsetMinutes 换算成本地日期时间。
''';

  static const nativeSystemPrompt = '''
你可以使用本地工具帮助用户管理日程、笔记、待办清单、获取时间/位置、打开安卓应用和创建对话标题。
需要调用工具时使用接口提供的 tool_calls；不需要工具时直接正常回答，不要提及工具。
收到工具结果后，再用自然语言给用户最终回复。
创建或修改数据前，应从用户输入中提取明确字段；缺少关键字段时先追问。
需要查看笔记内容时，先用 list_notes 查找笔记 id，再用 read_note 读取完整内容；如果用户给出明确标题，也可以直接用 read_note 按标题搜索。小范围修改笔记时，先 read_note，再用 propose_note_edit 按行提交 edits 让用户逐行确认；用户明确要求直接修改时才用 edit_note。创建、追加或整篇替换时用 save_note。笔记可通过 list_note_folders/save_note_folder 管理文件夹，save_note 可用 folderId 移动笔记。
需要查看待办清单内容时，先用 list_todo_lists 查找清单 id，再用 read_todo_list 读取完整内容；创建或修改待办项用 save_todo_item，完成/未完成待办项时设置 done。
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
        'name': 'propose_note_edit',
        'description': '按行提交笔记修改建议，不直接保存；用户会在笔记页逐行接受或拒绝。调用前必须先 read_note。',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': '已有笔记 id'},
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
              'description': '逐行修改建议。行号从 1 开始；多个 edit 不可重叠。',
              'items': {
                'type': 'object',
                'properties': {
                  'startLine': {'type': 'integer'},
                  'deleteCount': {'type': 'integer'},
                  'insertLines': {
                    'type': 'array',
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
              'description': '逐行修改列表。行号从 1 开始；多个 edit 不可重叠。',
              'items': {
                'type': 'object',
                'properties': {
                  'startLine': {'type': 'integer'},
                  'deleteCount': {'type': 'integer'},
                  'insertLines': {
                    'type': 'array',
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
        'description': '创建或修改待办清单。传 id 时修改已有清单；不传 id 时创建新清单。items 会替换整份清单的待办项。',
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
        'description': '创建、修改、完成或未完成一个待办项。不传 itemId 时创建新待办项；传 delete=true 时删除。',
        'parameters': {
          'type': 'object',
          'properties': {
            'listId': {'type': 'string', 'description': '待办清单 id'},
            'itemId': {'type': 'string', 'description': '待办项 id；为空则创建'},
            'text': {'type': 'string', 'description': '待办内容'},
            'done': {'type': 'boolean', 'description': 'true 表示完成，false 表示未完成'},
            'delete': {'type': 'boolean', 'description': '是否删除该待办项'},
          },
          'required': ['listId'],
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
        case 'edit_note':
          return await _editNote(call.arguments);
        case 'propose_note_edit':
          return _proposeNoteEdit(call.arguments);
        case 'list_note_folders':
          return _listNoteFolders();
        case 'save_note_folder':
          return await _saveNoteFolder(call.arguments);
        case 'list_todo_lists':
          return _listTodoLists(call.arguments);
        case 'read_todo_list':
          return _readTodoList(call.arguments);
        case 'save_todo_list':
          return await _saveTodoList(call.arguments);
        case 'save_todo_item':
          return await _saveTodoItem(call.arguments);
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
    final folderId = (args['folderId'] as String? ?? '').trim();
    final includeContent = args['includeContent'] as bool? ?? false;
    final notes = _features.notes.where((note) {
      if (folderId.isNotEmpty && note.folderId != folderId) return false;
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
          if (note.folderId != null) 'folderId': note.folderId,
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
    return {
      'ok': true,
      'note': note.toJson(),
      'contentHash': _contentHash(note.content),
      'currentRevisionId': note.currentRevisionId,
      'lineCount': _splitNoteLines(note.content).length,
    };
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
    final note = _features.getNote(id);
    if (note == null) return _error('未找到笔记: $id');
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
    if (hasContent) revision = await _features.saveNoteContent(id, nextContent);
    final savedNote = _features.getNote(id) ?? updated;
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
    final parsed = _parseNoteEditArgs(args, emptyMessage: 'edit_note 需要 edits');
    if (parsed.error != null) return _error(parsed.error!);
    final note = parsed.note!;
    final edits = parsed.edits;
    final nextContent = _applyLineEdits(note.content, edits);
    if (nextContent == null) return _error('edits 行号越界或存在重叠');
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

  Map<String, dynamic> _proposeNoteEdit(Map<String, dynamic> args) {
    final parsed = _parseNoteEditArgs(
      args,
      emptyMessage: 'propose_note_edit 需要 edits',
    );
    if (parsed.error != null) return _error(parsed.error!);
    final note = parsed.note!;
    final nextContent = _applyLineEdits(note.content, parsed.edits);
    if (nextContent == null) return _error('edits 行号越界或存在重叠');
    if (nextContent == note.content) return _error('修改建议没有产生内容变化');
    final proposal = _proposalFromEdits(
      note: note,
      edits: parsed.edits,
      baseRevisionId: parsed.baseRevisionId,
    );
    _features.setNoteEditProposal(proposal);
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

  _ParsedNoteEdit _parseNoteEditArgs(
    Map<String, dynamic> args, {
    required String emptyMessage,
  }) {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return _ParsedNoteEdit.error('缺少笔记 id');
    final note = _features.getNote(id);
    if (note == null) return _ParsedNoteEdit.error('未找到笔记: $id');
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
    return {
      'ok': true,
      'folders': _features.noteFolders.map((folder) {
        final count = _features.notes
            .where((note) => note.folderId == folder.id)
            .length;
        return {
          'id': folder.id,
          'title': folder.title,
          'createdAt': folder.createdAt.toIso8601String(),
          'updatedAt': folder.updatedAt.toIso8601String(),
          'noteCount': count,
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
      final updated = list.copyWith(items: [...list.items, item]);
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

  static String _joinNoteLines(List<String> lines) {
    return lines.join('\n');
  }

  static String? _applyLineEdits(String content, List<_NoteLineEdit> edits) {
    final lines = _splitNoteLines(content);
    final sorted = [...edits]
      ..sort((a, b) => b.startLine.compareTo(a.startLine));
    var previousStart = lines.length + 1;
    for (final edit in sorted) {
      final startIndex = edit.startLine - 1;
      final endIndex = startIndex + edit.deleteCount;
      if (edit.startLine < 1 || startIndex > lines.length) return null;
      if (endIndex > lines.length) return null;
      if (endIndex > previousStart - 1) return null;
      lines.replaceRange(startIndex, endIndex, edit.insertLines);
      previousStart = edit.startLine;
    }
    return _joinNoteLines(lines);
  }

  static NoteEditProposal _proposalFromEdits({
    required Note note,
    required List<_NoteLineEdit> edits,
    required String? baseRevisionId,
  }) {
    final lines = _splitNoteLines(note.content);
    return NoteEditProposal(
      id: _uuid.v4(),
      noteId: note.id,
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
