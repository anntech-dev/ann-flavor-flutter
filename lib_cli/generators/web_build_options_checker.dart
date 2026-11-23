import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// One finding of [WebBuildOptionsChecker]: an error stops the build, a warning does not.
class WebBuildOptionsFinding {
  final bool isError;
  final String path;
  final String message;
  final String? fix;
  const WebBuildOptionsFinding.error(this.path, this.message, {this.fix})
      : isError = true;
  const WebBuildOptionsFinding.warning(this.path, this.message, {this.fix})
      : isError = false;
}

/// REQ-WEB-00130: checks the `build:` options of one web flavor before `flutter build web` runs.
class WebBuildOptionsChecker {
  /// Value problems (errors) come from the core, for the flavor's own block and, for a field the
  /// flavor inherits, the web default's block. A flavor with a value problem gets no further
  /// check. Otherwise a warning when a `canvaskit_base_url` resolves but no template of the flavor
  /// uses `{{canvaskit_base_url}}`, because the setting would do nothing.
  static List<WebBuildOptionsFinding> check(
      String projectRoot, String flavorKey, core.WebPlatform web) {
    final flavor = web.flavors[flavorKey];
    if (flavor == null) return const [];

    final findings = <WebBuildOptionsFinding>[];
    final own = core.AnnSpecResolver.webBuildProblems(flavor.build);
    final inherited = core.AnnSpecResolver.webBuildProblems(web.defaults.build);
    for (final e in own.entries) {
      findings.add(WebBuildOptionsFinding.error(
          'app.web.flavor.$flavorKey.build.${e.key}', e.value));
    }
    for (final e in inherited.entries) {
      if (own.containsKey(e.key)) continue;
      final overridden = e.key == 'pwa_strategy'
          ? flavor.build?.pwaStrategy != null
          : flavor.build?.canvaskitBaseUrl != null;
      if (!overridden) {
        findings.add(WebBuildOptionsFinding.error(
            'app.web.default.build.${e.key}', e.value));
      }
    }
    if (findings.isNotEmpty) return findings;

    final resolved =
        core.AnnSpecResolver.resolveWebBuildOptions(flavor, web.defaults);
    if (resolved.canvaskitBaseUrl != null &&
        !_templatesUseVariable(projectRoot, flavorKey)) {
      findings.add(WebBuildOptionsFinding.warning(
        'app.web.flavor.$flavorKey.build.canvaskit_base_url',
        'canvaskit_base_url is "${resolved.canvaskitBaseUrl}" but no template in web_flavors/$flavorKey/ '
            'uses {{canvaskit_base_url}}, so the page does not load CanvasKit from it.',
        fix:
            'Run "sync-web --flavor $flavorKey --scaffold-bootstrap", or add {{canvaskit_base_url}} '
            'to the flavor\'s flutter_bootstrap.tmpl.js.',
      ));
    }
    if (resolved.canvaskitBaseUrl != null) {
      final page = _firstExisting(projectRoot, [
        'web_flavors/$flavorKey/index.tmpl.html',
        'web_flavors/$flavorKey/index.html',
        'web/index.html',
      ]);
      if (page != null &&
          !_loadsBootstrap(
              File(p.join(projectRoot, page)).readAsStringSync())) {
        findings.add(WebBuildOptionsFinding.warning(
          'app.web.flavor.$flavorKey.build.canvaskit_base_url',
          'canvaskit_base_url is "${resolved.canvaskitBaseUrl}" but the page $page does not load '
              'flutter_bootstrap.js, the file that carries it, so the setting has no effect.',
          fix:
              'Use the page that "sync-web --flavor $flavorKey --scaffold-index" writes, or add '
              '<script src="flutter_bootstrap.js" async></script> to the page.',
        ));
      }
    }
    return findings;
  }

  static String? _firstExisting(String projectRoot, List<String> relatives) {
    for (final r in relatives) {
      if (File(p.join(projectRoot, r)).existsSync()) return r;
    }
    return null;
  }

  /// A `<script>` whose `src` is `flutter_bootstrap.js`; a tag inside an HTML comment does not count.
  static bool _loadsBootstrap(String html) {
    final live = html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    return RegExp(
      r'''<script\b[^>]*\bsrc\s*=\s*["']?(?:\./)?flutter_bootstrap\.js["']?[\s>/]''',
      caseSensitive: false,
    ).hasMatch(live);
  }

  static bool _templatesUseVariable(String projectRoot, String flavorKey) {
    final dir = Directory(p.join(projectRoot, 'web_flavors', flavorKey));
    if (!dir.existsSync()) return false;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!p.basename(f.path).contains('.tmpl.')) continue;
      if (f.readAsStringSync().contains('{{canvaskit_base_url}}')) return true;
    }
    return false;
  }
}
