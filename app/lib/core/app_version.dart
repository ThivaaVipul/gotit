import 'package:package_info_plus/package_info_plus.dart';

/// The running app's version, as set by the build (0.0.0 for local builds).
Future<String> currentAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
}
