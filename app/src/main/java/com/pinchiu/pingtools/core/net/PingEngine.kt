package com.pinchiu.pingtools.core.net

import com.pinchiu.pingtools.core.model.PingConfig
import com.pinchiu.pingtools.core.model.PingEvent
import com.pinchiu.pingtools.core.model.PingMode
import com.pinchiu.pingtools.core.model.PingReply
import com.pinchiu.pingtools.core.model.PingSummary
import com.pinchiu.pingtools.core.util.Shell
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.normalizeHost
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.sqrt

/**
 * On-device ping engine.
 *
 * ICMP is attempted through the platform `ping` binary. A one-shot loopback
 * probe decides whether raw ICMP is permitted; when it is not, latency is
 * measured with TCP connects to common ports instead. Failures are reported as
 * [PingEvent.Failed] and cancellation is always rethrown.
 */
object PingEngine {

    private const val ICMP_PROBE_TIMEOUT_MS = 3_000L
    private const val MAX_PACKET_SIZE = 65_500
    private const val PERMISSION_FALLBACK_NOTE =
        "ICMP is not permitted on this device — using TCP connect latency"
    private const val UNAVAILABLE_FALLBACK_NOTE =
        "ICMP is unavailable on this device — using TCP connect latency"

    private val TCP_PORTS = listOf(443, 80, 53)

    private val TIME_PATTERN = Regex(
        """\btime\s*[=<]?\s*(\d+(?:\.\d+)?)\s*ms""",
        RegexOption.IGNORE_CASE
    )
    private val TTL_PATTERN = Regex("""\bttl\s*[=:]\s*(\d{1,3})\b""", RegexOption.IGNORE_CASE)
    private val BYTES_LEADING_PATTERN = Regex("""^\s*(\d{1,5})\s+bytes\b""", RegexOption.IGNORE_CASE)
    private val BYTES_EQUALS_PATTERN = Regex("""\bbytes\s*=\s*(\d{1,5})\b""", RegexOption.IGNORE_CASE)
    private val IPV4_PATTERN = Regex("""\b(\d{1,3}(?:\.\d{1,3}){3})\b""")

    fun ping(config: PingConfig): Flow<PingEvent> = flow {
        val target = normalizeHost(config.host)
        if (target.isBlank()) {
            emit(PingEvent.Failed("Enter a host name or IP address"))
            return@flow
        }

        val resolvedIp = try {
            resolveIpv4(target)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(PingEvent.Failed("Unable to resolve $target"))
            return@flow
        }
        if (resolvedIp == null) {
            emit(PingEvent.Failed("No IPv4 address found for $target"))
            return@flow
        }

        val icmpProbe = probeIcmp()
        val mode = if (icmpProbe.available) PingMode.ICMP else PingMode.TCP
        emit(PingEvent.Started(target, resolvedIp, mode))
        if (!icmpProbe.available) {
            emit(PingEvent.Note(icmpProbe.fallbackNote ?: UNAVAILABLE_FALLBACK_NOTE))
        }

        val totalCount = config.count.coerceAtLeast(0)
        val intervalMs = config.intervalMs.coerceAtLeast(0L)
        val replies = mutableListOf<PingReply>()
        var preferredTcpPort: Int? = null
        var sent = 0

        try {
            var seq = 1
            while (totalCount == 0 || sent < totalCount) {
                currentCoroutineContext().ensureActive()

                val attempt = if (mode == PingMode.ICMP) {
                    icmpAttempt(resolvedIp, config)
                } else {
                    val tcp = tcpAttempt(resolvedIp, config.timeoutMs, preferredTcpPort)
                    if (tcp != null) {
                        preferredTcpPort = tcp.port
                        Attempt(
                            rttMs = tcp.rttMs,
                            ttl = null,
                            bytes = 0,
                            from = "$resolvedIp:${tcp.port}"
                        )
                    } else {
                        Attempt()
                    }
                }

                val fatal = attempt.fatalMessage
                if (fatal != null) {
                    emit(PingEvent.Failed(fatal))
                    return@flow
                }

                sent++
                val rtt = attempt.rttMs
                if (rtt != null) {
                    val reply = PingReply(
                        seq = seq,
                        rttMs = rtt,
                        ttl = attempt.ttl,
                        bytes = attempt.bytes,
                        from = attempt.from ?: resolvedIp
                    )
                    // Continuous sessions end by cancellation (no Finished), so
                    // there is no reason to retain an unbounded reply history.
                    if (totalCount > 0) replies += reply
                    emit(PingEvent.Reply(reply))
                } else {
                    emit(PingEvent.Timeout(seq))
                }

                seq++
                val hasMore = totalCount == 0 || sent < totalCount
                if (hasMore && intervalMs > 0L) delay(intervalMs)
            }

            emit(PingEvent.Finished(summarize(sent, replies), replies.toList()))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(PingEvent.Failed(e.message ?: "Ping failed"))
        }
    }.flowOn(Dispatchers.IO)

