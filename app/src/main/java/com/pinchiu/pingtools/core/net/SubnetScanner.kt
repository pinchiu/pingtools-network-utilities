package com.pinchiu.pingtools.core.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.wifi.WifiManager
import com.pinchiu.pingtools.core.model.LanHost
import com.pinchiu.pingtools.core.model.SubnetConfig
import com.pinchiu.pingtools.core.model.SubnetInfo
import com.pinchiu.pingtools.core.model.SubnetScanEvent
import com.pinchiu.pingtools.core.util.Shell
import com.pinchiu.pingtools.core.util.ipv4ToLong
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.longToIpv4
import com.pinchiu.pingtools.core.util.normalizeMac
import com.pinchiu.pingtools.core.util.parseSubnetInput
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Local-network host discovery.
 *
 * Hosts are probed with the system ICMP ping binary; MAC addresses are read
 * from the kernel ARP table after every batch. Everything is best-effort and
 * bounded — no reply is a normal result, not an error.
 */
object SubnetScanner {

    private const val MAX_HOSTS = 4096
    private const val PORT_PROBE_TIMEOUT_MS = 400
    private const val HOSTNAME_TIMEOUT_MS = 600L
    private const val ARP_FILE = "/proc/net/arp"
    private const val ROUTE_FILE = "/proc/net/route"
    private const val ZERO_MAC = "00:00:00:00:00:00"

    /** Last gateway discovered through LinkProperties, used by [scan]. */
    @Volatile
    private var cachedGateway: String? = null

    private val WHITESPACE = Regex("\\s+")
    // Only reply lines use "time=" / "time<"; the statistics footer uses
    // "time 0ms", which must not be mistaken for a host reply.
    private val RTT_REGEX =
        Regex("""time\s*([=<])\s*([0-9]+(?:\.[0-9]+)?)\s*ms""", RegexOption.IGNORE_CASE)

