package com.pinchiu.pingtools.core.util

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

/**
 * Small process helper used by the ICMP-based engines.
 *
 * Android's toybox `ping` is used when available. It is subject to the
 * kernel's ping_group_range policy, so callers must handle failure and
 * fall back to TCP connect latency.
 */
object Shell {

    data class Result(
        val exitCode: Int,
        val stdout: String,
        val stderr: String
    ) {
        val combined: String get() = if (stderr.isBlank()) stdout else "$stdout\n$stderr".trim()
    }

    private val PING_BINARY: String = listOf(
        "/system/bin/ping",
        "/system/xbin/ping",
        "/vendor/bin/ping",
        "/bin/ping",
        "/usr/bin/ping"
    ).firstOrNull { java.io.File(it).canExecute() } ?: "ping"

    fun pingBinary(): String = PING_BINARY

    suspend fun exec(
        command: List<String>,
        timeoutMs: Long = 15_000,
        onLine: ((String) -> Unit)? = null
    ): Result = withContext(Dispatchers.IO) {
        val process = try {
            ProcessBuilder(command).redirectErrorStream(false).start()
        } catch (e: Exception) {
            return@withContext Result(-1, "", e.message ?: "Failed to start process")
        }

        val outBuilder = StringBuilder()
        val errBuilder = StringBuilder()
        val outReader = Thread {
            try {
                BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
                    lines.forEach { line ->
                        outBuilder.append(line).append('\n')
                        onLine?.invoke(line)
                    }
                }
            } catch (_: Exception) {
            }
        }
        val errReader = Thread {
            try {
                BufferedReader(InputStreamReader(process.errorStream)).useLines { lines ->
                    lines.forEach { line -> errBuilder.append(line).append('\n') }
                }
            } catch (_: Exception) {
            }
        }
        outReader.isDaemon = true
        errReader.isDaemon = true
        outReader.start()
        errReader.start()

        val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
        if (!finished) process.destroyForcibly()
        outReader.join(500)
        errReader.join(500)

        Result(
            exitCode = if (finished) process.exitValue() else -1,
            stdout = outBuilder.toString().trim(),
            stderr = errBuilder.toString().trim()
        )
    }
}