    // ------------------------------------------------------------------
    // ICMP
    // ------------------------------------------------------------------

    private suspend fun icmpAttempt(ip: String, config: PingConfig): Attempt {
        val timeoutSeconds = ceil(config.timeoutMs.coerceAtLeast(100) / 1000.0)
            .toInt()
            .coerceAtLeast(1)
        val size = config.packetSize.coerceIn(0, MAX_PACKET_SIZE)
        val ttl = config.ttl.coerceIn(1, 255)

        val result = Shell.exec(
            command = listOf(
                Shell.pingBinary(),
                "-c", "1",
                "-W", timeoutSeconds.toString(),
                "-s", size.toString(),
                "-t", ttl.toString(),
                ip
            ),
            timeoutMs = timeoutSeconds * 1000L + 2_000L
        )

        val output = result.combined
        val parsed = parseIcmpReply(output, ip, size)
        if (parsed != null) {
            return Attempt(
                rttMs = parsed.rttMs,
                ttl = parsed.ttl,
                bytes = parsed.bytes,
                from = parsed.from
            )
        }

        val fatal = fatalMessage(output)
        if (fatal != null) return Attempt(fatalMessage = fatal)
        return Attempt()
    }

    /**
     * Probes loopback once with the platform ping binary. On Android the
     * binary may be present but unable to open a raw/ping socket, which is the
     * case this fallback exists for.
     */
    private suspend fun probeIcmp(): IcmpProbe {
        val result = try {
            Shell.exec(
                command = listOf(
                    Shell.pingBinary(), "-c", "1", "-W", "1", "127.0.0.1"
                ),
                timeoutMs = ICMP_PROBE_TIMEOUT_MS
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return IcmpProbe(false, UNAVAILABLE_FALLBACK_NOTE)
        }

        val text = result.combined.lowercase()
        val succeeded = result.exitCode == 0 && !text.contains("100% packet loss")
        if (succeeded) return IcmpProbe(true, null)

        val permissionProblem = listOf(
            "permission", "not permitted", "operation not permitted", "socket",
            "unknown option", "invalid option", "unrecognized option", "bad option",
            "unable to create", "can't create"
        ).any { text.contains(it) }
        val note = if (permissionProblem) PERMISSION_FALLBACK_NOTE else UNAVAILABLE_FALLBACK_NOTE
        return IcmpProbe(false, note)
    }

    private fun parseIcmpReply(output: String, expectedIp: String, defaultBytes: Int): ParsedReply? {
        for (rawLine in output.lineSequence()) {
            val line = rawLine.trim()
            if (line.isEmpty()) continue
            if (!line.contains("bytes from", ignoreCase = true) &&
                !line.contains("reply from", ignoreCase = true)
            ) {
                continue
            }

            val lower = line.lowercase()
            if (lower.contains("time to live exceeded") ||
                lower.contains("ttl expired") ||
                lower.contains("ttl exceeded")
            ) {
                continue
            }

            val timeMatch = TIME_PATTERN.find(line) ?: continue
            val rtt = timeMatch.groupValues[1].toDoubleOrNull() ?: continue
            if (!rtt.isFinite() || rtt < 0.0) continue

            val address = ipv4After(line, "bytes from") ?: ipv4After(line, "reply from")
            // Ignore replies sourced from a router rather than the target.
            if (address != null && address != expectedIp) continue

            val ttl = TTL_PATTERN.find(line)?.groupValues?.get(1)?.toIntOrNull()
            val bytes = BYTES_LEADING_PATTERN.find(line)?.groupValues?.get(1)?.toIntOrNull()
                ?: BYTES_EQUALS_PATTERN.find(line)?.groupValues?.get(1)?.toIntOrNull()
                ?: defaultBytes

            return ParsedReply(
                rttMs = rtt,
                ttl = ttl,
                bytes = bytes,
                from = address ?: expectedIp
            )
        }
        return null
    }

    private fun fatalMessage(output: String): String? {
        val lower = output.lowercase()
        return when {
            lower.contains("network is unreachable") -> "Network is unreachable"
            lower.contains("unknown host") ||
                lower.contains("name or service not known") -> "Unknown host"
            else -> null
        }
    }

    // ------------------------------------------------------------------
    // TCP fallback
    // ------------------------------------------------------------------

    private suspend fun tcpAttempt(
        ip: String,
        timeoutMs: Int,
        preferredPort: Int?
    ): TcpAttempt? {
        val timeout = timeoutMs.coerceAtLeast(100)
        val ports = if (preferredPort == null) {
            TCP_PORTS
        } else {
            listOf(preferredPort) + TCP_PORTS.filter { it != preferredPort }
        }

        for (port in ports) {
            currentCoroutineContext().ensureActive()
            val rtt = connectTcp(ip, port, timeout) ?: continue
            return TcpAttempt(rtt, port)
        }
        return null
    }

    private suspend fun connectTcp(ip: String, port: Int, timeoutMs: Int): Double? =
        withContext(Dispatchers.IO) {
            var socket: Socket? = null
            try {
                socket = Socket()
                socket.tcpNoDelay = true
                val startedNs = System.nanoTime()
                socket.connect(InetSocketAddress(ip, port), timeoutMs)
                (System.nanoTime() - startedNs) / 1_000_000.0
            } catch (e: IOException) {
                null
            } catch (e: SecurityException) {
                null
            } finally {
                try {
                    socket?.close()
                } catch (_: IOException) {
                    // Best-effort close.
                }
            }
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

    private fun ipv4After(line: String, marker: String): String? {
        val index = line.indexOf(marker, ignoreCase = true)
        if (index < 0) return null
        val tail = line.substring(index + marker.length)
        return IPV4_PATTERN.findAll(tail)
            .map { it.groupValues[1] }
            .firstOrNull { isValidIpv4(it) }
    }

    private fun summarize(sent: Int, replies: List<PingReply>): PingSummary {
        val rtts = replies.map { it.rttMs }
        val received = rtts.size
        val loss = if (sent > 0) {
            (sent - received).coerceAtLeast(0) * 100.0 / sent
        } else {
            0.0
        }

        if (rtts.isEmpty()) {
            return PingSummary(
                sent = sent,
                received = 0,
                lossPercent = loss,
                minMs = 0.0,
                avgMs = 0.0,
                maxMs = 0.0,
                jitterMs = 0.0,
                stdDevMs = 0.0
            )
        }

        val avg = rtts.average()
        val jitter = if (rtts.size > 1) {
            rtts.zipWithNext { a, b -> abs(b - a) }.average()
        } else {
            0.0
        }
        val variance = rtts.map { value ->
            val delta = value - avg
            delta * delta
        }.average()

        return PingSummary(
            sent = sent,
            received = received,
            lossPercent = loss,
            minMs = rtts.min(),
            avgMs = avg,
            maxMs = rtts.max(),
            jitterMs = jitter,
            stdDevMs = sqrt(variance)
        )
    }

    private data class Attempt(
        val rttMs: Double? = null,
        val ttl: Int? = null,
        val bytes: Int = 0,
        val from: String? = null,
        val fatalMessage: String? = null
    )

    private data class ParsedReply(
        val rttMs: Double,
        val ttl: Int?,
        val bytes: Int,
        val from: String
    )

    private data class TcpAttempt(val rttMs: Double, val port: Int)

    private data class IcmpProbe(val available: Boolean, val fallbackNote: String?)
}
