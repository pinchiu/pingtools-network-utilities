# PingTools build contracts (agent coordination)

Project root: `/home/scott/Projects/pingtools-network-utilities`
Package: `com.pinchiu.pingtools`
Stack: Kotlin 2.0.21, Jetpack Compose (BOM 2024.09.00), Material 3, minSdk 24, compileSdk/targetSdk 36, AGP 8.12.3, Gradle 8.13, JDK 21 (jvmTarget 17).

The app is a network-utilities toolkit. It has **no backend**. All engines run on-device.

## Rules

1. **Only create/edit the files assigned to you.** Never modify shared files:
   `Models.kt`, `Format.kt`, `Shell.kt`, `HistoryStore.kt`, `Components.kt`,
   `Theme.kt`, `Color.kt`, `AppNav.kt`, `ToolRegistry.kt`, `MainActivity.kt`,
   `AndroidManifest.xml`, gradle files, or another agent's files.
2. Do not add dependencies. Available: Compose M3 + material-icons-extended,
   lifecycle-runtime-compose / viewmodel-compose, navigation-compose,
   activity-compose, kotlinx-coroutines-android, OkHttp 4.12, dnsjava 3.6.2,
   org.json (platform).
3. Keep the public signatures given below exactly. UI code is written against them.
4. Never let an exception escape an engine or a screen. Convert failures into the
   data/error fields. `CancellationException` must always be rethrown.
5. Text visible in the UI must be English. Code comments in English. No placeholder
   or "TODO" UI. No fabricated data — if something is unknown, show `--`.
6. Do not run `./gradlew clean`, `installDebug`, or release builds. You MAY run
   `./gradlew :app:compileDebugKotlin --console=plain -q` from the project root to
   type-check. Ignore errors in files you do not own (other agents may be mid-edit).
7. No secrets, no analytics, no ads, no telemetry.

## Shared utilities (already implemented)

`core/util/Format.kt`:
```kotlin
fun fmtLatency(ms: Double): String
fun fmtPercent(value: Double, decimals: Int = 1): String
fun formatBytes(bytes: Long): String
fun formatDuration(ms: Long): String
fun normalizeHost(input: String): String
fun isValidIpv4(value: String): Boolean
fun isPrivateIp(value: String): Boolean
fun parsePortSpec(spec: String): List<Int>          // throws IllegalArgumentException
fun serviceNameForPort(port: Int): String
val PORT_PRESETS: List<Pair<String, String>>         // label to spec
fun normalizeMac(input: String): String?
fun parseSubnetInput(input: String): SubnetInfo?     // "a.b.c.0/24" or range
fun ipv4ToLong(ip: String): Long?
fun longToIpv4(value: Long): String
```

`core/util/Shell.kt`:
```kotlin
object Shell {
    data class Result(val exitCode: Int, val stdout: String, val stderr: String) {
        val combined: String
    }
    fun pingBinary(): String   // absolute path to /system/bin/ping when present
    suspend fun exec(command: List<String>, timeoutMs: Long = 15_000,
                     onLine: ((String) -> Unit)? = null): Result
}
```

`ui/components/Components.kt` (Compose):
```kotlin
@Composable fun ToolScaffold(title: String, onBack: () -> Unit, subtitle: String? = null,
    scrollable: Boolean = true, actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit)
@Composable fun SectionCard(modifier: Modifier = Modifier, title: String? = null,
    content: @Composable ColumnScope.() -> Unit)
@Composable fun LabeledField(label: String, value: String, onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier, placeholder: String = "", enabled: Boolean = true,
    singleLine: Boolean = true, keyboardType: KeyboardType = KeyboardType.Text,
    trailing: (@Composable () -> Unit)? = null)
@Composable fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, loading: Boolean = false, icon: ImageVector? = null)
@Composable fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, icon: ImageVector? = null)
@Composable fun StatTile(label: String, value: String, modifier: Modifier = Modifier,
    accent: Color? = null, unit: String? = null)
enum class PillTone { Neutral, Success, Warning, Danger, Info }
@Composable fun Pill(text: String, tone: PillTone = PillTone.Neutral, modifier: Modifier = Modifier)
@Composable fun MonoText(text: String, modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.onSurface, size: TextUnit = 13.sp,
    weight: FontWeight = FontWeight.Normal, maxLines: Int = Int.MAX_VALUE)
@Composable fun EmptyState(icon: ImageVector, title: String, body: String, modifier: Modifier = Modifier)
@Composable fun ErrorBanner(message: String, modifier: Modifier = Modifier)
@Composable fun CopyableRow(label: String, value: String, modifier: Modifier = Modifier,
    valueColor: Color = MaterialTheme.colorScheme.onSurface)
@Composable fun DataRow(label: String, value: String, modifier: Modifier = Modifier,
    valueColor: Color = MaterialTheme.colorScheme.onSurface, mono: Boolean = true)
@Composable fun ResultCountRow(count: Int, label: String, modifier: Modifier = Modifier)
@Composable fun InlineAction(text: String, onClick: () -> Unit, enabled: Boolean = true)
@Composable fun KeyValueChip(key: String, value: String, modifier: Modifier = Modifier)
```

