import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gotit/core/clip/clip.dart';

/// What a recent item is.
enum RecentKind { text, link, image, files }

/// Which way it went, as this device sees it.
enum RecentWay { sent, received }

/// One file of a files item.
@immutable
class RecentFile {
  const RecentFile({required this.name, required this.size, this.location});

  final String name;

  /// In bytes, or -1 when unknown.
  final int size;

  /// Where it is: a path on the PC (the file that arrived, or the one that
  /// was sent), a content URI on the phone. Empty for a file the phone sent,
  /// which Android let Gotit read only while it was being shared.
  final String? location;

  Map<String, Object?> toJson() => {
    'name': name,
    'size': size,
    'location': ?location,
  };

  static RecentFile? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final size = json['size'];
    final location = json['location'];
    return RecentFile(
      name: name,
      size: size is int ? size : -1,
      location: location is String && location.isNotEmpty ? location : null,
    );
  }
}

/// Something that crossed: copied text, a link, an image, or files.
@immutable
class RecentItem {
  const RecentItem({
    required this.id,
    required this.kind,
    required this.way,
    required this.at,
    this.text = '',
    this.sensitive = false,
    this.screenshot = false,
    this.image,
    this.digest,
    this.width = 0,
    this.height = 0,
    this.imageBytes = 0,
    this.files = const [],
    this.batch,
  });

  final String id;
  final RecentKind kind;
  final RecentWay way;

  /// When it crossed, or was last copied again here.
  final DateTime at;

  /// The text, or the link.
  final String text;

  /// A password or a code: shown as dots, never kept on disk, and gone after
  /// a minute.
  final bool sensitive;

  /// An image that was a new phone screenshot.
  final bool screenshot;

  /// Where the image is kept: a PNG in Gotit's own folder.
  final String? image;

  /// The image's SHA-256, which tells two copies of it apart.
  final String? digest;

  /// The image's size in pixels, 0 when unknown.
  final int width;
  final int height;

  /// The PNG's size in bytes, which counts against the images' cap.
  final int imageBytes;

  /// The files, for a files item: one, or a batch.
  final List<RecentFile> files;

  /// The transfer batch the files went in.
  final String? batch;

  /// Whether it can go back on the clipboard.
  bool get copyable => kind != RecentKind.files;

  /// The files' total size in bytes, leaving out unknown sizes.
  int get totalSize => files.fold(0, (sum, file) => sum + max(0, file.size));

  RecentItem moved({required DateTime at}) => RecentItem(
    id: id,
    kind: kind,
    way: way,
    at: at,
    text: text,
    sensitive: sensitive,
    screenshot: screenshot,
    image: image,
    digest: digest,
    width: width,
    height: height,
    imageBytes: imageBytes,
    files: files,
    batch: batch,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'way': way.name,
    'at': at.millisecondsSinceEpoch,
    if (text.isNotEmpty) 'text': text,
    if (screenshot) 'screenshot': true,
    'image': ?image,
    'digest': ?digest,
    if (width > 0) 'width': width,
    if (height > 0) 'height': height,
    if (imageBytes > 0) 'imageBytes': imageBytes,
    if (files.isNotEmpty) 'files': [for (final file in files) file.toJson()],
    'batch': ?batch,
  };

