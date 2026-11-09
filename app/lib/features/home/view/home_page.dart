import 'package:flutter/material.dart';
import 'package:gotit/core/app_version.dart';

/// Stand-in home screen: the name and the version, until M2's real screens.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.loadVersion = currentAppVersion});

  final Future<String> Function() loadVersion;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<String> _version = widget.loadVersion();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Gotit', style: text.headlineLarge),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: _version,
              builder: (context, snapshot) => Text(
                snapshot.hasData ? 'Version ${snapshot.data}' : '',
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
