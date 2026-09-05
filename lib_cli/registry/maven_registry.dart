import 'dart:convert';
import 'dart:io';

/// Fetches the latest published version of a Maven Central artifact under
/// `dev.anntech.flavorize` from its `maven-metadata.xml` — the authoritative
/// "latest version" source for a Maven Central artifact (search.maven.org's
/// Solr search index can lag or miss artifacts entirely and is not meant for
/// exact-artifact lookups).
///
/// Throws on any network failure or missing version — callers that need a
/// non-throwing fallback should catch around this call, not inside it.
Future<String> fetchLatestMavenVersion(String artifactId) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(
      'https://repo1.maven.org/maven2/dev/anntech/flavorize/$artifactId/maven-metadata.xml',
    ));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception(
          'Maven Central returned HTTP ${response.statusCode} for $artifactId');
    }
    final body = await response.transform(const Utf8Decoder()).join();
    final match = RegExp(r'<latest>([^<]+)</latest>').firstMatch(body) ??
        RegExp(r'<release>([^<]+)</release>').firstMatch(body);
    if (match == null) {
      throw Exception(
          'Could not find a <latest>/<release> version for $artifactId in Maven Central metadata');
    }
    return match.group(1)!;
  } finally {
    client.close();
  }
}
