import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/core/link/pc_link.dart';
import 'package:gotit/core/link/phone_link.dart';

/// The phone's link, for its screens.
class PhoneLinkCubit extends Cubit<PhoneLinkState> {
  PhoneLinkCubit(super.initial, Stream<PhoneLinkState> changes) {
    _changes = changes.listen(emit);
  }

  late final StreamSubscription<PhoneLinkState> _changes;

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}

/// The PC's link, for its screens.
class PcLinkCubit extends Cubit<PcLinkState> {
  PcLinkCubit(super.initial, Stream<PcLinkState> changes) {
    _changes = changes.listen(emit);
  }

  late final StreamSubscription<PcLinkState> _changes;

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
