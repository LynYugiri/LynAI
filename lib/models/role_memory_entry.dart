/// 一条按角色隔离的长期记忆。
///
/// 每个角色下分两个 target：
/// - [targetMemory]：角色自己的笔记（环境事实、约定、经验）
/// - [targetUser]：该角色视角下的用户画像（偏好、沟通风格）
class RoleMemoryEntry {
  static const targetMemory = 'memory';
  static const targetUser = 'user';

  final String id;
  final String roleId;
  final String target;
  final String entry;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleMemoryEntry({
    required this.id,
    required this.roleId,
    required this.target,
    required this.entry,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RoleMemoryEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final target = json['target'] as String? ?? targetMemory;
    return RoleMemoryEntry(
      id: json['id'] as String? ?? '',
      roleId: json['roleId'] as String? ?? '',
      target: target == targetMemory || target == targetUser
          ? target
          : targetMemory,
      entry: json['entry'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'roleId': roleId,
    'target': target,
    'entry': entry,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
