import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

class BookmarkListScreen extends StatelessWidget {
  const BookmarkListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState.noBookmarks(
      onAddBookmark: () {
        // TODO(story-1.2): trigger inline add form via Cmd+N intent.
      },
    );
  }
}
