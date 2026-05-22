import 'dart:async';

import 'package:bookmarks/core/drive/connectivity_providers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Manual fake of [Connectivity]. We use `implements` + `noSuchMethod`
/// because `Connectivity` is a class (not an interface) and mocktail
/// isn't a project dep — same pattern as 4.2/4.3/4.4's `_FakeConnectivity`
/// style fakes (`_FakeDriveServer` etc).
class _FakeConnectivity implements Connectivity {
  _FakeConnectivity({
    List<ConnectivityResult> initial = const [ConnectivityResult.none],
  }) : _current = initial;

  List<ConnectivityResult> _current;
  final _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  void emit(List<ConnectivityResult> next) {
    _current = next;
    _controller.add(next);
  }

  Future<void> dispose() => _controller.close();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeConnectivity fake;

  setUp(() {
    fake = _FakeConnectivity();
  });

  tearDown(() async {
    await fake.dispose();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(overrides: [
      connectivityProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('initial state [wifi] yields true', () async {
    fake = _FakeConnectivity(initial: const [ConnectivityResult.wifi]);
    final container = buildContainer();
    final emitted = <bool>[];
    final sub = container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, next) {
        next.whenData(emitted.add);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(emitted, [true]);
  });

  test('initial state [none] yields false', () async {
    fake = _FakeConnectivity(initial: const [ConnectivityResult.none]);
    final container = buildContainer();
    final emitted = <bool>[];
    final sub = container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, next) {
        next.whenData(emitted.add);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(emitted, [false]);
  });

  test('stream [none] -> [wifi] yields false then true', () async {
    fake = _FakeConnectivity(initial: const [ConnectivityResult.none]);
    final container = buildContainer();
    final emitted = <bool>[];
    final sub = container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, next) {
        next.whenData(emitted.add);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(const [ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(emitted, [false, true]);
  });

  test(
      'stream [wifi] -> [wifi, ethernet] does not break the stream '
      '(same-state re-emit is filtered by Riverpod listener dedup; '
      'the orchestrator transition guard is the semantic enforcement '
      "— see drive_sync_providers_test 'connectivity online->online does "
      "NOT fire sync()')",
      () async {
    fake = _FakeConnectivity(initial: const [ConnectivityResult.wifi]);
    final container = buildContainer();
    final emitted = <bool>[];
    final sub = container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, next) {
        next.whenData(emitted.add);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(const [ConnectivityResult.wifi, ConnectivityResult.ethernet]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(emitted, [true, false],
        reason: 'after a same-state re-emit, the next real transition '
            'still flows through');
  });

  test('stream [wifi] -> [none] yields true then false', () async {
    fake = _FakeConnectivity(initial: const [ConnectivityResult.wifi]);
    final container = buildContainer();
    final emitted = <bool>[];
    final sub = container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, next) {
        next.whenData(emitted.add);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(emitted, [true, false]);
  });
}
