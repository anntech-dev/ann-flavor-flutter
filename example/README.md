# ann_flutter_flavor — Example App

A minimal Flutter app with two flavors (**free** and **pro**) showing how to use
[ann_flutter_flavor](https://pub.dev/packages/ann_flutter_flavor).

## Structure

```
annspec.yaml                  ← flavor spec (edit this, then run sync)
lib/
  flavors/
    main_free.dart            ← entry point for the "free" flavor
    main_pro.dart             ← entry point for the "pro" flavor
  generated/
    ann_flavor.g.dart         ← GENERATED — do not edit (run sync to regenerate)
  main.dart                   ← shared app UI (FlavorApp widget)
```

## Run

```sh
# Install dependencies
flutter pub get

# Run free flavor
flutter run --flavor free -t lib/flavors/main_free.dart

# Run pro flavor
flutter run --flavor pro  -t lib/flavors/main_pro.dart
```

## Regenerate flavor code

After editing `annspec.yaml`, regenerate `lib/generated/ann_flavor.g.dart`:

```sh
dart run ann_flutter_flavor sync
```
