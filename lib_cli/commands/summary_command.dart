import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../spec/annspec_reader.dart';
import '../model/annspec_model.dart';

final _sep = '─' * 56;
const _labelW = 11; // width of the label column

class SummaryCommand extends Command<void> {
  @override
  final name = 'summary';

  @override
  final description =
      'Show the fully resolved annspec.yaml — merged values per flavor and build type.';

  SummaryCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;

    AnnspecModel spec;
    try {
      spec = AnnspecReader.read(projectRoot);
    } catch (e) {
      print('✗ $e');
      return;
    }

    print('');
    print('ANN Flavor — annspec.yaml summary');
    print(_sep);
    print('  ${p.join(projectRoot, 'annspec.yaml')}');

    for (final platform in spec.platforms) {
      print('');
      print('');
      _printPlatform(platform);
    }
    print('');
  }

  // ── Platform ───────────────────────────────────────────────────────────────

  void _printPlatform(AnnspecPlatform plat) {
    print(plat.key.toUpperCase());
    print('');
    _printDefault(plat);
    for (final flavor in plat.flavors) {
      print('');
      _printFlavor(flavor, plat);
    }
  }

  // ── Default block ──────────────────────────────────────────────────────────

  void _printDefault(AnnspecPlatform plat) {
    _header('default');
    if (plat.baseId != null)             _row('id',        plat.baseId!);
    if (plat.baseName != null)           _row('name',      plat.baseName!);
    _version(plat.defaultVersionName, plat.defaultVersionCode);
    if (plat.minSdk != null)             _row('min sdk',   '${plat.minSdk}');
    if (plat.signingKeyFile != null)     _row('signing',   plat.signingKeyFile!);
    if (plat.teamId != null)             _row('team id',   plat.teamId!);
    if (plat.googlePlayApiKey != null)   _row('gplay key', plat.googlePlayApiKey!);
    if (plat.appStoreApiKey != null)     _row('store key', plat.appStoreApiKey!);
    if (plat.appStoreExportPlist != null)_row('export',    plat.appStoreExportPlist!);
    if (plat.defaultGmsAdsId != null)    _row('admob',     plat.defaultGmsAdsId!);
    _firebase(plat.defaultFirebaseRelease, plat.defaultFirebaseDebug);
    _auth(plat.defaultAuthRelease, plat.defaultAuthDebug);
  }

  // ── Flavor block ───────────────────────────────────────────────────────────

  void _printFlavor(AnnspecFlavor f, AnnspecPlatform plat) {
    final isFullOverride = f.id != null;
    final suffix = isFullOverride ? '  (full id override)' : '';
    _header('${f.key}$suffix');

    // Resolved effective id
    final effectiveId = f.id ?? '${plat.baseId ?? ''}${f.idSuffix ?? ''}';
    _row('id', effectiveId);

    if (f.name != null) _row('name', f.name!);
    _version(f.versionName, f.versionCode);
    _firebase(f.firebaseRelease, f.firebaseDebug);
    _auth(f.authRelease, f.authDebug);
    if (f.gmsAdsId != null) _row('admob', f.gmsAdsId!);
    _stores(f);
    _custom(f.customByBuildType);
  }

  // ── Field renderers ────────────────────────────────────────────────────────

  void _version(String? name, String? code) {
    if (name == null) return;
    _row('version', code != null ? '$name ($code)' : name);
  }

  void _firebase(AnnspecFirebase? rel, AnnspecFirebase? dbg) {
    if (rel == null && dbg == null) return;

    String? _desc(AnnspecFirebase fb) {
      if (fb.file != null)      return 'file    → ${fb.file}';
      if (fb.projectId != null) return 'project → ${fb.projectId}';
      return null; // has non-standard fields (e.g. build_target) — not shown here
    }

    final relDesc = rel != null ? _desc(rel) : null;
    final dbgDesc = dbg != null ? _desc(dbg) : null;
    if (relDesc == null && dbgDesc == null) return;

    if (relDesc != null && dbgDesc != null && relDesc == dbgDesc) {
      _row('firebase', relDesc);
    } else {
      if (relDesc != null) _row('firebase', 'release  $relDesc');
      if (dbgDesc != null) _cont('debug    $dbgDesc');
    }
  }

  void _auth(AnnspecAuth? rel, AnnspecAuth? dbg) {
    if (rel == null && dbg == null) return;

    bool _same() =>
        rel?.clientId == dbg?.clientId &&
        rel?.reversedClientId == dbg?.reversedClientId;

    void _printAuth(AnnspecAuth a) {
      if (a.clientId != null)
        _cont('  clientId          ${a.clientId}');
      if (a.reversedClientId != null)
        _cont('  reversedClientId  ${a.reversedClientId}');
    }

    if (rel != null && dbg != null && _same()) {
      _row('auth', '');
      _printAuth(rel);
    } else {
      if (rel != null) { _row('auth', 'release'); _printAuth(rel); }
      if (dbg != null) { _cont('debug');           _printAuth(dbg); }
    }
  }

  void _stores(AnnspecFlavor f) {
    final lines = <String>[];
    if (f.googlePlayPriority != null)
      lines.add('google_play    priority ${f.googlePlayPriority}');
    if (f.samsungAppId != null)
      lines.add('samsung_galaxy app_id   ${f.samsungAppId}');
    if (f.amazonAppId != null)
      lines.add('amazon         app_id   ${f.amazonAppId}');
    if (f.appleId != null)
      lines.add('app_store      apple_id ${f.appleId}');
    if (lines.isEmpty) return;
    _row('stores', lines.first);
    for (final l in lines.skip(1)) _cont(l);
  }

  void _custom(Map<String, Map<String, Map<String, dynamic>>> customByBt) {
    if (customByBt.isEmpty) return;

    final releaseCustom = customByBt['release'] ?? customByBt.values.first;
    final debugCustom   = customByBt['debug'];
    final hasDiff = debugCustom != null &&
        debugCustom.toString() != releaseCustom.toString();

    bool firstGroup = true;
    for (final group in releaseCustom.entries) {
      if (firstGroup) {
        _row('custom', group.key);
        firstGroup = false;
      } else {
        _cont(group.key);
      }
      for (final kv in group.value.entries) {
        final val = kv.value is List
            ? '[${(kv.value as List).join(', ')}]'
            : '${kv.value}';
        _cont('  ${kv.key.padRight(18)} $val');
      }
    }

    if (hasDiff) {
      _cont('(debug overrides differ — add --verbose for full breakdown)');
    }
  }

  // ── Print helpers ──────────────────────────────────────────────────────────

  void _header(String title) => print('  $title');

  /// Labeled row:  "    label       value"
  void _row(String label, String value) =>
      print('    ${label.padRight(_labelW)}  $value');

  /// Continuation row (empty label):  "               value"
  void _cont(String value) =>
      print('    ${''.padRight(_labelW)}  $value');
}
