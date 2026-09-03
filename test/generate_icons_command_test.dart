import 'dart:io';
import 'package:test/test.dart';

// Package root is one level up from the test/ directory.
final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _runGenerateIcons(Directory projectDir, {String? platform, String? flavor}) {
  final args = ['run', 'ann_flutter_flavor', 'generate-icons', '--project', projectDir.path];
  if (platform != null) args.addAll(['--platform', platform]);
  if (flavor != null) args.addAll(['--flavor', flavor]);
  return Process.run('dart', args, workingDirectory: _packageRoot);
}

void main() {
  group('generate-icons — flavor/platform selection', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('generate_icons_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('reports nothing to do when no icon paths are configured', () async {
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
    flavor:
      free:
        name: "Free"
        main_file: "lib/main.dart"
''');
      final result = await _runGenerateIcons(tempDir);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('No icon paths found'));
    });

    test('reports nothing to do when --flavor filters out every configured flavor', () async {
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
    flavor:
      free:
        name: "Free"
        main_file: "lib/main.dart"
        icon: "assets/icon.png"
''');
      final result = await _runGenerateIcons(tempDir, flavor: 'nonexistent_flavor');
      expect(result.exitCode, 0);
      expect(result.stdout, contains('No matching flavor/platform combination'));
    });

    test('reports nothing to do when --platform filters out every configured platform', () async {
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
    flavor:
      free:
        name: "Free"
        main_file: "lib/main.dart"
        icon: "assets/icon.png"
''');
      final result = await _runGenerateIcons(tempDir, platform: 'android');
      expect(result.exitCode, 0);
      expect(result.stdout, contains('No matching flavor/platform combination'));
    });

    test('clears a stray flutter_launcher_icons-*.yaml left by a prior interrupted run', () async {
      // Regression: flutter_launcher_icons globs the working directory for
      // ^flutter_launcher_icons-(.*)\.yaml$ and silently ignores our -f flag
      // if any match exists, running "flavor mode" for every match instead —
      // a config left behind by a crashed/killed prior run would silently
      // hijack every subsequent generate-icons run in this directory.
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
    flavor:
      free:
        name: "Free"
        main_file: "lib/main.dart"
''');
      final strayConfig = File('${tempDir.path}/flutter_launcher_icons-stale_flavor.yaml')
        ..writeAsStringSync('flutter_launcher_icons:\n  ios: true\n');

      final result = await _runGenerateIcons(tempDir);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Removing stray config from a previous run'));
      expect(strayConfig.existsSync(), isFalse);
    });
  });
}
