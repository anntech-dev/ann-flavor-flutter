import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

class LinksResult {
  /// Paths written or changed, relative to the project root.
  final List<String> written;
  final List<String> warnings;
  const LinksResult(this.written, this.warnings);
}

/// Writes the domain's `.well-known` files and the matching `_headers` block
/// (REQ-LINK-00060). Native settings are handled elsewhere (Android: the Gradle
/// plugin; iOS: [IosGenerator]).
///
/// Nothing is written unless `links.serve_from` (a web flavor's folder) or
/// `links.well_known_dir` (a site root) is set, so only the repository that serves a
/// domain ever writes its files.
class LinksGenerator {
  static const _begin = '# ann-flavor:links begin';
  static const _end = '# ann-flavor:links end';

  static LinksResult generate(core.AnnSpec spec, String projectRoot) {
    final links = core.AnnSpecResolver.resolveLinks(spec);
    if (links.errors.isNotEmpty) {
      throw StateError(links.errors.map((e) => '  - $e').join('\n'));
    }

    final target = _targetDir(links, projectRoot);
    final domain = _servedDomain(links);
    if (target == null || domain == null) return const LinksResult([], []);

    final onDomain = [
      for (final e in links.flavors.entries)
        if (e.value.domain == domain) e,
    ];
    final androids = [for (final e in onDomain) if (e.value.platforms.contains('android')) e.value]
      ..sort((a, b) => a.androidId!.compareTo(b.androidId!));
    final ioses = [for (final e in onDomain) if (e.value.platforms.contains('ios')) e.value]
      ..sort((a, b) => a.iosBundleId!.compareTo(b.iosBundleId!));

    final written = <String>[];
    final headerPaths = <String>[];
    final wellKnown = p.join(target, '.well-known');

    if (androids.isNotEmpty) {
      final statements = [
        for (final f in androids)
          {
            'relation': ['delegate_permission/common.handle_all_urls'],
            'target': {
              'namespace': 'android_app',
              'package_name': f.androidId,
              'sha256_cert_fingerprints': {...f.sha256Fingerprints, ...f.debugSha256Fingerprints}.toList()..sort(),
            },
          },
      ];
      if (_writeIfChanged(p.join(wellKnown, 'assetlinks.json'), _json(statements))) {
        written.add(p.relative(p.join(wellKnown, 'assetlinks.json'), from: projectRoot));
      }
      headerPaths.add('/.well-known/assetlinks.json');
    }

    if (ioses.isNotEmpty) {
      final details = [
        for (final f in ioses)
          {
            'appIDs': ['${f.teamId}.${f.iosBundleId}'],
            'components': [
              for (final prefix in [f.pathPrefix!, ...f.alsoHandles]) ...[
                {'/': prefix},
                {'/': '$prefix/*'},
              ],
            ],
          },
      ];
      final file = p.join(wellKnown, 'apple-app-site-association');
      if (_writeIfChanged(file, _json({'applinks': {'details': details}}))) {
        written.add(p.relative(file, from: projectRoot));
      }
      headerPaths.add('/.well-known/apple-app-site-association');
    }

    if (headerPaths.isNotEmpty) {
      final headers = p.join(target, '_headers');
      final existing = File(headers).existsSync() ? File(headers).readAsStringSync() : '';
      final updated = _withHeaderBlock(existing, headerPaths);
      if (updated != existing) {
        File(headers).parent.createSync(recursive: true);
        File(headers).writeAsStringSync(updated);
        written.add(p.relative(headers, from: projectRoot));
      }
    }

    return LinksResult(written, _redirectWarnings(target, projectRoot));
  }

  /// What `sync` tells the user about the Android side, or null when no flavor has an Android
  /// entry. The intent filter is not written by `sync`: the Gradle plugin patches each flavor's
  /// AndroidManifest.xml when Gradle configures the project (an Android build or an IDE Gradle sync).
  static String? androidNote(core.AnnSpec spec) {
    final links = core.AnnSpecResolver.resolveLinks(spec);
    final onAndroid = links.flavors.values.any((f) => f.platforms.contains('android'));
    if (!onAndroid) return null;
    return 'Android: the verified intent filter is written by the Gradle plugin at the next Android '
        'build or Gradle sync (android/app/src/<flavor>/AndroidManifest.xml), not by sync.';
  }

  /// Removes the marked `_headers` block (and nothing else) from [text]; used by `sync-web`
  /// so a flavor that does not serve the domain never inherits another flavor's block.
  static String stripHeaderBlock(String text) {
    final re = RegExp('\\n?${RegExp.escape(_begin)}[\\s\\S]*?${RegExp.escape(_end)}\\n?');
    return text.replaceFirst(re, '');
  }

  /// `serve_from` -> that web flavor's folder; `well_known_dir` -> that directory.
  static String? _targetDir(core.ResolvedLinks links, String projectRoot) {
    if (links.serveFrom != null) return p.join(projectRoot, 'web_flavors', links.serveFrom!);
    if (links.wellKnownDir != null) return p.normalize(p.join(projectRoot, links.wellKnownDir!));
    return null;
  }

  /// With `serve_from`, the served domain is that flavor's own; with `well_known_dir`
  /// the cores guarantee the flavors name a single domain.
  static String? _servedDomain(core.ResolvedLinks links) {
    if (links.serveFrom != null) return links.flavors[links.serveFrom!]?.domain;
    for (final f in links.flavors.values) {
      if (f.domain != null && f.platforms.any((p) => p == 'android' || p == 'ios')) return f.domain;
    }
    return null;
  }

  static String _json(Object value) => '${const JsonEncoder.withIndent('  ').convert(value)}\n';

  static bool _writeIfChanged(String path, String content) {
    final file = File(path);
    if (file.existsSync() && file.readAsStringSync() == content) return false;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return true;
  }

  /// Replaces the marked block, or appends it; text outside the block is never touched.
  static String _withHeaderBlock(String existing, List<String> paths) {
    final block = StringBuffer('$_begin\n');
    for (final path in paths) {
      block.write('$path\n  Content-Type: application/json\n');
    }
    block.write('$_end\n');

    final re = RegExp('${RegExp.escape(_begin)}[\\s\\S]*?${RegExp.escape(_end)}\\n?');
    if (re.hasMatch(existing)) return existing.replaceFirst(re, block.toString());
    if (existing.trim().isEmpty) return block.toString();
    return '${existing.endsWith('\n') ? existing : '$existing\n'}\n$block';
  }

  /// A catch-all rewrite may answer /.well-known/ with index.html. Whether the host lets a
  /// real static file win cannot be checked offline, so this is a warning, not an error.
  static List<String> _redirectWarnings(String target, String projectRoot) {
    final warnings = <String>[];
    for (final dir in {target, p.join(projectRoot, 'web')}) {
      final file = File(p.join(dir, '_redirects'));
      if (!file.existsSync()) continue;
      final catchAll = file.readAsLinesSync().any((l) {
        final t = l.trim();
        return t.isNotEmpty && !t.startsWith('#') && RegExp(r'^/\*\s+\S+\s+200\b').hasMatch(t);
      });
      if (catchAll) {
        warnings.add('${p.relative(file.path, from: projectRoot)} has a catch-all rewrite (/* ... 200); '
            'check that https://<domain>/.well-known/assetlinks.json is served as the real file after deploying');
      }
    }
    return warnings;
  }
}
