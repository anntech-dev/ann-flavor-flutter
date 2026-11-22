import '../model/ann_spec_model.dart';
import 'ann_spec_resolver.dart';

/// One flavor's resolved `links:` entry (REQ-LINK-00020).
class ResolvedLinksFlavor {
  final String? domain;
  final String? pathPrefix;
  final List<String> alsoHandles;
  /// Platforms the flavor exists on, in the fixed order android, ios, web.
  final List<String> platforms;
  final String? androidId;
  final String? iosBundleId;
  final String? teamId;
  /// Upper-case, sorted, unique; empty unless the flavor is an Android flavor.
  final List<String> sha256Fingerprints;
  final List<String> debugSha256Fingerprints;

  const ResolvedLinksFlavor({
    required this.domain,
    required this.pathPrefix,
    required this.alsoHandles,
    required this.platforms,
    required this.androidId,
    required this.iosBundleId,
    required this.teamId,
    required this.sha256Fingerprints,
    required this.debugSha256Fingerprints,
  });
}

/// The resolved `links:` block and its validation result (REQ-LINK-00020, -00070).
/// [errors] is empty when the block is valid; each entry is `<where>: <problem>`.
class ResolvedLinks {
  final String? serveFrom;
  final String? wellKnownDir;
  final Map<String, ResolvedLinksFlavor> flavors;
  final List<String> errors;

  const ResolvedLinks({
    this.serveFrom,
    this.wellKnownDir,
    this.flavors = const {},
    this.errors = const [],
  });
}

class LinksResolver {
  static final _domainRe =
      RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');
  static final _pathRe = RegExp(r'^/[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*$');
  static final _fingerprintRe = RegExp(r'^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$');
  static final _teamRe = RegExp(r'^[A-Z0-9]{10}$');

