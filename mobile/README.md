# PingTools — Flutter Cupertino app (v2)

This directory contains the v2 mobile app: a pure Cupertino Flutter rewrite of the native PingTools v1 app.

- Ten network tools with streaming results
- Frosted-glass `BackdropFilter` navigation bar
- iOS spring physics (`SpringSimulation`) on cards and buttons
- English / 繁體中文 switch, persisted
- In-app GitHub release check, APK download with SHA-256 verification, and Android installer hand-off
- Same app id and signing key as v1, so it upgrades in place

## Run

```bash
flutter pub get
flutter run
```

## Test

```bash
flutter analyze
flutter test
```

## Release

Create `android/key.properties` from `android/key.properties.example`, then:

```bash
flutter build apk --release
```

Or from the repository root:

```bash
./scripts/flutter-release.sh
```

The release script verifies the signature and copies the APK (plus SHA-256) to `dist/`.

Architecture details: [`../docs/FLUTTER_ARCHITECTURE.md`](../docs/FLUTTER_ARCHITECTURE.md).
