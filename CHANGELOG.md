# Changelog

## 0.1.0

- Initial release
- CLI `sync` command: generates `ann_flavor.g.dart` from `annspec.yaml`
- CLI `validate` command: validates spec for missing required fields
- Android wiring: patches `settings.gradle.kts` and `app/build.gradle.kts`
- iOS wiring: patches `Podfile` with CocoaPods plugin reference
- Runtime API: `AnnFlavor`, `AnnFlavorConfig`, `AnnPlatform`, `AnnSubscription`, `AnnAuthConfig`