`core/data/HistoryStore.kt`:
```kotlin
object HistoryStore {
    fun recent(context: Context, tool: String, limit: Int = 5): List<String>
    fun add(context: Context, tool: String, value: String)
    fun clear(context: Context)
    fun savedDevices(context: Context): List<WolDevice>
    fun saveDevice(context: Context, device: WolDevice)
    fun removeDevice(context: Context, mac: String)
}
```

History tool keys: `"ping"`, `"geo"`, `"trace"`, `"ports"`, `"dns"`, `"whois"`, `"subnet"`, `"wol"`, `"http"`.

`ui/ToolRegistry.kt`: `Routes.*`, `Tools.all`, `Tools.byRoute(route)`, each `ToolInfo` has
`route, title, subtitle, icon, accent`. Use `Tools.byRoute(Routes.PING)?.accent` for accents.

---

# ENGINE WAVE — exact APIs

Engines live in `app/src/main/java/com/pinchiu/pingtools/core/net/` unless stated.

## 1. PingEngine.kt

```kotlin
object PingEngine {
    fun ping(config: PingConfig): Flow<PingEvent>
}
```

- Resolve the target (`normalizeHost`, then `InetAddress.getByName` on `Dispatchers.IO`).
  Emit `PingEvent.Started(target, resolvedIp, mode)` once ready.
- Detect ICMP permission first with one probe to `127.0.0.1`:
  `Shell.exec(listOf(Shell.pingBinary(), "-c", "1", "-W", "1", "127.0.0.1"), 3000)`.
  If it fails with permission/socket/unknown-option errors, use `PingMode.TCP` and emit
  `PingEvent.Note("ICMP is not permitted on this device — using TCP connect latency")`.
- **ICMP:** one process per packet (`ping -c 1 -W <sec> -s <size> -t <ttl> <ip>`).
  Parse `time=12.3 ms`, `time<1ms`, `ttl=57`, and the `bytes from a.b.c.d` address.
  Success → `PingEvent.Reply`; no reply → `PingEvent.Timeout`.
  Fatal text (`Network is unreachable`, `unknown host`) → `Failed` and stop.
- **TCP fallback:** try ports 443, 80, 53 in that order; measure `Socket.connect`
  with `timeoutMs`; label `from = "$ip:$port"`, `bytes = 0`, `ttl = null`.
- `count == 0` → continuous until cancelled. Otherwise exactly `count` attempts.
  `intervalMs` delay between attempts. Respect cancellation at every loop step.
- On completion emit `PingEvent.Finished(summary, replies)`.
  Summary: loss %, min/avg/max, jitter = mean absolute delta between consecutive RTTs,
  stdDev = population standard deviation. Zero replies → all numeric fields 0.
- The flow must not throw for network errors; emit `Failed(message)`.

## 2. TracerouteEngine.kt

```kotlin
object TracerouteEngine {
    fun trace(config: TraceConfig): Flow<TraceEvent>
}
```

- Resolve target, emit `Started`.
- For TTL 1..`maxHops`, send `probesPerHop` ICMP probes:
  `ping -c 1 -W <ceil(timeoutMs/1000)> -t <ttl> <ip>`, sequential; collect RTTs.
