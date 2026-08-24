import '../model/ann_spec_model.dart';

class AnnSpecValidator {
  static List<String> validate(AnnSpec spec) {
    final errors = <String>[];
    _validateAndroid(spec.app.android, errors);
    _validateIos(spec.app.ios, errors);
    _validateWeb(spec.app.web, errors);
    _validateWindows(spec.app.windows, errors);
    return errors;
  }

  static void _validateAndroid(AndroidPlatform? android, List<String> errors) {
    if (android == null) return;
    final d = android.defaults;
    if (d.id == null || d.id!.isEmpty) {
      errors.add('android.default.id is required');
    }
    if (d.versionCode == null) {
      errors.add('android.default.version_code is required');
    } else if (d.versionCode! <= 0) {
      errors.add('android.default.version_code must be a positive integer');
    }
    android.flavors.forEach((name, flavor) {
      final finalId = (flavor.id ?? d.id ?? '') + flavor.idSuffix;
      if (finalId.isEmpty) {
        errors.add('android.flavor.$name: finalId is empty (set id or id_suffix)');
      }
      if (flavor.versionCode == null && d.versionCode == null) {
        errors.add('android.flavor.$name: version_code is required');
      }
    });
  }

  static void _validateIos(IosPlatform? ios, List<String> errors) {
    if (ios == null) return;
    final d = ios.defaults;
    if (d.id == null || d.id!.isEmpty) {
      errors.add('ios.default.id is required');
    }
    if (d.versionCode == null) {
      errors.add('ios.default.version_code is required');
    } else if (d.versionCode! <= 0) {
      errors.add('ios.default.version_code must be a positive integer');
    }
    ios.flavors.forEach((name, flavor) {
      final finalId = (flavor.id ?? d.id ?? '') + flavor.idSuffix;
      if (finalId.isEmpty) {
        errors.add('ios.flavor.$name: finalId is empty (set id or id_suffix)');
      }
      if (flavor.versionCode == null && d.versionCode == null) {
        errors.add('ios.flavor.$name: version_code is required');
      }
    });
  }

  static void _validateWeb(WebPlatform? web, List<String> errors) {
    if (web == null) return;
    final d = web.defaults;
    if (d.id == null || d.id!.isEmpty) {
      errors.add('web.default.id is required');
    }
  }

  static void _validateWindows(WindowsPlatform? windows, List<String> errors) {
    if (windows == null) return;
    final d = windows.defaults;
    if (d.id == null || d.id!.isEmpty) {
      errors.add('windows.default.id is required');
    }
  }
}
