import 'package:args/command_runner.dart';
import '../generators/firebase_generator.dart';
import '../spec/annspec_reader.dart';

/// Generates (and optionally runs) lib/generated/scripts/firebase.sh.
class FirebaseCommand extends Command<void> {
  @override
  final name = 'firebase';

  @override
  final description =
      'Generate lib/generated/scripts/firebase.sh from annspec.yaml. '
      'Use --run to also execute it immediately via flutterfire CLI.';

  FirebaseCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        help: 'Path to the Flutter project root.',
        defaultsTo: '.',
      )
      ..addFlag(
        'run',
        abbr: 'r',
        help: 'Run firebase.sh immediately after generating it.',
        defaultsTo: false,
      );
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;
    final runScript  = argResults!['run'] as bool;

    print('ANN Flavor — generating firebase.sh for $projectRoot');
    final spec = AnnspecReader.read(projectRoot);

    FirebaseGenerator.generate(spec, projectRoot, runScript: runScript);
  }
}
