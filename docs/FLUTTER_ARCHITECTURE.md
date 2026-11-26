# Flutter (Cupertino) architecture

The v2 app in [`mobile/`](../mobile) is a pure Cupertino Flutter application. It is a full rewrite of the v1 Jetpack Compose app, with the same package id (`com.pinchiu.pingtools`) and signing key so it upgrades in place.

## Layers

```
mobile/lib/
├── main.dart                 bootstrap (settings + runApp)
├── app.dart                  CupertinoApp, locale, light/dark theme
├── core/
│   ├── models.dart           immutable domain models and sealed events
│   ├── app_settings.dart     SharedPreferences: locale, theme, history, WoL
│   ├── native_bridge.dart    MethodChannel to the Android host
│   ├── net/                  network services (streams / futures)
│   └── util/format.dart      parsers and formatters
└── ui/
    ├── theme.dart            palette + CupertinoThemeData
    ├── localization.dart     context.tr(en, zh) and palette extension
    ├── widgets.dart          frosted page, springy tap, cards, fields, stats
    ├── tool_registry.dart    tool metadata (bilingual, icon, accent)
    └── screens/              one screen + ChangeNotifier ViewModel per tool
```

Following Flutter's recommended MVVM split, screens own a small
`ChangeNotifier` view model for streaming state and commands; networking lives
in stateless services under `core/net`; the views stay declarative. Screens
never block the UI isolate: sockets, processes and file I/O are asynchronous.

## Streaming engines

Long-running tools are cold Dart streams:

```dart
PingEngine.ping(PingConfig)          -> Stream<PingEvent>
TracerouteEngine.trace(TraceConfig)  -> Stream<TraceEvent>
PortScanner.scan(PortScanConfig)     -> Stream<PortScanEvent>
SubnetScanner.scan(SubnetConfig)     -> Stream<SubnetScanEvent>
```

One-shot engines return futures (`DnsEngine`, `WhoisEngine`, `HttpEngine`,
`GeoEngine`, `WolEngine`). All failures become typed error events/results, so the
UI never receives an unhandled network exception. Cancel a stream subscription
to stop a scan; engines close sockets, kill ping processes and stop loops.

## Native bridge

A single `MethodChannel` (`com.pinchiu.pingtools/native`) connects Dart to
Kotlin:

| Method | Purpose |
| --- | --- |
| `connectionInfo` | local IPv4/IPv6, prefix, gateway, DNS, Wi-Fi details, carrier, VPN |
| `appVersion` | installed `versionName` for the updater |
| `requestWifiPermissions` | runtime fine-location + nearby-Wi-Fi request |
| `openUrl` | Maps / GitHub links |
| `canInstallPackages` / `installApk` | APK install via FileProvider |

The Kotlin side only reads system state and starts intents; all network work
happens in Dart. Wi-Fi and telephony calls are individually guarded so denied
permissions degrade to `null` rather than crashing.

## In-app update flow

1. `UpdateService.check()` calls the GitHub `releases/latest` API with a
   `PingTools/2.0` user agent, picks the `.apk` asset and compares semantic
   versions.
2. The APK is streamed to
   `<app support dir>/updates/PingTools-<version>.apk` with progress callbacks.
3. When the release includes a `.sha256` asset, the downloaded file is verified
   with `package:crypto` before installation.
4. `NativeBridge.installApk` uses a `FileProvider` URI and
   `Intent.ACTION_VIEW` (`application/vnd.android.package-archive`). On Android
   8+ the app first opens the “install unknown apps” settings if the user has
   not allowed it, then the user retries.

The update is user-initiated and never silent. No server or account is involved.

## Cupertino details

- **Frosted navigation** — `FrostedPage` stacks a `BackdropFilter`
  (`ImageFilter.blur(sigmaX: 26)`) with a translucent palette colour over the
  scrolling content, plus a 0.5 pt hairline. The bar extends behind the status
  bar using `MediaQuery.paddingOf(context).top`.
- **Spring physics** — `SpringyTap` drives an unbounded `AnimationController`
  with `SpringSimulation(mass: 1, stiffness: 520, damping: 30)` for press-down
  and release; buttons and tool cards use it. Page transitions are native
  `CupertinoPageRoute` transitions.
- **Responsive layout** — content is capped at 860 dp and centered; the home
  tool grid switches between 2/3/4 columns with `LayoutBuilder`.
- **Bilingual UI** — every visible string goes through
  `context.tr('English', '繁體中文')`. The locale lives in `AppSettings` and is
  applied through `CupertinoApp.locale`, with Flutter's
  `GlobalCupertinoLocalizations`/`GlobalWidgetsLocalizations` delegates so
  system controls, pickers and text-selection menus follow the chosen language.
- **Metal-like dark palette** — custom cyan accent, near-black navy background,
  monospaced data values and restrained borders, with a matching light theme.

## Build and test

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release      # signed with android/key.properties
```

`key.properties` is git-ignored. The release keystore is the same one used by
v1 so Android accepts the v2 APK as an in-place upgrade.
