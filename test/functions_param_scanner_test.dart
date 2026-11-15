import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/functions_param_scanner.dart';

void main() {
  group('FunctionsParamScanner.scanSource', () {
    test('finds required params in double, single and backtick quotes', () {
      final scan = FunctionsParamScanner.scanSource('''
const a = defineString("RC_PROJECT_ID");
const b = defineInt('RETRIES');
const c = defineBoolean(`FEATURE_ON`);
const d = defineFloat("RATIO");
const e = defineList("IDS");
''');
      expect(scan.required, {'RC_PROJECT_ID', 'RETRIES', 'FEATURE_ON', 'RATIO', 'IDS'});
      expect(scan.optional, isEmpty);
      expect(scan.unchecked, 0);
    });

    test('a default option makes the param optional', () {
      final scan = FunctionsParamScanner.scanSource('''
const a = defineString("A", { default: "x" });
const b = defineString("B", {
  description: "needs a value",
  default: foo(1, 2),
});
const c = defineString("C", { description: "no default" });
''');
      expect(scan.optional, {'A', 'B'});
      expect(scan.required, {'C'});
    });

    test('the word default inside a string does not make a param optional', () {
      final scan = FunctionsParamScanner.scanSource(
          'defineString("A", { description: "falls back to default: none" });');
      expect(scan.required, {'A'});
      expect(scan.optional, isEmpty);
    });

    test('works on TypeScript with a module-qualified call', () {
      final scan = FunctionsParamScanner.scanSource('''
import * as params from "firebase-functions/params";
export const mailEndpoint = params.defineString("MAIL_ENDPOINT");
''');
      expect(scan.required, {'MAIL_ENDPOINT'});
    });

    test('ignores commented-out declarations', () {
      final scan = FunctionsParamScanner.scanSource('''
// const a = defineString("LINE_COMMENT");
/* const b = defineString("BLOCK_COMMENT"); */
const c = defineString("REAL");
''');
      expect(scan.required, {'REAL'});
    });

    test('a // inside a string is not treated as a comment', () {
      final scan = FunctionsParamScanner.scanSource('''
const url = "https://example.com/x"; const a = defineString("AFTER_URL");
''');
      expect(scan.required, {'AFTER_URL'});
    });

    test('defineSecret and defineJsonSecret go to secrets, not required', () {
      final scan = FunctionsParamScanner.scanSource('''
defineSecret("API_KEY");
defineJsonSecret("SA_JSON");
''');
      expect(scan.secrets, {'API_KEY', 'SA_JSON'});
      expect(scan.required, isEmpty);
    });

    test('non-literal names are counted as unchecked', () {
      final scan = FunctionsParamScanner.scanSource(r'''
defineString(name);
defineString(`PREFIX_${suffix}`);
defineString("OK");
''');
      expect(scan.unchecked, 2);
      expect(scan.required, {'OK'});
    });

    test('a name declared twice is required if any declaration has no default', () {
      final scan = FunctionsParamScanner.scanSource('''
defineString("A", { default: "x" });
defineString("A");
''');
      expect(scan.required, {'A'});
      expect(scan.optional, isEmpty);
    });

    test('does not match look-alike function names', () {
      final scan = FunctionsParamScanner.scanSource('myDefineString("NOPE"); defineStringX("NOPE2");');
      expect(scan.foundAnything, isFalse);
    });
  });

  group('FunctionsParamScanner.scan (directory)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fn_scan_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void write(String rel, String content) {
      final f = File('${dir.path}/$rel')..createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    test('reads .js and .ts files recursively; skips node_modules, .d.ts and other files', () {
      write('index.js', 'defineString("FROM_JS");');
      write('src/mail.ts', 'defineString("FROM_TS");');
      write('node_modules/dep/index.js', 'defineString("FROM_DEP");');
      write('types.d.ts', 'defineString("FROM_DTS");');
      write('notes.md', 'defineString("FROM_MD");');
      final scan = FunctionsParamScanner.scan(dir);
      expect(scan.required, {'FROM_JS', 'FROM_TS'});
    });

    test('a required declaration in one file wins over optional in another', () {
      write('a.js', 'defineString("X", { default: "d" });');
      write('b.js', 'defineString("X");');
      final scan = FunctionsParamScanner.scan(dir);
      expect(scan.required, {'X'});
      expect(scan.optional, isEmpty);
    });
  });
}
