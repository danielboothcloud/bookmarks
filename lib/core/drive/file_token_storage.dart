import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// File-backed implementation of [FlutterSecureStorage] used on macOS
/// when the app is built without an Apple development certificate.
///
/// **Why this exists.** macOS 26 (Tahoe) hardened Keychain Services to
/// require an `application-identifier` entitlement on the running
/// binary, even for un-sandboxed apps. That entitlement only lands in
/// the bundle when the binary is signed with a real Apple Team
/// (Personal Team via Xcode is fine; ad-hoc `flutter run` signing is
/// not). Without Xcode, no signing → no Keychain.
///
/// This class stores the same five tokens as plain JSON at
/// `~/Library/Application Support/dev.bookmarks.bookmarks/secrets.json`
/// with file permissions clamped to `0600` (user-only readable). For a
/// personal single-user utility on a FileVault-encrypted Mac, that
/// matches the on-disk security of `~/.aws/credentials`,
/// `~/.kube/config`, `~/.npmrc`, and similar tool-config files.
///
/// **Trade-off vs. Keychain.** A non-root process running as the same
/// user can read these tokens. With Keychain the OS additionally
/// gates each access via codesigning identity. For this app's threat
/// model (single-user personal utility; revocable tokens at
/// myaccount.google.com), the file-based fallback is an acceptable
/// dev/personal-use compromise.
///
/// `iOSOptions`, `MacOsOptions`, etc. parameters from the
/// [FlutterSecureStorage] interface are accepted for signature
/// compatibility and ignored — they only matter for the Keychain
/// implementation.
class FileTokenStorage implements FlutterSecureStorage {
  FileTokenStorage({required Directory directory})
      : _file = File(p.join(directory.path, _fileName)),
        _directory = directory;

  /// Default location: `~/Library/Application Support/<bundle-id>/`.
  /// Synchronous — relies on `$HOME` being set, which it always is in
  /// a user-launched macOS process.
  factory FileTokenStorage.macOSDefault() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError(
        'FileTokenStorage requires \$HOME to be set on macOS',
      );
    }
    return FileTokenStorage(
      directory: Directory(
        p.join(home, 'Library', 'Application Support', _bundleId),
      ),
    );
  }

  static const _bundleId = 'dev.bookmarks.bookmarks';
  static const _fileName = 'secrets.json';

  final File _file;
  final Directory _directory;

  /// Serialise concurrent reads/writes — every public method funnels
  /// through `_readMap` / `_writeMap`, both of which take this lock.
  final _lock = _Lock();

  Future<Map<String, String>> _readMap() async {
    if (!await _file.exists()) return <String, String>{};
    final raw = await _file.readAsString();
    if (raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (error) {
      // Corrupt or hand-edited secrets file. Quarantine and degrade to
      // empty so the user is treated as disconnected and re-auths,
      // rather than crashing the boot. The .corrupt sibling lets the
      // user (or a future diagnostics view) inspect what went wrong.
      try {
        final corrupt = File('${_file.path}.corrupt');
        if (await corrupt.exists()) await corrupt.delete();
        await _file.rename(corrupt.path);
      } catch (_) {
        // best-effort
      }
      // ignore: avoid_print
      print('FileTokenStorage: corrupt secrets.json quarantined ($error)');
      return <String, String>{};
    }
  }

  Future<void> _writeMap(Map<String, String> data) async {
    if (!await _directory.exists()) {
      await _directory.create(recursive: true);
    }
    final tmp = File('${_file.path}.tmp');
    var renamed = false;
    try {
      await tmp.writeAsString(jsonEncode(data), flush: true);
      // Restrict to user-only before the rename so the file is never
      // world-readable on disk, even briefly. `chmod` is in /bin and
      // always available on macOS.
      final chmod = await Process.run('chmod', ['600', tmp.path]);
      if (chmod.exitCode != 0) {
        // Non-fatal — log and continue. Failing here would leave the
        // user unable to persist tokens, which is worse than a slightly
        // more-readable file on a single-user box.
        // ignore: avoid_print
        print('FileTokenStorage: chmod 600 returned ${chmod.exitCode}: '
            '${chmod.stderr}');
      }
      await tmp.rename(_file.path);
      renamed = true;
    } finally {
      if (!renamed) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {
          // best-effort cleanup
        }
      }
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return _lock.run(() async {
      final map = await _readMap();
      return map[key];
    });
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return _lock.run(() async {
      final map = await _readMap();
      if (value == null) {
        map.remove(key);
      } else {
        map[key] = value;
      }
      await _writeMap(map);
    });
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return _lock.run(() async {
      final map = await _readMap();
      if (map.remove(key) != null) {
        await _writeMap(map);
      }
    });
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return _lock.run(_readMap);
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return _lock.run(() async {
      final map = await _readMap();
      return map.containsKey(key);
    });
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return _lock.run(() async {
      if (await _file.exists()) await _file.delete();
    });
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal async mutex — serialises read-modify-write sequences so a
/// concurrent `write` can't interleave with another `read`'s decoded
/// snapshot.
class _Lock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() body) {
    final completer = Completer<T>();
    final prev = _tail;
    _tail = prev.then((_) async {
      try {
        completer.complete(await body());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
