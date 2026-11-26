package com.pinchiu.pingtools.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.AltRoute
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Http
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material.icons.outlined.NetworkCheck
import androidx.compose.material.icons.outlined.PowerSettingsNew
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Router
import androidx.compose.material.icons.outlined.Scanner
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.pinchiu.pingtools.ui.theme.AccentAmber
import com.pinchiu.pingtools.ui.theme.AccentBlue
import com.pinchiu.pingtools.ui.theme.AccentCyan
import com.pinchiu.pingtools.ui.theme.AccentGreen
import com.pinchiu.pingtools.ui.theme.AccentRose
import com.pinchiu.pingtools.ui.theme.AccentTeal
import com.pinchiu.pingtools.ui.theme.AccentViolet

object Routes {
    const val HOME = "home"
    const val PING = "ping"
    const val GEO_PING = "geo"
    const val TRACE = "trace"
    const val PORTS = "ports"
    const val DNS = "dns"
    const val WHOIS = "whois"
    const val SUBNET = "subnet"
    const val WOL = "wol"
    const val CONNECTION = "connection"
    const val HTTP = "http"
    const val ABOUT = "about"
}

data class ToolInfo(
    val route: String,
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val accent: Color,
    val tag: String? = null
)

object Tools {
    val all: List<ToolInfo> = listOf(
        ToolInfo(
            route = Routes.PING,
            title = "Ping",
            subtitle = "ICMP latency, loss & jitter",
            icon = Icons.Outlined.NetworkCheck,
            accent = AccentCyan,
            tag = "ICMP"
        ),
        ToolInfo(
            route = Routes.GEO_PING,
            title = "Geo Ping",
            subtitle = "Target location & latency",
            icon = Icons.Outlined.Public,
            accent = AccentBlue,
            tag = "MAP"
        ),
        ToolInfo(
            route = Routes.TRACE,
            title = "Traceroute",
            subtitle = "Hop-by-hop network path",
            icon = Icons.AutoMirrored.Outlined.AltRoute,
            accent = AccentViolet
        ),
        ToolInfo(
            route = Routes.PORTS,
            title = "Port Scanner",
            subtitle = "TCP ports & service banners",
            icon = Icons.Outlined.Scanner,
            accent = AccentAmber
        ),
        ToolInfo(
            route = Routes.DNS,
            title = "DNS Lookup",
            subtitle = "A, AAAA, MX, TXT & more",
            icon = Icons.Outlined.Dns,
            accent = AccentTeal
        ),
        ToolInfo(
            route = Routes.WHOIS,
            title = "WHOIS",
            subtitle = "Domain & IP registration",
            icon = Icons.Outlined.Search,
            accent = AccentGreen
        ),
        ToolInfo(
            route = Routes.SUBNET,
            title = "Subnet Scanner",
            subtitle = "Discover hosts on a subnet",
            icon = Icons.Outlined.Router,
            accent = AccentCyan,
            tag = "LAN"
        ),
        ToolInfo(
            route = Routes.WOL,
            title = "Wake-on-LAN",
            subtitle = "Wake devices by MAC address",
            icon = Icons.Outlined.PowerSettingsNew,
            accent = AccentRose
        ),
        ToolInfo(
            route = Routes.CONNECTION,
            title = "Connection Info",
            subtitle = "Local & public network details",
            icon = Icons.Outlined.Wifi,
            accent = AccentBlue
        ),
        ToolInfo(
            route = Routes.HTTP,
            title = "HTTP Inspector",
            subtitle = "Status, headers & TLS details",
            icon = Icons.Outlined.Http,
            accent = AccentAmber
        )
    )

    fun byRoute(route: String): ToolInfo? = all.firstOrNull { it.route == route }

    val featured: List<ToolInfo> = all.take(6)
    val utilities: List<ToolInfo> = all.drop(6)
}
