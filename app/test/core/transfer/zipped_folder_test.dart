import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/transfer/zipped_folder.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('gotit_zip_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String at(String name) => '${dir.path}${Platform.pathSeparator}$name';

  /// A small folder: a text file, a photo in a subfolder, an empty folder.
  Directory trip() {
    final folder = Directory(at('Trip'))..createSync();
    File(at('Trip/notes.txt')).writeAsStringSync('hello ' * 200);
    Directory(at('Trip/photos')).createSync();
    File(at('Trip/photos/a.jpg')).writeAsBytesSync(List.filled(4000, 7));
    Directory(at('Trip/empty')).createSync();
    return folder;
  }

  test('a folder zips with itself at the top', () async {
    final folder = trip();
    await zipFolder(folder.path, at('Trip.zip'));
    final zip = ZipDecoder().decodeBytes(
      File(at('Trip.zip')).readAsBytesSync(),
    );
    final names = zip.files.map((f) => f.name).toList();
    expect(names, containsAll(['Trip/notes.txt', 'Trip/photos/a.jpg']));
    expect(names.where((n) => n.startsWith('Trip/empty')), hasLength(1));
    expect(
      zip.findFile('Trip/notes.txt')!.content,
      utf8.encode('hello ' * 200),
    );
    expect(zip.findFile('Trip/photos/a.jpg')!.content, List.filled(4000, 7));
    // A photo is stored as it is; text is compressed.
    expect(
      zip.findFile('Trip/photos/a.jpg')!.compression,
      CompressionType.none,
    );
    expect(
      zip.findFile('Trip/notes.txt')!.compression,
      CompressionType.deflate,
    );
  });

  test('an empty folder still makes a zip holding it', () async {
    final folder = Directory(at('Nothing'))..createSync();
    await zipFolder(folder.path, at('Nothing.zip'));
    final zip = ZipDecoder().decodeBytes(
      File(at('Nothing.zip')).readAsBytesSync(),
    );
    expect(zip.files.single.name, startsWith('Nothing'));
  });

  test('a zipped folder is made, read, then removed', () async {
    final folder = trip();
    final temp = Directory(at('temp'));
    final file = ZippedFolder(folder.path, temp: () async => temp);
    expect(file.name, 'Trip.zip');
    expect(file.size, -1);
    await file.prepare();
    expect(file.size, greaterThan(0));
    final bytes = await file.read().expand((piece) => piece).toList();
    expect(bytes, hasLength(file.size));
    expect(
      ZipDecoder().decodeBytes(bytes).findFile('Trip/notes.txt'),
      isNotNull,
    );
    await file.dispose();
    await file.dispose();
    expect(temp.listSync(), isEmpty);
  });

  test('a zipped folder stopped before it starts is not made', () async {
    final file = ZippedFolder(
      trip().path,
      temp: () async => Directory(at('t')),
    );
    file.stop();
    await expectLater(file.prepare(), throwsStateError);
    await file.dispose();
  });

  test('a folder that is not there is not made', () async {
    final file = ZippedFolder(
      at('missing'),
      temp: () async => Directory(at('t')),
    );
    await expectLater(file.prepare(), throwsStateError);
    await file.dispose();
  });

  test('folder names', () {
    expect(folderName(r'C:\Users\x\Trip'), 'Trip');
    expect(folderName(r'C:\Users\x\Trip\'), 'Trip');
    expect(folderName('/home/x/notes/'), 'notes');
    expect(folderName(r'D:\'), 'folder');
    expect(folderName(''), 'folder');
  });
}
