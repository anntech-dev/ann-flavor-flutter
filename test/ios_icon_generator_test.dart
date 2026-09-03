import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../lib_cli/icon/ios_icon_generator.dart';

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

    // File type and dimension checks (PNG-ness, 1024x1024 minimum) are
    // intentionally NOT enforced here — flutter_launcher_icons is the sole
    // authority on whether a source image is acceptable, and returns its own
    // error when it isn't.
  });

  // xcconfig_icon_wirer.dart was retired in plan 035 STEP-2.3:
  // ios_generator.dart now sets ASSETCATALOG_COMPILER_APPICON_NAME directly
  // and unconditionally on every generated xcconfig (ios_generator_test.dart
  // covers this), since a separate after-the-fact patch would be silently
  // wiped by STEP-2.2's delete-and-regenerate on the next sync.

  group('IosIconGenerator backup/restore', () {
    // Regression coverage for a real bug: flutter_launcher_icons hardcodes
    // its iOS output to ios/Runner/Assets.xcassets/AppIcon.appiconset/ (no
    // config override exists — ios_content_images_path, used previously
    // here, is not a real flutter_launcher_icons key and silently had no
    // effect). backupStockCatalog/restoreStockCatalog preserve whatever the
    // developer's own stock catalog contained across a generation run that
    // necessarily overwrites it in place.
    test('backupStockCatalog is a no-op when no stock catalog exists', () {
      final gen = IosIconGenerator(tempDir.path);
      expect(() => gen.backupStockCatalog(), returnsNormally);
      expect(() => gen.restoreStockCatalog(), returnsNormally);
    });

    test('restoreStockCatalog puts back exactly what backupStockCatalog saved', () {
      final stockDir = Directory(
        p.join(tempDir.path, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'),
      )..createSync(recursive: true);
      File(p.join(stockDir.path, 'Contents.json')).writeAsStringSync('{"original": true}');

      final gen = IosIconGenerator(tempDir.path);
      gen.backupStockCatalog();

      // Simulate flutter_launcher_icons overwriting the stock catalog in place.
      stockDir.deleteSync(recursive: true);
      stockDir.createSync(recursive: true);
      File(p.join(stockDir.path, 'Contents.json')).writeAsStringSync('{"overwritten": true}');

      gen.restoreStockCatalog();

      final restored = File(p.join(stockDir.path, 'Contents.json')).readAsStringSync();
      expect(restored, '{"original": true}');
      expect(Directory(p.join(tempDir.path, '.ann_icon_backup')).existsSync(), isFalse);
    });
  });
}
