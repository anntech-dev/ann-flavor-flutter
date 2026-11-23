# Changelog

## 1.16.0

**Fixed:** The web files that `sync-web --scaffold-manifest` and `--scaffold-index` write now match the rest of the tooling. The manifest and the page name the icons `generate-icons` writes (`Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`); before, they named lowercase files that do not exist, so every icon was a 404 on a host that tells letter cases apart, such as Cloudflare Pages (a Mac hides it). The scaffolded page is now Flutter's current one and loads `flutter_bootstrap.js` (Flutter 3.22 or newer); before, it used the old loader, so a `canvaskit_base_url` was silently ignored. **Added:** `validate` and `sync-web` now warn about a flavor whose `canvaskit_base_url` its page does not load, and about an icon the manifest or page names that is missing or has another letter case. Existing templates are never rewritten: if you scaffolded before this version, the warnings tell you what to change. The guide and the requirement now list the generated icon names. See "Checks on the page and the icons" on the Web page of the guide.


## 1.15.0

**Added:** `validate` now checks web sites (`app.web.site`): it reports a site with no flavors, an unknown flavor, a flavor listed twice or in two sites, a flavor without a `base_href` or at `/`, equal or nested paths, a missing Cloudflare project, a `mode` other than `pages`, and a hub folder that does not exist, is a file, or holds a folder or file named like a flavor path. See "Publishing several flavors as one site" on the Web page of the guide.


## 1.14.0

