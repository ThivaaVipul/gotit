import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/update/release_info.dart';

void main() {
  group('versions', () {
    test('parses X.Y.Z with or without a v', () {
      expect(parseVersion('v1.2.3'), [1, 2, 3]);
      expect(parseVersion('0.10.0'), [0, 10, 0]);
      expect(parseVersion('1.2'), isNull);
      expect(parseVersion('data'), isNull);
    });

    test('compares part by part, not as text', () {
      expect(isNewer('0.2.0', '0.1.9'), isTrue);
      expect(isNewer('0.10.0', '0.9.0'), isTrue);
      expect(isNewer('0.1.0', '0.1.0'), isFalse);
      expect(isNewer('0.1.0', '0.2.0'), isFalse);
      expect(isNewer('junk', '0.1.0'), isFalse);
    });

    test('0.0.0 is a local build', () {
      expect(isLocalBuild('0.0.0'), isTrue);
      expect(isLocalBuild('0.1.0'), isFalse);
    });
  });

  group('GitHub release', () {
    Map<String, Object?> asset(String name, {String scheme = 'https'}) => {
      'name': name,
      'browser_download_url': '$scheme://example.com/$name',
      'size': 10,
    };

    test('picks the APK, the setup and the checksums by name', () {
      final release = ReleaseInfo.fromGitHub({
        'tag_name': 'v0.2.0',
        'assets': [
          asset('gotit-0.2.0.apk'),
          asset('gotit-0.2.0-setup.exe'),
          asset('SHA256SUMS.txt'),
          asset('notes.txt'),
        ],
      })!;
      expect(release.version, '0.2.0');
      expect(
        release.apk!.url.toString(),
        'https://example.com/gotit-0.2.0.apk',
      );
      expect(release.setup!.name, 'gotit-0.2.0-setup.exe');
      expect(release.checksums!.name, 'SHA256SUMS.txt');
    });

    test('ignores files that are not served over HTTPS', () {
      final release = ReleaseInfo.fromGitHub({
        'tag_name': 'v0.2.0',
        'assets': [asset('gotit-0.2.0.apk', scheme: 'http')],
      })!;
      expect(release.apk, isNull);
    });

    test('is null for anything but a version tag', () {
      expect(ReleaseInfo.fromGitHub({'tag_name': 'data'}), isNull);
      expect(ReleaseInfo.fromGitHub('nope'), isNull);
    });
  });

  test('finds a checksum in a sha256sum listing', () {
    final hash = 'A' * 64;
    final listing =
        '$hash  gotit-0.2.0.apk\n'
        '${'b' * 64} *gotit-0.2.0-setup.exe\n';
    expect(checksumFor(listing, 'gotit-0.2.0.apk'), 'a' * 64);
    expect(checksumFor(listing, 'gotit-0.2.0-setup.exe'), 'b' * 64);
    expect(checksumFor(listing, 'other.apk'), isNull);
    expect(checksumFor('short  gotit-0.2.0.apk', 'gotit-0.2.0.apk'), isNull);
  });
}
