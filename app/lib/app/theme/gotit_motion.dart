import 'package:flutter/material.dart';

/// Shared timings and curves, so motion feels the same on every screen.
///
/// When the system asks for less motion, [of] hands out zero durations and
/// loops should stop: everything becomes an instant change.
@immutable
class GotitMotion extends ThemeExtension<GotitMotion> {
  const GotitMotion({
    this.tap = const Duration(milliseconds: 100),
    this.enter = const Duration(milliseconds: 280),
    this.exit = const Duration(milliseconds: 180),
    this.toggle = const Duration(milliseconds: 320),
    this.tick = const Duration(milliseconds: 300),
    this.cross = const Duration(milliseconds: 900),
    this.stagger = const Duration(milliseconds: 70),
    this.catchIn = const Duration(milliseconds: 1000),
    this.ring = const Duration(milliseconds: 2400),
    this.sweep = const Duration(seconds: 6),
  });

  /// Press feedback.
  final Duration tap;

  /// Something arriving: notes, list items, toasts.
  final Duration enter;

  /// Something leaving.
  final Duration exit;

  /// The sharing switch.
  final Duration toggle;

  /// A setup check drawing in, a progress bar growing.
  final Duration tick;

  /// A copy crossing the link between the two devices.
  final Duration cross;

  /// The gap between staggered items, such as pairing digits.
  final Duration stagger;

  /// The icon's ball flying into the catch.
  final Duration catchIn;

  /// One beat of the live ring around the other device.
  final Duration ring;

  /// One turn of the light around the connected card.
  final Duration sweep;

  /// Arriving: fast start, gentle stop.
  static const Curve arrive = Curves.easeOutCubic;

  /// Leaving: gentle start, fast finish.
  static const Curve leave = Curves.easeInCubic;

  /// Moving from place to place, such as a copy along the link.
  static const Curve move = Curves.easeInOutCubic;

  /// A small overshoot, for the switch and things that pop in.
  static const Curve spring = Curves.easeOutBack;

  static const standard = GotitMotion();

  /// No motion at all, for when the system asks for less.
  static const none = GotitMotion(
    tap: Duration.zero,
    enter: Duration.zero,
    exit: Duration.zero,
    toggle: Duration.zero,
    tick: Duration.zero,
    cross: Duration.zero,
    stagger: Duration.zero,
    catchIn: Duration.zero,
    ring: Duration.zero,
    sweep: Duration.zero,
  );

  /// Whether the system asks for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The timings to use in [context]: [none] when the system asks for less
  /// motion, otherwise the theme's.
  static GotitMotion of(BuildContext context) => reduced(context)
      ? none
      : Theme.of(context).extension<GotitMotion>() ?? standard;

  @override
  GotitMotion copyWith() => this;

  @override
  GotitMotion lerp(GotitMotion? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
