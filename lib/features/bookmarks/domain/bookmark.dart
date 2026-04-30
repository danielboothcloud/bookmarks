// TODO(story-1.2): replace with Freezed entity once `freezed` codegen runs
// for this file. Holding a plain stub class for now so other features can
// import this path without rewiring imports later.

class Bookmark {
  const Bookmark({
    required this.id,
    required this.url,
    required this.title,
  });

  final String id;
  final String url;
  final String title;
}
