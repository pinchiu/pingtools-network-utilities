# Changelog

All notable changes to PingTools are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-11-26

### Added

- **Ping** — ICMP echo with live RTT sparkline, loss, jitter, standard deviation
  and a TCP-connect fallback for devices that block raw ICMP.
- **Geo Ping** — resolves a host, measures latency and shows city-level
  geolocation, ISP/ASN, coordinates and an “Open in Maps” link.
- **Traceroute** — hop-by-hop ICMP TTL discovery with three probes per hop and
  best-effort reverse DNS.
- **Port Scanner** — concurrent TCP connect scan, presets, service names and
  banner grabbing.
- **DNS Lookup** — A, AAAA, CNAME, MX, NS, TXT, SOA, SRV, CAA and PTR queries
  against system, Cloudflare, Google, Quad9, OpenDNS or AdGuard resolvers.
- **WHOIS** — port-43 client with TLD bootstrap, IANA referrals, parsed key
  fields and the full raw record.
- **Subnet Scanner** — auto-detects the local subnet, scans any CIDR/range for
  live hosts, reverse-DNS names, gateway flagging and optional common-port probes.
- **Wake-on-LAN** — magic-packet sender with saved devices, custom broadcast,
  port and optional SecureOn password.
- **Connection Info** — local IPv4/IPv6, gateway, DNS, Wi-Fi details and public
  IP with ISP/ASN/geolocation.
- **HTTP Inspector** — status, redirects, timing, protocol, TLS details, headers
  and security-header checks.
- Dark/light Material 3 design with a custom network-blue palette, recent-target
  history and a small on-device store for saved Wake-on-LAN devices.
- GitHub Actions CI that builds the debug APK and runs unit tests.

[1.0.0]: https://github.com/pinchiu/pingtools-network-utilities/releases/tag/v1.0.0
