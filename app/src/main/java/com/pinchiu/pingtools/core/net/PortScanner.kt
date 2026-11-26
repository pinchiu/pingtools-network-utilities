package com.pinchiu.pingtools.core.net

import com.pinchiu.pingtools.core.model.PortResult
import com.pinchiu.pingtools.core.model.PortScanConfig
import com.pinchiu.pingtools.core.model.PortScanEvent
import com.pinchiu.pingtools.core.model.PortScanProgress
import com.pinchiu.pingtools.core.model.PortState
import com.pinchiu.pingtools.core.util.normalizeHost
import com.pinchiu.pingtools.core.util.serviceNameForPort
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import java.io.IOException
import java.net.ConnectException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NoRouteToHostException
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

/**
 * TCP connect port scanner.
 *
 * Every port gets its own bounded connect attempt; a [Semaphore] caps the
 * number of in-flight sockets. The flow never throws for network errors and
 * only ever terminates with [PortScanEvent.Finished] or [PortScanEvent.Failed].
 */
object PortScanner {

    private const val MAX_CONCURRENCY = 128
    private const val PROGRESS_INTERVAL_NANOS = 100_000_000L // ~10 updates per second
    private const val BANNER_TIMEOUT_MS = 600
    private const val BANNER_MAX_BYTES = 512
    private const val BANNER_MAX_CHARS = 160

    private val HTTP_PORTS = setOf(80, 8080)
    private val TLS_PORTS = setOf(443, 8443)
    private val WHITESPACE = Regex("\\s+")

