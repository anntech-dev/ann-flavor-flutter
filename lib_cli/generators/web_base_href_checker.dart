import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// One finding of [WebBaseHrefChecker]: an error stops the build, a warning does not.
class WebBaseHrefFinding {
  final bool isError;
  final String path;
  final String message;
  final String? fix;
  const WebBaseHrefFinding.error(this.path, this.message, {this.fix}) : isError = true;
  const WebBaseHrefFinding.warning(this.path, this.message, {this.fix}) : isError = false;
}

/// REQ-WEB-00060: checks a web flavor that sets `base_href` before `flutter build web` does.
class WebBaseHrefChecker {
  /// Nothing for a flavor without `base_href` or with `/`. A value that breaks the rules is the
  /// only finding (the page and manifest checks mean nothing for it).
  static List<WebBaseHrefFinding> check(String projectRoot, String flavorKey, String? baseHref) {
    if (baseHref == null) return const [];
    final problem = core.AnnSpecResolver.webBaseHrefProblem(baseHref);
    if (problem != null) {
      return [WebBaseHrefFinding.error('app.web.flavor.$flavorKey.base_href', problem)];
    }
    if (baseHref == '/') return const [];

    return [
      ..._checkPage(projectRoot, flavorKey),
      ..._checkManifest(projectRoot, flavorKey, baseHref),
    ];
  }

  static String? _firstExisting(String projectRoot, List<String> relatives) {
    for (final r in relatives) {
      if (File(p.join(projectRoot, r)).existsSync()) return r;
    }
    return null;
  }

  static List<WebBaseHrefFinding> _checkPage(String projectRoot, String flavorKey) {
    final page = _firstExisting(projectRoot, [
      'web_flavors/$flavorKey/index.tmpl.html',
      'web_flavors/$flavorKey/index.html',
      'web/index.html',
    ]);
    if (page == null) return const [];
    if (File(p.join(projectRoot, page)).readAsStringSync().contains(r'$FLUTTER_BASE_HREF')) {
      return const [];
    }
    return [
      WebBaseHrefFinding.error(
        page,
        r'The page has no $FLUTTER_BASE_HREF, so "flutter build web --base-href" stops with '
        '"Couldn\'t find the placeholder for base href".',
        fix: r'Replace <base href="/"> with <base href="$FLUTTER_BASE_HREF"> in this file.',
      ),
    ];
  }

  static List<WebBaseHrefFinding> _checkManifest(String projectRoot, String flavorKey, String baseHref) {
    final manifest = _firstExisting(projectRoot, [
      'web_flavors/$flavorKey/manifest.tmpl.json',
      'web_flavors/$flavorKey/manifest.json',
      'web/manifest.json',
    ]);
    if (manifest == null) return const [];

    Object? json;
    try {
      json = jsonDecode(File(p.join(projectRoot, manifest)).readAsStringSync());
    } on FormatException {
      return const [];
    }
    if (json is! Map) return const [];

    final findings = <WebBaseHrefFinding>[];
    for (final key in const ['start_url', 'scope']) {
      final raw = json[key];
      if (raw is! String) continue;
      final value = raw.replaceAll('{{base_href}}', baseHref);
      if (value.startsWith('/') && !value.startsWith(baseHref)) {
        findings.add(WebBaseHrefFinding.warning(
          manifest,
          '"$key" is "$raw" but the flavor is served from "$baseHref": the installed app would '
          'open outside its path.',
          fix: 'Use  "$key": "{{base_href}}"',
        ));
      }
    }
    return findings;
  }
}
