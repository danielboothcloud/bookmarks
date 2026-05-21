import 'local_snapshot.dart';
import 'merge_plan.dart';
import 'models/drive_bookmark.dart';
import 'models/drive_bookmarks_file.dart';
import 'models/drive_folder.dart';
import 'models/drive_tag.dart';

/// Pure per-record LWW merge engine. Story 4.3.
///
/// Inputs:
///  * [LocalSnapshot] — point-in-time read of the local Drift state.
///  * [DriveBookmarksFile] — v1 envelope freshly parsed from the
///    remote `bookmarks.json`.
///
/// Output:
///  * [MergePlan] — upsert / delete lists and a per-bookmark
///    junction-replacement map. No side effects; no Drift access; no
///    I/O. The applier is responsible for committing the plan inside
///    a single transaction.
///
/// Algorithm (per record id, per entity type):
///   in remote, not in local                  -> upsert (FR23, FR36)
///   in local, not in remote, lUpd >= rLast   -> keep local
///   in local, not in remote, lUpd <  rLast   -> delete local
///   in both, rUpd >  lUpd                    -> upsert remote (FR24)
///   in both, lUpd >  rUpd                    -> keep local
///   in both, rUpd == lUpd                    -> lexicographic id asc tiebreaker
///
/// Notes:
///  * `lLast` = `remote.lastModified` (the moment the remote envelope
///    was uploaded; treated as the upper bound on what the other
///    device knew when it pushed). Used ONLY in the "missing from
///    remote" branch — a local row whose updatedAt predates that
///    moment is interpreted as "the other device deleted it".
///  * `bookmark_tags` has no per-link `updatedAt`. The merge is
///    computed at the parent-bookmark granularity: the remote
///    bookmark's `tagIds` array replaces the local junction set IFF
///    the remote bookmark is the LWW winner (i.e. it was upserted).
///    Tag-only edits that don't bump the parent bookmark's
///    `updatedAt` will NOT propagate — acknowledged limitation
///    documented in `docs/sync-model.md`.
///  * The `updatedAt`-equal tiebreaker (lexicographic id asc) is
///    deterministic but vanishingly rare in single-user multi-device
///    use. It exists so two devices receiving the same remote at the
///    same time always converge to the same local state.
class MergeEngine {
  const MergeEngine._();

