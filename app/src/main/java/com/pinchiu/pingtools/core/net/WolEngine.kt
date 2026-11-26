package com.pinchiu.pingtools.core.net

import com.pinchiu.pingtools.core.model.WolOutcome
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.normalizeMac
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.UnknownHostException

/**
 * Wake-on-LAN sender.
 *
 * Builds the standard 102-byte magic packet (optionally extended with a
 * 6-byte SecureOn password) and sends it three times over UDP broadcast.
 */
object WolEngine {

    private const val PACKET_COUNT = 3
    private const val PACKET_SPACING_MS = 60L

    suspend fun wake(
        mac: String,
        broadcast: String = "255.255.255.255",
        port: Int = 9,
        secureOn: String? = null
    ): Result<WolOutcome> = withContext(Dispatchers.IO) {
        val normalizedMac = normalizeMac(mac)
            ?: return@withContext Result.failure(IllegalArgumentException("Invalid MAC address"))

        if (port !in 1..65535) {
            return@withContext Result.failure(
                IllegalArgumentException("Port must be between 1 and 65535")
            )
        }

        val normalizedSecureOn = if (secureOn.isNullOrBlank()) {
            null
        } else {
            normalizeMac(secureOn)
                ?: return@withContext Result.failure(
                    IllegalArgumentException("Invalid SecureOn password")
                )
        }

        val target = try {
            resolveBroadcast(broadcast)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return@withContext Result.failure(e)
        }

        val payload = buildMagicPacket(normalizedMac, normalizedSecureOn)

        try {
            val socket = DatagramSocket()
            try {
                socket.broadcast = true
                val packet = DatagramPacket(payload, payload.size, target, port)
                repeat(PACKET_COUNT) { index ->
                    socket.send(packet)
                    if (index < PACKET_COUNT - 1) delay(PACKET_SPACING_MS)
                }
            } finally {
                runCatching { socket.close() }
            }

            Result.success(
                WolOutcome(
                    mac = normalizedMac,
                    address = target.hostAddress ?: broadcast.trim(),
                    port = port,
                    packetsSent = PACKET_COUNT
                )
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun resolveBroadcast(input: String): InetAddress {
        val value = input.trim()
        if (value.isEmpty()) {
            throw IllegalArgumentException("Broadcast address is required")
        }
        if (isValidIpv4(value)) {
            return InetAddress.getByName(value)
        }
        val candidates = InetAddress.getAllByName(value)
        return candidates.firstOrNull { it is Inet4Address }
            ?: throw UnknownHostException("Broadcast address must resolve to IPv4")
    }

    private fun buildMagicPacket(mac: String, secureOn: String?): ByteArray {
        val macBytes = mac.split(':').map { it.toInt(16).toByte() }
        val passwordBytes = secureOn?.split(':')?.map { it.toInt(16).toByte() }.orEmpty()

        val packet = ByteArray(6 + 16 * macBytes.size + passwordBytes.size)
        for (index in 0 until 6) {
            packet[index] = 0xFF.toByte()
        }

        var offset = 6
        repeat(16) {
            for (byte in macBytes) {
                packet[offset++] = byte
            }
        }
        for (byte in passwordBytes) {
            packet[offset++] = byte
        }
        return packet
    }
}
