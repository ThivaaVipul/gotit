import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/features/home/view/home_page.dart';

/// The app shell: Slate, light or dark as the system says.
class GotitApp extends StatelessWidget {
  const GotitApp({required this.version, required this.updater, super.key});

  final String version;
  final Updater updater;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gotit',
      debugShowCheckedModeBanner: false,
      theme: gotitTheme(Brightness.light),
      darkTheme: gotitTheme(Brightness.dark),
      home: HomePage(version: version, updater: updater),
    );
  }
}
