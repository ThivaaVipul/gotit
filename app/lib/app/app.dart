import 'package:flutter/material.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/features/home/view/home_page.dart';

/// The app shell. The theme is a stand-in until the look pass before M2.
class GotitApp extends StatelessWidget {
  const GotitApp({required this.version, required this.updater, super.key});

  final String version;
  final Updater updater;

  static const _seed = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gotit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
      home: HomePage(version: version, updater: updater),
    );
  }
}
