# Changelog

All notable changes to PingTools are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/).

## [2.0.1] — 2026-11-26

### Fixed

- **Your last input is remembered per tool.** Ping, Geo Ping, Traceroute, Port
  Scanner (host and port list), DNS (query, record type and resolver), WHOIS,
  Subnet Scanner (CIDR and port-probe toggle), HTTP Inspector (URL and redirect
  setting) and the Wake-on-LAN form now restore what you typed after navigating
  away or restarting the app.
- Pending input writes are flushed when the app moves to the background, and
  saved immediately when a run starts or a screen is closed.

## [2.0.0] — 2026-11-26

### Changed

- **Rewritten in Flutter with a pure Cupertino architecture** (`mobile/`).
  The v1 Jetpack Compose implementation remains in the repository root.
- Same package id (`com.pinchiu.pingtools`) and signing key, so 2.0.0 installs
  as an in-place upgrade over 1.0.0.
- New responsive layout capped at 860 dp, adaptive 2/3/4-column tool grid.

### Added

- **iOS physics** — `SpringSimulation` (mass 1, stiffness 520, damping 30)
  drives press/release scaling on buttons and tool cards; native
  `CupertinoPageRoute` transitions throughout.
- **Frosted-glass navigation** — real `BackdropFilter` blur with a translucent
  bar, hairline border and content scrolling underneath.
- **English / 繁體中文 switch** — instant, persisted, applied to tool screens
  and Cupertino system controls.
- **In-app updates** — checks GitHub Releases, compares versions, downloads the
  APK with progress, verifies the attached SHA-256, launches the Android
  installer through a FileProvider, and guides the user through the
  “install unknown apps” permission when needed.
- Light / dark / system appearance with a custom network palette.
- Native bridge for connection details, Wi-Fi permissions, Maps/GitHub links,
  app version and APK installation.
- Unit tests for formatting, subnet math, version comparison, DNS wire parsing
  and Wake-on-LAN packets; Flutter CI workflow.

### Kept

- Ping, Geo Ping, Traceroute, Port Scanner, DNS Lookup, WHOIS, Subnet Scanner,
  Wake-on-LAN, Connection Info and HTTP Inspector, with recent-input history and
  saved Wake-on-LAN devices stored on-device.

## [1.0.0] — 2026-11-26

### Added

- Native Android (Kotlin + Jetpack Compose) release of the toolkit with ten
  network tools, Material 3 light/dark themes, streaming results, local history,
  saved Wake-on-LAN devices and CI.
