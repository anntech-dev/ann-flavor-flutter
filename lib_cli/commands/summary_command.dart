import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;
import '../spec/annspec_reader.dart';

const _labelW = 10;
final _divider = '─' * 52;

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

    core.AnnSpec spec;
    try {
      spec = AnnspecReader.read(projectRoot);
    } catch (e) {
      print('✗ $e');
      return;
    }

    print('');
    print('ANN Flavor — resolved summary');
    print(_divider);
    print('  ${p.join(projectRoot, 'annspec.yaml')}');

    if (spec.app.android != null) {
      print('');
      print('');
      final android = spec.app.android!;
      _printPlatform(
        'ANDROID',
        android.flavors.keys.isEmpty ? [''] : android.flavors.keys,
        buildTypeKeysFor: (flavorKey) => _mergedBuildTypeKeys(
            android.defaults.buildTypes.keys, android.flavors[flavorKey]?.buildTypes.keys ?? const []),
        resolve: (flavorKey, bt) => core.AnnSpecResolver.resolveAndroidFlavor(
            android.flavors[flavorKey] ?? const core.AndroidFlavor(), android.defaults, bt),
        stores: (flavorKey) => android.flavors[flavorKey]?.stores,
        androidBt: (flavorKey, bt) =>
            android.flavors[flavorKey]?.buildTypes[bt] ?? android.defaults.buildTypes[bt],
      );
    }
    if (spec.app.ios != null) {
      print('');
      print('');
      final ios = spec.app.ios!;
      _printPlatform(
        'IOS',
        ios.flavors.keys.isEmpty ? [''] : ios.flavors.keys,
        buildTypeKeysFor: (flavorKey) => _mergedBuildTypeKeys(
            ios.defaults.buildTypes.keys, ios.flavors[flavorKey]?.buildTypes.keys ?? const []),
        resolve: (flavorKey, bt) => core.AnnSpecResolver.resolveIosFlavor(
            ios.flavors[flavorKey] ?? const core.IosFlavor(), ios.defaults, bt),
        stores: (flavorKey) => ios.flavors[flavorKey]?.stores,
      );
    }
    if (spec.app.web != null) {
      print('');
      print('');
      final web = spec.app.web!;
      _printPlatform(
        'WEB',
        web.flavors.keys.isEmpty ? [''] : web.flavors.keys,
        buildTypeKeysFor: (flavorKey) => _mergedBuildTypeKeys(
            web.defaults.buildTypes.keys, web.flavors[flavorKey]?.buildTypes.keys ?? const []),
        resolve: (flavorKey, bt) => core.AnnSpecResolver.resolveWebFlavor(
            web.flavors[flavorKey] ?? const core.WebFlavor(), web.defaults, bt),
        stores: (flavorKey) => null,
      );
    }
    if (spec.app.windows != null) {
      print('');
      print('');
      final windows = spec.app.windows!;
      _printPlatform(
        'WINDOWS',
        windows.flavors.keys.isEmpty ? [''] : windows.flavors.keys,
        buildTypeKeysFor: (flavorKey) => _mergedBuildTypeKeys(
            windows.defaults.buildTypes.keys, windows.flavors[flavorKey]?.buildTypes.keys ?? const []),
        resolve: (flavorKey, bt) => core.AnnSpecResolver.resolveWindowsFlavor(
            windows.flavors[flavorKey] ?? const core.WindowsFlavor(), windows.defaults, bt),
        stores: (flavorKey) => null,
      );
    }
    print('');
  }

  /// release/debug always shown; any other configured build type (e.g.
  /// profile) shown too, in declaration order — matches the original's
  /// "always debug+release, plus whatever's actually configured" behavior.
  List<String> _mergedBuildTypeKeys(Iterable<String> defaultKeys, Iterable<String> flavorKeys) {
    final all = <String>{'release', 'debug', ...defaultKeys, ...flavorKeys};
    final ordered = <String>['release', 'debug'];
    for (final k in all) {
      if (k != 'release' && k != 'debug') ordered.add(k);
    }
    return ordered;
  }

  // ── Platform ───────────────────────────────────────────────────────────────

  void _printPlatform(
    String label,
    Iterable<String> flavorKeys, {
    required List<String> Function(String flavorKey) buildTypeKeysFor,
    required core.ResolvedBuildOutput Function(String flavorKey, String buildType) resolve,
    required core.FlavorStores? Function(String flavorKey) stores,
    core.BuildTypeConfig? Function(String flavorKey, String buildType)? androidBt,
  }) {
    print(label);

    final showHeader = flavorKeys.length > 1 || flavorKeys.first.isNotEmpty;
    for (final flavorKey in flavorKeys) {
      if (showHeader) print('');
      _printFlavor(flavorKey, buildTypeKeysFor(flavorKey), resolve, stores,
          showHeader: showHeader, androidBt: androidBt);
    }
  }

  void _printFlavor(
    String flavorKey,
    List<String> buildTypeKeys,
    core.ResolvedBuildOutput Function(String flavorKey, String buildType) resolve,
    core.FlavorStores? Function(String flavorKey) stores, {
    required bool showHeader,
    core.BuildTypeConfig? Function(String flavorKey, String buildType)? androidBt,
  }) {
    if (showHeader) {
      print('  ── $flavorKey $_divider'.substring(0, _divider.length + 5));
    }

    for (final bt in buildTypeKeys) {
      final r = resolve(flavorKey, bt);
      print('');
      print('  $bt');

      if (r.effectiveId.isNotEmpty) _row('id', r.effectiveId);
      if (r.effectiveName.isNotEmpty) _row('name', r.effectiveName);
      if (r.effectiveVersionName.isNotEmpty) {
        _row('version', _versionStr(r.effectiveVersionName, r.effectiveVersionCode));
      }

      _printFirebase(r.effectiveFirebase);
      _printAuth(r.effectiveAuth);

      if (r.effectiveGmsAdsId != null) _row('admob', r.effectiveGmsAdsId!);

      if (showHeader) _printStores(stores(flavorKey));

      _printCustom(r.effectiveCustom);

      _printAndroidBtFields(androidBt?.call(flavorKey, bt));
    }
  }

  // ── Field renderers ────────────────────────────────────────────────────────

  String _versionStr(String? name, int? code) =>
      code != null ? '$name ($code)' : name ?? '';

  void _printFirebase(core.FirebaseConfig? fb) {
    if (fb == null) return;
    if (fb.configFile != null) _row('firebase', 'config_file → ${fb.configFile}');
    if (fb.projectId != null) _row('firebase', 'project → ${fb.projectId}');
  }

  void _printAuth(core.AuthConfig? auth) {
    if (auth == null) return;
    if (auth.clientId != null)         _row('auth', 'clientId          ${auth.clientId}');
    if (auth.reversedClientId != null) _cont('     reversedClientId  ${auth.reversedClientId}');
  }

  void _printStores(core.FlavorStores? stores) {
    if (stores == null) return;
    final lines = <String>[];
    if (stores.googlePlay?.priority != null) {
      lines.add('google_play    priority ${stores.googlePlay!.priority}');
    }
    if (stores.samsungGalaxy?.appId != null) {
      lines.add('samsung_galaxy app_id   ${stores.samsungGalaxy!.appId}');
    }
    if (stores.amazon?.appId != null) {
      lines.add('amazon         app_id   ${stores.amazon!.appId}');
    }
    if (stores.appStore?.appleId != null) {
      lines.add('app_store      apple_id ${stores.appStore!.appleId}');
    }
    if (lines.isEmpty) return;
    _row('stores', lines.first);
    for (final l in lines.skip(1)) _cont(l);
  }

  void _printCustom(Map<String, Map<String, dynamic>> custom) {
    if (custom.isEmpty) return;
    bool first = true;
    for (final group in custom.entries) {
      if (first) { _row('custom', group.key); first = false; }
      else        _cont(group.key);
      for (final kv in group.value.entries) {
        final val = kv.value is List
            ? '[${(kv.value as List).join(', ')}]'
            : '${kv.value}';
        _cont('  ${kv.key.padRight(16)} $val');
      }
    }
  }

  void _printAndroidBtFields(core.BuildTypeConfig? btCfg) {
    if (btCfg == null) return;
    if (btCfg.minifyEnabled != null) {
      _row('minify', '${btCfg.minifyEnabled}  shrink: ${btCfg.shrinkResources ?? false}');
    }
    if (btCfg.ndkVersion != null) _row('ndk', btCfg.ndkVersion!);
    if (btCfg.ndkAbiFilters.isNotEmpty) _row('abi', btCfg.ndkAbiFilters.join(', '));
  }

  // ── Print helpers ──────────────────────────────────────────────────────────

  void _row(String label, String value) =>
      print('    ${label.padRight(_labelW)}  $value');

  void _cont(String value) =>
      print('    ${''.padRight(_labelW)}  $value');
}
