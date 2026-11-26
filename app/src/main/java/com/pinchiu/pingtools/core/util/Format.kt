package com.pinchiu.pingtools.core.util

import java.util.Locale
import com.pinchiu.pingtools.core.model.SubnetInfo

/** 0.42 ms / 8.1 ms / 143 ms */
fun fmtLatency(ms: Double): String = when {
    ms.isNaN() || ms.isInfinite() -> "--"
    ms < 1.0 -> String.format(Locale.US, "%.2f ms", ms)
    ms < 10.0 -> String.format(Locale.US, "%.1f ms", ms)
    ms < 100.0 -> String.format(Locale.US, "%.1f ms", ms)
    else -> String.format(Locale.US, "%.0f ms", ms)
}

fun fmtPercent(value: Double, decimals: Int = 1): String =
    String.format(Locale.US, "%.${decimals}f%%", value)

fun formatBytes(bytes: Long): String {
    if (bytes < 0) return "--"
    if (bytes < 1024) return "$bytes B"
    val units = arrayOf("KB", "MB", "GB", "TB")
    var value = bytes.toDouble() / 1024.0
    var index = 0
    while (value >= 1024 && index < units.lastIndex) {
        value /= 1024.0
        index++
    }
    return String.format(Locale.US, "%.1f %s", value, units[index])
}

fun formatDuration(ms: Long): String = when {
    ms < 1_000 -> "${ms}ms"
    ms < 60_000 -> String.format(Locale.US, "%.1fs", ms / 1000.0)
    else -> "${ms / 60_000}m ${(ms % 60_000) / 1000}s"
}

/** Strips scheme, path, port and trailing dots from a user-entered host. */
fun normalizeHost(input: String): String {
    var host = input.trim()
    host = host.removePrefix("http://").removePrefix("https://")
    host = host.substringBefore('/').substringBefore('?').substringBefore('#')
    if (host.startsWith("[") && host.contains("]")) {
        host = host.substringAfter('[').substringBefore(']')
    } else if (host.count { it == ':' } == 1) {
        host = host.substringBefore(':')
    }
    return host.trimEnd('.')
}

private val ipv4Regex = Regex("^(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})$")

fun isValidIpv4(value: String): Boolean {
    val match = ipv4Regex.matchEntire(value.trim()) ?: return false
    return match.groupValues.drop(1).all { part ->
        part.toIntOrNull()?.let { it in 0..255 && (part.length == 1 || !part.startsWith("0")) } == true
    }
}

fun isPrivateIp(value: String): Boolean {
    val match = ipv4Regex.matchEntire(value.trim()) ?: return false
    val (a, b) = match.groupValues.drop(1).mapNotNull { it.toIntOrNull() }.let {
        if (it.size < 2) return false else it[0] to it[1]
    }
    return a == 10 ||
        (a == 172 && b in 16..31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254) ||
        a == 127
}

/**
 * Parses "22,80,443,8000-8010" into a sorted, de-duplicated list of ports.
 * Throws [IllegalArgumentException] with a human-readable message on bad input.
 */
fun parsePortSpec(spec: String): List<Int> {
    val trimmed = spec.trim()
    if (trimmed.isEmpty()) throw IllegalArgumentException("Enter at least one port")
    val ports = sortedSetOf<Int>()
    for (part in trimmed.split(',', ' ', '\n')) {
        if (part.isBlank()) continue
        if (part.contains('-')) {
            val bounds = part.split('-', limit = 2)
            val start = bounds[0].trim().toIntOrNull()
                ?: throw IllegalArgumentException("Invalid port: $part")
            val end = bounds[1].trim().toIntOrNull()
                ?: throw IllegalArgumentException("Invalid port: $part")
            if (start > end) throw IllegalArgumentException("Range start must be <= end: $part")
            if (start !in 1..65535 || end !in 1..65535) {
                throw IllegalArgumentException("Ports must be 1-65535")
            }
            if (end - start > 4096) throw IllegalArgumentException("Range too large (max 4096 ports)")
            for (p in start..end) ports.add(p)
        } else {
            val port = part.trim().toIntOrNull()
                ?: throw IllegalArgumentException("Invalid port: $part")
            if (port !in 1..65535) throw IllegalArgumentException("Ports must be 1-65535")
            ports.add(port)
        }
    }
    if (ports.isEmpty()) throw IllegalArgumentException("Enter at least one port")
    if (ports.size > 4096) throw IllegalArgumentException("Too many ports (max 4096)")
    return ports.toList()
}

