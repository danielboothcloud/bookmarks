import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../folders/application/folder_providers.dart';
import '../../tags/application/tag_providers.dart';

/// The scoping rule applied to search results, derived from the current
/// sidebar selection. Three mutually-exclusive cases:
///
/// - [SearchScope.none]: no sidebar selection — search is unscoped (the
///   3.1 default).
/// - [SearchScope.folder]: a folder is selected — restrict results to
///   bookmarks whose `folder_id` is in [allowedIds] (the folder + its
///   recursive descendants, per FR12).
/// - [SearchScope.tag]: a tag is selected — restrict results to bookmarks
///   linked to [tagId] (FR15).
sealed class SearchScope {
  const SearchScope();
  const factory SearchScope.none() = _NoneScope;
  const factory SearchScope.folder(Set<String> allowedIds) = _FolderScope;
  const factory SearchScope.tag(String tagId) = _TagScope;
}

final class _NoneScope extends SearchScope {
  const _NoneScope();
}

final class _FolderScope extends SearchScope {
  const _FolderScope(this.allowedIds);
  final Set<String> allowedIds;
}

final class _TagScope extends SearchScope {
  const _TagScope(this.tagId);
  final String tagId;
}

/// Derives the current [SearchScope] from sidebar state. Folder + tag
/// selection are mutually exclusive in normal operation (the GoRouter
/// branches are siblings; branch-transition handlers clear the inactive
/// selection). If both happen to be set — defensive against an unusual
/// sync-merge race — folder wins because the folder branch sits left of
/// the tag branch in the sidebar (deterministic tiebreaker, document
/// and move on).
final searchScopeProvider = Provider<SearchScope>((ref) {
  final folderId = ref.watch(selectedFolderIdProvider);
  final tagId = ref.watch(selectedTagIdProvider);
  if (folderId != null) {
    final byParent = ref.watch(folderChildrenIndexProvider);
    final descendants = collectFolderDescendants(folderId, byParent);
    return SearchScope.folder(descendants);
  }
  if (tagId != null) {
    return SearchScope.tag(tagId);
  }
  return const SearchScope.none();
});

// Internal accessors so `searchResultsProvider` can pattern-match on the
// sealed class without exposing the private variants.
extension SearchScopeMatch on SearchScope {
  T match<T>({
    required T Function() none,
    required T Function(Set<String> allowedIds) folder,
    required T Function(String tagId) tag,
  }) {
    final scope = this;
    return switch (scope) {
      _NoneScope() => none(),
      _FolderScope(:final allowedIds) => folder(allowedIds),
      _TagScope(:final tagId) => tag(tagId),
    };
  }
}
