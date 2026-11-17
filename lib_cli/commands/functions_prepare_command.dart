import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../generators/functions_generator.dart';
import '../spec/annspec_reader.dart';

/// Prepares Firebase Functions deploy folders from the `firebase.functions` block of
/// annspec.yaml (REQ-FUNC-00030). Pure Dart: no shell, no symlinks.
class FunctionsPrepareCommand extends Command<void> {
  @override
  final name = 'functions-prepare';

  @override
  final description =
      'Copy each Firebase Functions package to build/functions/<codebase>/ and '
      'write one .env.<project_id> per project from annspec.yaml.';

  FunctionsPrepareCommand() {
    argParser
      ..addOption('project', abbr: 'p', defaultsTo: '.',
          help: 'Path to the project root (the folder containing annspec.yaml).')
      ..addOption('firebase-project',
          help: 'Alias of one firebase.projects entry. Writes only that '
              "project's .env file. Defaults to every declared project.")
      ..addOption('codebase',
          help: 'Comma-separated codebase names to prepare. Defaults to every '
              'declared codebase.')
      ..addFlag('skip-source-check', negatable: false,
          help: 'Do not scan the function source for param declarations.');
  }

  @override
  void run() {
    final projectRoot = p.canonicalize(argResults!['project'] as String);
    try {
      final spec = AnnspecReader.read(projectRoot);
      final result = FunctionsGenerator.prepare(
        spec,
        projectRoot,
        firebaseProject: argResults!['firebase-project'] as String?,
        onlyCodebases: (argResults!['codebase'] as String?)
            ?.split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet(),
        skipSourceCheck: argResults!['skip-source-check'] as bool,
      );
      result.written.forEach((codebase, files) {
        print('  ✓ $codebase → build/functions/$codebase (${files.join(', ')})');
      });
      for (final w in result.warnings) {
        print('  ⚠ $w');
      }
    } on FunctionsPrepareException catch (e) {
      stderr.writeln('  ✗ $e');
      exitCode = 1;
    } on Exception catch (e) {
      stderr.writeln('  ✗ $e');
      exitCode = 1;
    }
  }
}
