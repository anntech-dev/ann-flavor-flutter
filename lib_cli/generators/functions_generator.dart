import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;
import '../validators/functions_validator.dart';
import 'functions_param_scanner.dart';

/// Thrown with a message that is safe to show the user as-is.
class FunctionsPrepareException implements Exception {
  final String message;
  FunctionsPrepareException(this.message);

  @override
  String toString() => message;
}

class FunctionsPrepareResult {
  /// codebase name -> `.env` file names written into build/functions/<codebase>/.
  final Map<String, List<String>> written;
  final List<String> warnings;
  FunctionsPrepareResult(this.written, this.warnings);
}

/// Copies each Firebase Functions package to build/functions/<codebase>/ and
/// writes one `.env.<project_id>` per project (REQ-FUNC-00030). Copy only, no
/// symlinks and no shell (REQ-FUNC-00040); the source folder is never written
/// to.
class FunctionsGenerator {
  static const _skipDirs = {'node_modules', '.git'};
  static final _envValueNeedsQuotes = RegExp(r'''[\s#"'\\]''');
  static final _envKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static FunctionsPrepareResult prepare(
    core.AnnSpec spec,
    String projectRoot, {
    String? firebaseProject,
    Set<String>? onlyCodebases,
    bool skipSourceCheck = false,
  }) {
    final fn = spec.functions;
    if (fn == null || fn.codebases.isEmpty) {
      throw FunctionsPrepareException(
          'annspec.yaml has no functions.codebases — nothing to prepare.');
    }
    if (fn.projects.isEmpty) {
      throw FunctionsPrepareException(
          'annspec.yaml has no functions.projects — declare at least one Firebase project.');
    }

    final errors = <String>[...FunctionsValidator.validate(fn)];
    final warnings = <String>[];

    if (firebaseProject != null && !fn.projects.containsKey(firebaseProject)) {
      errors.add("Unknown functions project '$firebaseProject'. "
          'Declared: ${fn.projects.keys.join(', ')}');
    }
    final unknownCodebases =
        (onlyCodebases ?? const <String>{}).where((c) => !fn.codebases.containsKey(c)).toList();
    if (unknownCodebases.isNotEmpty) {
      errors.add("Unknown functions codebase '${unknownCodebases.join("', '")}'. "
          'Declared: ${fn.codebases.keys.join(', ')}');
    }
    if (errors.isNotEmpty) throw FunctionsPrepareException(errors.join('\n'));

    final aliases = firebaseProject == null ? fn.projects.keys.toList() : [firebaseProject];

    // Plan every codebase first so any problem is reported before anything is written.
    final plans = <String, _Plan>{};
    for (final entry in fn.codebases.entries) {
      if (onlyCodebases != null && !onlyCodebases.contains(entry.key)) continue;
      final name = entry.key;
      final codebase = entry.value;
      final src = p.normalize(p.join(projectRoot, codebase.source));
      if (!Directory(src).existsSync()) {
        errors.add("functions.codebases.$name: source '${codebase.source}' not found at $src "
            '(an uninitialised git submodule is a common cause)');
        continue;
      }

      final scan = skipSourceCheck ? null : FunctionsParamScanner.scan(Directory(src));
      final envs = <String, Map<String, String>>{};
      for (final alias in aliases) {
        final values = {...codebase.params, ...?codebase.projectParams[alias]};
        _checkValues(name, alias, values, errors);
        if (scan != null) _checkAgainstSource(name, alias, values, scan, errors, warnings);
        envs[fn.projects[alias]!.projectId!.trim()] = values;
      }
      if (scan != null && scan.unchecked > 0) {
        warnings.add('functions.codebases.$name: ${scan.unchecked} param declaration(s) use a '
            'non-literal name, so the source check is incomplete for them.');
      }
      plans[name] = _Plan(src, envs);
    }
    if (errors.isNotEmpty) throw FunctionsPrepareException(errors.join('\n'));

    final written = <String, List<String>>{};
    for (final entry in plans.entries) {
      final dest = Directory(p.join(projectRoot, 'build', 'functions', entry.key));
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      _copy(Directory(entry.value.source), dest, warnings);
      final files = <String>[];
      for (final env in entry.value.envs.entries) {
        final fileName = '.env.${env.key}';
        File(p.join(dest.path, fileName)).writeAsStringSync(_dotenv(env.value), flush: true);
        files.add(fileName);
      }
      written[entry.key] = files;
    }
    return FunctionsPrepareResult(written, warnings);
  }

  static void _checkValues(
      String codebase, String alias, Map<String, String> values, List<String> errors) {
    if (values.isEmpty) {
      errors.add("functions.codebases.$codebase: no values for project '$alias' — "
          'add params or project_params.$alias');
      return;
    }
    values.forEach((key, value) {
      if (!_envKey.hasMatch(key)) {
        errors.add("functions.codebases.$codebase: '$key' is not a valid param name "
            '(letters, digits and _ only, not starting with a digit)');
      } else if (value.trim().isEmpty) {
        errors.add("functions.codebases.$codebase: '$key' is blank for project '$alias'");
      }
    });
  }

  static void _checkAgainstSource(String codebase, String alias, Map<String, String> values,
      FunctionsParamScan scan, List<String> errors, List<String> warnings) {
    if (!scan.foundAnything) {
      final msg = "functions.codebases.$codebase: no defineString-style param declarations "
          'found in the source, so the values are not verified.';
      if (!warnings.contains(msg)) warnings.add(msg);
      return;
    }
    final missing = scan.required.where((n) => !values.containsKey(n)).toList()..sort();
    if (missing.isNotEmpty) {
      errors.add("functions.codebases.$codebase: project '$alias' has no value for required "
          'param(s) ${missing.join(', ')} (declared without a default in the source; the '
          'Firebase CLI would prompt for them during deploy)');
    }
    final secretsSet = values.keys.where(scan.secrets.contains).toList()..sort();
    if (secretsSet.isNotEmpty) {
      errors.add("functions.codebases.$codebase: ${secretsSet.join(', ')} is declared with "
          'defineSecret in the source — secrets are never written to .env; remove it from '
          'annspec.yaml and keep it in Secret Manager');
    }
    final unused = values.keys.where((k) => !scan.declared.contains(k)).toList()..sort();
    if (unused.isNotEmpty) {
      final msg = "functions.codebases.$codebase: ${unused.join(', ')} is not declared in the "
          'source (unused)';
      if (!warnings.contains(msg)) warnings.add(msg);
    }
  }

  static void _copy(Directory from, Directory to, List<String> warnings) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (_skipDirs.contains(name)) continue;
        _copy(entity, Directory(p.join(to.path, name)), warnings);
      } else if (entity is File) {
        if (name.startsWith('.env')) continue;
        if (name.startsWith('firebase-debug') && name.endsWith('.log')) continue;
        entity.copySync(p.join(to.path, name));
      } else {
        warnings.add('skipped symbolic link ${entity.path} (links are not copied)');
      }
    }
  }

  static String _dotenv(Map<String, String> values) {
    final buf = StringBuffer();
    final keys = values.keys.toList()..sort();
    for (final k in keys) {
      buf.write('$k=${_quote(values[k]!)}\n');
    }
    return buf.toString();
  }

  static String _quote(String v) {
    if (!_envValueNeedsQuotes.hasMatch(v) && !v.contains('\n') && !v.contains('\r')) return v;
    final escaped = v
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }
}

class _Plan {
  final String source;

  /// project_id -> merged values
  final Map<String, Map<String, String>> envs;
  _Plan(this.source, this.envs);
}