private val COMMON_SERVICE_NAMES = mapOf(
    7 to "echo", 9 to "discard", 20 to "ftp-data", 21 to "ftp", 22 to "ssh", 23 to "telnet",
    25 to "smtp", 53 to "dns", 67 to "dhcp", 69 to "tftp", 80 to "http", 110 to "pop3",
    111 to "rpcbind", 123 to "ntp", 135 to "msrpc", 137 to "netbios-ns", 138 to "netbios-dgm",
    139 to "netbios-ssn", 143 to "imap", 161 to "snmp", 389 to "ldap", 443 to "https",
    445 to "smb", 465 to "smtps", 500 to "isakmp", 514 to "syslog", 587 to "submission",
    631 to "ipp", 636 to "ldaps", 993 to "imaps", 995 to "pop3s", 1080 to "socks",
    1194 to "openvpn", 1433 to "mssql", 1521 to "oracle", 1723 to "pptp", 1883 to "mqtt",
    2049 to "nfs", 2375 to "docker", 3128 to "squid", 3306 to "mysql", 3389 to "rdp",
    5060 to "sip", 5432 to "postgresql", 5672 to "amqp", 5900 to "vnc", 6379 to "redis",
    8000 to "http-alt", 8080 to "http-proxy", 8443 to "https-alt", 8888 to "http-alt",
    9000 to "http-alt", 9090 to "http-alt", 9100 to "jetdirect", 27017 to "mongodb"
)

fun serviceNameForPort(port: Int): String = COMMON_SERVICE_NAMES[port] ?: ""

/** Common port presets offered in the port scanner UI. */
val PORT_PRESETS: List<Pair<String, String>> = listOf(
    "Top 20" to "21,22,23,25,53,80,110,139,143,443,445,1433,1521,3306,3389,5432,5900,6379,8080,8443",
    "Web" to "80,443,8000,8080,8081,8443,8888",
    "Remote" to "22,23,3389,5900,5985,5986",
    "Database" to "1433,1521,3306,5432,6379,27017",
    "Full 1-1024" to "1-1024"
)

/** Formats a MAC into AA:BB:CC:DD:EE:FF, or null when invalid. */
fun normalizeMac(input: String): String? {
    val hex = input.filter { it.isLetterOrDigit() }
    if (hex.length != 12 || !hex.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return null
    return hex.chunked(2).joinToString(":") { it.uppercase(Locale.US) }
}

/** Parses "a.b.c.d/nn" or an explicit range "a.b.c.1-a.b.c.254". */
fun parseSubnetInput(input: String): SubnetInfo? {
    val value = input.trim()
    if (value.isEmpty()) return null
    if (value.contains('/')) {
        val address = value.substringBefore('/')
        val prefix = value.substringAfter('/').toIntOrNull() ?: return null
        if (!isValidIpv4(address) || prefix !in 8..30) return null
        return SubnetInfo(
            cidr = "$address/$prefix",
            localIp = address,
            prefixLength = prefix,
            totalHosts = (1 shl (32 - prefix)) - 2
        )
    }
    val start = value.substringBefore('-').trim()
    val end = value.substringAfter('-', "").trim()
    if (end.isEmpty() || !isValidIpv4(start) || !isValidIpv4(end)) return null
    val startLong = ipv4ToLong(start) ?: return null
    val endLong = ipv4ToLong(end) ?: return null
    if (endLong <= startLong || endLong - startLong > 4094) return null
    var prefix = 32
    var mask = 0xFFFFFFFFL
    while (prefix > 8 && (startLong and mask) != startLong) {
        prefix--
        mask = mask shl 1
    }
    return SubnetInfo(
        cidr = value,
        localIp = start,
        prefixLength = prefix,
        totalHosts = (endLong - startLong + 1).toInt()
    )
}

fun ipv4ToLong(ip: String): Long? {
    if (!isValidIpv4(ip)) return null
    var result = 0L
    for (part in ip.split('.')) {
        result = (result shl 8) or part.toLong()
    }
    return result and 0xFFFFFFFFL
}

fun longToIpv4(value: Long): String =
    "${(value shr 24) and 0xFF}.${(value shr 16) and 0xFF}.${(value shr 8) and 0xFF}.${value and 0xFF}"
