import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../lib_cli/icon/launch_image_generator.dart';

const _stockStoryboard = '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0">
    <scenes>
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <subviews>
                            <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">
                            </imageView>
                        </subviews>
                    </view>
                </viewController>
            </objects>
        </scene>
    </scenes>
    <resources>
        <image name="LaunchImage" width="168" height="185"/>
    </resources>
</document>
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ann_launch_image_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File _writeStoryboard() {
    final dir = Directory(p.join(tempDir.path, 'ios', 'Runner', 'Base.lproj'))
      ..createSync(recursive: true);
    final file = File(p.join(dir.path, 'LaunchScreen.storyboard'))
      ..writeAsStringSync(_stockStoryboard);
    return file;
  }

  File _writeFakePng(String path) {
    final bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0];
    final file = File(path)..writeAsBytesSync(bytes);
    return file;
  }

  group('LaunchImageGenerator validation', () {
    test('throws on missing source file', () async {
      final gen = LaunchImageGenerator(tempDir.path);
      expect(
        () => gen.generateForFlavor('free', 'missing/launch.png'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('not found'),
        )),
      );
    });

    test('throws on non-PNG source', () async {
      final jpegFile = File(p.join(tempDir.path, 'launch.jpg'))
        ..writeAsStringSync('fake jpeg');
      final gen = LaunchImageGenerator(tempDir.path);
      expect(
        () => gen.generateForFlavor('free', jpegFile.path),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('PNG'),
        )),
      );
    });
  });

  group('LaunchImageGenerator.generateForFlavor', () {
    test('writes @1x/@2x/@3x images and a Contents.json into ios/ann/Assets.xcassets/<Flavor>LaunchImage.imageset/', () async {
      final png = _writeFakePng(p.join(tempDir.path, 'launch.png'));
      _writeStoryboard();

      final gen = LaunchImageGenerator(tempDir.path);
      await gen.generateForFlavor('free', png.path);

      final imageSetDir = Directory(
        p.join(tempDir.path, 'ios', 'ann', 'Assets.xcassets', 'FreeLaunchImage.imageset'),
      );
      expect(File(p.join(imageSetDir.path, 'LaunchImage.png')).existsSync(), isTrue);
      expect(File(p.join(imageSetDir.path, 'LaunchImage@2x.png')).existsSync(), isTrue);
      expect(File(p.join(imageSetDir.path, 'LaunchImage@3x.png')).existsSync(), isTrue);

      final contentsJson = File(p.join(imageSetDir.path, 'Contents.json'));
      expect(contentsJson.existsSync(), isTrue);
      expect(contentsJson.readAsStringSync(), contains('"scale": "2x"'));
    });

    test('patches the storyboard image reference from the stock name to <Flavor>LaunchImage', () async {
      final png = _writeFakePng(p.join(tempDir.path, 'launch.png'));
      final storyboard = _writeStoryboard();

      final gen = LaunchImageGenerator(tempDir.path);
      await gen.generateForFlavor('free', png.path);

      final content = storyboard.readAsStringSync();
      expect(content, contains('image="FreeLaunchImage"'));
      expect(content, contains('<image name="FreeLaunchImage"'));
      expect(content, isNot(contains('image="LaunchImage"')));
    });

    test('re-running for a different flavor repoints the storyboard, not duplicates it', () async {
      final png = _writeFakePng(p.join(tempDir.path, 'launch.png'));
      final storyboard = _writeStoryboard();

      final gen = LaunchImageGenerator(tempDir.path);
      await gen.generateForFlavor('free', png.path);
      await gen.generateForFlavor('pro', png.path);

      final content = storyboard.readAsStringSync();
      expect(content, contains('image="ProLaunchImage"'));
      expect(content, isNot(contains('image="FreeLaunchImage"')));
      // Still exactly one storyboard file — never duplicated per flavor.
      expect(
        Directory(p.join(tempDir.path, 'ios', 'Runner'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.storyboard'))
            .length,
        1,
      );
    });

    test('re-running for the same flavor is a no-op on the storyboard (idempotent)', () async {
      final png = _writeFakePng(p.join(tempDir.path, 'launch.png'));
      final storyboard = _writeStoryboard();

      final gen = LaunchImageGenerator(tempDir.path);
      await gen.generateForFlavor('free', png.path);
      final firstRun = storyboard.readAsStringSync();
      await gen.generateForFlavor('free', png.path);
      final secondRun = storyboard.readAsStringSync();

      expect(secondRun, equals(firstRun));
    });

    test('does not throw when the storyboard is missing — generates the imageset anyway', () async {
      final png = _writeFakePng(p.join(tempDir.path, 'launch.png'));
      final gen = LaunchImageGenerator(tempDir.path);

      await gen.generateForFlavor('free', png.path);

      final imageSetDir = Directory(
        p.join(tempDir.path, 'ios', 'ann', 'Assets.xcassets', 'FreeLaunchImage.imageset'),
      );
      expect(File(p.join(imageSetDir.path, 'LaunchImage.png')).existsSync(), isTrue);
    });
  });
}