- Router response patterns to parse (`From <ip> ... Time to live exceeded`,
  `From <ip> ... TTL expired`, `From <ip> icmp_seq=... Time to live exceeded`).
  Target reached when output has `bytes from <target>` with a `ttl=` field.
- Emit `HopFound(TraceHop(hop, address, hostname, rtts))` per TTL (address null and
  empty rtts when silent). Do reverse DNS only for non-private addresses, with a hard
  700 ms cap (use a single-thread executor + Future.get, never `canonicalHostName`
  without a timeout). `location`/`countryCode` stay null.
- Stop at target or after maxHops; emit `Finished(hops, reachedTarget)`.
- If ICMP permission probe fails, emit `Failed("ICMP is blocked on this device; traceroute requires raw ICMP support.")`.

## 3. PortScanner.kt

```kotlin
object PortScanner {
    fun scan(config: PortScanConfig): Flow<PortScanEvent>
}
```

- Resolve host, emit `Started(host, resolvedIp, total)`.
- TCP connect scan with a `Semaphore(config.concurrency.coerceIn(1, 128))`, total
  timeout per port = `config.timeoutMs`.
- Success → OPEN. `ConnectException` with "refused" → CLOSED. Timeout → FILTERED.
  Other unreachable errors → FILTERED.
- Emit `Progress(scanned, total, openSoFar sorted by port)` at most ~10×/second and
  always for a newly opened port.
- Banner grab on OPEN when `grabBanners`: 600 ms read timeout, up to 512 bytes; for
  80/443/8080/8443 send `HEAD / HTTP/1.0\r\nHost: <host>\r\n\r\n` first. Collapse
  whitespace, keep first line, max 160 chars, strip control chars.
- `Finished(results sorted by port, durationMs)`. Use `serviceNameForPort`.
- Cancellation: close open sockets; rethrow `CancellationException`.

## 4. SubnetScanner.kt

```kotlin
object SubnetScanner {
    fun scan(config: SubnetConfig): Flow<SubnetScanEvent>
    suspend fun detectLocalSubnet(): SubnetInfo?
    fun hostsFor(info: SubnetInfo): List<String>
}
```

- `detectLocalSubnet`: first non-loopback, site-local IPv4 `NetworkInterface` address
  with prefix 8..30. `cidr` = network address/prefix, `localIp` = device address,
  `gateway` from `/proc/net/route` (dest `00000000`, little-endian hex), `totalHosts`.
- `hostsFor`: CIDR → all usable host addresses (exclude network/broadcast; cap 4096);
  explicit range → every address in range. Empty when unparseable.
- `scan`: use `parseSubnetInput(config.cidr)`, emit `Failed` when null or >4096 hosts.
  Emit `Started(info)`. Probe in batches of `concurrency` with a single ICMP ping
  (`-c 1 -W max(1, ceil(timeoutMs/1000))`). After each batch read `/proc/net/arp` for
  MACs and emit `Progress(scanned, total, found sorted numerically)`.
  Hostname lookup: max 600 ms per discovered host, skip when absent/failure.
  `isGateway` when IP == info.gateway.
  If `includePortProbe`, probe `probePorts` on each discovered host (connect timeout
  400 ms) and attach open ports.
  `Finished(hosts, durationMs)`. Timeouts are normal, not errors.

## 5. WolEngine.kt

```kotlin
object WolEngine {
    suspend fun wake(
        mac: String,
        broadcast: String = "255.255.255.255",
        port: Int = 9,
        secureOn: String? = null
    ): Result<WolOutcome>
}
```

- Validate with `normalizeMac`; return `Result.failure(IllegalArgumentException("Invalid MAC address"))`
  when invalid. Build magic packet (6 × 0xFF + 16 × MAC + optional 6-byte SecureOn).
- `DatagramSocket().apply { broadcast = true }`, send 3 packets 60 ms apart, close.
  Resolve broadcast hostname to IP, validate port 1..65535. Wrap I/O errors in `Result.failure`.

## 6. DnsEngine.kt

```kotlin
object DnsEngine {
    val RESOLVERS: List<Pair<String, String>>   // display label to address, "system" first
    suspend fun lookup(name: String, type: DnsType, resolver: String? = null): DnsResult
    suspend fun reverse(ip: String, resolver: String? = null): DnsResult
}
```

