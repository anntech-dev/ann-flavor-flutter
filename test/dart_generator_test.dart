import 'dart:io';
import 'package:test/test.dart';

// Package root is one level up from the test/ directory.
final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _runSync(Directory projectDir) {
  return Process.run(
    'dart',
    ['run', 'ann_flutter_flavor', 'sync', '--project', projectDir.path,
     '--firebase-mode', 'script'],
    workingDirectory: _packageRoot,
  );
}

String _readGenerated(Directory dir) =>
    File('${dir.path}/lib/generated/ann_flavor.g.dart').readAsStringSync();

// Spec with firebase project_id on android (release + debug) and auth on android + iOS.
void _writeFirebaseAndAuthSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    firebase: true
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
        build_types:
          release:
            firebase:
              project_id: "my-project-prod"
            auth:
              clientId: "release-android-client"
          debug:
            firebase:
              project_id: "my-project-dev"
            auth:
              clientId: "debug-android-client"
  ios:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
        build_types:
          release:
            auth:
              clientId: "release-ios-client"
          debug:
            auth:
              clientId: "debug-ios-client"
''');
}

// Spec with no firebase integration — firebase helpers must not be generated.
void _writeNoFirebaseSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
  ios:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
''');
}

void main() {
  group('dart_generator — firebaseOptionsFor API', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_firebase_test_');
      _writeFirebaseAndAuthSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('firebaseOptionsFor override is generated on the flavor config class', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains(
          '@override FirebaseOptions? firebaseOptionsFor([AnnPlatform? platform, String? buildType])'));
    });

    test('no separate _XFirebase delegate class is generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('class _MyappFirebase')));
      expect(content, isNot(contains('static FirebaseOptions? optionsRelease')));
    });

    test('top-level flavorFirebaseOptions()/Release()/Debug() are no longer generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('flavorFirebaseOptions')));
    });

    test('exhaustive AnnPlatform switch — all four arms generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final methodStart = content.indexOf('firebaseOptionsFor([AnnPlatform? platform, String? buildType])');
      expect(methodStart, greaterThan(-1), reason: 'firebaseOptionsFor not found');
      final methodBody = content.substring(methodStart);
      expect(methodBody, contains('case AnnPlatform.android:'));
      expect(methodBody, contains('case AnnPlatform.ios:'));
      expect(methodBody, contains('case AnnPlatform.web:'));
      expect(methodBody, contains('case AnnPlatform.windows:'));
    });

    test('firebaseOptionsFor throws StateError for a flavor with no entry under that platform', () async {
      // _writeFirebaseAndAuthSpec has no app.web / app.windows section at all
      // — 'myapp' has no entry under either.
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains(
          "case AnnPlatform.web:\n        throw StateError(\n          \"'myapp'.firebaseOptionsFor(AnnPlatform.web, \$buildType): this flavor has no entry under app.web.flavor in annspec.yaml.\","));
    });
  });

  group('dart_generator — no firebase helpers when firebase not configured', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_nofb_test_');
      _writeNoFirebaseSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('firebaseOptionsFor not generated when firebase disabled', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('firebaseOptionsFor')));
    });

    test('flavorFirebaseOptions* top-level functions not generated when firebase disabled', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('flavorFirebaseOptions')));
    });
  });

  group('dart_generator — authFor API', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_auth_test_');
      _writeFirebaseAndAuthSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('authFor override is generated in flavor config class', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('@override AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType])'));
    });

    test('authFor resolves distinct release/debug client IDs per platform', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains("clientId: 'release-android-client'"));
      expect(content, contains("clientId: 'debug-android-client'"));
      expect(content, contains("clientId: 'release-ios-client'"));
      expect(content, contains("clientId: 'debug-ios-client'"));
    });

    test('exhaustive AnnPlatform switch in authFor — all four arms generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final methodStart = content.indexOf('authFor([AnnPlatform? platform, String? buildType])');
      expect(methodStart, greaterThan(-1), reason: 'authFor not found');
      final methodEnd = content.indexOf('\n  }\n\n', methodStart);
      final methodBody = methodEnd > methodStart
          ? content.substring(methodStart, methodEnd)
          : content.substring(methodStart);
      expect(methodBody, contains('case AnnPlatform.android:'));
      expect(methodBody, contains('case AnnPlatform.ios:'));
      expect(methodBody, contains('case AnnPlatform.web:\n        throw StateError('));
      expect(methodBody, contains('case AnnPlatform.windows:\n        throw StateError('));
    });
  });

  group('dart_generator — web/windows default auth from platform default', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_webauth_test_');
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
  ios:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
  web:
    default:
      id: com.example.test
      build_types:
        release:
          auth:
            clientId: "web-release-client-id"
        debug:
          auth:
            clientId: "web-debug-client-id"
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('authFor(platform, "release") emits web clientId from web.default.build_types', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains("case 'release': return AnnAuthConfig("));
      expect(content, contains("clientId: 'web-release-client-id'"));
    });

    test('authFor(platform, "debug") emits web clientId from web.default.build_types', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains("clientId: 'web-debug-client-id'"));
    });

    test('android/ios auth is null when not configured — no bleed from web default', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final methodStart = content.indexOf('authFor([AnnPlatform? platform, String? buildType])');
      // android and ios both resolve to no auth data at all, so their
      // identical nested switches are grouped into one case pattern.
      final androidStart = content.indexOf(
          'case AnnPlatform.android || AnnPlatform.ios:', methodStart);
      expect(androidStart, greaterThan(-1));
      final androidEnd = content.indexOf('case AnnPlatform.web:', androidStart);
      final androidBody = content.substring(androidStart, androidEnd);
      expect(androidBody, contains("case 'release': return null;"));
      expect(androidBody, contains("case 'debug': return null;"));
    });

    test('windows throws StateError — this flavor has no entry under app.windows.flavor', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains(
          "case AnnPlatform.windows:\n        throw StateError(\n          \"'myapp'.authFor(AnnPlatform.windows, \$buildType): this flavor has no entry under app.windows.flavor in annspec.yaml.\","));
    });
  });

  group('dart_generator — web/windows firebase imports', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_webwin_firebase_test_');
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    firebase: true
  web:
    default:
      id: com.example.test
      build_types:
        release:
          firebase:
            project_id: "my-project-prod"
        debug:
          firebase:
            project_id: "my-project-dev"
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  windows:
    default:
      id: com.example.test
      build_types:
        release:
          firebase:
            project_id: "my-project-prod"
        debug:
          firebase:
            project_id: "my-project-dev"
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    // Regression test: AnnspecReader's _mapWeb/_mapWebFlavor and
    // _mapWindows/_mapWindowsFlavor never wired firebaseRelease/firebaseDebug
    // through from the core-parsed spec, so dart_generator's import-collection
    // loop (flavor.firebaseRelease ?? platform?.defaultFirebaseRelease) always
    // evaluated to null for web/windows — silently dropping the
    // *_firebase_options.dart imports even when firebase.project_id was set.
    test('web release/debug firebase_options imports are generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains(
          "import './firebase/myapp_release_web_firebase_options.dart' as myappreleaseweb;"));
      expect(content, contains(
          "import './firebase/myapp_debug_web_firebase_options.dart' as myappdebugweb;"));
    });

    test('windows release/debug firebase_options imports are generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains(
          "import './firebase/myapp_release_windows_firebase_options.dart' as myappreleasewindows;"));
      expect(content, contains(
          "import './firebase/myapp_debug_windows_firebase_options.dart' as myappdebugwindows;"));
    });
  });

  group('dart_generator — custom() profile build type', () {
    late Directory tempDir;

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // Regression test: the 'profile' build type resolves for every custom
    // group (AnnSpecResolver.standardBuildTypes includes it), but when no
    // explicit `profile:` override exists in annspec.yaml, its resolved
    // value is identical to release's — a dedicated 'profile' case must not
    // be emitted; at runtime it should fall through to the release data.
    test('no explicit profile override — no profile case emitted, matches release', () async {
      tempDir = Directory.systemTemp.createTempSync('dartgen_custom_noprofile_test_');
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
        custom:
          revenuecat:
            api_key: "release-key"
''');
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('@override AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType])'));
      expect(content, isNot(contains("'profile' =>")));
      expect(content, contains("'release' => AnnCustomGroup({'api_key': 'release-key'})"));
    });

    // When a flavor DOES configure a distinct `profile:` build_types block,
    // its data must be preserved and reachable — not discarded by the
    // release-fallback optimization above.
    test('explicit profile override — profile case is emitted with its own data', () async {
      tempDir = Directory.systemTemp.createTempSync('dartgen_custom_profile_test_');
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
        build_types:
          release:
            custom:
              revenuecat:
                api_key: "release-key"
          profile:
            custom:
              revenuecat:
                api_key: "profile-only-key"
''');
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains("'profile' => AnnCustomGroup({'api_key': 'profile-only-key'})"));
      expect(content, contains("'release' => AnnCustomGroup({'api_key': 'release-key'})"));
    });
  });

  group('dart_generator — existsOn', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_existson_test_');
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      ledger_in:
        name: "Ledger In"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  ios:
    default:
      id: com.example.test
    flavor:
      ledger_in:
        name: "Ledger In"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  web:
    default:
      id: com.example.test
    flavor:
      ledger_in:
        name: "Ledger In"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
      ledger_admin:
        name: "Admin Console"
        main_file: "lib/main_admin.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('a web-only flavor reports false for android/ios/windows, true for web', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerAdminConfig');
      expect(classStart, greaterThan(-1), reason: '_LedgerAdminConfig class not found');
      final classBody = content.substring(classStart);
      // android/ios/windows all resolve to the same false — grouped into
      // one case pattern.
      expect(classBody, contains(
          'case AnnPlatform.android || AnnPlatform.ios || AnnPlatform.windows:\n        return false;'));
      expect(classBody, contains('case AnnPlatform.web:\n        return true;'));
    });

    test('ledger_in exists on android/ios/web (grouped), not on windows (no app.windows section at all)', () async {
      // This fixture defines no app.windows section, so ledger_in — despite
      // being configured on every platform the app actually has — is
      // correctly absent from windows specifically.
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerInConfig');
      expect(classStart, greaterThan(-1), reason: '_LedgerInConfig class not found');
      final existsOnStart = content.indexOf('existsOn([AnnPlatform? platform])', classStart);
      final existsOnEnd = content.indexOf('nameFor([AnnPlatform? platform])', existsOnStart);
      final existsOnBody = content.substring(existsOnStart, existsOnEnd);
      expect(existsOnBody, contains(
          'case AnnPlatform.android || AnnPlatform.ios || AnnPlatform.web:\n        return true;'));
      expect(existsOnBody, contains('case AnnPlatform.windows:\n        return false;'));
    });

    test('existsOn never emits a throw arm, unlike nameFor/idFor/etc.', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerAdminConfig');
      final existsOnStart = content.indexOf('existsOn([AnnPlatform? platform])', classStart);
      final existsOnEnd = content.indexOf('nameFor([AnnPlatform? platform])', existsOnStart);
      final existsOnBody = content.substring(existsOnStart, existsOnEnd);
      expect(existsOnBody, isNot(contains('throw StateError')));
    });

    test('a flavor present on all four platforms collapses existsOn to a bare return true', () async {
      final fullDir = Directory.systemTemp.createTempSync('dartgen_existson_full_test_');
      addTearDown(() => fullDir.deleteSync(recursive: true));
      File('${fullDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  ios:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  web:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  windows:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
      final result = await _runSync(fullDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(fullDir);
      final existsOnStart = content.indexOf('existsOn([AnnPlatform? platform])');
      final existsOnEnd = content.indexOf('nameFor([AnnPlatform? platform])', existsOnStart);
      final existsOnBody = content.substring(existsOnStart, existsOnEnd);
      expect(existsOnBody, contains('return true;'));
      expect(existsOnBody, isNot(contains('switch')));
    });
  });

  group('dart_generator — nameFor/idFor throw for a flavor absent from a platform (ledger_admin regression)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_webonly_test_');
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      ledger_in:
        name: "Ledger In"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  ios:
    default:
      id: com.example.test
    flavor:
      ledger_in:
        name: "Ledger In"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  web:
    default:
      id: com.example.test
    flavor:
      ledger_in:
        name: "Ledger In"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
      ledger_admin:
        name: "Admin Console"
        main_file: "lib/main_admin.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    // Regression test for the bug found while diagnosing a real ledger
    // diff: a web-only flavor's name was previously invisible to name
    // resolution (which only ever consulted android/ios), silently falling
    // back to the raw flavor key even though a real name was configured.
    test('nameFor(web) resolves the configured name for a flavor with no android/ios entry', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerAdminConfig');
      expect(classStart, greaterThan(-1), reason: '_LedgerAdminConfig class not found');
      final classBody = content.substring(classStart);
      expect(classBody, contains("case AnnPlatform.web:\n        return 'Admin Console';"));
    });

    // Design decision (confirmed with the user): querying a platform this
    // flavor has no entry under is always a throw — regardless of whether
    // the platform itself is otherwise configured for the app. null is
    // reserved only for "flavor exists here, but this specific field isn't
    // set" (e.g. auth/firebase/custom groups). android and ios both exist
    // as app platforms here, but ledger_admin has no entry under either —
    // so both throw, same as windows (which the app has no section for at
    // all).
    test('nameFor(android)/nameFor(ios) throw — this flavor has no entry under either platform', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerAdminConfig');
      final nameForStart = content.indexOf('nameFor([AnnPlatform? platform])', classStart);
      final nameForEnd = content.indexOf('idFor([AnnPlatform? platform])', nameForStart);
      final nameForBody = content.substring(nameForStart, nameForEnd);
      // android and ios each throw with their own platform-specific error
      // message text, so — unlike the old "return null" bodies — they are
      // NOT grouped into one case pattern (grouping only merges arms whose
      // generated text is identical, and the platform name inside each
      // error message makes every throw arm distinct).
      expect(nameForBody, contains(
          "case AnnPlatform.android:\n        throw StateError(\n          \"'ledger_admin'.nameFor(AnnPlatform.android): this flavor has no entry under app.android.flavor in annspec.yaml.\","));
      expect(nameForBody, contains(
          "case AnnPlatform.ios:\n        throw StateError(\n          \"'ledger_admin'.nameFor(AnnPlatform.ios): this flavor has no entry under app.ios.flavor in annspec.yaml.\","));
    });

    test('nameFor(windows) throws — this app has no app.windows section at all either', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerAdminConfig');
      final classBody = content.substring(classStart);
      expect(classBody, contains(
          "'ledger_admin'.nameFor(AnnPlatform.windows): this flavor has no entry under app.windows.flavor in annspec.yaml.\","));
    });

    test('idFor(android)/idFor(ios) throw — this flavor has no entry under either platform', () async {
      // Regression coverage: idFor previously either leaked the platform's
      // default.id (original bug) or returned null (the plan-036 two-tier
      // design) for a flavor with no entry under a platform that otherwise
      // exists for the app. Neither is correct — querying an unsupported
      // platform for this flavor is always a throw.
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerAdminConfig');
      final idForStart = content.indexOf('idFor([AnnPlatform? platform])', classStart);
      final idForEnd = content.indexOf('appleId', idForStart);
      final idForBody = content.substring(idForStart, idForEnd);
      // Not grouped — each platform's error message text differs, so no
      // two arms are text-identical (see nameFor's equivalent test above).
      expect(idForBody, contains(
          "case AnnPlatform.android:\n        throw StateError(\n          \"'ledger_admin'.idFor(AnnPlatform.android): this flavor has no entry under app.android.flavor in annspec.yaml.\","));
      expect(idForBody, contains(
          "case AnnPlatform.ios:\n        throw StateError(\n          \"'ledger_admin'.idFor(AnnPlatform.ios): this flavor has no entry under app.ios.flavor in annspec.yaml.\","));
    });

    test('idFor(web) resolves the real id for the platform this flavor actually exists under', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _LedgerAdminConfig');
      final idForStart = content.indexOf('idFor([AnnPlatform? platform])', classStart);
      final idForEnd = content.indexOf('appleId', idForStart);
      final idForBody = content.substring(idForStart, idForEnd);
      expect(idForBody, contains("case AnnPlatform.web:\n        return 'com.example.test';"));
    });

    test('nameFor()/idFor() are the methods directly overridden in the generated subclass', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('@override String? nameFor([AnnPlatform? platform])'));
      expect(content, contains('@override String? idFor([AnnPlatform? platform])'));
    });
  });

  group('dart_generator — nameFor/idFor throw for an absent flavor, never leak platform defaults', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_no_default_leak_test_');
      // Unlike the ledger_admin fixture above, this app's android DEFAULT
      // section sets a name/id — so nameFor/idFor's "flavor absent" check
      // must throw before ever consulting that default, not fall through to
      // it. Regression fixture for a bug found via manual review: android
      // defaults set a name/id, admin_console has no android flavor entry
      // at all, yet nameFor(android)/idFor(android) were resolving to the
      // default name/id instead of failing loudly.
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      name: "Default App Name"
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      mobile:
        name: "Mobile Flavor"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  web:
    default:
      id: com.example.test
    flavor:
      mobile:
        name: "Mobile Flavor"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
      admin_console:
        name: "Admin Console"
        main_file: "lib/main_admin.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('nameFor(android) throws for a flavor with no android entry, even though android.default.name is set', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _AdminConsoleConfig');
      expect(classStart, greaterThan(-1), reason: '_AdminConsoleConfig class not found');
      final classBody = content.substring(classStart);
      expect(classBody, contains(
          "case AnnPlatform.android:\n        throw StateError(\n          \"'admin_console'.nameFor(AnnPlatform.android): this flavor has no entry under app.android.flavor in annspec.yaml.\","));
      expect(classBody, isNot(contains("return 'Default App Name'")));
    });

    test('idFor(android) throws for a flavor with no android entry, even though android.default.id is set', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _AdminConsoleConfig');
      final idForStart = content.indexOf('idFor([AnnPlatform? platform])', classStart);
      final idForEnd = content.indexOf('appleId', idForStart);
      final idForBody = content.substring(idForStart, idForEnd);
      final androidStart = idForBody.indexOf('case AnnPlatform.android:');
      final androidEnd = idForBody.indexOf('case AnnPlatform.ios:', androidStart);
      final androidArm = idForBody.substring(androidStart, androidEnd);
      expect(androidArm, contains(
          "throw StateError(\n          \"'admin_console'.idFor(AnnPlatform.android): this flavor has no entry under app.android.flavor in annspec.yaml.\","));
      // web legitimately returns 'com.example.test' (its own base id) —
      // this only asserts android's arm doesn't leak it, not that the
      // string never appears anywhere in the method.
      expect(androidArm, isNot(contains("'com.example.test'")));
    });

    test('a flavor genuinely present on that platform still resolves the default correctly', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _MobileConfig');
      expect(classStart, greaterThan(-1), reason: '_MobileConfig class not found');
      final classBody = content.substring(classStart);
      expect(classBody, contains("case AnnPlatform.android"));
      expect(classBody, contains("return 'Mobile Flavor'"));
    });
  });

  group('dart_generator — idFor respects flavor.id full override', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_id_override_test_');
      // REQ-IDEN-00010: flavor.id (full override) and flavor.id_suffix are
      // mutually exclusive. Regression fixture: idFor previously only ever
      // read idSuffix, silently ignoring flavor.id entirely.
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        id: com.completely.different.id
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('idFor(android) returns the full flavor.id override, not default.id', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _MyappConfig');
      final idForStart = content.indexOf('idFor([AnnPlatform? platform])', classStart);
      final idForEnd = content.indexOf('appleId', idForStart);
      final idForBody = content.substring(idForStart, idForEnd);
      expect(idForBody, contains("return 'com.completely.different.id'"));
      expect(idForBody, isNot(contains('com.example.test')));
    });
  });

  group('dart_generator — customFor cross-platform independence', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_custom_crossplatform_test_');
      // Regression fixture for the exact bug found during this plan's
      // drafting: android and web both set custom.supabase.url for release,
      // to DIFFERENT values. The old implementation merged all platforms
      // into one Map<group, Map<buildType, value>>, so whichever platform
      // was iterated last silently won for both.
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
      build_types:
        release:
          custom:
            supabase:
              url: "https://android.example.com"
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
  web:
    default:
      id: com.example.test
      build_types:
        release:
          custom:
            supabase:
              url: "https://web.example.com"
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('customFor(android, ...) and customFor(web, ...) resolve independently — no cross-platform overwrite', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final customForStart = content.indexOf('customFor(String group, [AnnPlatform? platform, String? buildType])');
      expect(customForStart, greaterThan(-1), reason: 'customFor not found');
      final androidStart = content.indexOf('case AnnPlatform.android:', customForStart);
      final webStart = content.indexOf('case AnnPlatform.web:', customForStart);
      final androidBody = content.substring(androidStart, webStart);
      final webBody = content.substring(webStart);
      expect(androidBody, contains("'url': 'https://android.example.com'"));
      expect(androidBody, isNot(contains('https://web.example.com')));
      expect(webBody, contains("'url': 'https://web.example.com'"));
      expect(webBody, isNot(contains('https://android.example.com')));
    });

    test('customFor throws StateError for a flavor with no entry under that platform', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains(
          "case AnnPlatform.ios:\n        throw StateError(\n          \"'myapp'.customFor(AnnPlatform.ios, \$group, \$buildType): this flavor has no entry under app.ios.flavor in annspec.yaml.\","));
    });

    test('customFor(group, [platform, buildType]) is the method directly overridden in the generated subclass', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('@override AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType])'));
    });
  });

  group('dart_generator — _esc backslash escaping', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_esc_test_');
      // Single-quoted YAML scalar — preserves the backslash literally.
      // (A double-quoted YAML string treats \N as its own escape sequence,
      // which would never reach the generator as a literal backslash.)
      File('${tempDir.path}/annspec.yaml').writeAsStringSync(r'''
enabled: true
app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      myapp:
        name: 'Admin\Nightly'
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('a backslash in a config value is escaped, not passed through raw', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      // The generated literal must contain an escaped backslash (\\) before
      // the 'N', not a raw backslash that Dart would interpret as the start
      // of an escape sequence.
      expect(content, contains(r"return 'Admin\\Nightly';"));
      expect(content, isNot(contains(r"return 'Admin\Nightly';")));
    });
  });

  group('dart_generator — appleId', () {
    late Directory projectDir;

    setUp(() async {
      projectDir = await Directory.systemTemp.createTemp('appleId_test_');
      await Directory('${projectDir.path}/lib/generated').create(recursive: true);
    });

    tearDown(() async => projectDir.deleteSync(recursive: true));

    test('appleId emitted when set in iOS flavor', () async {
      File('${projectDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
    flavor:
      production:
        name: "Production"
        stores:
          app_store:
            apple_id: "1234567890"
''');
      final result = await _runSync(projectDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final generated = _readGenerated(projectDir);
      expect(generated, contains("get appleId => '1234567890'"));
    });

    test('appleId is null when not set in iOS flavor', () async {
      File('${projectDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
    flavor:
      production:
        name: "Production"
''');
      final result = await _runSync(projectDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final generated = _readGenerated(projectDir);
      expect(generated, contains('get appleId => null'));
    });
  });
}
