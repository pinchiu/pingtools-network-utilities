package com.pinchiu.pingtools.core.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.telephony.TelephonyManager
import com.pinchiu.pingtools.core.model.ConnectionInfo
import com.pinchiu.pingtools.core.model.PublicIpInfo
import com.pinchiu.pingtools.core.model.WifiDetails
import com.pinchiu.pingtools.core.util.isPrivateIp
import com.pinchiu.pingtools.core.util.isValidIpv4
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.xbill.DNS.ResolverConfig
import org.xbill.DNS.config.AndroidResolverConfigProvider
import java.io.File
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.Collections
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Device-side IP / connection information.
 *
 * [connectionInfo] never requires the location permission: every Wi-Fi and
 * telephony access is individually guarded, and unavailable values simply
 * stay null. Public IP and geolocation lookups use two providers with a
 * fallback, so a single 429 or outage does not break the feature.
 */
object IpInfoEngine {

    private const val USER_AGENT = "PingTools/1.0"
    private const val CONNECT_TIMEOUT_SECONDS = 8L
    private const val READ_TIMEOUT_SECONDS = 8L
    private val DNS_CONTEXT_LOCK = Any()

    private enum class GeoProvider { IPWHO, IPAPI }

    private val PUBLIC_ENDPOINTS = listOf(
        "https://ipwho.is/" to GeoProvider.IPWHO,
        "https://ipapi.co/json/" to GeoProvider.IPAPI
    )

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .callTimeout(CONNECT_TIMEOUT_SECONDS + READ_TIMEOUT_SECONDS + 4, TimeUnit.SECONDS)
            .followRedirects(true)
            .retryOnConnectionFailure(true)
            .build()
    }

    private val IPV6_CHARS = Regex("^[0-9A-Fa-f:.]+$")

    // -----------------------------------------------------------------------
    // Local connection information
    // -----------------------------------------------------------------------

    fun connectionInfo(context: Context): ConnectionInfo {
        installSystemDnsContext(context)
        return try {
            val app = context.applicationContext
            val manager = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val network = try {
                manager?.activeNetwork
            } catch (_: Exception) {
                null
            }
            val capabilities = if (network == null) null else try {
                manager?.getNetworkCapabilities(network)
            } catch (_: Exception) {
                null
            }
            val linkProperties = if (network == null) null else try {
                manager?.getLinkProperties(network)
            } catch (_: Exception) {
                null
            }

            val isVpn = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            val onWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            val local = localAddresses()
            val dnsServers = linkProperties?.dnsServers
                ?.mapNotNull { it.hostAddress?.substringBefore('%')?.takeIf { host -> host.isNotBlank() } }
                ?.distinct()
                ?: emptyList()
            val gateway = readGatewayFromProc() ?: defaultGateway(linkProperties)
            val wifi = if (onWifi) readWifi(app, capabilities) else null
            val operatorName = readOperatorName(app)

            ConnectionInfo(
                connectionType = connectionType(capabilities),
                localIpv4 = local.ipv4,
                localIpv6 = local.ipv6,
                gateway = gateway,
                dnsServers = dnsServers,
                wifi = wifi,
                mobileOperator = operatorName,
                isVpn = isVpn
            )
        } catch (_: Exception) {
            ConnectionInfo(connectionType = "Unknown")
        }
    }

    /**
     * dnsjava's Android config provider needs an application context before
     * `SimpleResolver()` can read the platform DNS servers. The home screen
     * always calls [connectionInfo] on startup, so installing it here makes
     * the "System" resolver in [DnsEngine] work for the rest of the process.
     */
    private fun installSystemDnsContext(context: Context) {
        if (dnsContextInstalled) return
        synchronized(DNS_CONTEXT_LOCK) {
            if (dnsContextInstalled) return
            try {
                AndroidResolverConfigProvider.setContext(context.applicationContext)
                ResolverConfig.refresh()
                dnsContextInstalled = true
            } catch (_: Throwable) {
                // Leave it unconfigured; DnsEngine reports a clear error if
                // the platform resolver is selected without a context.
            }
        }
    }

    @Volatile
    private var dnsContextInstalled = false

    private fun connectionType(capabilities: NetworkCapabilities?): String = when {
        capabilities == null -> "Offline"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "VPN"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Cellular"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "Bluetooth"
        else -> "Other"
    }

    // -----------------------------------------------------------------------
    // Wi-Fi and mobile radio details
    // -----------------------------------------------------------------------

    @Suppress("DEPRECATION")
    private fun readWifi(context: Context, capabilities: NetworkCapabilities?): WifiDetails {
        var ssid: String? = null
        var bssid: String? = null
        var rssi: Int? = null
        var linkSpeed: Int? = null
        var frequency: Int? = null

        try {
            val transportInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                capabilities?.transportInfo as? WifiInfo
            } else {
                null
            }
            val wifiInfo = transportInfo
                ?: (context.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.connectionInfo

            if (wifiInfo != null) {
                // Each property is guarded: some OEMs throw SecurityException
                // for SSID/BSSID while still allowing the rest.
                ssid = safeValue { wifiInfo.ssid }?.let(::cleanSsid)
                bssid = safeValue { wifiInfo.bssid }?.let(::cleanBssid)
                rssi = safeValue { wifiInfo.rssi }?.takeIf { it < 0 }
                linkSpeed = safeValue { wifiInfo.linkSpeed }?.takeIf { it > 0 }
                frequency = safeValue { wifiInfo.frequency }?.takeIf { it > 0 }
            }
        } catch (_: SecurityException) {
            // Location / nearby-device permission not granted: leave nulls.
        } catch (_: Exception) {
            // WifiManager unavailable or in a transient bad state.
        }

        return WifiDetails(
            ssid = ssid,
            bssid = bssid,
            rssiDbm = rssi,
            linkSpeedMbps = linkSpeed,
            frequencyMhz = frequency
        )
    }

    private fun cleanSsid(value: String?): String? {
        if (value == null) return null
        val cleaned = value.trim().removeSurrounding("\"").trim()
        if (cleaned.isEmpty()) return null
        if (cleaned.equals("<unknown ssid>", ignoreCase = true)) return null
        return cleaned
    }

    private fun cleanBssid(value: String?): String? {
        val cleaned = value?.trim()?.lowercase(Locale.US) ?: return null
        if (cleaned.isEmpty()) return null
        if (cleaned == "02:00:00:00:00:00" || cleaned == "00:00:00:00:00:00") return null
        return cleaned
    }

    private fun readOperatorName(context: Context): String? {
        return try {
            val telephony = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            val networkName = telephony?.networkOperatorName?.trim().orEmpty()
            if (networkName.isNotEmpty()) {
                networkName
            } else {
                telephony?.simOperatorName?.trim()?.takeIf { it.isNotEmpty() }
            }
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    // -----------------------------------------------------------------------
    // Local address / gateway discovery
    // -----------------------------------------------------------------------

    private data class LocalAddresses(val ipv4: String?, val ipv6: String?)

    private fun localAddresses(): LocalAddresses {
        var bestIpv4: Pair<Int, String>? = null
        var bestIpv6: Pair<Int, String>? = null

        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return LocalAddresses(null, null)
            for (networkInterface in Collections.list(interfaces)) {
                val usable = try {
                    networkInterface.isUp &&
                        !networkInterface.isLoopback &&
                        !networkInterface.isPointToPoint
                } catch (_: Exception) {
                    false
                }
                if (!usable) continue

                val addresses = try {
                    Collections.list(networkInterface.inetAddresses)
                } catch (_: Exception) {
                    continue
                }

                for (address in addresses) {
                    if (address.isLoopbackAddress || address.isMulticastAddress) continue
                    val host = address.hostAddress?.substringBefore('%') ?: continue
                    if (host.isBlank()) continue

                    if (address is Inet4Address) {
                        if (address.isLinkLocalAddress) continue
                        val score = if (address.isSiteLocalAddress) 100 else 10
                        if (bestIpv4 == null || score > bestIpv4.first) {
                            bestIpv4 = score to host
                        }
                    } else if (address is Inet6Address) {
                        if (address.isLinkLocalAddress) continue
                        val score = when {
                            address.isSiteLocalAddress -> 50
                            host.startsWith("fc", ignoreCase = true) ||
                                host.startsWith("fd", ignoreCase = true) -> 40
                            else -> 100
                        }
                        if (bestIpv6 == null || score > bestIpv6.first) {
                            bestIpv6 = score to host
                        }
                    }
                }
            }
        } catch (_: Exception) {
            // Fall through with whatever was collected.
        }

        return LocalAddresses(bestIpv4?.second, bestIpv6?.second)
    }

    private fun readGatewayFromProc(): String? {
        return try {
            val file = File("/proc/net/route")
            if (!file.canRead()) return null
            file.useLines { lines ->
                for (line in lines.drop(1)) {
                    val parts = line.trim().split(WHITESPACE)
                    if (parts.size < 4) continue
                    if (parts[1] != "00000000") continue
                    val gatewayHex = parts[2]
                    if (gatewayHex == "00000000") continue
                    val flags = parts[3].toIntOrNull(16) ?: 0
                    if (flags and 0x1 == 0) continue
                    // /proc/net/route stores the address in little-endian
                    // order, so reverse the hex byte pairs before formatting.
                    val bytePairs = gatewayHex.chunked(2).reversed()
                    if (bytePairs.size != 4) continue
                    val octets = bytePairs.mapNotNull { it.toIntOrNull(16) }
                    if (octets.size != 4) continue
                    val ip = octets.joinToString(".")
                    if (ip != "0.0.0.0") return@useLines ip
                }
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun defaultGateway(linkProperties: LinkProperties?): String? {
        return try {
            linkProperties?.routes
                ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
                ?.gateway
                ?.hostAddress
        } catch (_: Exception) {
            null
        }
    }

    // -----------------------------------------------------------------------
    // Public IP / geolocation
    // -----------------------------------------------------------------------

    suspend fun publicIp(): PublicIpInfo = withContext(Dispatchers.IO) {
        try {
            val errors = ArrayList<String>(2)
            for ((endpoint, provider) in PUBLIC_ENDPOINTS) {
                val fetched = fetchJson(endpoint)
                val json = fetched.json
                if (json == null) {
                    errors.add(fetched.error ?: "Request failed")
                    continue
                }
                val parsed = parseProvider(json, provider, requestedIp = null)
                if (parsed.error == null && !parsed.ip.isNullOrBlank()) {
                    return@withContext parsed
                }
                errors.add(parsed.error ?: "No IP address in response")
            }
            PublicIpInfo(error = errors.firstOrNull() ?: "Unable to determine public IP address")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PublicIpInfo(
                error = e.message?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: "Unable to determine public IP address"
            )
        }
    }

    suspend fun geoLookup(ip: String): PublicIpInfo = withContext(Dispatchers.IO) {
        try {
            val cleaned = cleanIp(ip)
            if (cleaned.isEmpty()) {
                return@withContext PublicIpInfo(error = "Enter an IP address")
            }
            if (!cleaned.contains(':') && !isValidIpv4(cleaned)) {
                return@withContext PublicIpInfo(error = "Invalid IP address")
            }
            if (!isIpLiteral(cleaned)) {
                return@withContext PublicIpInfo(error = "Invalid IP address")
            }
            if (isPrivateOrLocalIp(cleaned)) {
                return@withContext PublicIpInfo(
                    ip = cleaned,
                    error = "Private address — no public geolocation"
                )
            }

            val endpoints = listOf(
                "https://ipwho.is/$cleaned" to GeoProvider.IPWHO,
                "https://ipapi.co/$cleaned/json/" to GeoProvider.IPAPI
            )
            val errors = ArrayList<String>(2)
            for ((endpoint, provider) in endpoints) {
                val fetched = fetchJson(endpoint)
                val json = fetched.json
                if (json == null) {
                    errors.add(fetched.error ?: "Request failed")
                    continue
                }
                val parsed = parseProvider(json, provider, requestedIp = cleaned)
                if (parsed.error == null && !parsed.ip.isNullOrBlank()) {
                    return@withContext parsed
                }
                errors.add(parsed.error ?: "No data in response")
            }
            PublicIpInfo(
                ip = cleaned,
                error = errors.firstOrNull() ?: "Unable to geolocate this address"
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PublicIpInfo(
                ip = cleanIp(ip).takeIf { it.isNotBlank() },
                error = e.message?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: "Unable to geolocate this address"
            )
        }
    }

    private data class FetchOutcome(val json: JSONObject?, val error: String?)

    private fun fetchJson(url: String): FetchOutcome {
        return try {
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", USER_AGENT)
                .header("Accept", "application/json")
                .get()
                .build()
            client.newCall(request).execute().use { response ->
                val host = request.url.host
                if (!response.isSuccessful) {
                    FetchOutcome(null, "HTTP ${response.code} from $host")
                } else {
                    val body = response.body?.string()
                    if (body.isNullOrBlank()) {
                        FetchOutcome(null, "Empty response from $host")
                    } else {
                        FetchOutcome(JSONObject(body), null)
                    }
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            FetchOutcome(
                null,
                e.message?.trim().takeUnless { it.isNullOrEmpty() } ?: "Network error"
            )
        }
    }

    private fun parseProvider(
        json: JSONObject,
        provider: GeoProvider,
        requestedIp: String?
    ): PublicIpInfo = when (provider) {
        GeoProvider.IPWHO -> parseIpWho(json, requestedIp)
        GeoProvider.IPAPI -> parseIpApi(json, requestedIp)
    }

    private fun parseIpWho(json: JSONObject, requestedIp: String?): PublicIpInfo {
        if (!json.optBoolean("success", true)) {
            return PublicIpInfo(
                ip = requestedIp,
                error = json.stringOrNull("message") ?: "Lookup failed"
            )
        }
        val connection = json.optJSONObject("connection")
        val timezone = json.optJSONObject("timezone")
        return PublicIpInfo(
            ip = json.stringOrNull("ip") ?: requestedIp,
            isp = connection?.stringOrNull("isp"),
            org = connection?.stringOrNull("org"),
            asn = asnFrom(connection),
            city = json.stringOrNull("city"),
            region = json.stringOrNull("region"),
            country = json.stringOrNull("country"),
            countryCode = json.stringOrNull("country_code")?.uppercase(Locale.US),
            lat = json.nullableDouble("latitude"),
            lon = json.nullableDouble("longitude"),
            timezone = timezone?.stringOrNull("id")
        )
    }

    private fun parseIpApi(json: JSONObject, requestedIp: String?): PublicIpInfo {
        // ipapi.co has no `success` flag; only `error` is meaningful.
        if (json.optBoolean("error", false)) {
            return PublicIpInfo(
                ip = requestedIp,
                error = json.stringOrNull("reason") ?: "Lookup failed"
            )
        }
        val org = json.stringOrNull("org")
        return PublicIpInfo(
            ip = json.stringOrNull("ip") ?: requestedIp,
            isp = ispFromOrg(org),
            org = org,
            asn = json.stringOrNull("asn"),
            city = json.stringOrNull("city"),
            region = json.stringOrNull("region"),
            country = json.stringOrNull("country_name"),
            countryCode = json.stringOrNull("country_code")?.uppercase(Locale.US),
            lat = json.nullableDouble("latitude"),
            lon = json.nullableDouble("longitude"),
            timezone = json.stringOrNull("timezone")
        )
    }

    private fun asnFrom(connection: JSONObject?): String? {
        if (connection == null) return null
        return when (val raw = connection.opt("asn")) {
            is Number -> raw.toInt().takeIf { it > 0 }?.let { "AS$it" }
            is String -> {
                val text = raw.trim()
                when {
                    text.isEmpty() -> null
                    text.startsWith("AS", ignoreCase = true) -> text.uppercase(Locale.US)
                    else -> "AS$text"
                }
            }
            else -> null
        }
    }

    private fun ispFromOrg(org: String?): String? {
        if (org == null) return null
        val withoutAsn = org.replace(Regex("^AS\\d+\\s+"), "").trim()
        return withoutAsn.ifEmpty { org }
    }

    // -----------------------------------------------------------------------
    // Small helpers
    // -----------------------------------------------------------------------

    private fun isPrivateOrLocalIp(value: String): Boolean {
        if (isPrivateIp(value)) return true
        if (!value.contains(':')) return false
        val lower = value.lowercase(Locale.US)
        return lower == "::" ||
            lower == "::1" ||
            lower.startsWith("fe80:") ||
            lower.startsWith("fec0:") ||
            lower.startsWith("fc") ||
            lower.startsWith("fd")
    }

    private fun isIpLiteral(value: String): Boolean {
        if (isValidIpv4(value)) return true
        if (!value.contains(':') || !IPV6_CHARS.matches(value)) return false
        return try {
            InetAddress.getByName(value)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun cleanIp(value: String): String {
        var cleaned = value.trim()
        if (cleaned.startsWith("[") && cleaned.endsWith("]")) {
            cleaned = cleaned.substring(1, cleaned.length - 1)
        }
        val zone = cleaned.indexOf('%')
        if (zone > 0) cleaned = cleaned.substring(0, zone)
        return cleaned
    }

    private fun JSONObject.stringOrNull(name: String): String? {
        val value = optString(name).trim()
        return value.ifEmpty { null }
    }

    private fun JSONObject.nullableDouble(name: String): Double? {
        if (!has(name) || isNull(name)) return null
        val value = optDouble(name, Double.NaN)
        return value.takeIf { !it.isNaN() && !it.isInfinite() }
    }

    private inline fun <T> safeValue(block: () -> T): T? {
        return try {
            block()
        } catch (_: Exception) {
            null
        }
    }

    private val WHITESPACE = Regex("\\s+")
}
