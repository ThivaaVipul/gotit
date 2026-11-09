import 'dart:convert';
import 'dart:io';

import 'package:gotit/core/update/release_info.dart';

/// Where releases come from. An interface so tests can fake it.
abstract interface class UpdateSource {
  /// The latest published release, or null if there is none yet.
  Future<ReleaseInfo?> latest();

  Future<String> fetchText(Uri url);

  /// Downloads [url] into [to], reporting the share done (0 to 1) when the size is known.
  Future<void> download(Uri url, File to, {void Function(double)? onProgress});
}

/// GitHub Releases of the public repo, over plain HTTPS. No account, no token.
class GitHubReleases implements UpdateSource {
  GitHubReleases({HttpClient? client})
    : _client =
          client ??
          (HttpClient()
            ..userAgent = 'Gotit-updater'
            ..connectionTimeout = const Duration(seconds: 15));

  static final _latest = Uri.parse(
    'https://api.github.com/repos/ThivaaVipul/gotit/releases/latest',
  );

  final HttpClient _client;

  @override
  Future<ReleaseInfo?> latest() async {
    final request = await _client.getUrl(_latest);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GitHub answered ${response.statusCode}');
    }
    return ReleaseInfo.fromGitHub(jsonDecode(body));
  }

  @override
  Future<String> fetchText(Uri url) async {
    final response = await (await _client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Download answered ${response.statusCode}');
    }
    return response.transform(utf8.decoder).join();
  }

  @override
  Future<void> download(
    Uri url,
    File to, {
    void Function(double)? onProgress,
  }) async {
    final response = await (await _client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Download answered ${response.statusCode}');
    }
    final total = response.contentLength;
    var received = 0;
    final sink = to.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
  }
}