    fun scan(config: SubnetConfig): Flow<SubnetScanEvent> = flow<SubnetScanEvent> {
        val startedAt = System.nanoTime()
        try {
            val info = parseSubnetInput(config.cidr)
            if (info == null) {
                emit(SubnetScanEvent.Failed("Enter a valid subnet (e.g. 192.168.1.0/24) or an IP range"))
                return@flow
            }
            if (info.totalHosts > MAX_HOSTS) {
                emit(SubnetScanEvent.Failed("Subnet is too large — maximum $MAX_HOSTS hosts"))
                return@flow
            }

            val hosts = hostsFor(info)
            if (hosts.isEmpty()) {
                emit(SubnetScanEvent.Failed("No usable host addresses in this subnet"))
                return@flow
            }

            // parseSubnetInput does not know the router; borrow the device's
            // default gateway when it actually falls inside the scanned range.
            val effectiveGateway = info.gateway
                ?: cachedGateway?.takeIf { hosts.contains(it) }
                ?: detectLocalSubnet()?.gateway?.takeIf { hosts.contains(it) }
            val startedInfo = if (effectiveGateway != null) {
                info.copy(gateway = effectiveGateway)
            } else {
                info
            }

            emit(SubnetScanEvent.Started(startedInfo))

            val timeoutSec = (((config.timeoutMs.coerceAtLeast(1)) + 999) / 1000).coerceAtLeast(1)
            val batchSize = config.concurrency.coerceIn(1, 128)
            val found = LinkedHashMap<String, LanHost>()
            var scanned = 0

            for (batch in hosts.chunked(batchSize)) {
                val probes = coroutineScope {
                    batch.map { ip -> async { probeHost(ip, timeoutSec) } }.awaitAll()
                }

                val arp = readArpTable()
                for (probe in probes) {
                    if (!probe.replied) continue
                    found[probe.ip] = LanHost(
                        ip = probe.ip,
                        mac = arp[probe.ip],
                        rttMs = probe.rttMs,
                        isGateway = probe.ip == startedInfo.gateway
                    )
                }

                // ARP entries for earlier batches may have appeared since then.
                if (arp.isNotEmpty()) {
                    for ((ip, host) in found.entries.toList()) {
                        if (host.mac == null) {
                            arp[ip]?.let { mac -> found[ip] = host.copy(mac = mac) }
                        }
                    }
                }

                scanned += batch.size
                emit(
                    SubnetScanEvent.Progress(
                        scanned = scanned,
                        total = hosts.size,
                        found = sortedHosts(found.values)
                    )
                )
            }

            // One last ARP refresh: the kernel sometimes completes entries late.
            val finalArp = readArpTable()
            if (finalArp.isNotEmpty()) {
                for ((ip, host) in found.entries.toList()) {
                    if (host.mac == null) {
                        finalArp[ip]?.let { mac -> found[ip] = host.copy(mac = mac) }
                    }
                }
            }

            if (found.isNotEmpty()) {
                val resolved = resolveHostnames(found.values.toList())
                for (host in resolved) found[host.ip] = host
            }

            if (config.includePortProbe) {
                val probePorts = config.probePorts
                    .filter { it in 1..65535 }
                    .distinct()
                    .sorted()
                if (probePorts.isNotEmpty() && found.isNotEmpty()) {
                    val enriched = probeOpenPorts(found.values.toList(), probePorts, batchSize)
                    for (host in enriched) found[host.ip] = host
                }
            }

            emit(
                SubnetScanEvent.Finished(
                    hosts = sortedHosts(found.values),
                    durationMs = (System.nanoTime() - startedAt) / 1_000_000L
                )
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(SubnetScanEvent.Failed(e.message ?: "Subnet scan failed"))
        }
    }.flowOn(Dispatchers.IO)

    /**
     * Finds the device's first usable site-local IPv4 interface (10/8,
     * 172.16/12 or 192.168/16) with a prefix between 8 and 30 and derives the
     * network address plus the default gateway. Returns null when unavailable.
     *
     * A [Context] is optional but recommended: Android 10+ blocks
     * `/proc/net/route` for apps, so the gateway is normally read from
     * [LinkProperties] (or Wi-Fi DHCP info) instead.
     */
    suspend fun detectLocalSubnet(context: Context? = null): SubnetInfo? = withContext(Dispatchers.IO) {
        try {
            val linkProperties = readLinkProperties(context)
            val linkInterface = linkProperties?.interfaceName
            val linkGateway = linkProperties?.defaultIpv4Gateway()
            val wifiGateway = readWifiGateway(context)
            val routes = readDefaultRoutes()
            val candidates = mutableListOf<Candidate>()
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return@withContext null

            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                try {
                    if (!networkInterface.isUp || networkInterface.isLoopback) continue
                    for (interfaceAddress in networkInterface.interfaceAddresses) {
                        val address = interfaceAddress.address as? Inet4Address ?: continue
                        if (!address.isSiteLocalAddress) continue
                        val prefix = interfaceAddress.networkPrefixLength.toInt()
                        if (prefix !in 8..30) continue
                        val ip = address.hostAddress ?: continue
                        if (ipv4ToLong(ip) == null) continue
                        candidates += Candidate(networkInterface, ip, prefix)
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // A single unreadable interface must not abort detection.
                }
            }

            if (candidates.isEmpty()) return@withContext null

            val defaultIface = linkInterface ?: routes.firstOrNull()?.iface
            val chosen = candidates.firstOrNull { it.networkInterface.name == defaultIface }
                ?: candidates.firstOrNull { !isPointToPoint(it.networkInterface) }
                ?: candidates.first()

            val ipValue = ipv4ToLong(chosen.ip) ?: return@withContext null
            val mask = prefixMask(chosen.prefix)
            val network = ipValue and mask
            val gatewayCandidate = linkGateway
                ?: wifiGateway
                ?: routes.firstOrNull { it.iface == chosen.networkInterface.name }?.gateway
                ?: routes.firstOrNull()?.gateway
            // A default route on another interface (VPN, cellular) must not be
            // reported as this network's gateway.
            val gateway = gatewayCandidate?.takeIf { candidate ->
                val candidateValue = ipv4ToLong(candidate)
                candidateValue != null && (candidateValue and mask) == network
            }
            cachedGateway = gateway

            SubnetInfo(
                cidr = "${longToIpv4(network)}/${chosen.prefix}",
                localIp = chosen.ip,
                prefixLength = chosen.prefix,
                gateway = gateway,
                totalHosts = (1 shl (32 - chosen.prefix)) - 2
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
    }

    private fun readLinkProperties(context: Context?): LinkProperties? {
        if (context == null) return null
        return try {
            val app = context.applicationContext
            val manager = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val network = manager?.activeNetwork ?: return null
            manager.getLinkProperties(network)
        } catch (e: Exception) {
            null
        }
    }

    private fun LinkProperties.defaultIpv4Gateway(): String? = try {
        routes.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway
            ?.hostAddress
    } catch (e: Exception) {
        null
    }

    /**
     * Wi-Fi DHCP info is a fallback for devices/emulators where
     * [LinkProperties] does not expose a default route to apps.
     */
    @Suppress("DEPRECATION")
    private fun readWifiGateway(context: Context?): String? {
        if (context == null) return null
        return try {
            val app = context.applicationContext
            val wifi = app.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val raw = wifi?.dhcpInfo?.gateway ?: return null
            if (raw == 0) return null
            val value = raw.toLong() and 0xFFFFFFFFL
            val reversed = ((value and 0xFFL) shl 24) or
                ((value and 0xFF00L) shl 8) or
                ((value ushr 8) and 0xFF00L) or
                ((value ushr 24) and 0xFFL)
            longToIpv4(reversed).takeIf { it != "0.0.0.0" }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Expands a CIDR (network/broadcast excluded) or an explicit range into
     * concrete addresses. The result is capped at [MAX_HOSTS]; an unparseable
     * input yields an empty list.
     */
    fun hostsFor(info: SubnetInfo): List<String> {
        val raw = info.cidr.trim()
        if (raw.isEmpty()) return emptyList()

        if (raw.contains('/')) {
            val address = raw.substringBefore('/')
            val prefix = raw.substringAfter('/').toIntOrNull() ?: return emptyList()
            val ipValue = ipv4ToLong(address) ?: return emptyList()
            if (prefix !in 8..30) return emptyList()

            val mask = prefixMask(prefix)
            val network = ipValue and mask
            val broadcast = network or (mask.inv() and 0xFFFFFFFFL)
            val usable = broadcast - network - 1
            if (usable <= 0L) return emptyList()

            val count = minOf(usable, MAX_HOSTS.toLong()).toInt()
            return (1..count).map { offset -> longToIpv4(network + offset) }
        }

        val start = raw.substringBefore('-').trim()
        val end = raw.substringAfter('-', "").trim()
        if (start.isEmpty() || end.isEmpty()) return emptyList()
        val startValue = ipv4ToLong(start) ?: return emptyList()
        val endValue = ipv4ToLong(end) ?: return emptyList()
        if (endValue < startValue) return emptyList()

        val count = minOf(endValue - startValue + 1, MAX_HOSTS.toLong()).toInt()
        return (0 until count).map { offset -> longToIpv4(startValue + offset) }
    }

    // ---------------------------------------------------------------------
    // Probing
    // ---------------------------------------------------------------------

    private suspend fun probeHost(ip: String, timeoutSec: Int): HostProbe {
        val result = Shell.exec(
            command = listOf(Shell.pingBinary(), "-c", "1", "-W", timeoutSec.toString(), ip),
            timeoutMs = timeoutSec * 1000L + 2_500L
        )
        val text = result.combined
        val timeMatch = RTT_REGEX.find(text)
        // "time<1ms" confirms a reply but the exact value is unknown.
        val rtt = if (timeMatch != null && timeMatch.groupValues[1] == "=") {
            timeMatch.groupValues[2].toDoubleOrNull()
        } else {
            null
        }
        val replied = timeMatch != null || text.contains("bytes from", ignoreCase = true)
        return HostProbe(ip, replied, if (replied) rtt else null)
    }

    private suspend fun probeOpenPorts(
        hosts: List<LanHost>,
        ports: List<Int>,
        concurrency: Int
    ): List<LanHost> {
        if (hosts.isEmpty()) return hosts
        val batchSize = concurrency.coerceIn(1, 32)
        val enriched = mutableListOf<LanHost>()
        for (batch in hosts.chunked(batchSize)) {
            val batchResult = coroutineScope {
                batch.map { host ->
                    async {
                        val open = probePorts(host.ip, ports)
                        if (open.isEmpty()) host else host.copy(openPorts = open)
                    }
                }.awaitAll()
            }
            enriched += batchResult
        }
        return enriched
    }

    private suspend fun probePorts(ip: String, ports: List<Int>): List<Int> =
        withContext(Dispatchers.IO) {
            val open = mutableListOf<Int>()
            for (port in ports) {
                currentCoroutineContext().ensureActive()
                var socket: Socket? = null
                try {
                    val created = Socket()
                    socket = created
                    created.connect(InetSocketAddress(ip, port), PORT_PROBE_TIMEOUT_MS)
                    open += port
                } catch (e: IOException) {
                    // Closed or filtered — not an error for this scan.
                } catch (e: SecurityException) {
                    // Socket permission denied — leave the port out.
                } finally {
                    socket?.let { runCatching { it.close() } }
                }
            }
            open
        }

    // ---------------------------------------------------------------------
    // Name resolution
    // ---------------------------------------------------------------------

    /**
     * Reverse-DNS lookup with a hard per-host cap. getCanonicalHostName() is
     * blocking and ignores coroutine cancellation, so each lookup runs on a
     * worker thread and is collected with Future.get(timeout).
     */
    private suspend fun resolveHostnames(hosts: List<LanHost>): List<LanHost> =
        withContext(Dispatchers.IO) {
            if (hosts.isEmpty()) return@withContext hosts

            val executor = Executors.newFixedThreadPool(minOf(16, hosts.size)) { runnable ->
                Thread(runnable, "subnet-hostname").apply { isDaemon = true }
            }
            try {
                val futures = hosts.map { host ->
                    executor.submit(Callable {
                        try {
                            val address = InetAddress.getByName(host.ip)
                            val name = address.getCanonicalHostName()
                            if (name.isNullOrBlank() || name == host.ip) null else name
                        } catch (e: Exception) {
                            null
                        }
                    })
                }

                hosts.mapIndexed { index, host ->
                    currentCoroutineContext().ensureActive()
                    val name = try {
                        futures[index].get(HOSTNAME_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    } catch (e: Exception) {
                        futures[index].cancel(true)
                        null
                    }
                    if (name != null && name.isNotBlank()) host.copy(hostname = name) else host
                }
            } finally {
                executor.shutdownNow()
            }
        }

    // ---------------------------------------------------------------------
    // /proc parsing
    // ---------------------------------------------------------------------

    /** ARP entries with the complete flag (0x2) and a real unicast MAC. */
    private fun readArpTable(): Map<String, String> {
        val file = File(ARP_FILE)
        if (!file.isFile || !file.canRead()) return emptyMap()
        return try {
            val table = HashMap<String, String>()
            file.useLines { lines ->
                lines.drop(1).forEach { line ->
                    val parts = line.trim().split(WHITESPACE)
                    if (parts.size < 4) return@forEach
                    val ip = parts[0]
                    if (!isValidIpv4(ip)) return@forEach
                    val flags = parts[2]
                        .removePrefix("0x")
                        .removePrefix("0X")
                        .toIntOrNull(16) ?: 0
                    if ((flags and 0x2) == 0) return@forEach
                    val mac = normalizeMac(parts[3]) ?: return@forEach
                    if (mac == ZERO_MAC) return@forEach
                    table[ip] = mac
                }
            }
            table
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun readDefaultRoutes(): List<DefaultRoute> {
        val file = File(ROUTE_FILE)
        if (!file.isFile || !file.canRead()) return emptyList()
        return try {
            val routes = mutableListOf<DefaultRoute>()
            file.useLines { lines ->
                lines.drop(1).forEach { line ->
                    val parts = line.trim().split(WHITESPACE)
                    if (parts.size < 3) return@forEach
                    // Destination 00000000 (little-endian) is the default route.
                    if (parts[1] != "00000000") return@forEach
                    if (parts[2] == "00000000") return@forEach
                    val gateway = littleEndianHexToIpv4(parts[2]) ?: return@forEach
                    routes += DefaultRoute(parts[0], gateway)
                }
            }
            routes
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun littleEndianHexToIpv4(hex: String): String? {
        if (hex.length != 8) return null
        val value = hex.toLongOrNull(16) ?: return null
        val ip = ((value and 0xFFL) shl 24) or
            ((value and 0xFF00L) shl 8) or
            ((value ushr 8) and 0xFF00L) or
            ((value ushr 24) and 0xFFL)
        return longToIpv4(ip)
    }

    private fun prefixMask(prefix: Int): Long =
        (0xFFFFFFFFL shl (32 - prefix)) and 0xFFFFFFFFL

    private fun isPointToPoint(networkInterface: NetworkInterface): Boolean =
        try {
            networkInterface.isPointToPoint
        } catch (e: Exception) {
            false
        }

    private fun sortedHosts(hosts: Collection<LanHost>): List<LanHost> =
        hosts.sortedWith(
            compareBy<LanHost> { ipv4ToLong(it.ip) ?: Long.MAX_VALUE }
                .thenBy { it.ip }
        )

    private data class Candidate(
        val networkInterface: NetworkInterface,
        val ip: String,
        val prefix: Int
    )

    private data class DefaultRoute(val iface: String, val gateway: String)

    private data class HostProbe(val ip: String, val replied: Boolean, val rttMs: Double?)
}
