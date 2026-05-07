import 'tag.dart';

/// Sidebar-shaped projection: a tag plus its current linked-bookmark count.
/// The count is denormalised at query time -- not stored on the Tag row -- so
/// readers always see an atomically-consistent (tag, count) pair.
class TagWithCount {
  const TagWithCount({required this.tag, required this.count});
  final Tag tag;
  final int count;
}