- dnsjava 3.6.2: `SimpleResolver`, `Message.newQuery`, `Record.newRecord`,
  `Type`/`DClass`, `ReverseMap.fromAddress`. 4 s timeout, single retry is fine.
- Map every `DnsType` (A, AAAA, CNAME, MX, NS, TXT, SOA, SRV, CAA, PTR).
  `DnsRecord.type` = `Type.string(type)` (or record type name), `value = rdataToString()`,
  `ttl = record.ttl`. Resolver label in the result.
- `resolver == null || "system"` → default `SimpleResolver()`; otherwise the given IP.
- Reverse input: accept IPv4/IPv6; invalid → error result. Never throw.

## 7. WhoisEngine.kt

```kotlin
object WhoisEngine {
    suspend fun lookup(query: String): WhoisResult
}
```

- Normalize with `normalizeHost` for domains (keep IPv4 addresses as-is).
- Query `whois.iana.org:43`, parse `refer:` / `whois:` line, follow up to 2 referrals.
  Plain `Socket` with 8 s connect/read timeout, read to EOF, cap at 512 KB, ISO-8859-1.
- Parse `Key: Value` lines into `WhoisField`s (skip `%`, `#`, `>>>` comments; append
  indented continuation lines to the previous value; cap 200 fields).
- `server` = last server queried. Empty/blocked response → `error`.
- Never throw.

## 8. IpInfoEngine.kt

```kotlin
object IpInfoEngine {
    fun connectionInfo(context: Context): ConnectionInfo
    suspend fun publicIp(): PublicIpInfo
    suspend fun geoLookup(ip: String): PublicIpInfo
}
```

- OkHttp client with 8 s connect/read timeouts, `User-Agent: PingTools/1.0`.
- `publicIp()`: `https://ipwho.is/` then `https://ipapi.co/json/`. Parse into
  `PublicIpInfo` (isp/org/asn/city/region/country/countryCode/lat/lon/timezone).
- `geoLookup(ip)`: private IP → error `"Private address — no public geolocation"`;
  otherwise `https://ipwho.is/{ip}` then `https://ipapi.co/{ip}/json/`.
- `connectionInfo`: ConnectivityManager transports (Wi-Fi/Cellular/Ethernet/VPN),
  `LinkProperties` DNS servers, local IPv4/IPv6 from `NetworkInterface` (prefer
  site-local IPv4, skip loopback/point-to-point), gateway from `/proc/net/route`,
  Wi-Fi SSID/RSSI/link speed/frequency guarded by try/catch (permission may be denied;
  strip surrounding quotes from SSID), mobile operator name via TelephonyManager.
  Never throw; unknown fields stay null/empty.

## 9. HttpEngine.kt

```kotlin
object HttpEngine {
    suspend fun inspect(url: String, followRedirects: Boolean = true, timeoutMs: Int = 12000): HttpInfo
}
```

- Add `https://` when no scheme. Build an OkHttpClient per call with followRedirects,
  connect/read timeout, normal UA.
- Prefer `HEAD`; on 405/501/403 or I/O failure retry `GET` with `Range: bytes=0-0`.
  Consume/close the body without downloading it.
- Fill status code/message, protocol (`response.protocol.name`), final URL (`response.request.url`),
  server/content-type/content-length, `durationMs` (nanoTime around the call),
  TLS version/cipher from `response.handshake`, all headers in order.
  `security`: strings such as `HSTS: on/off`, `CSP: present/absent`,
  `Cleartext: yes/no`. Errors → `HttpInfo(url, error = ...)`.

---

# UI WAVE — requirements

Pattern (per screen file, one ViewModel in the same file):

```kotlin
class XViewModel(app: Application) : AndroidViewModel(app) {
    var ui by mutableStateOf(XUiState()); private set
    private var job: Job? = null
    fun start(...) { job?.cancel(); job = viewModelScope.launch { /* collect engine flow */ } }
    fun stop() { job?.cancel() }
    override fun onCleared() { stop() }
}
```

