import 'package:args/command_runner.dart';
import '../spec/annspec_reader.dart';
import '../generators/dart_generator.dart';
import '../generators/android_generator.dart';
import '../generators/ios_generator.dart';
import '../generators/firebase_generator.dart';

class SyncCommand extends Command<void> {
  @override
  final name = 'sync';

  @override
  final description =
      'Read annspec.yaml and sync all platform files (Dart codegen, '
      'Firebase script, Android Gradle wiring, iOS CocoaPods wiring).';

  SyncCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        help: 'Path to the Flutter project root.',
        defaultsTo: '.',
      )
      ..addFlag(
        'firebase',
        help: 'Also run firebase.sh immediately after generating it '
            '(requires flutterfire CLI to be installed).',
        defaultsTo: false,
        negatable: false,
      );
  }

  @override
  Future<void> run() async {
    final projectRoot  = argResults!['project'] as String;
    final runFirebase  = argResults!['firebase'] as bool;

    print('ANN Flavor — syncing $projectRoot\n');

    print('[1/5] Reading annspec.yaml...');
    final spec = AnnspecReader.read(projectRoot);
    print('  ✓ Found ${spec.platforms.length} platform(s).');

    print('\n[2/5] Generating Dart flavor file...');
    DartGenerator.generate(spec, projectRoot);

    print('\n[3/5] Generating Firebase script...');
    FirebaseGenerator.generate(spec, projectRoot, runScript: runFirebase);

    print('\n[4/5] Wiring Android (Gradle plugin + defaultConfig)...');
    AndroidGenerator.generate(projectRoot, spec);

    print('\n[5/5] Wiring iOS CocoaPods plugin...');
    IosGenerator.generate(projectRoot);

    print('\n✅  Sync complete.');
    if (!runFirebase) {
      print('    Firebase: run `dart run ann_flutter_flavor firebase --run` to generate options files.');
    }
    print('    iOS:      run `pod install` if Podfile changed.');
  }
}