    fun scan(config: PortScanConfig): Flow<PortScanEvent> = channelFlow<PortScanEvent> {
        val startedAt = System.nanoTime()

        val host = normalizeHost(config.host).ifBlank { config.host.trim() }
        val ports = config.ports.asSequence()
            .filter { it in 1..65535 }
            .distinct()
            .sorted()
            .toList()

        if (host.isEmpty()) {
            send(PortScanEvent.Started(config.host, null, ports.size))
            send(PortScanEvent.Failed("Enter a host to scan"))
            return@channelFlow
        }
        if (ports.isEmpty()) {
            send(PortScanEvent.Started(host, null, 0))
            send(PortScanEvent.Failed("No valid ports to scan"))
            return@channelFlow
        }

        val address = try {
            InetAddress.getByName(host)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }

        send(PortScanEvent.Started(host, address?.hostAddress, ports.size))
        if (address == null) {
            send(PortScanEvent.Failed("Cannot resolve host: $host"))
            return@channelFlow
        }

        try {
            val total = ports.size
            val concurrency = config.concurrency.coerceIn(1, MAX_CONCURRENCY)
            val connectTimeoutMs = config.timeoutMs.coerceAtLeast(1)

            val results = ConcurrentHashMap<Int, PortResult>()
            val activeSockets: MutableSet<Socket> =
                Collections.newSetFromMap(ConcurrentHashMap<Socket, Boolean>())

            coroutineScope {
                // A cancellation watcher: when the collector goes away this
                // closes every socket still blocked in connect()/read() so the
                // workers stop promptly instead of waiting for their timeouts.
                val socketReaper = launch(start = CoroutineStart.UNDISPATCHED) {
                    try {
                        awaitCancellation()
                    } finally {
                        activeSockets.forEach { socket -> runCatching { socket.close() } }
                    }
                }

                try {
                    // The nested scope waits for every worker before the
                    // reaper is cancelled, so sockets are not closed early.
                    coroutineScope {
                        val semaphore = Semaphore(concurrency)
                        val progressLock = Mutex()
                        var scanned = 0
                        var lastProgressNanos = 0L

                        for (port in ports) {
                            launch {
                                semaphore.withPermit {
                                    currentCoroutineContext().ensureActive()
                                    val result = scanPort(
                                        address = address,
                                        host = host,
                                        port = port,
                                        grabBanners = config.grabBanners,
                                        timeoutMs = connectTimeoutMs,
                                        activeSockets = activeSockets
                                    )

                                    progressLock.withLock {
                                        results[port] = result
                                        scanned += 1

                                        val now = System.nanoTime()
                                        val emitNow = result.state == PortState.OPEN ||
                                            lastProgressNanos == 0L ||
                                            now - lastProgressNanos >= PROGRESS_INTERVAL_NANOS ||
                                            scanned == total

                                        if (emitNow) {
                                            lastProgressNanos = now
                                            val open = results.values
                                                .filter { it.state == PortState.OPEN }
                                                .sortedBy { it.port }
                                            send(
                                                PortScanEvent.Progress(
                                                    PortScanProgress(
                                                        scanned = scanned,
                                                        total = total,
                                                        open = open
                                                    )
                                                )
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                } finally {
                    socketReaper.cancel()
                }
            }

            val ordered = results.values.sortedBy { it.port }
            send(
                PortScanEvent.Finished(
                    results = ordered,
                    durationMs = (System.nanoTime() - startedAt) / 1_000_000L
                )
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            send(PortScanEvent.Failed(e.message ?: "Port scan failed"))
        }
    }.flowOn(Dispatchers.IO)

    private fun scanPort(
        address: InetAddress,
        host: String,
        port: Int,
        grabBanners: Boolean,
        timeoutMs: Int,
        activeSockets: MutableSet<Socket>
    ): PortResult {
        val service = serviceNameForPort(port)
        var socket: Socket? = null
        try {
            val created = Socket()
            socket = created
            activeSockets.add(created)

            created.connect(InetSocketAddress(address, port), timeoutMs)
            val banner = if (grabBanners) grabBanner(created, host, port) else null
            return PortResult(port, PortState.OPEN, service, banner)
        } catch (e: CancellationException) {
            throw e
        } catch (e: SocketTimeoutException) {
            return PortResult(port, PortState.FILTERED, service, null)
        } catch (e: ConnectException) {
            val message = e.message?.lowercase().orEmpty()
            val state = if (message.contains("refused") || message.contains("reject")) {
                PortState.CLOSED
            } else {
                PortState.FILTERED
            }
            return PortResult(port, state, service, null)
        } catch (e: NoRouteToHostException) {
            return PortResult(port, PortState.FILTERED, service, null)
        } catch (e: IOException) {
            return PortResult(port, PortState.FILTERED, service, null)
        } catch (e: SecurityException) {
            return PortResult(port, PortState.FILTERED, service, null)
        } finally {
            val toClose = socket
            if (toClose != null) {
                activeSockets.remove(toClose)
                runCatching { toClose.close() }
            }
        }
    }

    /**
     * Reads a short greeting from an open socket. HTTP-ish ports are nudged
     * with a HEAD request first because most web servers do not speak first.
     * Any I/O failure simply means "no banner".
     */
    private fun grabBanner(socket: Socket, host: String, port: Int): String? {
        // A cleartext HEAD sent to a TLS listener produces a misleading 400.
        if (port in TLS_PORTS) return null
        return try {
            socket.soTimeout = BANNER_TIMEOUT_MS

            if (port in HTTP_PORTS) {
                val request = "HEAD / HTTP/1.0\r\nHost: $host\r\n\r\n"
                val output = socket.getOutputStream()
                output.write(request.toByteArray(Charsets.US_ASCII))
                output.flush()
            }

            val input = socket.getInputStream()
            val buffer = ByteArray(BANNER_MAX_BYTES)
            var total = 0
            while (total < buffer.size) {
                val read = try {
                    input.read(buffer, total, buffer.size - total)
                } catch (e: SocketTimeoutException) {
                    -1
                }
                if (read <= 0) break
                total += read

                // Only the first line is kept, so stop as soon as it arrives.
                var sawNewline = false
                for (index in 0 until total) {
                    if (buffer[index] == '\n'.code.toByte()) {
                        sawNewline = true
                        break
                    }
                }
                if (sawNewline) break
            }

            if (total <= 0) {
                null
            } else {
                sanitizeBanner(String(buffer, 0, total, Charsets.ISO_8859_1))
            }
        } catch (e: Exception) {
            null
        }
    }

    /** Keeps one printable line, collapses whitespace and caps the length. */
    private fun sanitizeBanner(raw: String): String? {
        val firstLine = raw.lineSequence().firstOrNull { it.isNotBlank() } ?: return null
        val cleaned = buildString {
            for (ch in firstLine) {
                append(if (ch.code < 0x20 || ch.code == 0x7F) ' ' else ch)
            }
        }
        val collapsed = cleaned.replace(WHITESPACE, " ").trim()
        if (collapsed.isEmpty()) return null
        return collapsed.take(BANNER_MAX_CHARS)
    }
}
