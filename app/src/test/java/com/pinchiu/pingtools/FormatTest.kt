package com.pinchiu.pingtools

import com.pinchiu.pingtools.core.util.formatBytes
import com.pinchiu.pingtools.core.util.fmtLatency
import com.pinchiu.pingtools.core.util.ipv4ToLong
import com.pinchiu.pingtools.core.util.isPrivateIp
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.longToIpv4
import com.pinchiu.pingtools.core.util.normalizeHost
import com.pinchiu.pingtools.core.util.normalizeMac
import com.pinchiu.pingtools.core.util.parsePortSpec
import com.pinchiu.pingtools.core.util.parseSubnetInput
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FormatTest {

    @Test fun latencyFormatting() {
        assertEquals("0.42 ms", fmtLatency(0.42))
        assertEquals("8.1 ms", fmtLatency(8.12))
        assertEquals("143 ms", fmtLatency(143.4))
        assertEquals("--", fmtLatency(Double.NaN))
    }

    @Test fun hostNormalization() {
        assertEquals("example.com", normalizeHost("https://example.com/path?q=1"))
        assertEquals("1.1.1.1", normalizeHost(" 1.1.1.1 "))
        assertEquals("example.com", normalizeHost("example.com:443"))
        assertEquals("2606:4700::1111", normalizeHost("[2606:4700::1111]"))
    }

    @Test fun ipValidation() {
        assertTrue(isValidIpv4("192.168.1.1"))
        assertFalse(isValidIpv4("256.1.1.1"))
        assertFalse(isValidIpv4("1.2.3"))
        assertTrue(isPrivateIp("10.1.2.3"))
        assertTrue(isPrivateIp("172.20.0.5"))
        assertTrue(isPrivateIp("192.168.0.2"))
        assertFalse(isPrivateIp("8.8.8.8"))
    }

    @Test fun portSpecParsing() {
        assertEquals(listOf(22, 80, 443), parsePortSpec("22, 80,443"))
        assertEquals(listOf(8000, 8001, 8002), parsePortSpec("8000-8002"))
        assertEquals(listOf(22, 80, 8000, 8001), parsePortSpec("22,80,8000-8001"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun portSpecRejectsInvalid() {
        parsePortSpec("0")
    }

    @Test(expected = IllegalArgumentException::class)
    fun portSpecRejectsHugeRange() {
        parsePortSpec("1-60000")
    }

    @Test fun macNormalization() {
        assertEquals("AA:BB:CC:DD:EE:FF", normalizeMac("aabbccddeeff"))
        assertEquals("AA:BB:CC:DD:EE:FF", normalizeMac("AA-BB-CC-DD-EE-FF"))
        assertNull(normalizeMac("not-a-mac"))
    }

    @Test fun subnetParsing() {
        val cidr = parseSubnetInput("192.168.1.0/24")
        assertEquals(24, cidr?.prefixLength)
        assertEquals(254, cidr?.totalHosts)
        assertNull(parseSubnetInput("192.168.1.0/31"))
        val range = parseSubnetInput("10.0.0.10-10.0.0.20")
        assertEquals(11, range?.totalHosts)
    }

    @Test fun byteFormatting() {
        assertEquals("512 B", formatBytes(512))
        assertEquals("1.0 KB", formatBytes(1024))
        assertEquals("1.5 MB", formatBytes(1024L * 1024L * 3 / 2))
    }

    @Test fun ipv4LongRoundTrip() {
        val value = ipv4ToLong("192.168.1.20")
        assertEquals("192.168.1.20", value?.let(::longToIpv4))
    }
}
