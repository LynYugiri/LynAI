import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../models/changelog_entry.dart';

class ChangelogParser {
  Future<List<ChangelogEntry>> loadAll() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final changelogFiles = manifest
        .listAssets()
        .where(
          (path) => path.startsWith('changelogs/') && path.endsWith('.md'),
        )
        .toList();

    final entries = <ChangelogEntry>[];
    for (final filePath in changelogFiles) {
      final content = await rootBundle.loadString(filePath);
      final entry = _parseFile(content, filePath);
      if (entry != null) entries.add(entry);
    }

    entries.sort((a, b) => _compareVersionsDesc(a.version, b.version));
    return entries;
  }

  Future<ChangelogEntry?> loadVersion(String version) async {
    final filename = 'changelogs/v$version.md';
    try {
      final content = await rootBundle.loadString(filename);
      return _parseFile(content, filename);
    } catch (_) {
      return null;
    }
  }

  ChangelogEntry? _parseFile(String content, String filePath) {
    final fileName = filePath.split('/').last;
    final version = fileName
        .replaceFirst(RegExp(r'^v'), '')
        .replaceFirst(RegExp(r'\.md$'), '');
    if (version.isEmpty) return null;

    final lines = content.split('\n');
    String date = '';
    final sections = <ChangelogSection>[];
    ChangelogSection? currentSection;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('## ')) {
        final heading = trimmed.substring(3).trim();
        final dateMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(heading);
        if (dateMatch != null) {
          date = dateMatch.group(0)!;
        }
        continue;
      }

      if (trimmed.startsWith('### ')) {
        if (currentSection != null && currentSection.items.isNotEmpty) {
          sections.add(currentSection);
        }
        currentSection = ChangelogSection(
          title: trimmed.substring(4).trim(),
          items: [],
        );
        continue;
      }

      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final item = trimmed.substring(2).trim();
        if (item.isNotEmpty) {
          currentSection ??= ChangelogSection(title: '', items: []);
          currentSection.items.add(item);
        }
      }
    }

    if (currentSection != null && currentSection.items.isNotEmpty) {
      sections.add(currentSection);
    }

    if (sections.isEmpty) return null;

    return ChangelogEntry(version: version, date: date, sections: sections);
  }

  int _compareVersionsDesc(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final length =
        aParts.length > bParts.length ? aParts.length : bParts.length;
    while (aParts.length < length) {
      aParts.add(0);
    }
    while (bParts.length < length) {
      bParts.add(0);
    }
    for (int i = 0; i < length; i++) {
      final cmp = bParts[i].compareTo(aParts[i]);
      if (cmp != 0) return cmp;
    }
    return 0;
  }
}
