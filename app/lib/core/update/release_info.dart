/// What the apps need to know about a GitHub release.
library;

final _version = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');

/// `[major, minor, patch]` for "1.2.3" or "v1.2.3", else null.
List<int>? parseVersion(String text) {
  final match = _version.firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

/// Whether [candidate] is a higher X.Y.Z version than [current].
bool isNewer(String candidate, String current) {
  final next = parseVersion(candidate);
  final now = parseVersion(current);
  if (next == null || now == null) return false;
  for (var i = 0; i < 3; i++) {
    if (next[i] != now[i]) return next[i] > now[i];
  }
  return false;
}

/// Builds made on a PC are 0.0.0 and never update themselves.
bool isLocalBuild(String version) => version == '0.0.0';

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);

  final String name;
  final Uri url;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    this.apk,
    this.setup,
    this.checksums,
  });

  /// X.Y.Z, without the "v".
  final String version;

  /// `gotit-<version>.apk`
  final ReleaseAsset? apk;

  /// `gotit-<version>-setup.exe`
  final ReleaseAsset? setup;

  /// `SHA256SUMS.txt`
  final ReleaseAsset? checksums;

  /// Reads GitHub's `releases/latest` JSON; null if it isn't a Gotit release.
  static ReleaseInfo? fromGitHub(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final tag = json['tag_name'];
    if (tag is! String || parseVersion(tag) == null) return null;
    final version = tag.trim().replaceFirst('v', '');
    final assets = <String, ReleaseAsset>{};
    final list = json['assets'];
    if (list is List<Object?>) {
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        final name = item['name'];
        final url = item['browser_download_url'];
        final size = item['size'];
        if (name is String && url is String) {
          final uri = Uri.tryParse(url);
          if (uri != null && uri.isScheme('https')) {
            assets[name] = ReleaseAsset(name, uri, size is int ? size : 0);
          }
        }
      }
    }
    return ReleaseInfo(
      version: version,
      apk: assets['gotit-$version.apk'],
      setup: assets['gotit-$version-setup.exe'],
      checksums: assets['SHA256SUMS.txt'],
    );
  }
}

/// The SHA-256 (lowercase hex) for [fileName] in a `sha256sum` listing.
String? checksumFor(String listing, String fileName) {
  for (final line in listing.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) continue;
    final name = parts[1].startsWith('*') ? parts[1].substring(1) : parts[1];
    if (name == fileName && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(parts[0])) {
      return parts[0].toLowerCase();
    }
  }
  return null;
}
