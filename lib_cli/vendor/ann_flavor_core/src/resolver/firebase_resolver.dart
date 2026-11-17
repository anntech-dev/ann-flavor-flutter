import '../model/ann_spec_model.dart';

/// The one view of everything Firebase in annspec.yaml (REQ-RULE-00090).
///
/// - [projects]: `firebase.projects` first, then legacy `functions.projects`
///   aliases not already present. For an alias in both, the `firebase.projects`
///   entry wins.
/// - [functions]: `firebase.functions` when present, otherwise the legacy
///   top-level `functions:` codebases (null when the legacy block has none).
/// - [deprecated]: deprecated forms in use: `functions`, `functions.projects`.
/// - [conflicts]: `functions` (both `firebase.functions` and a top-level
///   `functions:` are present) and `projects.<alias>` (the alias differs
///   between the two registries).
class ResolvedFirebase {
  final Map<String, FirebaseProject> projects;
  final FirebaseFunctions? functions;
  final RulesConfig? rules;
  final List<String> deprecated;
  final List<String> conflicts;

  const ResolvedFirebase({
    required this.projects,
    required this.functions,
    required this.rules,
    required this.deprecated,
    required this.conflicts,
  });
}

class FirebaseResolver {
  static ResolvedFirebase resolve(AnnSpec spec) {
    final block = spec.firebase;
    final legacy = spec.functions;
    final deprecated = <String>[];
    final conflicts = <String>[];

    final projects = <String, FirebaseProject>{...?block?.projects};

    if (legacy != null) deprecated.add('functions');
    if (legacy != null && legacy.projects.isNotEmpty)
      deprecated.add('functions.projects');
    for (final e
        in (legacy?.projects ?? const <String, FunctionsProject>{}).entries) {
      final existing = projects[e.key];
      if (existing == null) {
        projects[e.key] = FirebaseProject(
          projectId: e.value.projectId,
          serviceAccount: e.value.serviceAccount,
        );
      } else if (existing.projectId != e.value.projectId ||
          existing.serviceAccount != e.value.serviceAccount) {
        conflicts.add('projects.${e.key}');
      }
    }

    FirebaseFunctions? functions;
    if (block?.functions != null) {
      if (legacy != null) conflicts.insert(0, 'functions');
      functions = block!.functions;
    } else if (legacy != null && legacy.codebases.isNotEmpty) {
      functions = FirebaseFunctions(codebases: legacy.codebases);
    }

    return ResolvedFirebase(
      projects: projects,
      functions: functions,
      rules: block?.rules,
      deprecated: deprecated,
      conflicts: conflicts,
    );
  }
}
