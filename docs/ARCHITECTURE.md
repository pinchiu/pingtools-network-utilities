# Architecture

PingTools is a single-module Android app written in Kotlin with Jetpack Compose.
There is no backend: every tool runs on-device and results stream straight into
the UI.

## Layers

```
MainActivity
└── ui/PingToolsApp (Navigation Compose)
    ├── ui/screens/*Screen.kt        one screen + ViewModel per tool
    ├── ui/components/Components.kt  shared cards, fields, stat tiles, code text
    └── ui/theme/                    Material 3 palette, typography, theme store

core/
├── model/Models.kt      shared configs, results and sealed event types
├── net/*Engine.kt       pure networking engines, exposed as Flow
├── data/HistoryStore.kt recent inputs + saved Wake-on-LAN devices
└── util/                process runner and formatting/parsing helpers
```

Screens never open sockets or start processes. They call an engine from a
`viewModelScope` coroutine, reduce its events into a single Compose state object,
and render that state. Engines never touch Android UI and never throw for network
failures — they emit `Failed(...)`, set an `error` field, or return a `Result`.

## Streaming contract

Long-running tools expose a cold `Flow` of sealed events:

```kotlin
PingEngine.ping(config): Flow<PingEvent>
TracerouteEngine.trace(config): Flow<TraceEvent>
PortScanner.scan(config): Flow<PortScanEvent>
SubnetScanner.scan(config): Flow<SubnetScanEvent>
```

One-shot tools are `suspend` functions returning a result object:

```kotlin
DnsEngine.lookup(name, type, resolver): DnsResult
DnsEngine.reverse(ip, resolver): DnsResult
WhoisEngine.lookup(query): WhoisResult
HttpEngine.inspect(url, followRedirects, timeoutMs): HttpInfo
IpInfoEngine.connectionInfo(context): ConnectionInfo
IpInfoEngine.publicIp(): PublicIpInfo
IpInfoEngine.geoLookup(ip): PublicIpInfo
WolEngine.wake(mac, broadcast, port, secureOn): Result<WolOutcome>
```

This keeps cancellation predictable: cancelling the collecting job stops the
scan and closes in-flight sockets. `CancellationException` is always rethrown.

## Engine notes

### Ping

Android denies raw ICMP sockets to some apps depending on the kernel's
`ping_group_range` policy. The engine probes `127.0.0.1` once with the platform
`ping` binary:

- success → one `ping -c 1` process per packet, parsed for RTT, TTL and source;
- failure → TCP connect timing to 443, 80 or 53, labelled “TCP fallback” in the UI.

Statistics (min/avg/max, jitter, population standard deviation) are computed
from received replies; loss is derived from attempts. Continuous mode runs until
the flow is cancelled.

### Traceroute

There is no `traceroute` binary on modern Android, so the engine sends ICMP echo
requests with increasing TTL (`ping -t <ttl>`). Router replies are detected from
“Time to live exceeded”/“TTL expired” lines; the destination reply is recognised
by its source address. Reverse DNS runs on a daemon thread with a hard 700 ms
cap so a stuck resolver cannot stall the trace.

### Port scanner

TCP connect scanning with a `Semaphore` (max 128 in-flight sockets). A connect
success is `OPEN`, “connection refused” is `CLOSED`, timeouts and unreachable
errors are `FILTERED`. Open sockets are tracked so cancellation can close them.
Banners are read with a 600 ms timeout; cleartext HTTP ports are nudged with a
`HEAD` request, while TLS ports are not probed with cleartext to avoid a
misleading `400` banner.

### Subnet scanner

`NetworkInterface` supplies the local IPv4 address and prefix. The gateway comes
from `LinkProperties` (or Wi-Fi DHCP) because Android 10+ blocks `/proc/net/route`
for apps; `/proc/net/route` and `/proc/net/arp` are still used opportunistically
on older devices. Hosts are probed with the same ICMP binary in batches, then
reverse-resolved with a 600 ms cap and optionally port-probed. MAC addresses are
often unavailable on Android 10+ and are shown as `--` rather than guessed.

### DNS

`dnsjava` 3.6.2 with an explicit 4 s timeout and one retry. All record types are
mapped, including PTR through `ReverseMap`. “System” uses dnsjava's Android
resolver provider, which requires a `Context`; `IpInfoEngine.connectionInfo`
installs it at startup so the DNS screen works without extra plumbing.

### WHOIS

Raw TCP port 43. IANA only knows TLDs, so domains are bootstrapped by querying
the TLD (`com` → `whois.verisign-grs.com`) before the full name. Referrals are
followed at most twice, responses are capped at 512 KB, and duplicate servers are
skipped. The UI highlights registration dates, registrar, status and name servers.

### HTTP inspector

A `HEAD` request is attempted first, falling back to a ranged `GET` for servers
that reject `HEAD`. Response bodies are never downloaded. TLS version/cipher come
from OkHttp's handshake; security checks report HSTS, CSP, frame options, content
type options, referrer policy and cleartext usage.

## Platform limitations

- ICMP and port 43 may be blocked by mobile carriers; tools report this explicitly.
- MAC addresses and `/proc/net/*` are restricted on Android 10+.
- Public-IP geolocation is city-level and depends on `ipwho.is`/`ipapi.co`.
- Wi-Fi SSID/BSSID require location and (Android 13+) nearby-Wi-Fi permissions;
  some devices still redact them.

## Testing

- `app/src/test/java/.../FormatTest.kt` covers host/port/subnet/MAC parsing and
  formatting.
- CI builds the debug APK and runs those tests on every push.
- Engines were additionally exercised on a local JVM (ping, traceroute, DNS,
  WHOIS, HTTP) and in an Android 15 emulator (all ten tools, screenshots in
  `docs/screenshots`).
