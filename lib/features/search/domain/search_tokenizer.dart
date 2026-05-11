/// Single source of truth for how a free-text query is decomposed into
/// FTS5-safe bareword tokens. Both [SearchRepository] (for MATCH-string
/// construction with prefix `*`) and [searchQueryTokensProvider] (for
/// inline highlighting) consume this so the visual highlights can never
/// drift from what BM25 actually matched.
///
/// Rules (must match SearchRepository's existing 3.1 contract):
/// - Whitelist `\p{L}\p{N}_\s`; replace everything else with a space.
/// - Split on whitespace, drop empty fragments.
/// - Return tokens as bare strings (NO trailing `*` — callers append it
///   if they need prefix-MATCH syntax).
/// - Empty / whitespace-only input → empty list.
library;

final RegExp _nonTokenChars = RegExp(r'[^\p{L}\p{N}_\s]', unicode: true);
final RegExp _whitespace = RegExp(r'\s+');

List<String> searchTokens(String userQuery) {
  final cleaned = userQuery.replaceAll(_nonTokenChars, ' ');
  return cleaned
      .split(_whitespace)
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
}
