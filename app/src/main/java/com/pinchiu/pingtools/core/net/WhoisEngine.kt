package com.pinchiu.pingtools.core.net

import com.pinchiu.pingtools.core.model.WhoisField
import com.pinchiu.pingtools.core.model.WhoisResult
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.normalizeHost
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.IDN
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Minimal WHOIS client speaking raw TCP to port 43.
 *
 * The query starts at IANA, follows up to two `refer:` / `whois:` referrals
 * and returns both the parsed `Key: Value` fields and the final raw text.
 * Sockets have 8 second connect/read timeouts, the response is capped at
 * 512 KB, and every failure is reported through [WhoisResult.error].
 */
object WhoisEngine {

    private const val IANA_SERVER = "whois.iana.org"
    private const val WHOIS_PORT = 43
    private const val CONNECT_TIMEOUT_MS = 8_000
    private const val READ_TIMEOUT_MS = 8_000
    private const val TOTAL_TIMEOUT_MS = 15_000L
    private const val MAX_BYTES = 512 * 1024
    private const val MAX_REFERRALS = 2
    private const val MAX_FIELDS = 200

    private val REFERRAL_PATTERNS = listOf(
        Regex("(?im)^\\s*refer:\\s*(\\S+)"),
        Regex("(?im)^\\s*(?:registrar\\s+)?whois(?:\\s+server)?:\\s*(\\S+)"),
        Regex("(?im)^\\s*referralserver:\\s*(\\S+)")
    )

    private val SERVER_NAME = Regex("^[A-Za-z0-9.-]+$")
    private val FIELD_KEY = Regex("^[A-Za-z0-9][A-Za-z0-9 ._/&()'-]{0,60}$")
    private val IPV6_CHARS = Regex("^[0-9A-Fa-f:.]+$")

