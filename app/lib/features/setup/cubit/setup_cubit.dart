import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/core/platform/phone_setup.dart';

/// The phone's setup checklist: what is done, read again whenever the app
/// comes back from a settings page. Null until first read.
class SetupCubit extends Cubit<SetupStatus?> {
  SetupCubit(
    this._setup, {
    this.recheckAfter = const [Duration(seconds: 1), Duration(seconds: 3)],
  }) : super(null) {
    _watcher = _setup.watcherChanges.listen((_) => unawaited(refresh()));
    unawaited(refresh());
  }

  final PhoneSetup _setup;
  late final StreamSubscription<WatcherState> _watcher;

  /// Some makers' pages save a moment after they close (MIUI's battery
  /// saver does), so a step still open on return is read again after these.
  final List<Duration> recheckAfter;

  final _rechecks = <Timer>[];

  Future<void> refresh() async {
    try {
      final status = await _setup.status();
      if (isClosed) return;
      emit(status);
      if (status.done) _cancelRechecks();
    } on Object {
      // Leave the last known state.
    }
  }

  /// Back from a settings page: read now, and again shortly while a step
  /// is still open.
  void recheck() {
    _cancelRechecks();
    unawaited(refresh());
    for (final wait in recheckAfter) {
      _rechecks.add(
        Timer(wait, () {
          if (!(state?.done ?? false)) unawaited(refresh());
        }),
      );
    }
  }

  Future<void> askNotifications() => _setup.askNotifications();

  Future<void> askBattery() => _setup.askBattery();

  Future<void> openWatcher() => _setup.openWatcher();

  Future<void> openAppInfo() => _setup.openAppInfo();

  Future<void> openAutostart() async {
    await _setup.openAutostart();
    await refresh();
  }

  Future<void> askPhotos() => _setup.askPhotos();

  Future<void> addTile() async {
    await _setup.addTile();
    await refresh();
  }

  /// A step only you can tell is done.
  Future<void> mark(String step) async {
    await _setup.mark(step);
    await refresh();
  }

  void _cancelRechecks() {
    for (final timer in _rechecks) {
      timer.cancel();
    }
    _rechecks.clear();
  }

  @override
  Future<void> close() async {
    _cancelRechecks();
    await _watcher.cancel();
    return super.close();
  }
}
