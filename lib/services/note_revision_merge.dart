class NoteMergeResult {
  final String? content;
  final bool conflicted;

  const NoteMergeResult._(this.content, this.conflicted);

  const NoteMergeResult.merged(String content) : this._(content, false);
  const NoteMergeResult.conflict() : this._(null, true);
}

/// Performs a conservative line-based three-way merge.
///
/// Independent changed ranges are combined. Overlapping ranges only merge when
/// both sides produced identical replacement text; otherwise a durable conflict
/// must be presented to the caller.
NoteMergeResult mergeNoteMarkdown(String base, String ours, String theirs) {
  if (ours == theirs) return NoteMergeResult.merged(ours);
  if (ours == base) return NoteMergeResult.merged(theirs);
  if (theirs == base) return NoteMergeResult.merged(ours);

  final baseLines = _lines(base);
  final oursChange = _singleChange(baseLines, _lines(ours));
  final theirsChange = _singleChange(baseLines, _lines(theirs));
  if (oursChange == null || theirsChange == null) {
    return const NoteMergeResult.conflict();
  }
  if (oursChange.sameAs(theirsChange)) return NoteMergeResult.merged(ours);
  if (oursChange.overlaps(theirsChange)) {
    return const NoteMergeResult.conflict();
  }

  final changes = [oursChange, theirsChange]
    ..sort((a, b) => b.start.compareTo(a.start));
  final merged = List<String>.from(baseLines);
  for (final change in changes) {
    merged.replaceRange(change.start, change.end, change.replacement);
  }
  return NoteMergeResult.merged(merged.join('\n'));
}

List<String> _lines(String value) => value.split('\n');

_LineChange? _singleChange(List<String> before, List<String> after) {
  var start = 0;
  while (start < before.length &&
      start < after.length &&
      before[start] == after[start]) {
    start++;
  }
  var beforeEnd = before.length;
  var afterEnd = after.length;
  while (beforeEnd > start &&
      afterEnd > start &&
      before[beforeEnd - 1] == after[afterEnd - 1]) {
    beforeEnd--;
    afterEnd--;
  }
  return _LineChange(start, beforeEnd, after.sublist(start, afterEnd));
}

class _LineChange {
  final int start;
  final int end;
  final List<String> replacement;

  const _LineChange(this.start, this.end, this.replacement);

  bool overlaps(_LineChange other) {
    if (start == end && other.start == other.end) return start == other.start;
    if (start == end) return start >= other.start && start <= other.end;
    if (other.start == other.end) {
      return other.start >= start && other.start <= end;
    }
    return start < other.end && other.start < end;
  }

  bool sameAs(_LineChange other) =>
      start == other.start &&
      end == other.end &&
      _listEquals(replacement, other.replacement);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
