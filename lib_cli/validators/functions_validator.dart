import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// Semantic checks for the functions codebases (REQ-FUNC-00020,
/// REQ-FUNC-00070), over the resolved `firebase` view (REQ-RULE-00090). Structural unknown-key checks stay in the cores'
/// strict-mode checkers; this covers rules that need the whole block.
class FunctionsValidator {
  static final _driveLetter = RegExp(r'^[A-Za-z]:');

  /// Codebase checks over the resolved `firebase` view; one message per problem,
  /// empty when valid. Project checks live in [FirebaseValidator.validateProjects].
  static List<String> validate(core.ResolvedFirebase resolved) {
    final problems = <String>[];
    final fn = resolved.functions;
    if (fn == null) return problems;

    fn.codebases.forEach((name, codebase) {
      final sourceProblem = sourceProblemFor(codebase.source);
      if (sourceProblem != null) {
        problems.add("firebase.functions.codebases.$name: source '${codebase.source}' $sourceProblem");
      }
      for (final alias in codebase.projectParams.keys) {
        if (!resolved.projects.containsKey(alias)) {
          problems.add(
              "firebase.functions.codebases.$name.project_params: '$alias' is not declared under "
              'firebase.projects (declared: ${resolved.projects.keys.join(', ')})');
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
