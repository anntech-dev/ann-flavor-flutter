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
  }) {
    final dir = Directory('$projectRoot/web_flavors/$flavorKey');
    dir.createSync(recursive: true);
    Directory(p.join(dir.path, 'icons')).createSync(recursive: true);

    if (manifestTemplate) {
      final f = File(p.join(dir.path, 'manifest.tmpl.json'));
      if (!f.existsSync()) f.writeAsStringSync(_manifestTemplate);
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
  "start_url": ".",
  "display": "standalone",
  "background_color": "{{background_color}}",
  "theme_color": "{{theme_color}}",
  "description": "{{name}}",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [
    {
      "src": "icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    },
    {
      "src": "icons/icon-192-maskable.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "icons/icon-512-maskable.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ]
}
''';

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
  <link rel="apple-touch-icon" href="icons/icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png">
  <title>{{name}}</title>
  <link rel="manifest" href="manifest.json">
  <meta name="theme-color" content="{{theme_color}}">
  <script>
    // The value below is injected by flutter build, do not touch.
    const serviceWorkerVersion = null;
  </script>
  <script src="flutter.js" defer></script>
</head>
<body>
  <script>
    window.addEventListener('load', function(ev) {
      _flutter.loader.loadEntrypoint({
        serviceWorker: {
          serviceWorkerVersion: serviceWorkerVersion,
        }
      }).then(function(engineInitializer) {
        return engineInitializer.initializeEngine();
      }).then(function(appRunner) {
        return appRunner.runApp();
      });
    });
  </script>
</body>
</html>
''';
}
