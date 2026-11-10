import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/core/link/discovery.dart';
import 'package:gotit/core/link/phone_link.dart';

/// The PCs on the network, for the pairing list.
class NearbyCubit extends Cubit<List<FoundPc>> {
  NearbyCubit(PcFinder finder) : super(finder.current) {
    _changes = finder.changes.listen(emit);
  }

  late final StreamSubscription<List<FoundPc>> _changes;

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}

/// One pairing attempt as the code screen shows it.
class PairingState {
  const PairingState(this.step, {this.code});

  final PairProgress step;

  /// The code once both screens show it, kept for the "paired" moment.
  final String? code;
}

class PairingCubit extends Cubit<PairingState> {
  PairingCubit(this._attempt) : super(const PairingState(PairConnecting())) {
    _steps = _attempt.progress.listen((step) {
      emit(
        PairingState(step, code: step is PairShowCode ? step.code : state.code),
      );
    });
  }

  final PairAttempt _attempt;
  late final StreamSubscription<PairProgress> _steps;

  bool get finished =>
      state.step is PairDone ||
      state.step is PairRefused ||
      state.step is PairFailed;

  @override
  Future<void> close() async {
    // Leaving the screen before the end cancels the attempt.
    if (!finished) await _attempt.cancel();
    await _steps.cancel();
    return super.close();
  }
}
