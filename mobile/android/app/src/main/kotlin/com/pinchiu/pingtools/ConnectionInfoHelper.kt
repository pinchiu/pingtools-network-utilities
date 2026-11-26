package com.pinchiu.pingtools

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.telephony.TelephonyManager
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.NetworkInterface

/**
 * Collects connection details for the Flutter method channel. Every framework
 * call is individually guarded: missing permissions simply produce nulls.
 */
object ConnectionInfoHelper {

    fun collect(context: Context): Map<String, Any?> {
        val app = context.applicationContext
        val manager = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val network = runCatching { manager?.activeNetwork }.getOrNull()
        val capabilities = network?.let { n -> runCatching { manager?.getNetworkCapabilities(n) }.getOrNull() }
        val linkProperties = network?.let { n -> runCatching { manager?.getLinkProperties(n) }.getOrNull() }

        val onWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val onCellular = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
        val isVpn = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true

        val addresses = localAddresses()
        val gateway = defaultIpv4Gateway(linkProperties)
        val dns = linkProperties?.dnsServers
            ?.mapNotNull { it.hostAddress?.substringBefore('%')?.takeIf { host -> host.isNotBlank() } }
            ?.distinct()
            .orEmpty()

        val wifi = if (onWifi) readWifi(app, capabilities) else null
        val operator = if (onCellular) readOperator(app) else null

        return mapOf(
            "connectionType" to when {
                capabilities == null -> "Offline"
                isVpn -> "VPN"
                onWifi -> "Wi-Fi"
                onCellular -> "Cellular"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "Bluetooth"
                else -> "Other"
            },
            "localIpv4" to addresses.ipv4,
            "localIpv6" to addresses.ipv6,
            "prefixLength" to addresses.prefixLength,
            "gateway" to gateway,
            "dnsServers" to dns,
            "isVpn" to isVpn,
            "mobileOperator" to operator,
            "wifi" to wifi
        )
    }

    fun appVersion(context: Context): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "2.0.0"
    } catch (_: Exception) {
        "2.0.0"
    }

    private data class LocalAddresses(
        val ipv4: String?,
        val ipv6: String?,
        val prefixLength: Int?
    )

    private fun localAddresses(): LocalAddresses {
        var ipv4: String? = null
        var ipv6: String? = null
        var prefix: Int? = null
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return LocalAddresses(null, null, null)
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                if (!iface.isUp || iface.isLoopback) continue
                for (address in iface.interfaceAddresses) {
                    val host = address.address?.hostAddress?.substringBefore('%') ?: continue
                    when (val addr = address.address) {
                        is Inet4Address -> {
                            if (addr.isSiteLocalAddress) {
                                ipv4 = host
                                prefix = address.networkPrefixLength.toInt()
                            } else if (ipv4 == null) {
                                ipv4 = host
                                prefix = address.networkPrefixLength.toInt()
                            }
                        }
                        is Inet6Address -> {
                            if (!addr.isLinkLocalAddress && !addr.isLoopbackAddress) ipv6 = host
                        }
                    }
                }
            }
        } catch (_: Exception) {
            // Best effort.
        }
        return LocalAddresses(ipv4, ipv6, prefix)
    }

    private fun defaultIpv4Gateway(linkProperties: LinkProperties?): String? = try {
        linkProperties?.routes
            ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway
            ?.hostAddress
    } catch (_: Exception) {
        null
    }

    @Suppress("DEPRECATION")
    private fun readWifi(context: Context, capabilities: NetworkCapabilities?): Map<String, Any?>? {
        var ssid: String? = null
        var bssid: String? = null
        var rssi: Int? = null
        var linkSpeed: Int? = null
        var frequency: Int? = null

        val info: WifiInfo? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                capabilities?.transportInfo as? WifiInfo
            } else {
                (context.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.connectionInfo
            }
        } catch (_: Exception) {
            null
        }

        if (info != null) {
            try {
                val rawSsid = info.ssid
                    ?.removeSurrounding("\"")
                    ?.takeUnless { it == "<unknown ssid>" || it.isBlank() || it.startsWith("0x") }
                ssid = rawSsid
                bssid = info.bssid
                    ?.takeUnless { it == "02:00:00:00:00:00" || it.isBlank() }
                rssi = info.rssi.takeUnless { it == 0 || it <= -127 }
                linkSpeed = info.linkSpeed.takeIf { it > 0 }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    frequency = info.frequency.takeIf { it > 0 }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        rssi = info.rssi.takeUnless { it == 0 || it <= -127 }
                    }
                }
            } catch (_: Exception) {
                // Permission denied for SSID/BSSID/radio details.
            }
        }

        return mapOf(
            "ssid" to ssid,
            "bssid" to bssid,
            "rssiDbm" to rssi,
            "linkSpeedMbps" to linkSpeed,
            "frequencyMhz" to frequency
        )
    }

    private fun readOperator(context: Context): String? = try {
        val telephony = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        telephony?.networkOperatorName?.takeIf { it.isNotBlank() }
    } catch (_: Exception) {
        null
    }
}
