import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;
import 'functions_validator.dart';

class FirebaseIssues {
  final List<String> errors;
  final List<String> warnings;
  FirebaseIssues(this.errors, this.warnings);
}

/// Semantic checks for the `firebase:` block and the deprecated top-level
/// `functions:` (REQ-RULE-00030, REQ-RULE-00080), over the view the cores
/// resolve (REQ-RULE-00090). Structural unknown-key checks stay in the cores'
/// strict-mode checkers.
class FirebaseValidator {
  /// Errors and warnings for the whole block. Messages look like
  /// `<path>: <problem>`.
  static FirebaseIssues validate(core.ResolvedFirebase resolved, String projectRoot) {
    final errors = <String>[
      ...conflictMessages(resolved),
      ...validateProjects(resolved),
      ...FunctionsValidator.validate(resolved),
      if (resolved.rules != null) ...validateRules(resolved.rules!, projectRoot),
    ];
    return FirebaseIssues(errors, deprecationMessages(resolved));
  }

  /// REQ-RULE-00030: both locations of functions, or one alias defined differently.
  static List<String> conflictMessages(core.ResolvedFirebase resolved) => [
        for (final c in resolved.conflicts)
          if (c == 'functions')
            'firebase.functions: both firebase.functions and a top-level functions: block are '
                'present — move the codebases into firebase.functions and remove the top-level block'
          else if (c.startsWith('projects.'))
            "firebase.projects.${c.substring('projects.'.length)}: differs from "
                "functions.projects.${c.substring('projects.'.length)} — keep the one under "
                'firebase.projects and remove the other',
      ];

  static List<String> deprecationMessages(core.ResolvedFirebase resolved) => [
        for (final d in resolved.deprecated)
          if (d == 'functions')
            'functions: the top-level functions: block is deprecated — move it under firebase: as '
                'firebase.functions (codebases only)'
          else if (d == 'functions.projects')
            'functions.projects: deprecated — move the projects to firebase.projects',
      ];

  /// REQ-FUNC-00070: every project has a non-blank, unique `project_id`.
  static List<String> validateProjects(core.ResolvedFirebase resolved) {
    final problems = <String>[];
    final seenIds = <String, String>{};
    resolved.projects.forEach((alias, project) {
      final id = project.projectId?.trim() ?? '';
      if (id.isEmpty) {
        problems.add('firebase.projects.$alias: project_id is missing or blank');
        return;
      }
      final other = seenIds[id];
      if (other != null) {
        problems.add("firebase.projects.$alias: project_id '$id' is already used by '$other' "
            '(both would write the same .env file)');
      } else {
        seenIds[id] = alias;
      }
    });
    return problems;
  }

  /// REQ-RULE-00040 and REQ-RULE-00080: path rules, files exist, CORS is a JSON
  /// array of objects, and the block is not empty.
  static List<String> validateRules(core.RulesConfig rules, String projectRoot) {
    final problems = <String>[];
    if (rules.firestore == null && rules.storage == null) {
      problems.add('firebase.rules: declare firestore, storage or both');
    }

    void checkFile(String key, String value, {bool corsJson = false}) {
      final pathProblem = FunctionsValidator.sourceProblemFor(value);
      if (pathProblem != null) {
        problems.add("$key: '$value' $pathProblem");
        return;
      }
      final file = File(p.normalize(p.join(projectRoot, value)));
      if (!file.existsSync()) {
        problems.add("$key: '$value' not found at ${file.path} "
            '(an uninitialised git submodule is a common cause)');
        return;
      }
      if (corsJson) {
        final problem = _corsProblem(file);
        if (problem != null) problems.add("$key: '$value' $problem");
      }
    }

    final fs = rules.firestore;
    if (fs != null) {
      checkFile('firebase.rules.firestore.source', fs.source);
      if (fs.indexes != null) checkFile('firebase.rules.firestore.indexes', fs.indexes!);
    }
    final st = rules.storage;
    if (st != null) {
      checkFile('firebase.rules.storage.source', st.source);
      if (st.cors != null) checkFile('firebase.rules.storage.cors', st.cors!, corsJson: true);
    }
    return problems;
  }

  /// Null when [file] holds a JSON array of objects (what `gcloud storage buckets
  /// update --cors-file` needs).
  static String? _corsProblem(File file) {
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      return 'is not valid JSON (${e.message})';
    }
    if (decoded is! List) return 'must be a JSON array of CORS objects, not a single object';
    if (decoded.any((e) => e is! Map)) return 'must be a JSON array of CORS objects';
    return null;
  }
}
