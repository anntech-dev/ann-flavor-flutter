import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'testspec_validator.dart';

const _classes = {
  'android': {'phone', 'tablet_7', 'tablet_10', 'tv', 'wear'},
  'ios': {'iphone_medium', 'iphone_large', 'ipad_13', 'apple_tv'},
};

class _Store {
  final String platform;
  final Set<String> needs;

  /// A flavor whose devices of the platform are all of these classes needs nothing more.
  final Set<String> enoughAlone;
  const _Store(this.platform, this.needs, [this.enoughAlone = const {}]);
}

const _stores = {
  'google_play': _Store('android', {'phone'}, {'tv', 'wear'}),
  'samsung_galaxy': _Store('android', {'phone'}),
  'amazon': _Store('android', {'phone'}, {'tv'}),
  'app_store': _Store('ios', {'iphone_medium', 'iphone_large'}, {'apple_tv'}),
};

const _rootKeys = {'version', 'screenshots', 'stores', 'defaults', 'devices', 'flavor'};
const _screenshotKeys = {'enabled', 'locale'};
const _fileKeys = {'driver_file', 'test_file'};
const _deviceKeys = {
  'platform', 'class', 'avd', 'simulator', 'port_number', 'driver_file', 'test_file', 'phone_type',
  'flutter_command',
};
const _flavorKeys = {'tests', 'devices', 'stores', 'driver_file', 'test_file', 'screenshots'};
const _reservedParameters = {'testcase_name', 'flavor', 'phone_type'};

class _Device {
  final String platform;
  final String deviceClass;
  final YamlMap entry;
  const _Device(this.platform, this.deviceClass, this.entry);
}

/// Checks a version 2 test spec (REQ-FCLI-00080, REQ-TEST-00010 to 00050).
class TestspecV2Validator {
  final YamlMap root;
  final String projectRoot;
  final Map<String, Set<String>> annspecFlavorKeys;

  final errors = <TestspecIssue>[];
  final warnings = <TestspecIssue>[];
  final infos = <TestspecIssue>[];

  /// Devices with a platform and a class of it, by key.
  final _devices = <String, _Device>{};

  /// A file that several devices or flavors use is reported once.
  final _reportedFiles = <String>{};

  TestspecV2Validator(this.root, this.projectRoot, this.annspecFlavorKeys);

  void validate() {
    _unknownKeys(root, _rootKeys, 'annai_app_tests');
    final screenshots = _section(root, 'screenshots', _screenshotKeys);
    final enabled = screenshots['enabled'];
    if (enabled != null && enabled is! bool) {
      _error('annai_app_tests.screenshots.enabled', 'screenshots.enabled must be true or false.',
          'Words such as yes, no, on and off are read differently by different tools.');
    }
    final defaults = _section(root, 'defaults', _fileKeys);
    final rootStores = _storeList(root['stores'], 'annai_app_tests.stores');

    final devices = root['devices'];
    final deviceNames = <String>{};
    if (devices is! YamlMap || devices.isEmpty) {
      _error('annai_app_tests.devices', 'No devices are defined.',
          'Add  devices:  with a platform, a class and an avd or simulator for each.');
    } else {
      _checkDevices(devices);
      deviceNames.addAll(devices.keys.map((k) => '$k'));
      _checkRootStores(rootStores);
    }

    final flavors = root['flavor'];
    if (flavors is! YamlMap || flavors.isEmpty) {
      _error('annai_app_tests.flavor', 'No flavors are defined.',
          'Add  flavor:  with the tests of each flavor ("" for a project without flavors).');
      return;
    }
    for (final e in flavors.entries) {
      _checkFlavor('${e.key}', e.value, deviceNames, rootStores, defaults,
          screenshotsEnabled: screenshots['enabled'] != false);
    }
  }

  void _error(String path, String message, [String? fix]) => errors.add(TestspecIssue(path, message, fix: fix));
  void _warning(String path, String message, [String? fix]) =>
      warnings.add(TestspecIssue(path, message, fix: fix));
  void _info(String path, String message) => infos.add(TestspecIssue(path, message));

  void _unknownKeys(YamlMap map, Set<String> known, String path) {
    for (final key in map.keys) {
      if (!known.contains('$key')) {
        _warning('$path.$key', "'$key' is not a key of the test spec.", 'Known keys: ${known.join(', ')}.');
      }
    }
  }