**Added:** Web flavors have two new optional build options, in a `build:` block on `app.web.default` or on one flavor: `pwa_strategy` (`none` turns Flutter's service worker off) and `canvaskit_base_url` (where the page loads the CanvasKit drawing engine from, so several flavors on one site can share one copy). `sync-web --scaffold-bootstrap` creates a `flutter_bootstrap.tmpl.js` that uses the address, and `{{canvaskit_base_url}}` is available in your web templates. `validate` and `sync-web` report a wrong value as an error and warn when an address is set but no template uses it. Flavors without the block are unchanged. See "Build options" on the Web page of the guide.


## 1.13.0

**Added:** A web flavor can now be served under a path, such as `https://example.com/banking/`. Set `base_href: /banking/` on the flavor in `annspec.yaml`. `{{base_href}}` is then available in your web templates, and a new web manifest uses it for `start_url` and `scope`. `validate` and `sync-web` now tell you before the build fails if the page has no `$FLUTTER_BASE_HREF` (an error) or the manifest points outside the path (a warning). Flavors without `base_href` are unchanged. See "Serving a flavor under a path" on the Web page of the guide.


## 1.12.0

**Added:** `lib/generated/ann_links.g.dart` now also has ready-made helpers, so you do not read the map by hand. `linkFlavorOwningUri(uri)` (or `linkFlavorOwning(path)`) tells which flavor owns an incoming link, `flavor.handlesPath(path)` says whether this app should open it (its own prefix or one it also handles), `flavor.uri('/result/42')` builds the link to share, and `AnnLinkFlavorKey` names the flavors without typing strings. The `annLinks` map is unchanged, so nothing you already wrote breaks. See "Typed helpers" on the Deep Links page of the guide.

## 1.11.0

**Added:** With a `links:` section, `sync` now also writes `lib/generated/ann_links.g.dart`: the domain, path prefixes, app ids and platforms of each linked flavor as plain Dart data. Your code, or a link package, can read which prefix belongs to which flavor (for example that `/ta` links are Tamil's), which prefix to use when it builds a link to share, and the store ids, instead of writing them a second time. Without a `links:` section nothing is written. See "Reading the links in Dart" on the Deep Links page of the guide.

## 1.10.3

**Changed:** `sync` now says, in its deep links step, that the Android link rule is not written by `sync`: the Gradle plugin writes it into each flavor's `AndroidManifest.xml` the next time Gradle configures the project (an Android build such as `flutter build apk`, or a Gradle sync in Android Studio). Before, the manifests looked unchanged right after `sync` and it seemed the Android side was missing. The Deep Links page of the guide says the same.

## 1.10.2

**Fixed:** `validate` no longer shows two warnings that did not apply. It used to warn that a flavor with no `id` or `id_suffix` shares the default application ID, even when no other flavor has the same one (a main flavor that keeps the published ID next to suffixed flavors is normal). It now warns only when two flavors of a platform really end up with the same application ID. It also used to warn that no `service_account` was set for every build that names a Firebase `project_id`, although the default `sync` only writes `firebase.sh`, which you run while logged in. That warning now appears only with `validate --firebase-mode inline`, for when `sync` runs `flutterfire` itself, for example in CI.

## 1.10.1

**Fixed:** 1.10.0 could not be published because of a development-only check, so it never reached pub.dev. 1.10.1 has everything described under 1.10.0 (the `links:` section for deep links) with no change in behavior. If you were waiting for 1.10.0, upgrade to 1.10.1.

## 1.10.0

**Added:** Deep links from `annspec.yaml`. A new optional `links:` section makes links such as `https://links.example.com/en/test` open your app when it is installed. Give each app its own path (`/en`, `/ta`), list the signing fingerprints, and `sync` writes the iPhone setting for each app, and, for the repository that serves your domain, the two files Google and Apple read (`assetlinks.json` and `apple-app-site-association`) with the right headers. Several apps on one domain end up in the same files. An app can also open another app's links (`also_handles`). `sync` and `validate` stop with a clear message for a missing or malformed fingerprint or Team ID, a bad domain or path, or two apps whose paths overlap. Nothing changes for apps without a `links:` section. See the new Deep Links page in the guide.

**Fixed:** Preparing one web flavor no longer leaves another flavor's deep link files behind in `web/`, so a separate site (for example an admin site) does not ship them.

## 1.9.1

**Fixed:** `sync` and `upgrade` no longer stop with "`projects` is not a recognised firebase field" when `annspec.yaml` has the top-level `firebase:` section from 1.9.0. `validate` already accepted it; `sync` ran its own check that did not.

## 1.9.0

**Added:** One `firebase:` section in `annspec.yaml` for everything Firebase. Name your Firebase projects once under `firebase.projects` and use them for both Functions and rules, put the Functions settings under `firebase.functions`, and declare your Firestore and Storage rules files (and a Storage CORS file) under `firebase.rules`. `validate` now checks the whole section: duplicate or blank project ids, rules files that do not exist, a CORS file that is not a JSON list, and the same project written two different ways.

**Changed:** The top-level `functions:` section from 1.8.0 still works, but `validate` now warns about it and shows exactly what to move under `firebase:`. Having both `firebase.functions` and a top-level `functions:`, or the same project defined differently in both places, is an error. `functions-prepare` reads the new section and gives the same result as before.

## 1.8.2

**Fixed:** Generating web icons no longer changes your own `web/` folder. Before, `generate-icons` replaced `web/favicon.png`, deleted the files in `web/icons/` and reset the colors in `web/manifest.json`. Your `web/` folder is now set aside while the icons are made and put back afterwards, even if something fails. The icons still end up in `web_flavors/<flavor>/icons/`. If an earlier run was interrupted and left a `web.ann-backup` folder behind, the command now stops and tells you how to restore it.

## 1.8.1

**Fixed:** 1.8.0 could not be published because of a development-only check, so it never reached pub.dev. 1.8.1 has everything described under 1.8.0 (the `functions:` section and the `functions-prepare` command) with no change in behavior. If you were waiting for 1.8.0, upgrade to 1.8.1.

## 1.8.0

**Added:** A new `functions:` section in `annspec.yaml` and a `functions-prepare` command for Firebase Functions. Name your Firebase projects once, give each functions codebase its own settings, and the command copies your shared functions package into `build/functions/<codebase>/` and writes the `.env` file for each project from your own spec — so per-app values no longer live inside the shared package. It checks your function code for the values it needs and stops, before deploy, if a project is missing one or if a secret would be written to a file. `validate` now also checks the new section. Works the same on macOS, Linux and Windows.

## 1.7.6

**Fixed:** Generated plist files (e.g. `exportOptions.plist`) escaped `<` and `&` in string values but left `>` as a literal character — for example `<none>` came out as `&lt;none>` instead of `&lt;none&gt;`. Still valid XML either way, but inconsistent with the plist convention every other tool follows. `>` is now escaped consistently.

## 1.7.5

**Changed:** If your `annspec.yaml` doesn't pin a `tooling.gradle_plugin` version, `sync` now looks up the real, currently-published ANN Gradle plugin version from Maven Central instead of using a version bundled with this package — so you always get an up-to-date version even if you haven't upgraded `ann_flutter_flavor` in a while. This does mean `sync` now needs network access in that specific case; pin `tooling.gradle_plugin` in your `annspec.yaml` if you want `sync` to stay fully offline. If the lookup fails (no network, registry down), `sync` now fails with a clear error instead of silently using a possibly-outdated version.

## 1.7.4

**Added:** `sync` now generates a per-flavor, per-build-type `ios/ann/ExportOptions/<flavor>-<build_type>.plist` from your `annspec.yaml`, replacing a hand-maintained `exportOptions.plist` shared across your whole app. It auto-fills your team ID and App Store provisioning profile, and you can add or override any key with a new `export_options:` field (cascades the same way as your other iOS settings). If you were setting `credentials.app_store.export_options_plist`, `export_options_team_id`, or `export_options_signing_certificate`, remove them — they're retired and no longer read.

## 1.7.3

**Fixed:** 1.7.2 was published broken — every command failed immediately with a dependency resolution error. Fully fixed, safe to upgrade.

## 1.7.2

**Changed:** Version-only release, published alongside the other plugins for parity. No functional changes.

## 1.7.1

**Fixed:** Plugin-contributed permission text (added in 1.7.0) was being mixed into the wrong generated file, making it harder to tell what came from your own config versus a plugin. It now goes into its own file, with no change to the final build output.

## 1.7.0

**Added:** Plugins can now ship default Info.plist/entitlements values (e.g. permission descriptions) that your annspec.yaml can always override. Useful for plugins like ad SDKs that need standard iOS permission text.

## 1.6.2

**Fixed:** A bug where syncing could accidentally remove a local development override for the CocoaPods plugin dependency.

## 1.6.1

**Added:** Generated iOS build files that don't need to be committed to git are now automatically ignored.

## 1.6.0

**Fixed:** Info.plist and entitlements overrides configured for debug (or any non-release) build type were silently ignored and never made it into the generated app.

**Changed:** These per-build-type files are now merged into the app at pod-install time rather than being baked in earlier, working together with a matching update to the CocoaPods plugin.

## 1.5.0

**Added:** A new `env:` option lets you pass custom key-value pairs straight into the generated iOS build settings, with the same per-flavor override behavior as other settings. Also, a Google/Supabase sign-in setting (REVERSED_CLIENT_ID) is now generated automatically from your auth configuration, so you no longer need to set it by hand.

## 1.4.0

**Changed:** The Fastlane integration gem name changed (matching a rename of the underlying package). Syncing your project now updates your Gemfile automatically. Note: you still need to manually update the `fastlane_require` line in your Fastfile.

## 1.3.0

**Changed:** Generated iOS entitlements files now contain only the values you explicitly configured, instead of also duplicating your app's base entitlements file. There's no change to your actual built app — only to what the intermediate generated file contains.

## 1.2.0

**Changed:** Generated iOS Info.plist files no longer duplicate your app's base Info.plist content or hardcode values like app name and version — those already resolve correctly through Xcode's own build settings.

**Added:** Syncing your project now automatically fixes a few standard keys in your app's Info.plist if they're missing or set incorrectly. If you'd hand-written a literal value for one of these (like a hardcoded app name), it will be replaced with the correct placeholder — move any such values into your annspec.yaml instead. This may reformat the file the first time it runs; that's expected and harmless.

## 1.1.0

**Added:** You can now configure entitlements (like Sign in with Apple) per flavor in annspec.yaml, generating a proper entitlements file for each one. Previously, hand-authored entitlements could be silently lost when iOS project files were regenerated — this keeps that configuration safe and version-controlled.

## 1.0.28

**Fixed:** A bug in a third-party icon-generation library was corrupting iOS project build settings during app icon generation. Icon generation now protects your project file from this corruption automatically.

## 1.0.27

**Fixed:** Generating iOS icons for more than one flavor in a single run used to crash starting with the second flavor. All flavors now generate successfully in one pass.

## 1.0.26

**Fixed:** A leftover temporary file from an earlier interrupted run could cause a later, unrelated icon-generation run to silently produce the wrong output. Stale temp files are now cleaned up automatically before every run.

## 1.0.25

**Changed:** Removed a redundant source-image validation step for iOS icon generation. Any problem with your source image (wrong format, too small, etc.) is now reported directly and consistently, matching how Android and web icon generation already behave.

## 1.0.24

**Fixed:** Icon generation could fail with a "command not found" error when launched from the Studio plugin, depending on the system environment. It now reliably finds the correct tool regardless of how it was launched.

## 1.0.23

**Fixed:** Web icon generation as part of the icon-generation command was silently doing nothing. It now works correctly. Also fixed a side effect where a previous run's generated web icons could be left behind unintentionally.

## 1.0.22

**Added:** A new `generate-icons` command is now the single, unified way to generate app icons for Android, iOS, and web — used both from the command line and from Studio's "Generate App Icons" action.

**Fixed:** A long-standing bug meant generated iOS icons were being written into your app's own shared icon catalog instead of a dedicated per-flavor location — overwriting your app's default icon instead of creating a separate icon per flavor. This is now fixed, and your app's original icon is preserved.

## 1.0.21

**Fixed:** A pre-flight check that runs before iOS builds could fail silently on machines with certain system language settings, leaving a real configuration problem unfixed. This now works reliably regardless of system locale.

## 1.0.20

**Fixed:** A new project's very first iOS build could fail with a Swift version conflict error. An additional pre-flight fix now runs early enough to prevent this.

## 1.0.19

**Added:** You can now set the iOS deployment target and Swift version for your whole app in annspec.yaml, generated automatically into your iOS build settings.

**Fixed:** Fixed a fresh project's first iOS build failing because Flutter's default project template ships with the iOS platform line commented out.

## 1.0.18

**Changed:** The flavor `name` property no longer requires null-checking — it now always falls back to a sensible default instead of potentially being null.

**Added:** Added a convenient `id` shorthand for getting a flavor's identifier.

## 1.0.17

**Internal:** Internal refactor of how generated flavor code is structured. No change to any public API or app behavior.

**Added:** Restored convenient shorthand accessors (like `.name`, `.auth`) for the common case of querying the currently active platform and build type.

## 1.0.16

**Changed (breaking):** Reworked how generated code lets you query flavor properties (name, id, auth, Firebase options, custom config) for a specific platform. Each method now takes optional parameters, and a new `existsOn` check lets you safely test whether a flavor is configured for a given platform before querying it. The older separate convenience properties (`.name`, `.auth`, etc.) were removed in favor of this unified approach. Querying a property for a platform your flavor doesn't support now throws a clear error instead of silently returning wrong data.

**Fixed:** Previously, querying a flavor's name or ID for a platform it wasn't configured on could silently return an unrelated default value instead of failing clearly. Also fixed a case where a full ID override in configuration was being ignored.

## 1.0.14

**Added:** New per-platform accessor methods (`nameFor`, `idFor`, `authFor`, `firebaseOptionsFor`) give consistent, predictable behavior when a flavor's configuration varies — or is missing — for a specific platform.

**Changed:** Older properties like `.name` and `.auth` still work as convenient shortcuts built on top of the new methods.

**Deprecated:** A few older method names are deprecated in favor of the new, clearer ones.

**Removed (breaking):** Some old top-level helper functions for Firebase options were removed; use the new per-flavor methods instead.

**Fixed:** Fixed several bugs where flavor names, custom config values, and generated string values could resolve incorrectly or inconsistently across platforms and build types.

## 1.0.13

**Fixed:** Critical fix — installing this package from pub.dev (rather than using it inside its own monorepo) was completely broken, causing every command to fail with a package-resolution error. This is now fixed and verified against a real pub.dev-style install.

## 1.0.12

**Added:** Added support for generating per-flavor iOS launch screen images, matching what Studio's plugin already offered.

## 1.0.11

**Changed:** Generated iOS app icons now live in a dedicated tool-owned location instead of your app's own icon folder, keeping generated files clearly separated from files you manage yourself. Also fixed the corresponding build setting being set reliably every time you sync.

## 1.0.10

**Added:** Added per-flavor iOS Info.plist generation, replacing fragile in-place text edits to your app's single Info.plist. Custom keys you've added by hand (like camera permission text) are always preserved.

**Changed:** Generated iOS build configuration files moved to a new, clearly separated location that's safe to delete and regenerate at any time. Generation now fully regenerates output each time instead of patching files in place, so removed or changed settings always take effect.

## 1.0.9

**Changed:** Internal refactor — the tool now reads configuration through a shared internal library instead of its own separate copy. No user-facing behavior change from this alone.

**Fixed:** Fixed a bug where Firebase and auth settings configured only at the top ("default") level, without being repeated per flavor, were incorrectly ignored. Also fixed bundle/package IDs sometimes missing a configured suffix. Note: this may change generated output for projects that were unknowingly relying on the old, incorrect behavior.

## 1.0.8

**Added:** Internal groundwork for a future Info.plist customization feature. No visible behavior change in this release.

## 1.0.7

**Fixed:** Fixed a case where a stale Firebase configuration file path could cause iOS builds to fail with a "file not found" error during the build phase that copies Firebase config into your app.

## 1.0.6

**Added:** Syncing your project now automatically adds a required Firebase setup hook to your iOS Podfile if it's missing, so Firebase config works correctly out of the box for new projects.

## 1.0.5

**Changed:** Syncing your project no longer automatically regenerates iOS app icons as a side effect, since that step is slow and requires an extra dependency. Generate icons explicitly instead, using the dedicated icon-generation action or command.

## 1.0.4

**Fixed:** Generated code for custom configuration values no longer includes a redundant, always-identical case for "profile" builds, slightly simplifying the generated output.

## 1.0.3

**Fixed:** Fixed Firebase configuration being silently ignored for web and Windows platforms — only Android and iOS were previously wired up correctly.

## 1.0.2

**Fixed:** Fixed the `upgrade` command looking up the wrong package names for the Gradle and Fastlane plugins, which caused version lookups to silently fail. Also fixed syncing writing an incorrect, uninstallable Fastlane gem name into your Gemfile — this is now corrected automatically, including fixing any already-broken Gemfile from a previous sync.

## 1.0.1

**Changed:** Configuration parsing now goes through a shared internal library instead of ad-hoc parsing logic.

**Fixed:** Fixed a precedence bug where a flavor's own Firebase settings could be incorrectly overridden by unrelated default settings. Also fixed custom configuration not resolving correctly for profile builds.

## 1.0.0

**Added:** New `tooling:` section in annspec.yaml lets you declare and pin plugin versions. A new `upgrade` command automatically finds and applies the latest matching versions.

**Changed:** Syncing now writes more precise version constraints into your project files when a version is declared in the new `tooling:` section.

## 0.7.11

**Fixed:** Bundled plugin updates fix a profile-build Firebase config issue on Android and a Firebase file path issue on iOS.

## 0.7.10

**Fixed:** Bundled Android plugin update fixes a bug where your Firebase config file was being deleted after every build, causing failures on subsequent builds.

## 0.7.9

**Changed:** Maintenance release — no user-facing changes.

## 0.7.8

**Changed:** Bundled Android plugin update stops an unnecessary file rewrite on every build when nothing actually changed.

## 0.7.7

**Fixed:** Fixed a bug that could create duplicate entries in your Gemfile depending on which quote style was used.

## 0.7.6

**Fixed:** Fixed the required Podfile setup lines that get written during sync.

## 0.7.5

**Fixed:** Fixed an incorrect plugin name being written into your Podfile during sync.

## 0.7.4

**Changed:** Maintenance release — no user-facing changes.

## 0.7.3

**Fixed:** Fixed duplicate-entry detection in your Gemfile to handle both quote styles correctly.

## 0.7.2

**Changed:** Removed web icon generation from the `sync-web` command (use the dedicated app icons command instead) and stopped automatically modifying .gitignore for web build output files, since those are meant to be tracked in git.

## 0.7.1

**Added:** Web asset syncing now correctly excludes a Cloudflare Workers config template from being copied into your web output. Also added a new template variable for referencing the per-flavor web output directory.

## 0.7.0

**Added:** New `sync-web` command handles web flavor setup end-to-end: selecting a flavor, rendering template files, regenerating version info, generating PWA icons, and copying everything into your web build. Also added template-based scaffolding helpers for getting started with web manifests and HTML.

## 0.6.0

**Added:** Your app's App Store ID (if configured) is now available at runtime through the generated flavor config.

## 0.5.0

**Added:** Added per-flavor iOS icon support, including automatic generation from a source image and the build settings needed for Xcode to pick up the right icon per flavor. Syncing now includes icon generation as an automatic step for any flavor with an icon configured.

## 0.4.12

**Fixed:** Fixed a bug where platform-level default auth configuration was being ignored for web and Windows, and in some cases for Android and iOS as well.

## 0.4.11

**Fixed:** Fixed a Dart compile error in generated code that only configured some platforms. Also cleaned up a lint warning in generated files.

## 0.4.10

**Added:** Added separate helper functions for getting Firebase options by build type, and a convenient default `auth()` method that automatically picks the right config for the current build.

**Breaking:** The `auth()` method was renamed to `authRelease()` — if you had overridden it, rename your override. Running `sync` regenerates the affected file automatically with the correct name.

**Fixed:** Bundled Android plugin update ensures Firebase file copying happens reliably before build cleanup runs.

## 0.4.9

**Fixed:** Bundled Android plugin update fixes a Firebase config file copy path issue.

## 0.4.8

**Fixed:** Fixed an incorrect command-line flag name used when generating Firebase configuration for iOS.

## 0.4.7

**Added:** You can now specify which Xcode target Firebase setup should target, configurable per flavor and build type.

**Fixed:** Fixed Firebase setup for iOS failing due to an incorrect output file argument.

## 0.4.6

**Added:** New `validate-testspec` command validates your test spec file on its own, with a machine-readable output option for CI use. Syncing now also automatically adds the required CocoaPods plugin to your Gemfile when iOS is configured, fixing a previously confusing "plugin not installed" build failure.

**Fixed:** Fixed noisy terminal output from Firebase setup scripts when run in non-interactive environments. Also fixed Firebase config files being written to a temporary location instead of a stable, committable one, and adjusted cleanup so committed Firebase files are no longer accidentally deleted on re-run.

## 0.4.5

**Fixed:** Fixed the Gradle plugin version not being updated in your project when an entry already existed but was out of date.

**Changed:** The default mode for generating Firebase configuration during sync changed from running immediately to generating a script you run separately — this prevents sync from hanging when Firebase authentication isn't available. If you relied on the old immediate-run behavior, you'll need to opt back into it explicitly; see the migration note in the technical changelog for the exact flag.

## 0.4.4

**Changed:** Maintenance release — bundled Android plugin version update, no functional change to this package.

## 0.4.3

**Changed:** Maintenance release — bundled Android plugin version update fixing a Firebase default config issue, no change to this package's own behavior.

## 0.4.2

**Changed:** Generated Podfile and Gemfile entries now include an explanatory comment so it's clear they shouldn't be removed by hand. Also, syncing no longer overwrites your app's bundle ID or minimum SDK version in your Android build file — those remain yours to manage. Firebase setup scripts are now more robust, reporting success or failure clearly and exiting with an error code if anything failed. Generated Firebase commands are also now more accurate for multi-flavor projects.

## 0.4.1

**Added:** Firebase service account credentials can now be set once at a shared level instead of being repeated for every build type, using the same override cascade as other settings.

## 0.4.0

**Added:** New `--firebase-mode script` option generates a shell script for Firebase setup instead of running it immediately — useful when Firebase credentials aren't available at sync time. Sync now also validates your configuration before generating any files, aborting cleanly if there are errors. Added a `--format json` output option for CI and IDE integrations. Added a `doctor` command (replacing the old `version` command) that checks your installed plugin versions against expected targets.

**Changed:** Reordered internal sync steps for better performance. Using `config_file` for Firebase on iOS is now a hard error — iOS must use `project_id` instead.

## 0.3.0

**Changed:** Firebase setup now authenticates exclusively via a service account — Google Cloud/Firebase CLI login is no longer used or supported.

**Added:** Added a `validate --format json` option for IDE integration, and a new `version` command that checks your installed plugin versions against what's expected. Also added several new validation warnings around Firebase configuration.

## 0.2.5

**Changed:** Internal publishing process improvements — no user-facing changes.

## 0.2.4

**Added:** Firebase setup now times out after 120 seconds instead of potentially hanging forever on auth or network issues.

**Fixed:** Fixed relative signing certificate/key paths sometimes not resolving correctly depending on which directory a build was run from.

## 0.2.2

**Changed:** Redesigned the `summary` command's output to be organized by flavor and build type, showing the fully resolved value of every setting after all your configuration layers are applied.

## 0.2.1

**Added:** The `validate` command now shows a warning when your spec is disabled, and gives much more detailed error and warning messages — including the exact location of the problem and a suggested fix.

## 0.2.0

**Changed (breaking):** The root configuration key in annspec.yaml was renamed from `annai_app:` to `app:`. A clear migration message is shown if the old key is detected.

## 0.1.9

**Changed:** Internal documentation and packaging improvements for pub.dev — no user-facing behavior changes.

## 0.1.7

**Added:** Greatly expanded the `validate` command with comprehensive checks across bundle IDs, version formats, Firebase settings, store IDs, signing paths, and unrecognized fields.

## 0.1.6

**Added:** Build type (debug/release) is now detected automatically — no need to pass it manually during setup. Firebase configuration is simplified into two clear modes: pointing to a static config file, or generating one automatically. An example app with multiple flavors is now included in the package.

## 0.1.4

**Added:** New `integrations:` section lets you enable Fastlane and Melos support, automatically generating the relevant configuration files. Manually written content in these files is always preserved.

## 0.1.3

**Changed:** Internal publishing pipeline improvements — no user-facing behavior changes.

## 0.1.2

**Changed:** Internal CI/workflow fix — no user-facing behavior changes.

## 0.1.1

Initial release.
