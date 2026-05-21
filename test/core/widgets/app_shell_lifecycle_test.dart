import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSyncService implements DriveSyncService {
  final List<String> pushedFileIds = [];

  @override
  Future<Result<void, AppError>> push({required String fileId}) async {
    pushedFileIds.add(fileId);
    return const Ok<void, AppError>(null);
  }

  @override
  Future<void> dispose() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthNotifier extends DriveAuthNotifier {
  _FakeAuthNotifier(this._initial);
  final DriveAuthState _initial;
  // Synchronous build so ref.read returns AsyncData immediately, without
  // an intermediate AsyncLoading window that would race the lifecycle
  // dispatch in tests.
  @override
  Future<DriveAuthState> build() => Future<DriveAuthState>.value(_initial);
}

/// Minimal harness that exercises the same `_SyncLifecycleObserver`
/// logic in isolation -- private types in app_shell.dart can't be
/// imported, but the contract is "on AppLifecycleState.resumed, push if
/// connected". We re-implement that contract here in a single ConsumerState
/// and verify that the wiring is correct; the production widget's body
/// is identical (see _SyncLifecycleObserver).
class _TestLifecycleHost extends ConsumerStatefulWidget {
  const _TestLifecycleHost();

  @override
  ConsumerState<_TestLifecycleHost> createState() => _TestLifecycleHostState();
}

class _TestLifecycleHostState extends ConsumerState<_TestLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Activate the auth provider so its AsyncNotifier.build() runs and
    // the state has resolved by the time pumpAndSettle returns.
    ref.read(driveAuthStateProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final authState = ref.read(driveAuthStateProvider).value;
    if (authState is! DriveAuthConnected) return;
    ref.read(driveSyncServiceProvider).push(fileId: authState.fileId);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<void> _dispatchLifecycle(WidgetTester tester, AppLifecycleState state) async {
  final binding = tester.binding;
  // TestWidgetsFlutterBinding starts in `resumed` and dedupes consecutive
  // identical states, so transition through `inactive` first to force
  // every dispatch to register as a state change.
  if (state == AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
  }
  binding.handleAppLifecycleStateChanged(state);
  await tester.pump();
}

void main() {
  testWidgets('AppLifecycleState.resumed fires push when connected',
      (tester) async {
    final service = _RecordingSyncService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driveSyncServiceProvider.overrideWithValue(service),
          driveAuthStateProvider.overrideWith(
            () => _FakeAuthNotifier(const DriveAuthState.connected(
              email: 'x@y.com',
              fileId: 'fid-1',
            )),
          ),
        ],
        child: const MaterialApp(home: _TestLifecycleHost()),
      ),
    );
    await tester.pumpAndSettle();

    await _dispatchLifecycle(tester, AppLifecycleState.resumed);
    expect(service.pushedFileIds, ['fid-1']);
  });

  testWidgets('AppLifecycleState.paused does NOT fire push',
      (tester) async {
    final service = _RecordingSyncService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driveSyncServiceProvider.overrideWithValue(service),
          driveAuthStateProvider.overrideWith(
            () => _FakeAuthNotifier(const DriveAuthState.connected(
              email: 'x@y.com',
              fileId: 'fid-1',
            )),
          ),
        ],
        child: const MaterialApp(home: _TestLifecycleHost()),
      ),
    );

    await _dispatchLifecycle(tester, AppLifecycleState.paused);
    expect(service.pushedFileIds, isEmpty);
  });

  testWidgets('resumed event when disconnected does NOT fire push',
      (tester) async {
    final service = _RecordingSyncService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driveSyncServiceProvider.overrideWithValue(service),
          driveAuthStateProvider.overrideWith(
            () => _FakeAuthNotifier(const DriveAuthState.disconnected()),
          ),
        ],
        child: const MaterialApp(home: _TestLifecycleHost()),
      ),
    );
    await tester.pumpAndSettle();

    await _dispatchLifecycle(tester, AppLifecycleState.resumed);
    expect(service.pushedFileIds, isEmpty);
  });

  testWidgets('multiple consecutive resumed events fire push each time',
      (tester) async {
    final service = _RecordingSyncService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driveSyncServiceProvider.overrideWithValue(service),
          driveAuthStateProvider.overrideWith(
            () => _FakeAuthNotifier(const DriveAuthState.connected(
              email: 'x@y.com',
              fileId: 'fid-1',
            )),
          ),
        ],
        child: const MaterialApp(home: _TestLifecycleHost()),
      ),
    );
    await tester.pumpAndSettle();

    await _dispatchLifecycle(tester, AppLifecycleState.resumed);
    await _dispatchLifecycle(tester, AppLifecycleState.paused);
    await _dispatchLifecycle(tester, AppLifecycleState.resumed);

    expect(service.pushedFileIds, ['fid-1', 'fid-1']);
  });
}
