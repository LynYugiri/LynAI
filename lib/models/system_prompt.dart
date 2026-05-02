class SystemPrompt {
  final String id;
  final String title;
  final String content;

  SystemPrompt({required this.id, required this.title, required this.content});

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    return SystemPrompt(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'title': title, 'content': content};
  }

  SystemPrompt copyWith({String? title, String? content}) {
    return SystemPrompt(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
    );
  }
}
