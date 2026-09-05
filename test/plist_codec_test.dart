import 'package:test/test.dart';
import '../lib_cli/plist/plist_codec.dart';

void main() {
  group('PlistCodec.decode', () {
    test('decodes string, bool, array, and nested dict values', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Name</key>
	<string>Test App</string>
	<key>Enabled</key>
	<true/>
	<key>Disabled</key>
	<false/>
	<key>Orientations</key>
	<array>
		<string>Portrait</string>
		<string>Landscape</string>
	</array>
	<key>Nested</key>
	<dict>
		<key>Inner</key>
		<string>Value</string>
	</dict>
</dict>
</plist>
''';
      final decoded = PlistCodec.decode(xml);
      expect(decoded['Name'], 'Test App');
      expect(decoded['Enabled'], true);
      expect(decoded['Disabled'], false);
      expect(decoded['Orientations'], ['Portrait', 'Landscape']);
      expect(decoded['Nested'], {'Inner': 'Value'});
    });

    test('decodes integer and real values', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>Count</key>
	<integer>42</integer>
	<key>Ratio</key>
	<real>3.14</real>
</dict>
</plist>
''';
      final decoded = PlistCodec.decode(xml);
      expect(decoded['Count'], 42);
      expect(decoded['Ratio'], 3.14);
    });
  });

  group('PlistCodec.encode', () {
    test('produces valid Apple plist XML that round-trips through decode', () {
      final values = <String, dynamic>{
        'CFBundleDisplayName': r'$(APP_DISPLAY_NAME)',
        'HasFeatureX': true,
        'SupportedOrientations': ['Portrait', 'Landscape'],
        'Nested': {'Key': 'Value'},
      };
      final xml = PlistCodec.encode(values);
      expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<!DOCTYPE plist PUBLIC'));
      expect(xml, contains('<plist version="1.0">'));

      final redecoded = PlistCodec.decode(xml);
      expect(redecoded, values);
    });

    test('escapes special XML characters in string values', () {
      final values = <String, dynamic>{'Name': 'Tom & Jerry <Show>'};
      final xml = PlistCodec.encode(values);
      final redecoded = PlistCodec.decode(xml);
      expect(redecoded['Name'], 'Tom & Jerry <Show>');
    });

    test('escapes > alongside < and & in the raw XML output (ann-flavor-tooling#72)', () {
      final xml = PlistCodec.encode(<String, dynamic>{'thinning': '<none>'});
      expect(xml, contains('<string>&lt;none&gt;</string>'),
          reason: '> must be escaped to &gt; consistently with < → &lt;, '
              'matching Apple plist convention — a bare > left unescaped is '
              'valid XML but inconsistent with every other plist writer');
      expect(xml, isNot(contains('&lt;none>')),
          reason: 'the trailing > must not be left as a literal character');
    });
  });
}
