package com.pinchiu.pingtools.core.net

import com.pinchiu.pingtools.core.model.HttpInfo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException

/**
 * HTTP header inspector.
 *
 * Sends a HEAD request first and falls back to a ranged GET (one byte) for
 * servers that reject HEAD. The body is never downloaded: the response is
 * closed after the status line and headers have been read.
 */
object HttpEngine {

    private const val USER_AGENT = "PingTools/1.0"
    private const val DEFAULT_TIMEOUT_MS = 12_000
    private val HEAD_FALLBACK_CODES = setOf(403, 405, 501)

    private val SCHEME_PREFIX = Regex("^([A-Za-z][A-Za-z0-9+.-]*)://")

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    suspend fun inspect(
        url: String,
        followRedirects: Boolean = true,
        timeoutMs: Int = DEFAULT_TIMEOUT_MS
    ): HttpInfo = withContext(Dispatchers.IO) {
        val input = url.trim()
        val normalized = normalizeUrl(input)
        if (normalized == null) {
            val message = if (input.isEmpty()) {
                "Enter a URL"
            } else {
                "Enter a valid http or https URL"
            }
            return@withContext HttpInfo(url = input, error = message)
        }

        val timeout = if (timeoutMs in 1..60_000) timeoutMs.toLong() else DEFAULT_TIMEOUT_MS.toLong()
        val client = OkHttpClient.Builder()
            .followRedirects(followRedirects)
            .followSslRedirects(followRedirects)
            .connectTimeout(timeout, TimeUnit.MILLISECONDS)
            .readTimeout(timeout, TimeUnit.MILLISECONDS)
            .writeTimeout(timeout, TimeUnit.MILLISECONDS)
            .callTimeout(timeout + 2_000L, TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            .build()

        val started = System.nanoTime()
        try {
            val response = perform(client, normalized)
            try {
                buildInfo(normalized, response, elapsedMs(started))
            } finally {
                response.close()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            HttpInfo(
                url = normalized,
                durationMs = elapsedMs(started),
                error = friendlyError(e, normalized, timeout)
            )
        }
    }

    // -----------------------------------------------------------------------
    // Request execution
    // -----------------------------------------------------------------------

    private fun perform(client: OkHttpClient, url: String): Response {
        val head = Request.Builder()
            .url(url)
            .header("User-Agent", USER_AGENT)
            .header("Accept", "*/*")
            .head()
            .build()

        var headResponse: Response? = null
        try {
            headResponse = client.newCall(head).execute()
            if (headResponse.code !in HEAD_FALLBACK_CODES) {
                return headResponse
            }
            headResponse.close()
            headResponse = null
        } catch (_: IOException) {
            headResponse?.close()
            headResponse = null
        }

        val get = Request.Builder()
            .url(url)
            .header("User-Agent", USER_AGENT)
            .header("Accept", "*/*")
            .header("Range", "bytes=0-0")
            .get()
            .build()
        return client.newCall(get).execute()
    }

    // -----------------------------------------------------------------------
    // Result mapping
    // -----------------------------------------------------------------------

    private fun buildInfo(
        requestedUrl: String,
        response: Response,
        durationMs: Long
    ): HttpInfo {
        val finalUrl = response.request.url.toString()
        val handshake = response.handshake
        val contentLength = response.header("Content-Length")?.trim()?.toLongOrNull()
            ?: response.body?.contentLength()?.takeIf { it > 0 }

        return HttpInfo(
            url = requestedUrl,
            finalUrl = finalUrl,
            statusCode = response.code,
            statusMessage = response.message.ifBlank { reasonPhrase(response.code) },
            protocol = response.protocol.name,
            server = response.header("Server"),
            contentType = response.header("Content-Type"),
            contentLength = contentLength,
            durationMs = durationMs,
            tlsVersion = handshake?.tlsVersion?.javaName,
            tlsCipher = handshake?.cipherSuite?.javaName,
            headers = response.headers.map { it.first to it.second },
            security = securityChecks(response, finalUrl)
        )
    }

    private fun securityChecks(
        response: Response,
        finalUrl: String
    ): List<Pair<String, String>> {
        val headers = response.headers
        val hsts = headers["Strict-Transport-Security"] != null
        val csp = headers["Content-Security-Policy"] != null ||
            headers["Content-Security-Policy-Report-Only"] != null
        val frameOptions = headers["X-Frame-Options"] != null
        val contentTypeOptions = headers["X-Content-Type-Options"] != null
        val referrerPolicy = headers["Referrer-Policy"] != null
        val permissionsPolicy = headers["Permissions-Policy"] != null
        val cleartext = finalUrl.startsWith("http://", ignoreCase = true)

        return buildList {
            add("HSTS" to if (hsts) "on" else "off")
            add("CSP" to if (csp) "present" else "absent")
            add("X-Frame-Options" to if (frameOptions) "present" else "absent")
            add("X-Content-Type-Options" to if (contentTypeOptions) "present" else "absent")
            add("Referrer-Policy" to if (referrerPolicy) "present" else "absent")
            add("Permissions-Policy" to if (permissionsPolicy) "present" else "absent")
            add("Cleartext" to if (cleartext) "yes" else "no")
        }
    }

    // -----------------------------------------------------------------------
    // URL / error helpers
    // -----------------------------------------------------------------------

    private fun normalizeUrl(input: String): String? {
        if (input.isEmpty()) return null
        val candidate = when {
            input.startsWith("//") -> "https:$input"
            SCHEME_PREFIX.containsMatchIn(input) -> input
            else -> "https://$input"
        }
        val scheme = SCHEME_PREFIX.find(candidate)?.groupValues?.get(1)?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        return candidate.toHttpUrlOrNull()?.toString()
    }

    private fun friendlyError(e: Exception, url: String, timeoutMs: Long): String = when (e) {
        is UnknownHostException -> {
            val host = url.toHttpUrlOrNull()?.host
            if (host.isNullOrBlank()) "Unknown host" else "Unknown host: $host"
        }
        is SocketTimeoutException -> "Request timed out after ${timeoutMs / 1000}s"
        is SSLException -> "TLS error: " +
            (e.message?.trim().takeUnless { it.isNullOrEmpty() } ?: "handshake failed")
        is IllegalArgumentException -> "Invalid URL: " +
            (e.message?.trim().takeUnless { it.isNullOrEmpty() } ?: "unsupported format")
        else -> e.message?.trim().takeUnless { it.isNullOrEmpty() }
            ?: e::class.java.simpleName.ifEmpty { "Request failed" }
    }

    private fun reasonPhrase(code: Int): String = when (code) {
        200 -> "OK"
        201 -> "Created"
        202 -> "Accepted"
        204 -> "No Content"
        206 -> "Partial Content"
        301 -> "Moved Permanently"
        302 -> "Found"
        303 -> "See Other"
        304 -> "Not Modified"
        307 -> "Temporary Redirect"
        308 -> "Permanent Redirect"
        400 -> "Bad Request"
        401 -> "Unauthorized"
        403 -> "Forbidden"
        404 -> "Not Found"
        405 -> "Method Not Allowed"
        408 -> "Request Timeout"
        409 -> "Conflict"
        410 -> "Gone"
        418 -> "I'm a teapot"
        429 -> "Too Many Requests"
        500 -> "Internal Server Error"
        501 -> "Not Implemented"
        502 -> "Bad Gateway"
        503 -> "Service Unavailable"
        504 -> "Gateway Timeout"
        else -> ""
    }

    private fun elapsedMs(started: Long): Long = (System.nanoTime() - started) / 1_000_000L
}
