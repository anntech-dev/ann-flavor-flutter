import 'package:args/command_runner.dart';
import '../spec/annspec_reader.dart';
import '../generators/dart_generator.dart';
import '../generators/android_generator.dart';
import '../generators/ios_generator.dart';

class SyncCommand extends Command<void> {
  @override
  final name = 'sync';

  @override
  final description =
      'Read annspec.yaml and sync all platform files (Dart codegen, '
      'Android Gradle plugin wiring, iOS CocoaPods plugin wiring).';

  SyncCommand() {
    argParser.addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Flutter project root.',
      defaultsTo: '.',
    );
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;
    print('ANN Flavor — syncing $projectRoot');

    print('\n[1/4] Reading annspec.yaml...');
    final spec = AnnspecReader.read(projectRoot);
    print('  ✓ Found ${spec.platforms.length} platform(s).');

    print('\n[2/4] Generating Dart flavor file...');
    DartGenerator.generate(spec, projectRoot);

    print('\n[3/4] Wiring Android Gradle plugin...');
    AndroidGenerator.generate(projectRoot);

    print('\n[4/4] Wiring iOS CocoaPods plugin...');
    IosGenerator.generate(projectRoot);

    print('\n✅  Sync complete.');
    print('    Next: run `pod install` if iOS config changed.');
  }
}