  /// Compute a [MergePlan] from a [LocalSnapshot] and a parsed
  /// [DriveBookmarksFile]. Pure: no I/O, no exceptions for non-fatal
  /// input states (an empty plan on empty inputs is the normal output).
  ///
  /// Callers are responsible for envelope-version validation BEFORE
  /// invoking this engine; the engine assumes a valid v1 envelope.
  ///
  /// [hasEverSynced] gates the "delete local because remote omits it"
  /// branch. On the very first merge of a fresh install — when the
  /// gate has never been opened — we have no way to distinguish "the
  /// other device deleted this record" from "the user added this
  /// record offline before ever connecting to Drive". When false, the
  /// engine refuses to delete by absence; the missing-from-remote
  /// records remain in the local DB and propagate up to Drive via the
  /// chained push.
  static MergePlan merge({
    required LocalSnapshot local,
    required DriveBookmarksFile remote,
    bool hasEverSynced = true,
  }) {
    final remoteLastModified =
        DateTime.parse(remote.lastModified).toUtc().millisecondsSinceEpoch;

    final localBookmarksById = <String, BookmarkRecord>{
      for (final r in local.bookmarks)
        r.id: BookmarkRecord(id: r.id, updatedAt: r.updatedAt),
    };
    final localFoldersById = <String, FolderRecord>{
      for (final r in local.folders)
        r.id: FolderRecord(id: r.id, updatedAt: r.updatedAt),
    };
    final localTagsById = <String, TagRecord>{
      for (final r in local.tags)
        r.id: TagRecord(id: r.id, updatedAt: r.updatedAt),
    };

    final remoteBookmarksById = <String, DriveBookmark>{
      for (final b in remote.bookmarks) b.id: b,
    };
    final remoteFoldersById = <String, DriveFolder>{
      for (final f in remote.folders) f.id: f,
    };
    final remoteTagsById = <String, DriveTag>{
      for (final t in remote.tags) t.id: t,
    };

    // --- Bookmarks ---
    final bookmarksToUpsert = <DriveBookmark>[];
    final bookmarksToDelete = <String>[];
    final bookmarkTagLinksToReplace = <String, List<String>>{};

    final bookmarkIds = <String>{
      ...localBookmarksById.keys,
      ...remoteBookmarksById.keys,
    };
    for (final id in bookmarkIds) {
      final localRec = localBookmarksById[id];
      final remoteRec = remoteBookmarksById[id];
      final decision = _decide(
        localUpdatedAt: localRec?.updatedAt,
        remoteUpdatedAt: remoteRec == null
            ? null
            : _parseIsoMs(remoteRec.updatedAt),
        remoteLastModified: remoteLastModified,
        id: id,
        hasEverSynced: hasEverSynced,
      );
      switch (decision) {
        case _Decision.upsertRemote:
          bookmarksToUpsert.add(remoteRec!);
          bookmarkTagLinksToReplace[id] =
              List<String>.unmodifiable(remoteRec.tagIds);
        case _Decision.deleteLocal:
          bookmarksToDelete.add(id);
        case _Decision.keepLocal:
          // No-op.
          break;
      }
    }

    // --- Folders ---
    final foldersToUpsertUnsorted = <DriveFolder>[];
    final foldersToDelete = <String>[];

    final folderIds = <String>{
      ...localFoldersById.keys,
      ...remoteFoldersById.keys,
    };
    for (final id in folderIds) {
      final localRec = localFoldersById[id];
      final remoteRec = remoteFoldersById[id];
      final decision = _decide(
        localUpdatedAt: localRec?.updatedAt,
        remoteUpdatedAt: remoteRec == null
            ? null
            : _parseIsoMs(remoteRec.updatedAt),
        remoteLastModified: remoteLastModified,
        id: id,
        hasEverSynced: hasEverSynced,
      );
      switch (decision) {
        case _Decision.upsertRemote:
          foldersToUpsertUnsorted.add(remoteRec!);
        case _Decision.deleteLocal:
          foldersToDelete.add(id);
        case _Decision.keepLocal:
          break;
      }
    }
    final foldersToUpsert = _topologicalSort(foldersToUpsertUnsorted);

    // --- Tags ---
    final tagsToUpsert = <DriveTag>[];
    final tagsToDelete = <String>[];

    final tagIds = <String>{
      ...localTagsById.keys,
      ...remoteTagsById.keys,
    };
    for (final id in tagIds) {
      final localRec = localTagsById[id];
      final remoteRec = remoteTagsById[id];
      final decision = _decide(
        localUpdatedAt: localRec?.updatedAt,
        remoteUpdatedAt: remoteRec == null
            ? null
            : _parseIsoMs(remoteRec.updatedAt),
        remoteLastModified: remoteLastModified,
        id: id,
        hasEverSynced: hasEverSynced,
      );
      switch (decision) {
        case _Decision.upsertRemote:
          tagsToUpsert.add(remoteRec!);
        case _Decision.deleteLocal:
          tagsToDelete.add(id);
        case _Decision.keepLocal:
          break;
      }
    }

    return MergePlan(
      bookmarksToUpsert: bookmarksToUpsert,
      bookmarksToDelete: bookmarksToDelete,
      foldersToUpsert: foldersToUpsert,
      foldersToDelete: foldersToDelete,
      tagsToUpsert: tagsToUpsert,
      tagsToDelete: tagsToDelete,
      bookmarkTagLinksToReplace: bookmarkTagLinksToReplace,
    );
  }

