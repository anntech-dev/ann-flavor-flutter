import 'dart:io';
import 'package:path/path.dart' as p;

/// Scaffolds starter template files in web_flavors/<flavorKey>/.
class WebScaffoldGenerator {
  final String projectRoot;
  WebScaffoldGenerator(this.projectRoot);

  void scaffold(
    String flavorKey, {
    bool manifestTemplate = false,
    bool indexTemplate = false,
    bool bootstrapTemplate = false,
  }) {
    final dir = Directory('$projectRoot/web_flavors/$flavorKey');
    dir.createSync(recursive: true);
    Directory(p.join(dir.path, 'icons')).createSync(recursive: true);

    if (manifestTemplate) {
      final f = File(p.join(dir.path, 'manifest.tmpl.json'));
      if (!f.existsSync()) f.writeAsStringSync(_manifestTemplate);
    }

    if (bootstrapTemplate) {
      final f = File(p.join(dir.path, 'flutter_bootstrap.tmpl.js'));
      if (!f.existsSync()) f.writeAsStringSync(_bootstrapTemplate);
    }

    if (indexTemplate) {
      final f = File(p.join(dir.path, 'index.tmpl.html'));
      if (!f.existsSync()) f.writeAsStringSync(_indexTemplate);
    }
  }

  static const _manifestTemplate = '''{
  "name": "{{name}}",
  "short_name": "{{short_name}}",
  "id": "{{id}}",
  "start_url": "{{base_href}}",
  "scope": "{{base_href}}",
  "display": "standalone",
  "background_color": "{{background_color}}",
  "theme_color": "{{theme_color}}",
  "description": "{{name}}",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [
    {
      "src": "icons/Icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icons/Icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    },
    {
      "src": "icons/Icon-maskable-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "icons/Icon-maskable-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ]
}
''';

  // Flutter's own placeholders ({{flutter_js}}, {{flutter_build_config}},
  // {{flutter_service_worker_version}}) stay as written: sync-web renders only its own variables
  // and flutter build fills the rest. An empty canvasKitBaseUrl is ignored by the loader.
  static const _bootstrapTemplate = '''{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
  config: {
    canvasKitBaseUrl: "{{canvaskit_base_url}}"
  }
});
''';

  // Flutter's current page with the tooling's variables (REQ-WEB-00250). The page loads
  // flutter_bootstrap.js, which carries the build options of the flavor (canvaskit_base_url); it has no
  // service worker block and no flutter.js tag. Needs Flutter 3.22 or newer.
  static const _indexTemplate = '''<!DOCTYPE html>
<html>
<head>
  <base href="\$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="{{name}}">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="{{name}}">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png">
  <title>{{name}}</title>
  <link rel="manifest" href="manifest.json">
  <meta name="theme-color" content="{{theme_color}}">
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';
}
