/// 新手向导的用户输入快照。
///
/// 只保存用户主动选择/填写的结构化内容，用于下次重新进入向导时预填。
/// 该模型不读写文件或网络。
class OnboardingInput {
  static const currentVersion = 1;

  final int version;
  final List<String> purposes;
  final String occupation;
  final String occupationCustom;
  final String freeText;
  final DateTime updatedAt;

  const OnboardingInput({
    this.version = currentVersion,
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
    'purposes': purposes,
    'occupation': occupation,
    if (occupationCustom.isNotEmpty) 'occupationCustom': occupationCustom,
    if (freeText.isNotEmpty) 'freeText': freeText,
    'updatedAt': updatedAt.toIso8601String(),
  };

  OnboardingInput copyWith({
    int? version,
    List<String>? purposes,
    String? occupation,
    String? occupationCustom,
    String? freeText,
    DateTime? updatedAt,
  }) {
    return OnboardingInput(
      version: version ?? this.version,
      purposes: purposes ?? this.purposes,
      occupation: occupation ?? this.occupation,
      occupationCustom: occupationCustom ?? this.occupationCustom,
      freeText: freeText ?? this.freeText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
