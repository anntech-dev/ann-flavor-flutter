import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// Semantic checks for the top-level `functions:` block (REQ-FUNC-00020,
/// REQ-FUNC-00070). Structural unknown-key checks stay in the cores'
/// strict-mode checkers; this covers rules that need the whole block.
class FunctionsValidator {
  static final _driveLetter = RegExp(r'^[A-Za-z]:');

  /// Returns one message per problem; empty when the block is valid.
  static List<String> validate(core.FunctionsConfig fn) {
    final problems = <String>[];

    final seenIds = <String, String>{};
    fn.projects.forEach((alias, project) {
      final id = project.projectId?.trim() ?? '';
      if (id.isEmpty) {
        problems.add("functions.projects.$alias: project_id is missing or blank");
        return;
      }
      final other = seenIds[id];
      if (other != null) {
        problems.add(
            "functions.projects.$alias: project_id '$id' is already used by '$other' "
            '(both would write the same .env file)');
      } else {
        seenIds[id] = alias;
      }
    });

    fn.codebases.forEach((name, codebase) {
      final sourceProblem = sourceProblemFor(codebase.source);
      if (sourceProblem != null) {
        problems.add("functions.codebases.$name: source '${codebase.source}' $sourceProblem");
      }
      for (final alias in codebase.projectParams.keys) {
        if (!fn.projects.containsKey(alias)) {
          problems.add(
              "functions.codebases.$name.project_params: '$alias' is not declared under "
              'functions.projects (declared: ${fn.projects.keys.join(', ')})');
        }
      }
    });

    return problems;
  }

  /// Null when [source] is an acceptable relative path (REQ-FUNC-00020).
  static String? sourceProblemFor(String source) {
    final s = source.trim();
    if (s.isEmpty) return 'is blank';
    if (s.startsWith('/') || s.startsWith(r'\') || _driveLetter.hasMatch(s)) {
      return 'must be relative to annspec.yaml, not an absolute path';
    }
    if (s.contains(r'\')) return r'must use / as the path separator, not \';
    return null;
  }
}
