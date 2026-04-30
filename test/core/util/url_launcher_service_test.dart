import 'package:bookmarks/core/util/url_launcher_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _RecordingLauncher extends UrlLauncherPlatform {
  final List<LaunchOptions> launches = [];
  final List<String> launchedUrls = [];
  bool shouldThrow = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (shouldThrow) {
      throw PlatformException(code: 'no_handler', message: 'no handler');
    }
    launches.add(options);
    launchedUrls.add(url);
    return true;
  }
}

void main() {
  late _RecordingLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = original;
  });

  test('openExternal does nothing for unparsable input (no host)', () async {
    await openExternal('not a url');
    expect(launcher.launchedUrls, isEmpty);
  });

  test('openExternal does nothing for input lacking a host', () async {
    await openExternal('mailto:');
    expect(launcher.launchedUrls, isEmpty);
  });

  test(
      'openExternal forwards a valid URL to launchUrl with '
      'LaunchMode.externalApplication (AC4)', () async {
    await openExternal('https://example.com/path?q=1');
    expect(launcher.launchedUrls, ['https://example.com/path?q=1']);
    expect(launcher.launches.single.mode, PreferredLaunchMode.externalApplication);
  });

  test('openExternal swallows PlatformException and returns normally',
      () async {
    launcher.shouldThrow = true;
    await openExternal('https://example.com');
    // No exception escapes.
    expect(launcher.launchedUrls, isEmpty);
  });
}
