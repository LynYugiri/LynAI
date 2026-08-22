/// 新手向导的用户输入快照。
///
/// 只保存用户主动选择/填写的结构化内容，用于下次重新进入向导时预填。
/// 该模型不读写文件或网络。
class OnboardingInput {
  static const currentVersion = 1;

  /// 用途 key 到展示文案的映射，向导页与生成服务共用，保证同一用途在
  /// 界面、本地模板和 AI 提示词里表述一致。
  static const purposeLabels = <String, String>{
    'chat': '聊天与问答',
    'writing': '写作与润色',
    'coding': '编程与调试',
    'research': '学习与研究',
    'knowledge': '建立个人知识库',
    'todos': '管理日程与待办',
    'schedule': '安排日程',
    'cards': '用记忆卡复习',
    'roleplay': '沉浸式角色对话',
    'automation': '自动化工作流',
    'notes': '记录与整理笔记',
    'privacy': '把数据留在本地',
  };

  /// 职业 key 到展示文案的映射，供界面和生成服务共用。
  static const occupationLabels = <String, String>{
    'student': '学生',
    'developer': '开发者',
    'researcher': '研究人员',
    'creator': '内容创作者',
    'professional': '职场人士',
    'freelancer': '自由职业',
    'teacher': '教师',
    'other': '其他',
  };

  final int version;
  final String userName;
  final List<String> purposes;
  final String occupation;
  final String occupationCustom;
  final String freeText;
  final DateTime updatedAt;

  const OnboardingInput({
    this.version = currentVersion,
    this.userName = '',
    this.purposes = const [],
    this.occupation = 'other',
    this.occupationCustom = '',
    this.freeText = '',
    required this.updatedAt,
  });

  factory OnboardingInput.empty() {
    return OnboardingInput(updatedAt: DateTime.now());
  }

  bool get isEmpty =>
      userName.trim().isEmpty &&
      purposes.isEmpty &&
      occupation == 'other' &&
      occupationCustom.trim().isEmpty &&
      freeText.trim().isEmpty;

  factory OnboardingInput.fromJson(Map<String, dynamic> json) {
    final rawPurposes = json['purposes'];
    final purposes = <String>[];
    if (rawPurposes is List) {
      for (final item in rawPurposes) {
        final value = item.toString().trim();
        if (value.isNotEmpty) purposes.add(value);
      }
    }
    return OnboardingInput(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      userName: (json['userName'] as String?)?.trim() ?? '',
      purposes: purposes.toSet().toList(growable: false),
      occupation: (json['occupation'] as String?)?.trim().isNotEmpty == true
          ? (json['occupation'] as String).trim()
          : 'other',
      occupationCustom:
          (json['occupationCustom'] as String?)?.trim().isNotEmpty == true
          ? (json['occupationCustom'] as String).trim()
          : '',
      freeText: (json['freeText'] as String?)?.trim() ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    if (userName.isNotEmpty) 'userName': userName,
    'purposes': purposes,
    'occupation': occupation,
    if (occupationCustom.isNotEmpty) 'occupationCustom': occupationCustom,
    if (freeText.isNotEmpty) 'freeText': freeText,
    'updatedAt': updatedAt.toIso8601String(),
  };

  OnboardingInput copyWith({
    int? version,
    String? userName,
    List<String>? purposes,
    String? occupation,
    String? occupationCustom,
    String? freeText,
    DateTime? updatedAt,
  }) {
    return OnboardingInput(
      version: version ?? this.version,
      userName: userName ?? this.userName,
      purposes: purposes ?? this.purposes,
      occupation: occupation ?? this.occupation,
      occupationCustom: occupationCustom ?? this.occupationCustom,
      freeText: freeText ?? this.freeText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
