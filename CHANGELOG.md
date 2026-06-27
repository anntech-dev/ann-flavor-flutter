# Changelog

## 0.1.9

**pub.dev score improvements** — no API or behaviour changes.

- Fixed static analysis errors: `lib_cli/` is now included in the published package so `dart run ann_flutter_flavor` works correctly
- Shortened package description to meet pub.dev requirements (60–180 characters)

## 0.1.8

**Bug fix:** Running `dart run ann_flutter_flavor` now works correctly when installed from pub.dev.

## 0.1.7

**`validate` command is now much more thorough.** It catches common `annspec.yaml` mistakes before they cause a build failure:

- Conflicting `id` and `id_suffix` on the same flavor
- `firebase.file` and `firebase.project_id` both set at the same time
- `firebase.file` used on iOS (iOS requires `project_id`)
- Store configuration on the wrong platform (e.g. `google_play` under iOS, `app_store` under Android)
- `google_play.priority` set to a value outside the valid range (1–5)
- Android-specific build options (`minifyEnabled`, `shrinkResources`, NDK settings) placed under an iOS build type

See [CLI Commands](docs/flutter/cli-commands.md) for the full list of errors and warnings.

## 0.1.6

Internal release — dependency and tooling updates only. No API or behaviour changes.

## 0.1.5

- `AnnFlavor.init()` no longer requires passing `buildType` — it is detected automatically at compile time. Remove any `--dart-define=BUILD_TYPE=...` you previously needed.
- Added a runnable example app under `example/`.
- Full API documentation on all public classes.

## 0.1.4

**Custom attributes** — define any key-value data in `annspec.yaml` and access it at runtime per flavor and build type.

- Add a `custom:` block at `default`, `flavor`, or `build_types` level (any platform).
- Values cascade and deep-merge from default → flavor → build type.
- Access at runtime via `AnnFlavor.of(context).custom('group_name')` with typed getters: `string()`, `boolean()`, `integer()`, `decimal()`, `strings()`.

**Android** — per-flavor `AndroidManifest.xml` is now generated automatically. AdMob metadata is injected when `admob.gms_ads_id` is set.

**iOS** — per-flavor xcconfig files are generated automatically. `Info.plist` is patched to use xcconfig variables for bundle ID, display name, and version.

**AdMob** — `gms_ads_id` is now nested under an `admob:` block in the spec (breaking change from 0.1.3).

## 0.1.0

Initial release — `sync` and `validate` CLI commands, Android and iOS wiring, and the core runtime API.
