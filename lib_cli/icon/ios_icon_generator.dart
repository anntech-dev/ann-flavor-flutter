import 'dart:io';
import 'package:path/path.dart' as p;

/// Generates per-flavor iOS app icons via `flutter_launcher_icons`.
///
/// `flutter_launcher_icons` hardcodes its iOS output to
/// `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — there is no supported
/// config key to redirect it (`ios_content_images_path`, used by earlier
/// versions of this generator and by the Studio plugin, does not exist in
/// the real package; it silently had no effect). This class instead lets
/// the tool write to its real, fixed location, then relocates the result
/// into the actual per-flavor catalog this tooling owns
/// (`ios/ann/Assets.xcassets/<Flavor>AppIcon.appiconset/`).
///
/// Call [backupStockCatalog] once before generating any flavor, and
/// [restoreStockCatalog] once after every flavor has been generated — this
/// preserves whatever the developer's own `ios/Runner/Assets.xcassets/`
/// catalog contained before generation ran, since each flavor's run
/// otherwise overwrites it in place.
class IosIconGenerator {
  final String projectRoot;

  IosIconGenerator(this.projectRoot);

  Directory get _stockCatalogDir =>
      Directory(p.join(projectRoot, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'));

  Directory get _backupDir =>
      Directory(p.join(projectRoot, '.ann_icon_backup', 'AppIcon.appiconset'));

  /// Copies the developer's existing `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
  /// (if any) to a temporary backup location, so it can be restored after
  /// every flavor's generation run has overwritten it in place. A no-op if
  /// the stock catalog doesn't exist yet.
  void backupStockCatalog() {
    if (!_stockCatalogDir.existsSync()) return;
    if (_backupDir.existsSync()) _backupDir.deleteSync(recursive: true);
    _backupDir.parent.createSync(recursive: true);
    _copyDirectory(_stockCatalogDir, _backupDir);
  }

  /// Restores whatever [backupStockCatalog] saved, and deletes the backup.
  /// A no-op if [backupStockCatalog] never found anything to back up.
  void restoreStockCatalog() {
    if (!_backupDir.existsSync()) return;
    if (_stockCatalogDir.existsSync()) _stockCatalogDir.deleteSync(recursive: true);
    _stockCatalogDir.createSync(recursive: true);
    _copyDirectory(_backupDir, _stockCatalogDir);
    _backupDir.parent.deleteSync(recursive: true);
  }

  File get _pbxprojFile =>
      File(p.join(projectRoot, 'ios', 'Runner.xcodeproj', 'project.pbxproj'));

  Future<void> generateForFlavor(String flavorName, String sourcePath) async {
    _resolveSource(sourcePath);

    final tempConfig = File(p.join(projectRoot, 'flutter_launcher_icons_$flavorName.yaml'));
    tempConfig.writeAsStringSync(_buildConfig(sourcePath));

    // flutter_launcher_icons' overwrite path (used when no --flavor is
    // passed, which is how we always invoke it) also naively text-edits
    // project.pbxproj: changeIosLauncherIcon() in its own ios.dart rewrites
    // the value of any XCBuildConfiguration line containing the substring
    // "ASSETCATALOG" to the icon name it's setting -- intended to only touch
    // ASSETCATALOG_COMPILER_APPICON_NAME, but its match is too broad and also
    // corrupts unrelated keys like ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS
    // (YES -> the literal icon name). We already own all pbxproj icon-catalog
    // wiring ourselves (via ann-flavor-cocoapods), so its pbxproj edits are
    // both unneeded and actively harmful -- snapshot and restore the file
    // around every flutter_launcher_icons invocation so none of its edits
    // survive, regardless of what it decides to touch.
    final pbxprojBackup = _pbxprojFile.existsSync() ? _pbxprojFile.readAsStringSync() : null;

    try {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'flutter_launcher_icons', '-f', tempConfig.path],
        workingDirectory: projectRoot,
      );
      if (result.exitCode != 0) {
        throw Exception(
          '[Annai] flutter_launcher_icons failed for iOS flavor "$flavorName":\n'
          '${result.stderr}\n${result.stdout}',
        );
      }
      _relocateGeneratedCatalog(flavorName);
    } finally {
      if (tempConfig.existsSync()) tempConfig.deleteSync();
      if (pbxprojBackup != null) _pbxprojFile.writeAsStringSync(pbxprojBackup);
    }
  }

  // flutter_launcher_icons always writes to the fixed
  // ios/Runner/Assets.xcassets/AppIcon.appiconset/ — move that output into
  // the real per-flavor catalog this tooling owns, then clear the stock
  // location's CONTENTS (not the directory itself) so the next flavor's run
  // starts from a clean slate. The directory must still exist afterward:
  // flutter_launcher_icons' overwrite path (ios.dart's overwriteDefaultIcons,
  // used when no --flavor is passed) writes via File.writeAsBytes without
  // creating missing parent directories first -- deleting the directory
  // itself here left every flavor after the first crashing with
  // PathNotFoundException, since nothing ever recreated it before the next
  // flutter_launcher_icons run. It gets fully restored to the developer's
  // original content by restoreStockCatalog once every flavor is done.
  void _relocateGeneratedCatalog(String flavorName) {
    if (!_stockCatalogDir.existsSync()) {
      throw Exception(
        '[Annai] flutter_launcher_icons did not produce '
        '${_stockCatalogDir.path} for iOS flavor "$flavorName".',
      );
    }
    final iconSetName = _capitalize(flavorName) + 'AppIcon';
    final destDir = Directory(
      p.join(projectRoot, 'ios', 'ann', 'Assets.xcassets', '$iconSetName.appiconset'),
    );
    if (destDir.existsSync()) destDir.deleteSync(recursive: true);
    destDir.parent.createSync(recursive: true);
    _copyDirectory(_stockCatalogDir, destDir);
    for (final entity in _stockCatalogDir.listSync(recursive: false)) {
      entity.deleteSync(recursive: true);
    }
  }

  void _copyDirectory(Directory source, Directory dest) {
    dest.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectory(entity, Directory(destPath));
      } else if (entity is File) {
        entity.copySync(destPath);
      }
    }
  }

  File _resolveSource(String srcPath) {
    final candidates = [
      File(srcPath),
      File(p.join(projectRoot, srcPath)),
      File(p.join(p.dirname(projectRoot), srcPath)),
    ];
    return candidates.firstWhere(
      (f) => f.existsSync(),
      orElse: () => throw Exception(
        '[Annai] Icon source file not found: $srcPath\n'
        'Check the icon path in annspec.yaml.',
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _buildConfig(String sourcePath) => '''
flutter_launcher_icons:
  android: false
  ios: true
  image_path: "$sourcePath"
''';
}
