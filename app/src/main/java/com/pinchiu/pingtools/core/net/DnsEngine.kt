package com.pinchiu.pingtools.core.net

import com.pinchiu.pingtools.core.model.DnsRecord
import com.pinchiu.pingtools.core.model.DnsResult
import com.pinchiu.pingtools.core.model.DnsType
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.normalizeHost
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.xbill.DNS.DClass
import org.xbill.DNS.Message
import org.xbill.DNS.Name
import org.xbill.DNS.Rcode
import org.xbill.DNS.Record
import org.xbill.DNS.ReverseMap
import org.xbill.DNS.Section
import org.xbill.DNS.SimpleResolver
import org.xbill.DNS.TextParseException
import org.xbill.DNS.Type
import java.io.IOException
import java.net.IDN
import java.net.InetAddress
import java.time.Duration

/**
 * Thin, exception-safe wrapper around dnsjava.
 *
 * Every lookup is performed on [Dispatchers.IO] with a 4 second per-attempt
 * timeout and at most one retry, so a hanging resolver can never stall a
 * caller indefinitely. All failures are reported through [DnsResult.error].
 */
object DnsEngine {

    /**
     * Display label to resolver address. The first entry means "use the
     * platform resolver"; the rest are literal IP addresses so no bootstrap
     * DNS lookup is required.
     */
    val RESOLVERS: List<Pair<String, String>> = listOf(
        "System" to "system",
        "Cloudflare" to "1.1.1.1",
        "Google" to "8.8.8.8",
        "Quad9" to "9.9.9.9",
        "OpenDNS" to "208.67.222.222",
        "AdGuard" to "94.140.14.14"
    )

    private const val TIMEOUT_SECONDS = 4L
    private const val MAX_ATTEMPTS = 2

    private val IPV6_LITERAL = Regex("^[0-9A-Fa-f:.]+$")
    private val IS_ANDROID = System.getProperty("java.vendor")
        ?.contains("Android", ignoreCase = true) == true

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    suspend fun lookup(name: String, type: DnsType, resolver: String? = null): DnsResult =
        withContext(Dispatchers.IO) {
            val started = System.nanoTime()
            val queryText = name.trim()
            val label = resolverLabel(resolver)
            try {
                val server = resolveServer(resolver)
                if (queryText.isEmpty()) {
                    throw IllegalArgumentException("Enter a domain name or IP address")
                }
                val questionName = if (type == DnsType.PTR && isIpLiteral(queryText)) {
                    val address = parseIpLiteral(queryText)
                        ?: throw IllegalArgumentException("Invalid IP address")
                    ReverseMap.fromAddress(address)
                } else {
                    toAbsoluteName(queryText)
                }
                performQuery(queryText, type, questionName, label, server, started)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                DnsResult(
                    query = queryText,
                    type = type,
                    resolver = label,
                    durationMs = elapsedMs(started),
                    error = friendlyMessage(e)
                )
            }
        }