  YamlMap _section(YamlMap parent, String name, Set<String> known) {
    final value = parent[name];
    if (value == null) return YamlMap();
    if (value is! YamlMap) {
      _warning('annai_app_tests.$name', "'$name' must be a map; it is ignored.");
      return YamlMap();
    }
    _unknownKeys(value, known, 'annai_app_tests.$name');
    return value;
  }

  /// The known stores of a `stores` list, or null when none is given.
  List<String>? _storeList(dynamic value, String path) {
    if (value == null) return null;
    if (value is! YamlList) {
      _error(path, "'stores' must be a list.", 'For example  stores: [google_play]');
      return const [];
    }
    final unknown = value.map((v) => '$v').where((v) => !_stores.containsKey(v)).toList();
    if (unknown.isNotEmpty) {
      _error(path, 'Unknown store: ${unknown.join(', ')}.', 'Known stores: ${_stores.keys.join(', ')}.');
    }
    return value.map((v) => '$v').where(_stores.containsKey).toList();
  }

  void _checkDevices(YamlMap devices) {
    final portOfAvd = <String, int>{};
    final avdOfPort = <int, String>{};
    for (final e in devices.entries) {
      final path = 'annai_app_tests.devices.${e.key}';
      final entry = e.value is YamlMap ? e.value as YamlMap : YamlMap();
      _unknownKeys(entry, _deviceKeys, path);

      final platform = entry['platform'];
      if (!_classes.containsKey(platform)) {
        _error('$path.platform', 'platform must be android or ios.');
        continue;
      }
      final classes = _classes[platform]!;
      final deviceClass = entry['class'];
      if (!classes.contains(deviceClass)) {
        _error('$path.class', 'class must be a class of $platform.', 'One of: ${classes.join(', ')}.');
      }
      final targetKey = platform == 'android' ? 'avd' : 'simulator';
      final target = '${entry[targetKey] ?? ''}'.trim();
      if (target.isEmpty) {
        _error('$path.$targetKey', "'$targetKey' is missing.");
      }

      final rawPort = entry['port_number'];
      final port = rawPort == null ? null : int.tryParse('$rawPort');
      if (rawPort != null && port == null) {
        _error('$path.port_number', 'port_number must be a whole number.');
      } else if (port != null && platform == 'android' && target.isNotEmpty) {
        if (portOfAvd.containsKey(target) && portOfAvd[target] != port) {
          _error('$path.port_number', "AVD '$target' already has port ${portOfAvd[target]}.");
        } else if (avdOfPort.containsKey(port) && avdOfPort[port] != target) {
          _error('$path.port_number', "Port $port is already used by AVD '${avdOfPort[port]}'.");
        } else {
          portOfAvd[target] = port;
          avdOfPort[port] = target;
        }
      }

      final phoneType = entry['phone_type'];
      if (phoneType != null) {
        for (final type in '$phoneType'.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty)) {
          if (!knownPhoneTypes.contains(type.toUpperCase())) {
            _info('$path.phone_type', "Unknown phone type '$type' — custom types are allowed but check for typos.");
          }
        }
      }

      if (classes.contains(deviceClass)) {
        _devices['${e.key}'] = _Device(platform as String, deviceClass as String, entry);
      }
    }
  }

  void _checkRootStores(List<String>? stores) {
    for (final store in stores ?? const <String>[]) {
      final platform = _stores[store]!.platform;
      if (!_devices.values.any((d) => d.platform == platform)) {
        _warning('annai_app_tests.stores', "'$store' needs an $platform device, and none is defined.");
      }
    }
  }

  void _checkFlavor(
    String flavor,
    dynamic value,
    Set<String> deviceNames,
    List<String>? rootStores,
    YamlMap defaults, {
    required bool screenshotsEnabled,
  }) {
    final path = 'annai_app_tests.flavor.$flavor';
    final entry = value is YamlMap ? value : YamlMap();
    _unknownKeys(entry, _flavorKeys, path);
    _checkTests(entry['tests'], '$path.tests');

    var names = _devices.keys.toList();
    final listed = entry['devices'];
    if (listed != null && listed is! YamlList) {
      _error('$path.devices', "'devices' must be a list of device keys.");
      names = [];
    } else if (listed is YamlList) {
      final asked = listed.map((n) => '$n').toList();
      final unknown = asked.where((n) => !deviceNames.contains(n)).toList();
      if (unknown.isNotEmpty) {
        _error('$path.devices', 'Device not defined: ${unknown.join(', ')}.');
      }
      names = asked.where(_devices.containsKey).toList();
    }
    final devices = {for (final n in names) n: _devices[n]!};

    final byClass = <String, List<String>>{};
    devices.forEach((name, d) => byClass.putIfAbsent(d.deviceClass, () => []).add(name));
    final doubled = byClass.entries.where((e) => e.value.length > 1).toList();
    if (doubled.isNotEmpty) {
      _error('$path.devices',
          'Two devices of one class: ${doubled.map((e) => '${e.value.join(' and ')} (${e.key})').join('; ')}.',
          'List one device of each class under  devices:  of the flavor.');
    }

    _checkStores(path, entry, devices, rootStores);
    _checkScreenshots(entry['screenshots'], '$path.screenshots');

    for (final platform in devices.values.map((d) => d.platform).toSet()) {
      final keys = annspecFlavorKeys[platform] ?? const <String>{};
      if (keys.isNotEmpty && !keys.contains(flavor)) {
        _warning(path, "Flavor '$flavor' is not defined in annspec.yaml ($platform).",
            "Add '$flavor' to annspec.yaml app.$platform.flavor, or remove it from anntestspec.yaml.");
      }
    }

    for (final e in devices.entries) {
      for (final key in _fileKeys) {
        if (key == 'driver_file' && !screenshotsEnabled) continue;
        _checkFile(key, path, e.key, e.value.entry, entry, defaults);
      }
    }
  }

  void _checkTests(dynamic tests, String path) {
    if (tests is! YamlMap || tests.isEmpty) {
      _error(path, 'The flavor has no tests.', 'Add  tests:  with at least one test case.');
      return;
    }
    for (final e in tests.entries) {
      final parameters = e.value;
      if (parameters == null) continue;
      if (parameters is! YamlMap || parameters.values.any((v) => v is YamlMap || v is YamlList)) {
        _error('$path.${e.key}', 'A test case is empty or a map of single values.');
        continue;
      }
      for (final key in parameters.keys.where((k) => _reservedParameters.contains('$k'))) {
        _warning('$path.${e.key}.$key', "'$key' is ignored: the tooling sets it.");
      }
    }
  }

  void _checkStores(String path, YamlMap entry, Map<String, _Device> devices, List<String>? rootStores) {
    final own = _storeList(entry['stores'], '$path.stores');
    for (final store in own ?? rootStores ?? const <String>[]) {
      final rules = _stores[store]!;
      final classes = devices.values.where((d) => d.platform == rules.platform).map((d) => d.deviceClass).toSet();
      if (classes.isEmpty) {
        // A root store applies only where the flavor has a device of its platform.
        if (own != null) {
          _error('$path.stores', "'$store' needs an ${rules.platform} device, and the flavor has none.");
        }
        continue;
      }
      final missing = rules.needs.difference(classes);
      if (missing.isNotEmpty && !rules.enoughAlone.containsAll(classes)) {
        _warning('$path.stores.$store', "'$store' needs a device of class ${missing.join(' and ')}.");
      }
      if (store == 'app_store' &&
          classes.any((c) => c.startsWith('iphone_')) &&
          !classes.contains('ipad_13')) {
        _info('$path.stores.$store', 'If the app runs on iPad, App Store also needs an ipad_13 device.');
      }
    }
  }

  void _checkScreenshots(dynamic screenshots, String path) {
    if (screenshots == null || screenshots is YamlList) return;
    final known = {..._classes.keys, for (final classes in _classes.values) ...classes};
    if (screenshots is YamlMap &&
        screenshots.entries.every((e) => known.contains('${e.key}') && e.value is YamlList)) {
      return;
    }
    _error(path, "'screenshots' must be a list of names, or lists keyed by platform or class.",
        'Keys: ${known.join(', ')}.');
  }

  /// The device comes before the flavor, and the flavor before the defaults.
  void _checkFile(
    String key,
    String flavorPath,
    String deviceName,
    YamlMap device,
    YamlMap flavor,
    YamlMap defaults,
  ) {
    final sources = {
      'annai_app_tests.devices.$deviceName.$key': device[key],
      '$flavorPath.$key': flavor[key],
      'annai_app_tests.defaults.$key': defaults[key],
    };
    for (final source in sources.entries) {
      final file = '${source.value ?? ''}'.trim();
      if (file.isEmpty) continue;
      if (!File(p.join(projectRoot, file)).existsSync() && _reportedFiles.add(source.key)) {
        _warning(source.key, '$key not found on disk: $file');
      }
      return;
    }
    _warning('$flavorPath.devices.$deviceName.$key', '$key is not set for device $deviceName.');
  }
}
