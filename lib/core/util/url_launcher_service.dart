import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:url_launcher/url_launcher.dart';

/// Opens [rawUrl] in the user's default external browser. Uses
/// [LaunchMode.externalApplication] explicitly so platforms that would
/// otherwise prefer an in-app webview still hand off to the system
/// browser (AC4: "default system browser").
///
/// Silently no-ops on parse failure or launch failure: per the UX feedback
/// pattern (success silent, problems calm and inline), a missing browser
/// handler is a catastrophic edge case that does not warrant a toast,
/// dialog, or banner. `debugPrint` aids local debugging only.
Future<void> openExternal(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || uri.host.isEmpty) {
    if (kDebugMode) {
      debugPrint('openExternal: cannot parse "$rawUrl"');
    }
    return;
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('openExternal: launch failed for $uri: $e');
    }
  }
}