  /// The item in [json], or null when it isn't one this version understands.
  static RecentItem? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final kind = _byName(RecentKind.values, json['kind']);
    final way = _byName(RecentWay.values, json['way']);
    final at = json['at'];
    if (id is! String || id.isEmpty || kind == null || way == null) {
      return null;
    }
    if (at is! int) return null;
    String? text(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    int number(String key) {
      final value = json[key];
      return value is int ? value : 0;
    }

    final files = [
      if (json['files'] case final List<Object?> list)
        for (final file in list) ?RecentFile.fromJson(file),
    ];
    final item = RecentItem(
      id: id,
      kind: kind,
      way: way,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      text: text('text') ?? '',
      screenshot: json['screenshot'] == true,
      image: text('image'),
      digest: text('digest'),
      width: number('width'),
      height: number('height'),
      imageBytes: number('imageBytes'),
      files: List.unmodifiable(files),
      batch: text('batch'),
    );
    final whole = switch (kind) {
      RecentKind.text || RecentKind.link => item.text.isNotEmpty,
      RecentKind.image => item.image != null,
      RecentKind.files => item.files.isNotEmpty,
    };
    return whole ? item : null;
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Whether [text] is just one web address (http or https), nothing more.
bool isWebLink(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 2048) return false;
  if (RegExp(r'\s').hasMatch(trimmed)) return false;
  final uri = Uri.tryParse(trimmed);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// [url] without its scheme, as it is shown: "example.com/page".
String shownLink(String url) =>
    url.trim().replaceFirst(RegExp('^https?://', caseSensitive: false), '');

/// A PNG's width and height from its header, or (0, 0) when it isn't one.
(int, int) pngSize(Uint8List png) {
  const ihdr = [0x49, 0x48, 0x44, 0x52];
  if (png.length < 24) return (0, 0);
  for (var i = 0; i < ihdr.length; i++) {
    if (png[12 + i] != ihdr[i]) return (0, 0);
  }
  final data = ByteData.sublistView(png);
  return (data.getUint32(16), data.getUint32(20));
}

/// The last [max] things that crossed either way, newest first. The list is
/// kept in Gotit's own folder across restarts (`recent.json`, and images as
/// PNG files in `recent/`). Sensitive items stay in memory only, and leave
/// after [sensitiveFor].
class RecentList extends ValueNotifier<List<RecentItem>> {
  RecentList._(
    this._folder,
    List<RecentItem> items, {
    required this.max,
    required this.sensitiveFor,
    required this.maxImageBytes,
    required this.undoFor,
    required this._clock,
    required this._random,
  }) : super(List.unmodifiable(items));

  /// Opens the list kept in [folder]. A missing or damaged list starts empty;
  /// items whose image is gone are dropped, and images no item uses are
  /// deleted.
  static Future<RecentList> open(
    Directory folder, {
    int max = 20,
    Duration sensitiveFor = const Duration(minutes: 1),
    int maxImageBytes = 100 * 1024 * 1024,
    Duration undoFor = const Duration(seconds: 8),
    DateTime Function()? clock,
    Random? random,
  }) async {
    final items = <RecentItem>[];
    final file = File(_join(folder.path, _listName));
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json case {'items': final List<Object?> saved}) {
          for (final entry in saved) {
            final item = RecentItem.fromJson(entry);
            if (item == null) continue;
            final image = item.image;
            if (image != null && !File(image).existsSync()) continue;
            items.add(item);
          }
        }
      }
    } on FormatException {
      // A damaged list: start again.
    } on FileSystemException {
      // Unreadable: the same.
    }
    final list = RecentList._(
      folder,
      items.take(max).toList(),
      max: max,
      sensitiveFor: sensitiveFor,
      maxImageBytes: maxImageBytes,
      undoFor: undoFor,
      clock: clock ?? DateTime.now,
      random: random ?? Random.secure(),
    );
    await list._clearStrayImages();
    return list;
  }

  /// A list that is never written anywhere and keeps no images, for tests
  /// of what shows it.
  @visibleForTesting
  factory RecentList.unsaved({
    int max = 20,
    Duration sensitiveFor = const Duration(minutes: 1),
    Duration undoFor = const Duration(seconds: 8),
  }) => RecentList._(
    null,
    const [],
    max: max,
    sensitiveFor: sensitiveFor,
    maxImageBytes: 0,
    undoFor: undoFor,
    clock: DateTime.now,
    random: Random(),
  );

  static const _listName = 'recent.json';
  static const _imagesName = 'recent';

  /// Where the list is kept; none for [RecentList.unsaved].
  final Directory? _folder;
  final int max;
  final Duration sensitiveFor;

  /// The most room kept images may take; the oldest go first past it.
  final int maxImageBytes;

  /// How long a removed item can come back, before its image is deleted.
  final Duration undoFor;
  final DateTime Function() _clock;
  final Random _random;

  final _expiries = <String, Timer>{};
  final _deadlines = <String, DateTime>{};
  final _binned = <String, Timer>{};
  Future<void>? _saving;
  bool _saveAgain = false;
  bool _disposed = false;

  Directory? get _images {
    final folder = _folder;
    return folder == null ? null : Directory(_join(folder.path, _imagesName));
  }

  /// Adds a copy that crossed [way]. The same text or image again moves to
  /// the top instead. A sensitive image crosses but isn't listed.
  Future<RecentItem?> addClip(Clip clip, RecentWay way) async {
    if (clip.isEmpty) return null;
    final now = _clock();
    if (clip.isImage) {
      if (clip.sensitive) return null;
      final png = clip.image!;
      final digest = sha256.convert(png).toString();
      final same = _first((item) => item.digest == digest);
      if (same != null) return _toTop(same, at: now);
      final images = _images;
      if (images == null) return null;
      final id = _newId();
      final file = File(_join(images.path, '$id.png'));
      try {
        await images.create(recursive: true);
        await file.writeAsBytes(png, flush: true);
      } on FileSystemException {
        return null;
      }
      final (width, height) = pngSize(png);
      final item = RecentItem(
        id: id,
        kind: RecentKind.image,
        way: way,
        at: now,
        screenshot: clip.screenshot,
        image: file.path,
        digest: digest,
        width: width,
        height: height,
        imageBytes: png.length,
      );
      _put(item);
      _capImages(keep: id);
      return item;
    }
    final link = !clip.sensitive && isWebLink(clip.text);
    final text = link ? clip.text.trim() : clip.text;
    final same = _first(
      (item) =>
          item.copyable &&
          item.kind != RecentKind.image &&
          item.text == text &&
          item.sensitive == clip.sensitive,
    );
    if (same != null) return _toTop(same, at: now);
    final item = RecentItem(
      id: _newId(),
      kind: link ? RecentKind.link : RecentKind.text,
      way: way,
      at: now,
      text: text,
      sensitive: clip.sensitive,
    );
    _put(item);
    return item;
  }

  /// Adds files that went together [way], as one item.
  RecentItem? addFiles(List<RecentFile> files, RecentWay way, {String? batch}) {
    if (files.isEmpty) return null;
    final item = RecentItem(
      id: _newId(),
      kind: RecentKind.files,
      way: way,
      at: _clock(),
      files: List.unmodifiable(files),
      batch: batch,
    );
    _put(item);
    return item;
  }

  /// [id] was copied again here: to the top, as of now. A sensitive item
  /// keeps its minute.
  RecentItem? copiedAgain(String id) {
    final item = _first((item) => item.id == id);
    return item == null ? null : _toTop(item, at: _clock());
  }

  /// Takes [id] off the list. [restore] can bring it back for [undoFor].
  RecentItem? remove(String id) {
    final item = _first((item) => item.id == id);
    if (item == null) return null;
    _set([
      for (final other in value)
        if (other.id != id) other,
    ]);
    _bin(item);
    return item;
  }

  /// Takes everything off the list. [restore] can bring it back for
  /// [undoFor].
  List<RecentItem> clear() {
    final gone = value;
    if (gone.isEmpty) return const [];
    _set(const []);
    gone.forEach(_bin);
    return gone;
  }

  /// Puts [items] back where they were (Undo), newest first. A sensitive
  /// item whose minute is up stays gone.
  void restore(List<RecentItem> items) {
    final now = _clock();
    final back = [
      for (final item in items)
        if (!item.sensitive || (_deadlines[item.id]?.isAfter(now) ?? false))
          item,
    ];
    for (final item in back) {
      _binned.remove(item.id)?.cancel();
    }
    final known = {for (final item in value) item.id};
    final merged = [
      ...value,
      for (final item in back)
        if (!known.contains(item.id)) item,
    ]..sort((a, b) => b.at.compareTo(a.at));
    _set(merged.take(max).toList());
    for (final item in back) {
      if (item.sensitive) _expireLater(item, _deadlines[item.id]!);
    }
  }

  /// When the sensitive item [id] leaves the list, or null.
  DateTime? deadlineOf(String id) => _deadlines[id];

  /// Waits until what changed is on disk.
  Future<void> flush() async {
    while (_saving != null) {
      await _saving;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in [..._expiries.values, ..._binned.values]) {
      timer.cancel();
    }
    super.dispose();
  }

  // ----------------------------------------------------------------------

  RecentItem? _first(bool Function(RecentItem item) test) {
    for (final item in value) {
      if (test(item)) return item;
    }
    return null;
  }

  void _put(RecentItem item) {
    final next = [item, ...value];
    final dropped = next.length > max
        ? next.sublist(max)
        : const <RecentItem>[];
    _set(next.take(max).toList());
    dropped.forEach(_forget);
    if (item.sensitive) {
      final deadline = item.at.add(sensitiveFor);
      _deadlines[item.id] = deadline;
      _expireLater(item, deadline);
    }
  }

  RecentItem _toTop(RecentItem item, {required DateTime at}) {
    final moved = item.moved(at: at);
    _set([
      moved,
      for (final other in value)
        if (other.id != item.id) other,
    ]);
    return moved;
  }

  void _expireLater(RecentItem item, DateTime deadline) {
    _expiries.remove(item.id)?.cancel();
    final wait = deadline.difference(_clock());
    _expiries[item.id] = Timer(wait.isNegative ? Duration.zero : wait, () {
      _expiries.remove(item.id);
      if (_disposed) return;
      _deadlines.remove(item.id);
      if (_first((other) => other.id == item.id) == null) return;
      _set([
        for (final other in value)
          if (other.id != item.id) other,
      ]);
    });
  }

  /// Keeps the images' total under [maxImageBytes], dropping the oldest.
  void _capImages({required String keep}) {
    var total = value.fold(0, (sum, item) => sum + item.imageBytes);
    if (total <= maxImageBytes) return;
    final dropped = <RecentItem>[];
    for (final item in value.reversed) {
      if (total <= maxImageBytes) break;
      if (item.kind != RecentKind.image || item.id == keep) continue;
      total -= item.imageBytes;
      dropped.add(item);
    }
    if (dropped.isEmpty) return;
    final gone = {for (final item in dropped) item.id};
    _set([
      for (final item in value)
        if (!gone.contains(item.id)) item,
    ]);
    dropped.forEach(_forget);
  }

  /// Off the list for good, unless [restore] brings it back in time.
  void _bin(RecentItem item) {
    _expiries.remove(item.id)?.cancel();
    _binned.remove(item.id)?.cancel();
    _binned[item.id] = Timer(undoFor, () {
      _binned.remove(item.id);
      if (_first((other) => other.id == item.id) != null) return;
      _forget(item);
    });
  }

  /// Off the list for good: its image is deleted.
  void _forget(RecentItem item) {
    _expiries.remove(item.id)?.cancel();
    _deadlines.remove(item.id);
    final image = item.image;
    if (image != null) unawaited(_deleteQuietly(File(image)));
  }

  void _set(List<RecentItem> items) {
    if (_disposed) return;
    value = List.unmodifiable(items);
    _save();
  }

  void _save() {
    if (_folder == null) return;
    if (_saving != null) {
      _saveAgain = true;
      return;
    }
    _saving = _write().whenComplete(() {
      _saving = null;
      if (_saveAgain && !_disposed) {
        _saveAgain = false;
        _save();
      }
    });
  }

  Future<void> _write() async {
    final json = jsonEncode({
      'version': 1,
      'items': [
        for (final item in value)
          if (!item.sensitive) item.toJson(),
      ],
    });
    final folder = _folder;
    if (folder == null) return;
    try {
      await folder.create(recursive: true);
      final file = File(_join(folder.path, _listName));
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json, flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      // Not kept this time; the next change tries again.
    }
  }

  /// Deletes kept images no item uses (left by a crash, say).
  Future<void> _clearStrayImages() async {
    final used = {
      for (final item in value)
        if (item.image case final image?) File(image).absolute.path,
    };
    final images = _images;
    if (images == null || !await images.exists()) return;
    try {
      await for (final entry in images.list()) {
        if (entry is File && !used.contains(entry.absolute.path)) {
          await _deleteQuietly(entry);
        }
      }
    } on FileSystemException {
      // Left for next time.
    }
  }

  String _newId() => List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Gone already, or in use: left for the next start.
  }
}

String _join(String folder, String name) =>
    '$folder${Platform.pathSeparator}$name';
