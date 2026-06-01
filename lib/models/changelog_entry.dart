class ChangelogSection {
  const ChangelogSection({required this.title, required this.items});

  final String title;
  final List<String> items;
}

class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.sections,
  });

  final String version;
  final String date;
  final List<ChangelogSection> sections;
}