  /// LWW decision shared across all three entity types.
  static _Decision _decide({
    required int? localUpdatedAt,
    required int? remoteUpdatedAt,
    required int remoteLastModified,
    required String id,
    required bool hasEverSynced,
  }) {
    if (localUpdatedAt == null && remoteUpdatedAt != null) {
      return _Decision.upsertRemote;
    }
    if (localUpdatedAt == null && remoteUpdatedAt == null) {
      // Defensively unreachable — ids come from local ∪ remote, so at
      // least one side has the record. Keep local as the safe default.
      return _Decision.keepLocal;
    }
    if (remoteUpdatedAt == null && localUpdatedAt != null) {
      // Missing-from-remote branch. The "other device deleted it"
      // interpretation only holds when we've previously synced — only
      // then could the other device have seen our local write before
      // omitting it. On a never-yet-synced device the record may simply
      // be offline-created and never pushed; keep it.
      if (!hasEverSynced) return _Decision.keepLocal;
      if (localUpdatedAt < remoteLastModified) {
        return _Decision.deleteLocal;
      }
      return _Decision.keepLocal;
    }
    // Both present.
    if (remoteUpdatedAt! > localUpdatedAt!) return _Decision.upsertRemote;
    if (localUpdatedAt > remoteUpdatedAt) return _Decision.keepLocal;
    // Tie on updatedAt — same id on both sides, so lexicographic
    // tiebreak is a wash. Pick remote as the deterministic default.
    return _Decision.upsertRemote;
  }

  static int _parseIsoMs(String iso) {
    return DateTime.parse(iso).toUtc().millisecondsSinceEpoch;
  }

  /// Topologically sort folder upserts so a parent always appears
  /// before its child. Kahn's algorithm on the in-degree of each
  /// folder's `parentId` reference within the upsert set. Folders
  /// whose `parentId` is null OR references a folder not in the
  /// upsert set come first (their parent — if any — is already in
  /// the DB or is being created in the same set as a root).
  ///
  /// Tie ordering inside a level: by `id` ascending, for determinism.
  /// Cycles are tolerated by appending remaining nodes in id-asc
  /// order at the end (a cyclic remote would indicate corruption;
  /// the merge still proceeds, and the next merge will resolve).
  static List<DriveFolder> _topologicalSort(List<DriveFolder> folders) {
    if (folders.length <= 1) return List.unmodifiable(folders);
    final byId = <String, DriveFolder>{for (final f in folders) f.id: f};
    final ids = byId.keys.toSet();
    final children = <String, List<String>>{};
    final inDegree = <String, int>{for (final id in ids) id: 0};
    for (final f in folders) {
      final parentId = f.parentId;
      if (parentId != null && ids.contains(parentId)) {
        children.putIfAbsent(parentId, () => <String>[]).add(f.id);
        inDegree[f.id] = (inDegree[f.id] ?? 0) + 1;
      }
    }
    final ready = inDegree.entries
        .where((e) => e.value == 0)
        .map((e) => e.key)
        .toList()
      ..sort();
    final sorted = <DriveFolder>[];
    while (ready.isNotEmpty) {
      final next = ready.removeAt(0);
      sorted.add(byId[next]!);
      final kids = children[next] ?? const <String>[];
      final newly = <String>[];
      for (final c in kids) {
        final remaining = (inDegree[c] ?? 0) - 1;
        inDegree[c] = remaining;
        if (remaining == 0) newly.add(c);
      }
      newly.sort();
      // Insert in sorted order while preserving overall determinism.
      for (final n in newly) {
        ready.add(n);
      }
      ready.sort();
    }
    if (sorted.length != folders.length) {
      // Cycle — append remaining nodes deterministically.
      final missing = ids.difference(sorted.map((f) => f.id).toSet()).toList()
        ..sort();
      for (final id in missing) {
        sorted.add(byId[id]!);
      }
    }
    return List.unmodifiable(sorted);
  }
}

/// Local-side projection used internally by the engine.
class BookmarkRecord {
  const BookmarkRecord({required this.id, required this.updatedAt});
  final String id;
  final int updatedAt;
}

class FolderRecord {
  const FolderRecord({required this.id, required this.updatedAt});
  final String id;
  final int updatedAt;
}

class TagRecord {
  const TagRecord({required this.id, required this.updatedAt});
  final String id;
  final int updatedAt;
}

enum _Decision { upsertRemote, deleteLocal, keepLocal }
