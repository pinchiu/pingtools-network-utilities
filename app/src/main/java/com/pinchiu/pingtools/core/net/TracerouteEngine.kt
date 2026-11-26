package com.pinchiu.pingtools.core.net

import com.pinchiu.pingtools.core.model.TraceConfig
import com.pinchiu.pingtools.core.model.TraceEvent
import com.pinchiu.pingtools.core.model.TraceHop
import com.pinchiu.pingtools.core.util.Shell
import com.pinchiu.pingtools.core.util.isPrivateIp
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.normalizeHost
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlin.math.ceil

/**
 * IPv4 traceroute built on repeated single-packet pings.
 *
 * Each TTL is probed [TraceConfig.probesPerHop] times. That keeps the engine
 * compatible with Android's unprivileged toybox `ping` and avoids needing a
 * separate traceroute binary. Reverse DNS is best-effort and strictly capped.
 * Geo enrichment is intentionally not performed, so location fields stay null.
 */
object TracerouteEngine {

    private const val ICMP_PROBE_TIMEOUT_MS = 3_000L
    private const val REVERSE_DNS_TIMEOUT_MS = 700L
    private const val ICMP_BLOCKED_MESSAGE =
        "ICMP is blocked on this device; traceroute requires raw ICMP support."

    private val TIME_PATTERN = Regex(
        """\btime\s*[=<]?\s*(\d+(?:\.\d+)?)\s*ms""",
        RegexOption.IGNORE_CASE
    )
    private val TTL_PATTERN = Regex("""\bttl\s*[=:]\s*(\d{1,3})\b""", RegexOption.IGNORE_CASE)
    private val IPV4_PATTERN = Regex("""\b(\d{1,3}(?:\.\d{1,3}){3})\b""")

    fun trace(config: TraceConfig): Flow<TraceEvent> = flow {
        val target = normalizeHost(config.host)
        if (target.isBlank()) {
            emit(TraceEvent.Failed("Enter a host name or IP address"))
            return@flow
        }

        val targetIp = try {
            resolveIpv4(target)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(TraceEvent.Failed("Unable to resolve $target"))
            return@flow
        }
        if (targetIp == null) {
            emit(TraceEvent.Failed("No IPv4 address found for $target"))
            return@flow
        }

        emit(TraceEvent.Started(target, targetIp))

        val icmpAvailable = try {
            probeIcmp()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            false
        }
        if (!icmpAvailable) {
            emit(TraceEvent.Failed(ICMP_BLOCKED_MESSAGE))
            return@flow
        }

        val maxHops = config.maxHops.coerceIn(0, 255)
        val probesPerHop = config.probesPerHop.coerceAtLeast(1)
        val hops = mutableListOf<TraceHop>()
        var reachedTarget = false

        try {
            for (ttl in 1..maxHops) {
                currentCoroutineContext().ensureActive()

                val addresses = mutableListOf<String>()
                val rtts = mutableListOf<Double>()
                var targetReached = false

                var probe = 0
                while (probe < probesPerHop) {
                    currentCoroutineContext().ensureActive()
                    val result = probeHop(targetIp, ttl, config.timeoutMs)
                    if (result.address != null) addresses += result.address
                    if (result.rttMs != null) rtts += result.rttMs
                    if (result.reachedTarget) targetReached = true
                    probe++
                }

                val address = if (targetReached) targetIp else addresses.firstOrNull()
                val hostname = if (config.resolveNames && address != null && !isPrivateIp(address)) {
                    reverseLookup(address)
                } else {
                    null
                }

                val hop = TraceHop(
                    hop = ttl,
                    address = address,
                    hostname = hostname,
                    rtts = rtts.toList()
                )
                hops += hop
                emit(TraceEvent.HopFound(hop))

                if (targetReached) {
                    reachedTarget = true
                    break
                }
            }

            emit(TraceEvent.Finished(hops.toList(), reachedTarget))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(TraceEvent.Failed(e.message ?: "Traceroute failed"))
        }
    }.flowOn(Dispatchers.IO)

    // ------------------------------------------------------------------
    // Probe
    // ------------------------------------------------------------------

    private suspend fun probeHop(targetIp: String, ttl: Int, timeoutMs: Int): ProbeResult {
        val timeoutSeconds = ceil(timeoutMs.coerceAtLeast(100) / 1000.0)
            .toInt()
            .coerceAtLeast(1)

        val startedNs = System.nanoTime()
        val result = Shell.exec(
            command = listOf(
                Shell.pingBinary(),
                "-c", "1",
                "-W", timeoutSeconds.toString(),
                "-t", ttl.toString(),
                targetIp
            ),
            timeoutMs = timeoutSeconds * 1000L + 2_000L
        )
        val elapsedMs = (System.nanoTime() - startedNs) / 1_000_000.0

        return parseProbe(result.combined, targetIp, elapsedMs)
    }

