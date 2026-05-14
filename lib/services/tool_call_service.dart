import 'dart:convert';

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
需要查看笔记内容时，先用 list_notes 查找笔记 id，再用 read_note 读取完整内容；如果用户给出明确标题，也可以直接用 read_note 按标题搜索。笔记可通过 list_note_folders/save_note_folder 管理文件夹，save_note 可用 folderId 移动笔记。
需要查看待办清单内容时，先用 list_todo_lists 查找清单 id，再用 read_todo_list 读取完整内容；创建或修改待办项用 save_todo_item，完成/未完成待办项时设置 done。
日程时间使用带时区偏移的 ISO-8601 字符串；用户说“今天/明天”时必须先结合 get_current_time 的 iso 与 timezoneOffsetMinutes 换算成本地日期时间。
''';

  static const nativeSystemPrompt = '''
你可以使用本地工具帮助用户管理日程、笔记、待办清单、获取时间/位置、打开安卓应用和创建对话标题。
需要调用工具时使用接口提供的 tool_calls；不需要工具时直接正常回答，不要提及工具。
收到工具结果后，再用自然语言给用户最终回复。
创建或修改数据前，应从用户输入中提取明确字段；缺少关键字段时先追问。
需要查看笔记内容时，先用 list_notes 查找笔记 id，再用 read_note 读取完整内容；如果用户给出明确标题，也可以直接用 read_note 按标题搜索。笔记可通过 list_note_folders/save_note_folder 管理文件夹，save_note 可用 folderId 移动笔记。
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
        'description': '创建或修改并保存笔记。传 id 时修改已有笔记；不传 id 时创建新笔记。',
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
      final newId = await _features.addNote(
        title,
        folderId: hasFolderId && folderId.isNotEmpty ? folderId : null,
      );
      final note = _features.getNote(newId);
      if (note == null) return _error('创建笔记失败');
      final updated = note.copyWith(content: content);
      await _features.updateNote(updated);
      return {'ok': true, 'note': updated.toJson()};
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
      content: nextContent,
      folderId: hasFolderId
          ? (folderId.isEmpty ? null : folderId)
          : note.folderId,
    );
    await _features.updateNote(updated);
    return {'ok': true, 'note': updated.toJson()};
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
