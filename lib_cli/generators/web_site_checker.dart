import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// One finding of [WebSiteChecker]. Every finding is an error: a site that breaks a rule cannot be
/// assembled.
class WebSiteFinding {
  final String path;
  final String message;
  final String? fix;
  const WebSiteFinding(this.path, this.message, {this.fix});
}

/// REQ-WEB-00160 and REQ-WEB-00180: checks the `app.web.site` blocks before anything is built.
class WebSiteChecker {
  /// The rule problems come from the core (`app.web.site.<name>.<field>: <problem>`, split at the
  /// first ": "). The file checks need the project folder: for a site with a usable `hub_dir`, the
  /// folder must exist, be a folder, and hold no entry named like the first segment of a flavor path.
  static List<WebSiteFinding> check(String projectRoot, core.WebPlatform web) {
    final findings = <WebSiteFinding>[];
    final problems = core.AnnSpecResolver.webSiteProblems(web);
    for (final problem in problems) {
      final i = problem.indexOf(': ');
      findings.add(i < 0
          ? WebSiteFinding('app.web.site', problem)
          : WebSiteFinding(problem.substring(0, i), problem.substring(i + 2)));
    }

    for (final site in core.AnnSpecResolver.resolveWebSites(web)) {
      final hub = site.hubDir;
      if (hub == null) continue;
      final hubPath = 'app.web.site.${site.name}.hub_dir';
      // a hub path the core already rejected (empty, absolute, "..") is not looked at on disk
      if (problems.any((q) => q.startsWith('$hubPath:'))) continue;

      final dir = Directory(p.join(projectRoot, hub));
      if (File(dir.path).existsSync()) {
        findings.add(WebSiteFinding(hubPath, '"$hub" is a file, not a folder.',
            fix: 'Point hub_dir at the folder that holds the hub page.'));
        continue;
      }
      if (!dir.existsSync()) {
        findings.add(WebSiteFinding(hubPath, '"$hub" does not exist.',
            fix:
                'Create the folder with the hub page (and _headers or _redirects), or remove hub_dir.'));
        continue;
      }

      final entries = {for (final e in dir.listSync()) p.basename(e.path)};
      for (final f in site.flavors) {
        final path = f.path;
        if (path == null || path == '/') continue;
        final first =
            path.split('/').firstWhere((s) => s.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty && entries.contains(first)) {
          findings.add(WebSiteFinding(
            hubPath,
            'The hub folder "$hub" holds "$first", which is where flavor "${f.key}" is served ($path).',
            fix:
                'Rename or move "$first" in the hub folder, or give the flavor another base_href.',
          ));
        }
      }
    }
    return findings;
  }
}
