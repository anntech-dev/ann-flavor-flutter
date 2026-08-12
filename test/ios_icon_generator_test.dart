import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../lib_cli/icon/ios_icon_generator.dart';
import '../lib_cli/icon/xcconfig_icon_wirer.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ann_icon_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('IosIconGenerator validation', () {
    test('throws on missing source file', () async {
      final gen = IosIconGenerator(tempDir.path);
      expect(
        () => gen.generateForFlavor('free', 'missing/icon.png'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('not found'),
        )),
      );
    });

    test('throws on non-PNG source', () async {
      final jpegFile = File(p.join(tempDir.path, 'icon.jpg'))
        ..writeAsStringSync('fake jpeg');
      final gen = IosIconGenerator(tempDir.path);
      expect(
        () => gen.generateForFlavor('free', jpegFile.path),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('PNG'),
        )),
      );
    });

    test('throws on source smaller than 1024x1024', () async {
      final smallPng = _writeFakePng(p.join(tempDir.path, 'small.png'), 512, 512);
      final gen = IosIconGenerator(tempDir.path);
      expect(
        () => gen.generateForFlavor('free', smallPng.path),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('1024'),
        )),
      );
    });
  });

  group('xcconfig_icon_wirer', () {
    test('appends key when absent', () {
      final flutterDir = Directory(p.join(tempDir.path, 'ios', 'Flutter'))
        ..createSync(recursive: true);
      final xcconfig = File(p.join(flutterDir.path, 'freeRelease.xcconfig'))
        ..writeAsStringSync('PRODUCT_BUNDLE_IDENTIFIER=com.example\n');

      wireXcconfig(tempDir.path, 'free');

      final content = xcconfig.readAsStringSync();
      expect(content, contains('ASSETCATALOG_COMPILER_APPICON_NAME=FreeAppIcon'));
    });

    test('updates existing key in-place', () {
      final flutterDir = Directory(p.join(tempDir.path, 'ios', 'Flutter'))
        ..createSync(recursive: true);
      final xcconfig = File(p.join(flutterDir.path, 'freeRelease.xcconfig'))
        ..writeAsStringSync(
          'PRODUCT_BUNDLE_IDENTIFIER=com.example\n'
          'ASSETCATALOG_COMPILER_APPICON_NAME=OldIcon\n',
        );

      wireXcconfig(tempDir.path, 'free');

      final content = xcconfig.readAsStringSync();
      expect(content, contains('ASSETCATALOG_COMPILER_APPICON_NAME=FreeAppIcon'));
      expect(content, isNot(contains('OldIcon')));
    });

    test('skips missing xcconfig gracefully', () {
      // No ios/Flutter dir — should not throw
      expect(() => wireXcconfig(tempDir.path, 'free'), returnsNormally);
    });
  });
}

/// Writes a minimal valid PNG file with the given IHDR dimensions.
File _writeFakePng(String path, int width, int height) {
  final bytes = <int>[];

  // PNG signature
  bytes.addAll([137, 80, 78, 71, 13, 10, 26, 10]);

  // IHDR chunk: length (13), type, width, height, bit depth (8), color type (2=RGB), ...
  void writeInt32(int v) {
    bytes.add((v >> 24) & 0xFF);
    bytes.add((v >> 16) & 0xFF);
    bytes.add((v >> 8) & 0xFF);
    bytes.add(v & 0xFF);
  }

  final ihdrData = <int>[];
  ihdrData.addAll(_int32Bytes(width));
  ihdrData.addAll(_int32Bytes(height));
  ihdrData.addAll([8, 2, 0, 0, 0]); // bit depth 8, RGB, compression, filter, interlace

  writeInt32(13); // IHDR length
  bytes.addAll([73, 72, 68, 82]); // 'IHDR'
  bytes.addAll(ihdrData);
  writeInt32(_crc32([73, 72, 68, 82, ...ihdrData]));

  // Minimal IEND chunk
  writeInt32(0);
  bytes.addAll([73, 69, 78, 68]); // 'IEND'
  writeInt32(_crc32([73, 69, 78, 68]));

  final file = File(path);
  file.writeAsBytesSync(bytes);
  return file;
}

List<int> _int32Bytes(int v) => [
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ];

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      if (crc & 1 != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return (~crc) & 0xFFFFFFFF;
}
