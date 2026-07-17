/// Source-independent actions produced by a merge planner.
enum MergeAction { unchanged, addIncoming, keepLocal, useIncoming, conflict }

/// A conflict description shared by backup import and durable sync UI.
class MergeConflictView {
  final String id;
  final String domain;
  final String title;
  final String localSummary;
  final String incomingSummary;

  const MergeConflictView({
    required this.id,
    required this.domain,
    required this.title,
    required this.localSummary,
    required this.incomingSummary,
  });
}

/// A stable three-way view of one unresolved note-page head pair.
class NotePageMergeSession {
  final String noteId;
  final String pageId;
  final Set<String> expectedHeadIds;
  final String localHeadId;
  final String incomingHeadId;
  final String? baseRevisionId;
  final String localContent;
  final String incomingContent;
  final String baseContent;
  final String initialResult;

  const NotePageMergeSession({
    required this.noteId,
    required this.pageId,
    required this.expectedHeadIds,
    required this.localHeadId,
    required this.incomingHeadId,
    required this.baseRevisionId,
    required this.localContent,
    required this.incomingContent,
    required this.baseContent,
    required this.initialResult,
  });
}

enum NotePageMergeCommitStatus { committed, staleHeads }

class NotePageMergeCommitResult {
  final NotePageMergeCommitStatus status;
  final String? revisionId;

  const NotePageMergeCommitResult.committed(String this.revisionId)
    : status = NotePageMergeCommitStatus.committed;

  const NotePageMergeCommitResult.staleHeads()
    : status = NotePageMergeCommitStatus.staleHeads,
      revisionId = null;
}

/// Pure merge classification reusable by import and synchronization.
class MergePlanner {
  const MergePlanner._();

  static MergeAction classify<T>({
    required T? local,
    required T incoming,
    required bool Function(T left, T right) equals,
  }) {
    if (local == null) return MergeAction.addIncoming;
    if (equals(local, incoming)) return MergeAction.unchanged;
    return MergeAction.conflict;
  }

  /// Resolves versioned records. Higher revisions win, then newer timestamps.
  static MergeAction latestWins({
    required Map<String, dynamic>? local,
    required Map<String, dynamic>? incoming,
    String revisionKey = 'revision',
    String updatedAtKey = 'updatedAt',
  }) {
    if (local == null) return MergeAction.addIncoming;
    if (incoming == null) return MergeAction.keepLocal;
    if (local.toString() == incoming.toString()) return MergeAction.unchanged;
    final localRevision = (local[revisionKey] as num?)?.toInt() ?? 0;
    final incomingRevision = (incoming[revisionKey] as num?)?.toInt() ?? 0;
    if (localRevision != incomingRevision) {
      return incomingRevision > localRevision
          ? MergeAction.useIncoming
          : MergeAction.keepLocal;
    }
    final localTime = DateTime.tryParse(local[updatedAtKey]?.toString() ?? '');
    final incomingTime = DateTime.tryParse(
      incoming[updatedAtKey]?.toString() ?? '',
    );
    if (localTime != null &&
        incomingTime != null &&
        localTime != incomingTime) {
      return incomingTime.isAfter(localTime)
          ? MergeAction.useIncoming
          : MergeAction.keepLocal;
    }
    return MergeAction.conflict;
  }
}
