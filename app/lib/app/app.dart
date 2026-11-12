import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/link/pc_link.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/features/home/cubit/link_cubits.dart';
import 'package:gotit/features/home/view/home_page.dart';
import 'package:gotit/features/pairing/view/pair_page.dart';
import 'package:gotit/features/pairing/widgets/pair_request_sheet.dart';

/// The app shell: Slate, light or dark as the system says.
class GotitApp extends StatelessWidget {
  const GotitApp({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final pcLink = services.pcLink;
    final phoneLink = services.phoneLink;
    final app = MaterialApp(
      title: 'Gotit',
      navigatorKey: services.navigator,
      debugShowCheckedModeBanner: false,
      theme: gotitTheme(Brightness.light),
      darkTheme: gotitTheme(Brightness.dark),
      // A pairing request shows above every screen, Settings included.
      builder: pcLink == null
          ? null
          : (context, child) => _PairRequests(child: child!),
      home: phoneLink == null
          ? HomePage(services: services)
          : _PhoneHome(services: services, link: phoneLink),
    );
    // The link's state sits above the app, so every screen can read it.
    if (pcLink != null) {
      return BlocProvider(
        create: (_) => PcLinkCubit(pcLink.state, pcLink.states),
        child: app,
      );
    }
    if (phoneLink != null) {
      return BlocProvider(
        create: (_) => PhoneLinkCubit(phoneLink.state, phoneLink.states),
        child: app,
      );
    }
    return app;
  }
}

/// The phone: pairing until there is a PC, then home. Coming back to the
/// front tries the PC again at once.
class _PhoneHome extends StatefulWidget {
  const _PhoneHome({required this.services, required this.link});

  final AppServices services;
  final PhoneLink link;

  @override
  State<_PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<_PhoneHome> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        widget.link.retryNow();
        unawaited(widget.services.updater.checkIfStale());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PhoneLinkCubit, PhoneLinkState, bool>(
      selector: (state) => state.pc != null,
      builder: (context, paired) => AnimatedSwitcher(
        duration: GotitMotion.of(context).enter,
        switchInCurve: GotitMotion.arrive,
        switchOutCurve: GotitMotion.leave,
        child: paired
            ? HomePage(key: const ValueKey('home'), services: widget.services)
            : PairPage(key: const ValueKey('pair'), services: widget.services),
      ),
    );
  }
}

/// On the PC: a phone's pairing request covers whatever is on screen.
class _PairRequests extends StatelessWidget {
  const _PairRequests({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: BlocSelector<PcLinkCubit, PcLinkState, PairRequest?>(
            selector: (state) => state.request,
            builder: (context, request) => AnimatedSwitcher(
              duration: GotitMotion.of(context).enter,
              switchInCurve: GotitMotion.arrive,
              switchOutCurve: GotitMotion.leave,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: request == null
                  ? const SizedBox.shrink()
                  : Material(
                      key: ObjectKey(request),
                      type: MaterialType.transparency,
                      child: PairRequestSheet(request: request),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