    suspend fun reverse(ip: String, resolver: String? = null): DnsResult =
        withContext(Dispatchers.IO) {
            val started = System.nanoTime()
            val queryText = ip.trim()
            val label = resolverLabel(resolver)
            try {
                val server = resolveServer(resolver)
                if (queryText.isEmpty()) {
                    throw IllegalArgumentException("Enter an IP address")
                }
                val address = parseIpLiteral(queryText)
                    ?: throw IllegalArgumentException("Invalid IP address")
                performQuery(
                    queryText = queryText,
                    type = DnsType.PTR,
                    questionName = ReverseMap.fromAddress(address),
                    label = label,
                    server = server,
                    started = started
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                DnsResult(
                    query = queryText,
                    type = DnsType.PTR,
                    resolver = label,
                    durationMs = elapsedMs(started),
                    error = friendlyMessage(e)
                )
            }
        }

    // -----------------------------------------------------------------------
    // Query execution (blocking, called from Dispatchers.IO)
    // -----------------------------------------------------------------------

    private fun performQuery(
        queryText: String,
        type: DnsType,
        questionName: Name,
        label: String,
        server: String?,
        started: Long
    ): DnsResult {
        val question = Message.newQuery(
            Record.newRecord(questionName, typeCode(type), DClass.IN)
        )
        val resolver = if (server == null) createSystemResolver() else SimpleResolver(server)
        resolver.setTimeout(Duration.ofSeconds(TIMEOUT_SECONDS))

        var response: Message? = null
        var lastFailure: Exception? = null
        for (attempt in 0 until MAX_ATTEMPTS) {
            try {
                val candidate = resolver.send(question)
                response = candidate
                // One retry for a transient server failure.
                if (candidate.rcode == Rcode.SERVFAIL && attempt < MAX_ATTEMPTS - 1) {
                    continue
                }
                break
            } catch (e: IOException) {
                lastFailure = e
            } catch (e: Exception) {
                lastFailure = e
            }
        }

        val answer = response
        if (answer == null) {
            return DnsResult(
                query = queryText,
                type = type,
                resolver = label,
                durationMs = elapsedMs(started),
                error = friendlyMessage(lastFailure ?: IOException("DNS query failed"))
            )
        }

        val rcode = answer.rcode
        val records = if (rcode == Rcode.NOERROR) {
            answer.getSection(Section.ANSWER).mapNotNull { record ->
                val recordType = Type.string(record.type).ifBlank { "TYPE${record.type}" }
                val value = try {
                    record.rdataToString()
                } catch (_: Exception) {
                    return@mapNotNull null
                }
                DnsRecord(
                    type = recordType,
                    value = value,
                    ttl = record.ttl
                )
            }
        } else {
            emptyList()
        }

        return DnsResult(
            query = queryText,
            type = type,
            resolver = label,
            records = records,
            durationMs = elapsedMs(started),
            error = rcodeError(rcode)
        )
    }

    // -----------------------------------------------------------------------
    // Parsing / normalization helpers
    // -----------------------------------------------------------------------

    /**
     * The platform resolver needs dnsjava's Android config provider to have
     * an application context (installed by IpInfoEngine on startup). When
     * that never happened dnsjava quietly falls back to 127.0.0.1, so fail
     * fast with an actionable message instead of waiting for a timeout.
     */
    private fun createSystemResolver(): SimpleResolver {
        val resolver = SimpleResolver()
        if (IS_ANDROID) {
            val address = resolver.address?.address
            if (address == null || address.isLoopbackAddress) {
                throw IllegalStateException(
                    "System DNS is unavailable on this device — choose a resolver"
                )
            }
        }
        return resolver
    }

    private fun typeCode(type: DnsType): Int = when (type) {
        DnsType.A -> Type.A
        DnsType.AAAA -> Type.AAAA
        DnsType.CNAME -> Type.CNAME
        DnsType.MX -> Type.MX
        DnsType.NS -> Type.NS
        DnsType.TXT -> Type.TXT
        DnsType.SOA -> Type.SOA
        DnsType.SRV -> Type.SRV
        DnsType.CAA -> Type.CAA
        DnsType.PTR -> Type.PTR
    }

    private fun toAbsoluteName(raw: String): Name {
        var host = normalizeHost(raw)
        if (host.isEmpty()) throw IllegalArgumentException("Invalid domain name")
        if (host.any { it.code > 127 }) {
            host = try {
                IDN.toASCII(host)
            } catch (_: Exception) {
                host
            }
        }
        val absolute = if (host.endsWith('.')) host else "$host."
        return try {
            Name.fromString(absolute)
        } catch (e: TextParseException) {
            throw IllegalArgumentException("Invalid domain name")
        }
    }

    /**
     * Returns null for the platform resolver, otherwise a validated literal
     * resolver address. Accepts a display label as well as an address.
     */
    private fun resolveServer(value: String?): String? {
        val requested = value?.trim().orEmpty()
        if (requested.isEmpty() || requested.equals("system", ignoreCase = true)) return null
        val address = RESOLVERS.firstOrNull { it.second.equals(requested, ignoreCase = true) }?.second
            ?: RESOLVERS.firstOrNull { it.first.equals(requested, ignoreCase = true) }?.second
            ?: requested
        if (!isIpLiteral(address)) {
            throw IllegalArgumentException("Invalid resolver address: $requested")
        }
        return cleanIp(address)
    }

    private fun resolverLabel(value: String?): String {
        val requested = value?.trim().orEmpty()
        if (requested.isEmpty() || requested.equals("system", ignoreCase = true)) {
            return RESOLVERS.first().first
        }
        RESOLVERS.firstOrNull { it.second.equals(requested, ignoreCase = true) }?.let {
            return it.first
        }
        RESOLVERS.firstOrNull { it.first.equals(requested, ignoreCase = true) }?.let {
            return it.first
        }
        return requested
    }

    private fun parseIpLiteral(value: String): InetAddress? {
        val cleaned = cleanIp(value)
        if (cleaned.isEmpty()) return null
        val candidate = isValidIpv4(cleaned) ||
            (cleaned.contains(':') && IPV6_LITERAL.matches(cleaned))
        if (!candidate) return null
        return try {
            InetAddress.getByName(cleaned)
        } catch (_: Exception) {
            null
        }
    }

    private fun isIpLiteral(value: String): Boolean = parseIpLiteral(value) != null

    private fun cleanIp(value: String): String {
        var cleaned = value.trim()
        if (cleaned.startsWith("[") && cleaned.endsWith("]")) {
            cleaned = cleaned.substring(1, cleaned.length - 1)
        }
        val zone = cleaned.indexOf('%')
        if (zone > 0) cleaned = cleaned.substring(0, zone)
        return cleaned
    }

    private fun rcodeError(rcode: Int): String? = when (rcode) {
        Rcode.NOERROR -> null
        Rcode.NXDOMAIN -> "Domain not found (NXDOMAIN)"
        Rcode.SERVFAIL -> "DNS server failure (SERVFAIL)"
        Rcode.REFUSED -> "Query refused by resolver"
        Rcode.NOTIMP -> "Query type not supported by resolver"
        else -> Rcode.string(rcode)
    }

    private fun friendlyMessage(error: Throwable): String {
        if (error is TextParseException) return "Invalid domain name"
        val message = error.message?.trim().orEmpty()
        return message.ifEmpty { error::class.java.simpleName.ifEmpty { "DNS lookup failed" } }
    }

    private fun elapsedMs(started: Long): Long = (System.nanoTime() - started) / 1_000_000L
}
