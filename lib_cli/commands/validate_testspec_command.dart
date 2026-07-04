import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../validators/testspec_validator.dart';

class ValidateTestspecCommand extends Command<void> {
  @override
  final name = 'validate-testspec';

  @override
  final description = 'Validate anntestspec.yaml structure and report any issues.';

  ValidateTestspecCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
    argParser.addOption(
      'format',
      allowed: ['human', 'json'],
      defaultsTo: 'human',
      help: 'Output format: "human" (default) or "json" for machine consumers.',
    );
  }

  @override
  Future<void> run() async {
    final jsonMode = (argResults!['format'] as String) == 'json';
    try {
      await _runValidate(jsonMode);
    } catch (e) {
      if (jsonMode) {
        _printJson(null, TestspecResult(present: false), parseError: 'Internal error: $e');
      } else {
        rethrow;
      }
      exitCode = 1;
    }
  }

  Future<void> _runValidate(bool jsonMode) async {
    final projectRoot = argResults!['project'] as String;

    if (!jsonMode) {
      print('ANN Flavor — validating anntestspec.yaml in $projectRoot');
      print('');
    }

    final testspecFile = findTestspecFile(projectRoot);
    final result = validateTestspec(testspecFile, projectRoot);

    if (jsonMode) {
      _printJson(testspecFile.path, result);
    } else {
      _printResults(result);
    }

    if (!result.present || result.errors.isNotEmpty) exitCode = 1;
  }

  void _printJson(String? specPath, TestspecResult result, {String? parseError}) {
    if (parseError != null) {
      print(jsonEncode({
        'present': false,
        'valid': false,
        'specPath': specPath != null ? p.absolute(specPath) : null,
        'errors': [{'severity': 'error', 'path': 'anntestspec.yaml', 'message': parseError, 'fix': null}],
        'warnings': <dynamic>[],
        'infos': <dynamic>[],
      }));
      return;
    }

    if (!result.present) {
      print(jsonEncode({
        'present': false,
        'valid': false,
        'specPath': specPath != null ? p.absolute(specPath) : null,
        'errors': [{'severity': 'error', 'path': 'anntestspec.yaml', 'message': 'anntestspec.yaml not found.', 'fix': 'Create anntestspec.yaml at the project root.'}],
        'warnings': <dynamic>[],
        'infos': <dynamic>[],
      }));
      return;
    }

    print(jsonEncode({
      'present': true,
      'valid': result.errors.isEmpty,
      'specPath': p.absolute(result.specPath!),
      'errors': result.errors
          .map((e) => {'severity': 'error', 'path': e.path, 'message': e.message, 'fix': e.fix})
          .toList(),
      'warnings': result.warnings
          .map((w) => {'severity': 'warning', 'path': w.path, 'message': w.message, 'fix': w.fix})
          .toList(),
      'infos': result.infos
          .map((i) => {'severity': 'info', 'path': i.path, 'message': i.message, 'fix': i.fix})
          .toList(),
    }));
  }

  void _printResults(TestspecResult result) {
    if (!result.present) {
      print('  ✗  anntestspec.yaml not found.');
      return;
    }

    if (result.warnings.isNotEmpty) {
      print('  ⚠  ${result.warnings.length} warning${result.warnings.length == 1 ? '' : 's'}:');
      for (final w in result.warnings) _printIssue(w, icon: '⚠');
      print('');
    }
    if (result.infos.isNotEmpty) {
      print('  ℹ  ${result.infos.length} info item${result.infos.length == 1 ? '' : 's'}:');
      for (final i in result.infos) _printIssue(i, icon: 'ℹ');
      print('');
    }

    if (result.errors.isEmpty) {
      final suffix = result.warnings.isEmpty && result.infos.isEmpty ? '.' : ' (with items above).';
      print('  ✅  anntestspec.yaml is valid$suffix');
    } else {
      print('  ✗  ${result.errors.length} error${result.errors.length == 1 ? '' : 's'}:');
      for (final e in result.errors) _printIssue(e, icon: '✗');
    }
  }

  void _printIssue(TestspecIssue issue, {required String icon}) {
    print('');
    print('    $icon  ${issue.path}');
    print('       ${issue.message}');
    if (issue.fix != null) print('       → ${issue.fix}');
  }
}
