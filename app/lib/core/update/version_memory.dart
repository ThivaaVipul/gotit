import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Remembers which version ran last, so a start right after an update can say so.
abstract final class VersionMemory {
  /// Stores [current] and returns the version stored before it, if any.
  static Future<String?> swap(String current) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/last_version.txt');
      final last = await file.exists()
          ? (await file.readAsString()).trim()
          : null;
      await file.writeAsString(current);
      return last;
    } on Object {
      return null;
    }
  }
}