    /**
     * Android's ping often omits a `time=` field on ICMP TTL-exceeded messages.
     * In that case the measured process turn-around is used as an upper bound
     * so a responding hop still carries an RTT instead of looking silent.
     */
    private fun parseProbe(output: String, targetIp: String, elapsedMs: Double): ProbeResult {
        val lines = output.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()

        // Preferred target match: "64 bytes from <target>: ... ttl=57 time=..."
        for (line in lines) {
            val address = ipv4After(line, "bytes from") ?: continue
            if (address != targetIp) continue
            val ttl = TTL_PATTERN.find(line)?.groupValues?.get(1)?.toIntOrNull()
            if (ttl == null) continue
            val rtt = TIME_PATTERN.find(line)?.groupValues?.get(1)?.toDoubleOrNull()
            return ProbeResult(targetIp, rtt ?: elapsedRtt(elapsedMs), true)
        }

        // Compatibility with builds that omit ttl= on the destination echo reply.
        for (line in lines) {
            val address = ipv4After(line, "bytes from") ?: continue
            if (address != targetIp) continue
            val rtt = TIME_PATTERN.find(line)?.groupValues?.get(1)?.toDoubleOrNull()
            return ProbeResult(targetIp, rtt ?: elapsedRtt(elapsedMs), true)
        }

        // Router replies: "From 10.0.0.1 ... Time to live exceeded",
        // "TTL expired in transit", or "Reply from ...: TTL expired".
        for (line in lines) {
            val lower = line.lowercase()
            val expired = lower.contains("time to live exceeded") ||
                lower.contains("ttl expired") ||
                lower.contains("ttl exceeded")
            if (!expired) continue

            val address = ipv4After(line, "from") ?: firstIpv4(line)
            val rtt = TIME_PATTERN.find(line)?.groupValues?.get(1)?.toDoubleOrNull()
            return ProbeResult(
                address = address,
                rttMs = if (address != null) (rtt ?: elapsedRtt(elapsedMs)) else null,
                reachedTarget = false
            )
        }

        return ProbeResult(null, null, false)
    }

    private fun elapsedRtt(elapsedMs: Double): Double = elapsedMs.coerceAtLeast(0.0)

    // ------------------------------------------------------------------
    // ICMP permission check
    // ------------------------------------------------------------------

    private suspend fun probeIcmp(): Boolean {
        val result = Shell.exec(
            command = listOf(Shell.pingBinary(), "-c", "1", "-W", "1", "127.0.0.1"),
            timeoutMs = ICMP_PROBE_TIMEOUT_MS
        )
        if (result.exitCode != 0) return false

        val text = result.combined.lowercase()
        if (text.contains("100% packet loss") ||
            text.contains("unknown option") ||
            text.contains("invalid option")
        ) {
            return false
        }
        return text.contains("bytes from") ||
            text.contains("reply from") ||
            text.contains("1 packets received") ||
            text.contains("1 received") ||
            text.contains("1 replies")
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private suspend fun resolveIpv4(host: String): String? = withContext(Dispatchers.IO) {
        val address = InetAddress.getByName(host)
        if (address is Inet4Address) {
            address.hostAddress
        } else {
            InetAddress.getAllByName(host).firstOrNull { it is Inet4Address }?.hostAddress
        }
    }

    /**
     * Best-effort reverse DNS with a hard 700 ms wall-clock cap. A fresh
     * single-thread daemon executor is used so a stuck resolver can never
     * block the main traceroute loop indefinitely.
     */
    private fun reverseLookup(ip: String): String? {
        val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "pingtools-rdns").apply { isDaemon = true }
        }
        return try {
            val future = executor.submit(
                Callable { InetAddress.getByName(ip).canonicalHostName }
            )
            try {
                val name = future.get(REVERSE_DNS_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .trim()
                    .trimEnd('.')
                if (name.isBlank() || name == ip) null else name
            } catch (e: TimeoutException) {
                future.cancel(true)
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                future.cancel(true)
                null
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        } finally {
            executor.shutdownNow()
        }
    }

    private fun ipv4After(line: String, marker: String): String? {
        val index = line.indexOf(marker, ignoreCase = true)
        if (index < 0) return null
        return firstIpv4(line.substring(index + marker.length))
    }

    private fun firstIpv4(text: String): String? =
        IPV4_PATTERN.findAll(text)
            .map { it.groupValues[1] }
            .firstOrNull { isValidIpv4(it) }

    private data class ProbeResult(
        val address: String?,
        val rttMs: Double?,
        val reachedTarget: Boolean
    )
}