- `@Composable fun XScreen(onBack: () -> Unit)` exactly (Home has its own signature).
- `val vm: XViewModel = viewModel()`; state read directly (Compose state).
- Cancel on back: `DisposableEffect(Unit) { onDispose { vm.stop() } }` and BackHandler stop.
- Inputs validated before starting; show `ErrorBanner` for bad host/ports.
- Remember recent inputs with `HistoryStore` and render them as `AssistChip`s.
- Use `ToolScaffold` for every tool screen. Accent from `Tools.byRoute(Routes.X)?.accent`.
- Streaming output must stay smooth: cap rendered lines (e.g. last 200) and key lists.
- No nested vertical scrollables inside the scrollable `ToolScaffold`; use `Column`
  or set `scrollable = false` with a `LazyColumn` and bottom padding.
- All clickable icons need `contentDescription`. Touch targets ≥ 44 dp.
- Empty/loading/error states are mandatory. Never show a blank screen.
- Format with `fmtLatency`, `fmtPercent`, `formatBytes`, `formatDuration`.

## Screen assignments

**Agent UI-CORE**
- `PingScreen.kt` — host + continuous toggle, Start/Stop, hero latest RTT, ICMP/TCP pill,
  stat tiles (sent/received/loss/avg), live RTT sparkline (`Canvas`, last 60 samples),
  scrolling reply log (mono), summary card, history chips. Default target `1.1.1.1`.
- `TraceScreen.kt` — host, start/stop, hop list streaming (hop #, host/IP, 3 RTTs,
  `*` for timeouts), reached-target badge, copy-all action, hop count + elapsed time,
  empty state. Default `github.com`.
- `PortScannerScreen.kt` — host + ports field, preset chips (`PORT_PRESETS`), scan/stop,
  progress bar, open-port cards (port, service, banner) with counts, closed/filtered
  summary, history. Default host = gateway if available? Use `1.1.1.1`; ports = Top 20.

**Agent UI-NET**
- `DnsScreen.kt` — name/IP, type dropdown (all `DnsType`), resolver dropdown
  (`DnsEngine.RESOLVERS`), lookup, records table (type/value/TTL), copy, history,
  PTR convenience: if input is an IP, default type PTR.
- `WhoisScreen.kt` — query, lookup, highlighted fields (Registrar, Creation Date,
  Expiry Date, Updated Date, Name Servers, Status — match case-insensitively),
  remaining fields, collapsible raw text, copy raw, history.
- `SubnetScannerScreen.kt` — auto-detect on first open (`SubnetScanner.detectLocalSubnet`),
  editable CIDR (e.g. `192.168.1.0/24` or range), "Probe common ports" switch,
  scan/stop, progress, host list sorted by IP with hostname/MAC/RTT/gateway badge and
  open ports, counts, copy host list, empty state.

**Agent UI-EXTRA**
- `GeoPingScreen.kt` — host (default `8.8.8.8`), "Locate & ping": resolve, ping 4 packets,
  `IpInfoEngine.geoLookup(ip)`, location card (flag emoji from country code, city/region/
  country, ISP/ASN, lat/lon, timezone), latency stats, `geo:` map intent button,
  private-IP/offline message.
- `WolScreen.kt` — saved devices (HistoryStore) cards with send/delete, add-device form
  (name, MAC, broadcast, port), validation, success snackbar, "Test" explanation. No network.
- `ConnectionInfoScreen.kt` — load on first composition + refresh; connection type,
  local IPv4/IPv6, gateway, DNS list, public IP + geo/ISP, Wi-Fi SSID/BSSID/RSSI/link speed,
  runtime ACCESS_FINE_LOCATION request when SSID is null (then reload), copyable values.
- `HttpInspectorScreen.kt` — URL, redirect switch, inspect; status pill (2xx green,
  3xx amber, 4xx/5xx red), timing/protocol/TLS/server/content meta, header list,
  security checks, error state, history.
- `HomeScreen.kt` — signature:
  `@Composable fun HomeScreen(onOpenTool: (String) -> Unit, onOpenAbout: () -> Unit)`.
  Custom `Scaffold` + `TopAppBar` ("PingTools" + About icon), hero connection card
  (type, local IP, public IP via `IpInfoEngine`, refresh on resume, graceful offline),
  tool grid (2 columns, rows built with `Tools.all.chunked(2)`) using each tool's
  icon/accent/tag, footer note. No back arrow.

Use `com.pinchiu.pingtools.ui.Routes`, `Tools`, `ToolInfo`, `byRoute`.
