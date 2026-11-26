package com.pinchiu.pingtools.core.model

// ---------------------------------------------------------------------------
// Shared data model. Engine implementations and UI screens both compile
// against these types, so keep names/signatures stable.
// ---------------------------------------------------------------------------

enum class PingMode { ICMP, TCP }

data class PingConfig(
    val host: String,
    /** 0 means continuous until the flow is cancelled. */
    val count: Int = 0,
    val intervalMs: Long = 1_000L,
    val timeoutMs: Int = 1_500,
    val packetSize: Int = 56,
    val ttl: Int = 64
)

data class PingReply(
    val seq: Int,
    val rttMs: Double,
    val ttl: Int? = null,
    val bytes: Int = 56,
    val from: String
)

data class PingSummary(
    val sent: Int,
    val received: Int,
    val lossPercent: Double,
    val minMs: Double,
    val avgMs: Double,
    val maxMs: Double,
    val jitterMs: Double,
    val stdDevMs: Double
)

sealed interface PingEvent {
    data class Started(
        val target: String,
        val resolvedIp: String?,
        val mode: PingMode
    ) : PingEvent

    data class Reply(val reply: PingReply) : PingEvent
    data class Timeout(val seq: Int) : PingEvent

    /** Non-fatal status text (e.g. "ICMP blocked, using TCP fallback"). */
    data class Note(val message: String) : PingEvent

    data class Finished(
        val summary: PingSummary,
        val replies: List<PingReply>
    ) : PingEvent

    data class Failed(val message: String) : PingEvent
}

// ---------------------------------------------------------------------------

data class TraceConfig(
    val host: String,
    val maxHops: Int = 30,
    val probesPerHop: Int = 3,
    val timeoutMs: Int = 1_500,
    val resolveNames: Boolean = true,
    val geoLookup: Boolean = false
)

data class TraceHop(
    val hop: Int,
    val address: String?,
    val hostname: String? = null,
    val rtts: List<Double> = emptyList(),
    val location: String? = null,
    val countryCode: String? = null
)

sealed interface TraceEvent {
    data class Started(val target: String, val resolvedIp: String?) : TraceEvent
    data class HopFound(val hop: TraceHop) : TraceEvent
    data class Finished(val hops: List<TraceHop>, val reachedTarget: Boolean) : TraceEvent
    data class Failed(val message: String) : TraceEvent
}

// ---------------------------------------------------------------------------

enum class PortState { OPEN, CLOSED, FILTERED }

data class PortScanConfig(
    val host: String,
    val ports: List<Int>,
    val concurrency: Int = 64,
    val timeoutMs: Int = 900,
    val grabBanners: Boolean = true
)

data class PortResult(
    val port: Int,
    val state: PortState,
    val service: String = "",
    val banner: String? = null
)

data class PortScanProgress(
    val scanned: Int,
    val total: Int,
    val open: List<PortResult>
)

sealed interface PortScanEvent {
    data class Started(
        val host: String,
        val resolvedIp: String?,
        val total: Int
    ) : PortScanEvent

    data class Progress(val progress: PortScanProgress) : PortScanEvent
    data class Finished(val results: List<PortResult>, val durationMs: Long) : PortScanEvent
    data class Failed(val message: String) : PortScanEvent
}

// ---------------------------------------------------------------------------

enum class DnsType { A, AAAA, CNAME, MX, NS, TXT, SOA, SRV, CAA, PTR }

data class DnsRecord(
    val type: String,
    val value: String,
    val ttl: Long? = null
)

data class DnsResult(
    val query: String,
    val type: DnsType,
    val resolver: String,
    val records: List<DnsRecord> = emptyList(),
    val durationMs: Long = 0,
    val error: String? = null
)

// ---------------------------------------------------------------------------

data class WhoisField(val key: String, val value: String)

data class WhoisResult(
    val query: String,
    val server: String,
    val raw: String = "",
    val fields: List<WhoisField> = emptyList(),
    val durationMs: Long = 0,
    val error: String? = null
)

// ---------------------------------------------------------------------------

data class SubnetConfig(
    val cidr: String,
    val includePortProbe: Boolean = false,
    val probePorts: List<Int> = listOf(22, 80, 443, 445, 3389, 8080),
    val timeoutMs: Int = 350,
    val concurrency: Int = 48
)

data class LanHost(
    val ip: String,
    val mac: String? = null,
    val hostname: String? = null,
    val rttMs: Double? = null,
    val openPorts: List<Int> = emptyList(),
    val isGateway: Boolean = false
)

data class SubnetInfo(
    val cidr: String,
    val localIp: String,
    val prefixLength: Int,
    val gateway: String? = null,
    val totalHosts: Int = 0
)

sealed interface SubnetScanEvent {
    data class Started(val info: SubnetInfo) : SubnetScanEvent
    data class Progress(
        val scanned: Int,
        val total: Int,
        val found: List<LanHost>
    ) : SubnetScanEvent

    data class Finished(val hosts: List<LanHost>, val durationMs: Long) : SubnetScanEvent
    data class Failed(val message: String) : SubnetScanEvent
}

// ---------------------------------------------------------------------------

data class WolDevice(
    val name: String,
    val mac: String,
    val broadcast: String = "255.255.255.255",
    val port: Int = 9
)

data class WolOutcome(
    val mac: String,
    val address: String,
    val port: Int,
    val packetsSent: Int
)

// ---------------------------------------------------------------------------

data class WifiDetails(
    val ssid: String? = null,
    val bssid: String? = null,
    val rssiDbm: Int? = null,
    val linkSpeedMbps: Int? = null,
    val frequencyMhz: Int? = null
)

data class ConnectionInfo(
    val connectionType: String,
    val localIpv4: String? = null,
    val localIpv6: String? = null,
    val gateway: String? = null,
    val dnsServers: List<String> = emptyList(),
    val wifi: WifiDetails? = null,
    val mobileOperator: String? = null,
    val isVpn: Boolean = false
)

data class PublicIpInfo(
    val ip: String? = null,
    val isp: String? = null,
    val org: String? = null,
    val asn: String? = null,
    val city: String? = null,
    val region: String? = null,
    val country: String? = null,
    val countryCode: String? = null,
    val lat: Double? = null,
    val lon: Double? = null,
    val timezone: String? = null,
    val error: String? = null
)

// ---------------------------------------------------------------------------

data class HttpInfo(
    val url: String,
    val finalUrl: String = url,
    val statusCode: Int = 0,
    val statusMessage: String = "",
    val protocol: String = "",
    val server: String? = null,
    val contentType: String? = null,
    val contentLength: Long? = null,
    val durationMs: Long = 0,
    val tlsVersion: String? = null,
    val tlsCipher: String? = null,
    val headers: List<Pair<String, String>> = emptyList(),
    val security: List<Pair<String, String>> = emptyList(),
    val error: String? = null
)
