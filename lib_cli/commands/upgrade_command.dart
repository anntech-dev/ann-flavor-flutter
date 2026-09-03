import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import '../spec/annspec_reader.dart';

class UpgradeCommand extends Command<void> {
  @override
  String get name => 'upgrade';

  @override
  String get description =>
      'Resolves latest plugin versions from their registries, '
      'updates tooling: in annspec.yaml, then runs sync spec.';

  UpgradeCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
  }

  @override
  Future<void> run() async {
    final root = argResults!['project'] as String;
    final specPath = _findSpecFile(root);
    if (specPath == null) {
      print('annspec.yaml not found in $root');
      return;
    }

    final spec = AnnspecReader.read(root);
    final tooling = spec.tooling;
    if (tooling == null) {
      print('ℹ  No tooling: section in annspec.yaml — nothing to upgrade.');
      return;
    }

    if (tooling.gradlePlugin != null) {
      await _resolveAndPatch(specPath, 'gradle_plugin',
          tooling.gradlePlugin!, _fetchMavenLatest);
    }
    if (tooling.cocoapodsPlugin != null) {
      await _resolveAndPatch(specPath, 'cocoapods_plugin',
          tooling.cocoapodsPlugin!, _fetchRubyGemsLatest);
    }
    if (tooling.fastlanePlugin != null) {
      await _resolveAndPatch(specPath, 'fastlane_plugin',
          tooling.fastlanePlugin!, _fetchRubyGemsLatest);
    }

    // Always run sync after upgrade so consumer files are up to date.
    print('\nRunning sync spec...');
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'ann_flutter_flavor', 'sync', '--project', root, '--silent'],
      workingDirectory: root,
    );
    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      exitCode = result.exitCode;
    }
  }

  Future<void> _resolveAndPatch(
    String specPath,
    String field,
    String constraint,
    Future<String?> Function(String) fetchLatest,
  ) async {
    if (!constraint.startsWith('^')) {
      // Exact pin — no network call needed.
      print('ℹ  $field: $constraint (exact pin — skipping registry)');
      return;
    }

    final base = constraint.substring(1); // strip '^'
    final gemOrArtifact = _artifactName(field);
    print('🔍 Resolving $field from registry...');

    String? latest;
    try {
      latest = await fetchLatest(gemOrArtifact);
    } catch (e) {
      print('⚠️  $field: registry error — $e. Leaving unchanged.');
      return;
    }

    if (latest == null) {
      print('⚠️  $field: could not determine latest version. Leaving unchanged.');
      return;
    }

    if (latest == base) {
      print('✓  $field: already at $base');
      return;
    }

    print('↑  $field: $base → $latest');
    _patchSpecField(specPath, field, '^$latest');
  }

  void _patchSpecField(String specPath, String field, String newValue) {
    final file = File(specPath);
    final lines = file.readAsLinesSync();
    final updated = lines.map((line) {
      // Match lines like "  gradle_plugin: ^2.3.6" or "  gradle_plugin: 2.3.6"
      final pattern = RegExp(r'^(\s*' + field + r'\s*:\s*)(.+)$');
      final m = pattern.firstMatch(line);
      if (m != null) return '${m.group(1)}$newValue';
      return line;
    }).toList();
    file.writeAsStringSync(updated.join('\n') + '\n');
  }

  String? _findSpecFile(String root) {
    final f = File('$root/annspec.yaml');
    return f.existsSync() ? f.path : null;
  }

  String _artifactName(String field) {
    switch (field) {
      case 'gradle_plugin':
        return 'flavorize'; // groupId:artifactId = dev.anntech.flavorize:flavorize
      case 'cocoapods_plugin':
        return 'ann-flavor-cocoapods';
      case 'fastlane_plugin':
        return 'ann-flavor-fastlane'; // published gem name (plan 040 — renamed
        // from the wrong "ann-flavor-flutter", which collided with the Dart
        // package name; "fastlane-plugin-*" is only the local directory convention)
      default:
        return field;
    }
  }

  Future<String> _httpGet(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      return await response.transform(const Utf8Decoder()).join();
    } finally {
      client.close();
    }
  }

  Future<String?> _fetchMavenLatest(String artifactId) async {
    // maven-metadata.xml is the authoritative "latest version" source for a
    // Maven Central artifact — search.maven.org's Solr search index can lag or
    // miss artifacts entirely and is not meant for exact-artifact lookups.
    final body = await _httpGet(
      'https://repo1.maven.org/maven2/dev/anntech/flavorize/$artifactId/maven-metadata.xml',
    );
    final match = RegExp(r'<latest>([^<]+)</latest>').firstMatch(body) ??
        RegExp(r'<release>([^<]+)</release>').firstMatch(body);
    return match?.group(1);
  }

  Future<String?> _fetchRubyGemsLatest(String gemName) async {
    final body = await _httpGet('https://rubygems.org/api/v1/gems/$gemName.json');
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['version'] as String?;
  }
}