    private val BLOCKED_MARKERS = listOf(
        "access denied",
        "not authorized",
        "query refused",
        "too many requests",
        "exceeded the query limit",
        "quota exceeded"
    )

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    suspend fun lookup(query: String): WhoisResult = withContext(Dispatchers.IO) {
        val started = System.nanoTime()
        val original = query.trim()

        try {
            val target = normalizeTarget(original)
            var server = IANA_SERVER
            var raw = ""
            var lastError: String? = null
            var referrals = 0
            val visited = mutableSetOf(IANA_SERVER.lowercase())

            // IANA only knows TLDs, not second-level names. Bootstrap from the
            // TLD (com -> whois.verisign-grs.com) before querying the domain,
            // otherwise example.com would return only five useless IANA fields.
            if (!isIpTarget(target)) {
                val tld = target.substringAfterLast('.', "")
                if (tld.isNotBlank() && tld != target) {
                    val bootstrap = try {
                        queryServer(IANA_SERVER, tld)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        null
                    }
                    val registry = bootstrap?.let {
                        parseReferral(it, IANA_SERVER, visited)
                    }
                    if (registry != null) server = registry
                }
            }

            while (true) {
                visited.add(server.lowercase())
                val response = try {
                    queryServer(server, target)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    lastError = "Whois server $server did not respond: " +
                        (e.message?.trim().takeUnless { it.isNullOrEmpty() } ?: "connection failed")
                    break
                }

                if (response.isBlank()) {
                    lastError = "Empty response from $server"
                    break
                }
                raw = if (raw.isEmpty()) response else "$raw\n\n$response"

                if (referrals >= MAX_REFERRALS) break
                val next = parseReferral(response, server, visited) ?: break
                server = next
                referrals++
            }

            val fields = if (raw.isBlank()) emptyList() else parseFields(raw)
            val error = when {
                raw.isBlank() -> lastError ?: "No response from whois server"
                lastError != null -> lastError
                else -> blockedReason(raw)
            }

            WhoisResult(
                query = original,
                server = server,
                raw = raw,
                fields = fields,
                durationMs = elapsedMs(started),
                error = error
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            WhoisResult(
                query = original,
                server = "",
                durationMs = elapsedMs(started),
                error = e.message?.trim().takeUnless { it.isNullOrEmpty() } ?: "Whois lookup failed"
            )
        }
    }

    // -----------------------------------------------------------------------
    // Target normalization
    // -----------------------------------------------------------------------

    private fun normalizeTarget(input: String): String {
        if (input.isEmpty()) throw IllegalArgumentException("Enter a domain or IP address")

        // Never allow CR/LF injection into the port 43 query.
        val cleaned = input.replace(Regex("[\\r\\n\\u0000]"), "").trim()
        if (cleaned.isEmpty()) throw IllegalArgumentException("Enter a domain or IP address")

        val target = when {
            isValidIpv4(cleaned) -> cleaned
            cleaned.contains(':') && IPV6_CHARS.matches(stripZoneAndBrackets(cleaned)) ->
                stripZoneAndBrackets(cleaned)
            else -> normalizeHost(cleaned)
        }

        if (target.isEmpty()) throw IllegalArgumentException("Enter a domain or IP address")
        if (target.any { it.isWhitespace() }) throw IllegalArgumentException("Invalid query")
        if (target.none { it.code > 127 }) return target
        return try {
            IDN.toASCII(target)
        } catch (_: Exception) {
            target
        }
    }

    private fun isIpTarget(target: String): Boolean =
        isValidIpv4(target) || (target.contains(':') && IPV6_CHARS.matches(target))

    private fun stripZoneAndBrackets(value: String): String {
        var cleaned = value.trim()
        if (cleaned.startsWith("[") && cleaned.endsWith("]")) {
            cleaned = cleaned.substring(1, cleaned.length - 1)
        }
        val zone = cleaned.indexOf('%')
        if (zone > 0) cleaned = cleaned.substring(0, zone)
        return cleaned
    }

    // -----------------------------------------------------------------------
    // Referral handling
    // -----------------------------------------------------------------------

    private fun parseReferral(
        response: String,
        currentServer: String,
        visited: Set<String>
    ): String? {
        val current = currentServer.lowercase()
        for (pattern in REFERRAL_PATTERNS) {
            for (match in pattern.findAll(response)) {
                val host = normalizeServer(match.groupValues[1]) ?: continue
                val normalized = host.lowercase()
                if (normalized == current || normalized in visited) continue
                return host
            }
        }
        return null
    }

    private fun normalizeServer(raw: String): String? {
        var value = raw.trim().trim(',', ';', '"', '\'', '.')
        value = value.removePrefix("whois://").removePrefix("rwhois://")
        value = value.substringBefore('/').substringBefore('?').substringBefore('#')
        if (value.contains('@')) value = value.substringAfter('@')
        if (value.count { it == ':' } == 1) value = value.substringBefore(':')
        value = value.trimEnd('.')
        if (value.isEmpty() || value.length > 253 || !value.contains('.')) return null
        if (!SERVER_NAME.matches(value)) return null
        return value
    }

    // -----------------------------------------------------------------------
    // Raw socket I/O
    // -----------------------------------------------------------------------

    private fun queryServer(server: String, query: String): String {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(server, WHOIS_PORT), CONNECT_TIMEOUT_MS)
            socket.soTimeout = READ_TIMEOUT_MS

            val output = socket.getOutputStream()
            output.write("$query\r\n".toByteArray(Charsets.ISO_8859_1))
            output.flush()

            val input = socket.getInputStream()
            val buffer = ByteArray(8 * 1024)
            val collected = ByteArrayOutputStream()
            val deadline = System.currentTimeMillis() + TOTAL_TIMEOUT_MS

            while (collected.size() < MAX_BYTES) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) break
                socket.soTimeout = remaining.coerceAtMost(READ_TIMEOUT_MS.toLong())
                    .toInt()
                    .coerceAtLeast(1)
                val read = input.read(buffer)
                if (read < 0) break
                val accepted = minOf(read, MAX_BYTES - collected.size())
                collected.write(buffer, 0, accepted)
                if (accepted < read) break
            }

            return String(collected.toByteArray(), Charsets.ISO_8859_1)
        }
    }

    // -----------------------------------------------------------------------
    // Response parsing
    // -----------------------------------------------------------------------

    private fun parseFields(raw: String): List<WhoisField> {
        val fields = ArrayList<WhoisField>(minOf(MAX_FIELDS, 64))
        var key: String? = null
        var value: StringBuilder? = null

        fun flush() {
            val fieldKey = key
            val fieldValue = value?.toString()?.trim()
            if (fields.size < MAX_FIELDS &&
                !fieldKey.isNullOrEmpty() &&
                !fieldValue.isNullOrEmpty()
            ) {
                fields.add(WhoisField(fieldKey, fieldValue))
            }
            key = null
            value = null
        }

        for (rawLine in raw.lineSequence()) {
            if (fields.size >= MAX_FIELDS && key == null) break
            val line = rawLine.trimEnd()
            val trimmed = line.trim()
            if (trimmed.isEmpty()) {
                flush()
                continue
            }
            if (trimmed.startsWith("%") ||
                trimmed.startsWith("#") ||
                trimmed.startsWith(">>>")
            ) {
                flush()
                continue
            }

            // A field may itself be indented (Verisign and some registrars
            // indent every line), so detect "Key: value" before treating an
            // indented line as a continuation of the previous value.
            val colon = line.indexOf(':')
            val separated = colon > 0 &&
                (colon == line.length - 1 || line[colon + 1].isWhitespace())
            val candidateKey = if (separated) line.substring(0, colon).trim() else ""
            if (separated && FIELD_KEY.matches(candidateKey)) {
                flush()
                key = candidateKey
                value = StringBuilder(line.substring(colon + 1).trim())
                continue
            }

            if (key != null && (line.startsWith(" ") || line.startsWith("\t"))) {
                value?.append(' ')?.append(trimmed)
                continue
            }
            flush()
        }
        flush()
        return fields
    }

    private fun blockedReason(raw: String): String? {
        val start = raw.trim().take(1_500).lowercase()
        if (start.startsWith("<!doctype") || start.startsWith("<html")) {
            return "Unexpected HTML response from whois server"
        }
        val marker = BLOCKED_MARKERS.firstOrNull { start.contains(it) }
        return if (marker == null) null else "Whois server rejected the query ($marker)"
    }

    private fun elapsedMs(started: Long): Long = (System.nanoTime() - started) / 1_000_000L
}