  static ResolvedLinks resolve(AnnSpec spec) {
    final cfg = spec.links;
    if (cfg == null) return const ResolvedLinks();

    final errors = <String>[];
    final serve = cfg.serveFrom;
    final dir = cfg.wellKnownDir;
    final d = cfg.defaults;

    final serveIsWebFlavor = serve != null && spec.flavorExistsOn('web', serve);
    if (serve != null && !serveIsWebFlavor) errors.add('serve_from: not a web flavor');
    if (serve != null && dir != null) errors.add('serve_from, well_known_dir: both set');

    if (d?.domain != null && !_domainRe.hasMatch(d!.domain!)) errors.add('default.domain: invalid');
    _checkFingerprints(errors, 'default.android.sha256_fingerprints', d?.android?.sha256Fingerprints ?? const []);
    _checkFingerprints(errors, 'default.android.debug_sha256_fingerprints', d?.android?.debugSha256Fingerprints ?? const []);
    final defaultTeam = d?.ios?.teamId;
    if (defaultTeam != null && !_teamRe.hasMatch(defaultTeam)) errors.add('default.ios.team_id: invalid');

    final names = cfg.flavors.keys.toList()..sort();
    final resolved = <String, ResolvedLinksFlavor>{};

    for (final name in names) {
      final f = cfg.flavors[name]!;
      final platforms = [
        for (final p in const ['android', 'ios', 'web'])
          if (spec.flavorExistsOn(p, name)) p,
      ];
      final onAndroid = platforms.contains('android');
      final onIos = platforms.contains('ios');

      final domain = f.domain ?? d?.domain;
      final fingerprints = onAndroid
          ? _union(d?.android?.sha256Fingerprints, f.android?.sha256Fingerprints)
          : const <String>[];
      final debugFingerprints = onAndroid
          ? _union(d?.android?.debugSha256Fingerprints, f.android?.debugSha256Fingerprints)
          : const <String>[];

      String? androidId;
      if (onAndroid) {
        final p = spec.app.android!;
        androidId = AnnSpecResolver.resolveAndroidFlavor(p.flavors[name]!, p.defaults, 'release').effectiveId;
      }
      String? iosBundleId;
      String? team;
      if (onIos) {
        final p = spec.app.ios!;
        final iosFlavor = p.flavors[name]!;
        iosBundleId = AnnSpecResolver.resolveIosFlavor(iosFlavor, p.defaults, 'release').effectiveId;
        team = f.ios?.teamId ??
            d?.ios?.teamId ??
            iosFlavor.credentials?.signing?.teamId ??
            p.defaults.credentials?.signing?.teamId;
      }

      resolved[name] = ResolvedLinksFlavor(
        domain: domain,
        pathPrefix: f.pathPrefix,
        alsoHandles: f.alsoHandles,
        platforms: platforms,
        androidId: androidId,
        iosBundleId: iosBundleId,
        teamId: team,
        sha256Fingerprints: fingerprints,
        debugSha256Fingerprints: debugFingerprints,
      );

      if (platforms.isEmpty) {
        errors.add('flavors.$name: unknown flavor');
        continue;
      }
      if (!onAndroid && !onIos) {
        errors.add('flavors.$name: no android or ios target');
        continue;
      }

      if (domain == null) {
        errors.add('flavors.$name.domain: missing');
      } else if (f.domain != null && !_domainRe.hasMatch(f.domain!)) {
        errors.add('flavors.$name.domain: invalid');
      }

      final prefix = f.pathPrefix;
      if (prefix == null) {
        errors.add('flavors.$name.path_prefix: missing');
      } else if (!_pathRe.hasMatch(prefix)) {
        errors.add('flavors.$name.path_prefix: invalid');
      }

      for (var i = 0; i < f.alsoHandles.length; i++) {
        final a = f.alsoHandles[i];
        final where = 'flavors.$name.also_handles[$i]';
        if (!_pathRe.hasMatch(a)) {
          errors.add('$where: invalid');
        } else if (a == prefix) {
          errors.add('$where: is own path_prefix');
        } else if (!names.any((g) => g != name &&
            cfg.flavors[g]!.pathPrefix == a &&
            (cfg.flavors[g]!.domain ?? d?.domain) == domain)) {
          errors.add('$where: not owned by another flavor');
        }
      }

      if (onAndroid) {
        _checkFingerprints(errors, 'flavors.$name.android.sha256_fingerprints', f.android?.sha256Fingerprints ?? const []);
        _checkFingerprints(errors, 'flavors.$name.android.debug_sha256_fingerprints', f.android?.debugSha256Fingerprints ?? const []);
        if (fingerprints.isEmpty) errors.add('flavors.$name.android.sha256_fingerprints: missing');
      }

      if (onIos) {
        final own = f.ios?.teamId;
        if (own != null && !_teamRe.hasMatch(own)) {
          errors.add('flavors.$name.ios.team_id: invalid');
        } else if (team == null && (serve != null || dir != null)) {
          errors.add('flavors.$name.ios.team_id: missing');
        } else if (team != null && own == null && d?.ios?.teamId == null &&
            (serve != null || dir != null) && !_teamRe.hasMatch(team)) {
          // taken from the iOS signing section and about to be written into the association file
          errors.add('flavors.$name.ios.team_id: invalid');
        }
      }
    }

    final checked = [
      for (final n in names)
        if (resolved[n]!.platforms.any((p) => p == 'android' || p == 'ios')) n,
    ];
    for (var i = 0; i < checked.length; i++) {
      for (var j = i + 1; j < checked.length; j++) {
        final a = resolved[checked[i]]!;
        final b = resolved[checked[j]]!;
        final shareNative = a.platforms.any((p) => (p == 'android' || p == 'ios') && b.platforms.contains(p));
        if (shareNative &&
            a.domain != null && a.domain == b.domain &&
            a.pathPrefix != null && _pathRe.hasMatch(a.pathPrefix!) &&
            b.pathPrefix != null && _pathRe.hasMatch(b.pathPrefix!) &&
            _overlaps(a.pathPrefix!, b.pathPrefix!)) {
          errors.add('flavors.${checked[j]}.path_prefix: overlaps flavors.${checked[i]}.path_prefix');
        }
      }
    }
    for (var i = 0; i < checked.length; i++) {
      for (var j = i + 1; j < checked.length; j++) {
        final a = resolved[checked[i]]!;
        final b = resolved[checked[j]]!;
        if (a.androidId != null && a.androidId == b.androidId) {
          errors.add('flavors.${checked[j]}.android: duplicate package ${b.androidId}');
        }
        if (a.iosBundleId != null && a.iosBundleId == b.iosBundleId) {
          errors.add('flavors.${checked[j]}.ios: duplicate bundle id ${b.iosBundleId}');
        }
      }
    }

    if (serveIsWebFlavor && !cfg.flavors.containsKey(serve)) {
      errors.add('serve_from: flavor has no links entry');
    }
    if (dir != null && cfg.flavors.isEmpty) errors.add('well_known_dir: no flavors');
    if (dir != null && {for (final n in checked) if (resolved[n]!.domain != null) resolved[n]!.domain}.length > 1) {
      errors.add('well_known_dir: flavors name more than one domain');
    }

    return ResolvedLinks(serveFrom: serve, wellKnownDir: dir, flavors: resolved, errors: errors);
  }

  static void _checkFingerprints(List<String> errors, String where, List<String> values) {
    for (var i = 0; i < values.length; i++) {
      if (!_fingerprintRe.hasMatch(values[i])) errors.add('$where[$i]: invalid');
    }
  }

  static List<String> _union(List<String>? a, List<String>? b) =>
      {...?a?.map((e) => e.toUpperCase()), ...?b?.map((e) => e.toUpperCase())}.toList()..sort();

  /// Whole-segment overlap: equal, or one is a path-segment prefix of the other.
  static bool _overlaps(String a, String b) =>
      a == b || a.startsWith('$b/') || b.startsWith('$a/');
}
