import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// One finding of [WebIconChecker]. Every finding is a warning (REQ-WEB-00260).
class WebIconFinding {
  final String path;
  final String message;
  final String? fix;
  const WebIconFinding(this.path, this.message, {this.fix});
}

/// REQ-WEB-00260: the icon files a web flavor's manifest and page refer to must exist with exactly
/// that case. A case-sensitive host such as Cloudflare Pages answers 404 for a file of another case,
/// and a case-insensitive file system (a Mac) says "exists", so names are compared with a directory
/// listing, never with `File.exists`.
class WebIconChecker {
  static List<WebIconFinding> check(String projectRoot, String flavorKey) {
    final manifest = _firstExisting(projectRoot, [
      'web_flavors/$flavorKey/manifest.tmpl.json',
      'web_flavors/$flavorKey/manifest.json',
      'web/manifest.json',
    ]);
    final page = _firstExisting(projectRoot, [
      'web_flavors/$flavorKey/index.tmpl.html',
      'web_flavors/$flavorKey/index.html',
      'web/index.html',
    ]);
    // the flavor folder first, then web/ (what sync-web copies into and Flutter serves)
    final roots = ['web_flavors/$flavorKey', 'web'];

    final findings = <WebIconFinding>[];
    if (manifest != null) {
      findings.addAll(_checkDocument(projectRoot, roots, manifest,
          _manifestReferences(projectRoot, manifest)));
    }
    if (page != null) {
      findings.addAll(_checkDocument(
          projectRoot, roots, page, _pageReferences(projectRoot, page)));
    }
    return findings;
  }

  static String? _firstExisting(String projectRoot, List<String> relatives) {
    for (final r in relatives) {
      if (File(p.join(projectRoot, r)).existsSync()) return r;
    }
    return null;
  }

  static List<String> _manifestReferences(String projectRoot, String manifest) {
    try {
      final json =
          jsonDecode(File(p.join(projectRoot, manifest)).readAsStringSync());
      if (json is! Map || json['icons'] is! List) return const [];
      return [
        for (final i in json['icons'] as List)
          if (i is Map && i['src'] is String) i['src'] as String,
      ];
    } on FormatException {
      return const [];
    }
  }

  static List<String> _pageReferences(String projectRoot, String page) {
    final html = File(p.join(projectRoot, page))
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final refs = <String>[];
    for (final tag
        in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final text = tag.group(0)!;
      final rel = _attribute(text, 'rel');
      final href = _attribute(text, 'href');
      if (rel == null || href == null) continue;
      final isIcon = rel.toLowerCase().split(RegExp(r'\s+')).any((t) =>
          t == 'icon' || t.endsWith('-icon') || t.endsWith('icon-precomposed'));
      if (isIcon) refs.add(href);
    }
    return refs;
  }

  static String? _attribute(String tag, String name) {
    final m = RegExp('\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
            caseSensitive: false)
        .firstMatch(tag);
    return m == null ? null : (m.group(1) ?? m.group(2) ?? m.group(3));
  }

  static List<WebIconFinding> _checkDocument(String projectRoot,
      List<String> roots, String document, List<String> references) {
    final findings = <WebIconFinding>[];
    final seen = <String>{};
    for (final raw in references) {
      if (!seen.add(raw)) continue;
      final ref = _relativeReference(raw);
      if (ref == null) continue;
      final result = _resolve(projectRoot, roots, ref);
      if (result.found) continue;
      if (result.nearMatch != null) {
        findings.add(WebIconFinding(
          document,
          '"$ref" does not exist with that case; "${result.nearMatch}" does. A case-sensitive host '
          'such as Cloudflare Pages answers 404 for "$ref".',
          fix:
              'Change the reference to "${_withoutRoot(result.nearMatch!, roots)}" '
              'in $document, or rename the file.',
        ));
      } else {
        findings.add(WebIconFinding(
          document,
          '"$ref" is not in ${roots.map((r) => '$r/').join(' or ')}.',
          fix:
              'Run "dart run ann_flutter_flavor generate-icons --platform web", or correct the name.',
        ));
      }
    }
    return findings;
  }

  /// `web_flavors/a/icons/Icon-192.png` -> `icons/Icon-192.png`: the reference as the page writes it.
  static String _withoutRoot(String path, List<String> roots) {
    for (final r in roots) {
      if (path.startsWith('$r/')) return path.substring(r.length + 1);
    }
    return path;
  }

  /// The path to look for, or null for a reference that is not checked: an absolute URL, a `data:`
  /// URI, a root-absolute path, one with a variable, or one that climbs out of its folder.
  static String? _relativeReference(String raw) {
    var ref = raw.trim();
    if (ref.isEmpty) return null;
    if (ref.contains('{{') || ref.contains(r'$')) return null;
    if (RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(ref) ||
        ref.startsWith('//') ||
        ref.startsWith('/')) return null;
    ref = ref.split('?').first.split('#').first;
    while (ref.startsWith('./')) {
      ref = ref.substring(2);
    }
    if (ref.isEmpty || ref.split('/').contains('..')) return null;
    return ref;
  }

  static _Resolution _resolve(
      String projectRoot, List<String> roots, String ref) {
    final segments =
        ref.split('/').where((s) => s.isNotEmpty && s != '.').toList();
    String? near;
    for (final root in roots) {
      final result =
          _walk(Directory(p.join(projectRoot, root)), segments, root);
      if (result.found) return result;
      near ??= result.nearMatch;
    }
    return _Resolution(false, near);
  }

  // Walks the segments through directory listings: an exact name continues, a name that differs only in
  // case is remembered as the near match (and followed, to report the rest of the path), anything else stops.
  static _Resolution _walk(
      Directory start, List<String> segments, String rootLabel) {
    var dir = start;
    final shown = <String>[rootLabel];
    var exact = true;
    for (var i = 0; i < segments.length; i++) {
      if (!dir.existsSync()) return const _Resolution(false, null);
      final names = {for (final e in dir.listSync()) p.basename(e.path)};
      final want = segments[i];
      String? actual;
      if (names.contains(want)) {
        actual = want;
      } else {
        for (final n in names) {
          if (n.toLowerCase() == want.toLowerCase()) {
            actual = n;
            exact = false;
            break;
          }
        }
      }
      if (actual == null) return const _Resolution(false, null);
      shown.add(actual);
      if (i == segments.length - 1) {
        return exact
            ? const _Resolution(true, null)
            : _Resolution(false, shown.join('/'));
      }
      dir = Directory(p.join(dir.path, actual));
    }
    return const _Resolution(false, null);
  }
}

class _Resolution {
  final bool found;
  final String? nearMatch;
  const _Resolution(this.found, this.nearMatch);
}
