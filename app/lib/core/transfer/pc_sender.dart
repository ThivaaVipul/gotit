import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gotit/core/transfer/folder_store.dart';
import 'package:gotit/core/transfer/transfers.dart';
import 'package:gotit/core/transfer/zipped_folder.dart';

/// What became of a request to send files from the PC.
enum SendAnswer {
  /// On their way.
  sending,

  /// None of the paths was a file or a folder.
  nothing,

  /// No phone is paired.
  unpaired,

  /// Sharing is off; ask, then send again with turnOn.
  off,

  /// The phone isn't connected.
  away,
}

/// Sends files and folders from the PC to the phone, however they came:
/// dropped on the window, Send to, or Ctrl+F2. Folders are zipped first.
/// Nothing waits for a phone that is away, apart from a few seconds just
/// after Gotit started (Send to may have started it).
class PcSender {
  PcSender({
    required this.link,
    required this.transfers,
    required this.phoneName,
    required this.sharingOn,
    required this.turnSharingOn,
    required this.temp,
    this.linkWait = const Duration(seconds: 6),
    this.startWindow = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _startedAt = _now();
  }

  final FileLink link;
  final Transfers transfers;

  /// The paired phone's name; null while unpaired.
  final String? Function() phoneName;
  final bool Function() sharingOn;
  final void Function() turnSharingOn;

  /// Where folders are zipped.
  final Future<Directory> Function() temp;

  /// How long a send waits for the link, just after a start.
  final Duration linkWait;

  /// How long after the start a send still waits for the link.
  final Duration startWindow;
  final DateTime Function() _now;
  late final DateTime _startedAt;

  /// Sends what is at [paths]; [turnOn] turns sharing on first ("Turn on and
  /// send"). [onDone] hears how a send that got under way ended.
  Future<SendAnswer> send(
    List<String> paths, {
    bool turnOn = false,
    void Function(SendResult result)? onDone,
  }) async {
    final files = filesAt(paths);
    if (files.isEmpty) return SendAnswer.nothing;
    if (phoneName() == null) return SendAnswer.unpaired;
    if (!sharingOn()) {
      if (!turnOn) return SendAnswer.off;
      turnSharingOn();
    }
    if (!link.linked) {
      final left = _startedAt.add(startWindow).difference(_now());
      if (left <= Duration.zero) return SendAnswer.away;
      try {
        await link.linkedChanges
            .firstWhere((up) => up)
            .timeout(left < linkWait ? left : linkWait);
      } on Object {
        return SendAnswer.away;
      }
    }
    unawaited(transfers.send(files).then((result) => onDone?.call(result)));
    return SendAnswer.sending;
  }

  /// The files at [paths], and the folders as zips; anything else is left
  /// out.
  List<OutgoingFile> filesAt(List<String> paths) => [
    for (final path in paths)
      switch (FileSystemEntity.typeSync(path)) {
        FileSystemEntityType.file => PathFile(path),
        FileSystemEntityType.directory => ZippedFolder(path, temp: temp),
        _ => null,
      },
  ].nonNulls.toList();
}

/// The paths Gotit was started with to send (`--send` and the files, as the
/// Send to shortcut passes them), or null for a normal start. A long list a
/// second launch handed over comes as `--send-list` and a file holding it,
/// which is read and deleted.
Future<List<String>?> sendRequest(List<String> args) async {
  final at = args.indexOf('--send-list');
  if (at >= 0 && at + 1 < args.length) {
    final list = File(args[at + 1]);
    try {
      final paths = (jsonDecode(await list.readAsString()) as List<Object?>)
          .whereType<String>()
          .toList();
      return paths;
    } on Object {
      return const [];
    } finally {
      try {
        await list.delete();
      } on FileSystemException {
        // Gone already.
      }
    }
  }
  final send = args.indexOf('--send');
  if (send < 0) return null;
  return args.sublist(send + 1).where((arg) => arg.isNotEmpty).toList();
}

/// The arguments a second launch hands to the running Gotit, which reads
/// them in pieces of at most 16 KB: a long Send to list goes through a file
/// in [temp] instead.
Future<List<String>> handOverArgs(
  List<String> args,
  Future<Directory> Function() temp, {
  int limit = 8 * 1024,
}) async {
  if (utf8.encode(jsonEncode(args)).length <= limit) return args;
  final paths = await sendRequest(args);
  if (paths == null) return args;
  final dir = await temp();
  await dir.create(recursive: true);
  final tag = Random.secure().nextInt(1 << 32).toRadixString(16);
  final list = File('${dir.path}${Platform.pathSeparator}send-$tag.json');
  await list.writeAsString(jsonEncode(paths));
  return ['--send-list', list.path];
}
