package com.pinchiu.pingtools.ui.screens

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bluetooth
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Router
import androidx.compose.material.icons.outlined.SignalCellularAlt
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.model.ConnectionInfo
import com.pinchiu.pingtools.core.model.PublicIpInfo
import com.pinchiu.pingtools.core.net.IpInfoEngine
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.CopyableRow
import com.pinchiu.pingtools.ui.components.DataRow
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.Pill
import com.pinchiu.pingtools.ui.components.PillTone
import com.pinchiu.pingtools.ui.components.SecondaryButton
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.ToolScaffold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ConnectionUiState(
    val connection: ConnectionInfo? = null,
    val publicInfo: PublicIpInfo? = null,
    val loading: Boolean = true,
    val publicLoading: Boolean = false,
    val error: String? = null,
    val publicError: String? = null
)

class ConnectionInfoViewModel(app: Application) : AndroidViewModel(app) {
    var ui by mutableStateOf(ConnectionUiState())
        private set

    private var job: Job? = null

    fun load() {
        job?.cancel()
        ui = ui.copy(loading = true, publicLoading = true, error = null, publicError = null)
        job = viewModelScope.launch {
            try {
                val connection = withContext(Dispatchers.IO) {
                    IpInfoEngine.connectionInfo(getApplication())
                }
                ui = ui.copy(connection = connection, loading = false)

                if (connection.connectionType == "Offline") {
                    ui = ui.copy(
                        publicInfo = null,
                        publicLoading = false,
                        publicError = "Offline"
                    )
                    return@launch
                }

                val publicInfo = try {
                    IpInfoEngine.publicIp()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    PublicIpInfo(
                        error = e.message?.trim().takeUnless { it.isNullOrEmpty() }
                            ?: "Public IP lookup failed"
                    )
                }
                ui = ui.copy(
                    publicInfo = publicInfo,
                    publicLoading = false,
                    publicError = publicInfo.error
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                ui = ui.copy(
                    loading = false,
                    publicLoading = false,
                    error = e.message?.trim().takeUnless { it.isNullOrEmpty() }
                        ?: "Unable to read connection information"
                )
            }
        }
    }

    fun stop() {
        job?.cancel()
    }

    override fun onCleared() {
        stop()
        super.onCleared()
    }
}

@Composable
fun ConnectionInfoScreen(onBack: () -> Unit) {
    val vm: ConnectionInfoViewModel = viewModel()
    val ui = vm.ui
    val accent = Tools.byRoute(Routes.CONNECTION)?.accent ?: MaterialTheme.colorScheme.primary
    val context = LocalContext.current
    val wifiPermissions = remember {
        buildList {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.NEARBY_WIFI_DEVICES)
            }
        }.toTypedArray()
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) {
        // Reload whether granted or denied: the Wi-Fi card then shows either
        // the details or a clear "Unavailable" fallback.
        vm.load()
    }

    val fineLocationGranted = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
    val nearbyWifiGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.NEARBY_WIFI_DEVICES
        ) == PackageManager.PERMISSION_GRANTED
    val wifiDetailsAllowed = fineLocationGranted && nearbyWifiGranted

    val requestLocation: () -> Unit = {
        try {
            permissionLauncher.launch(wifiPermissions)
        } catch (_: Exception) {
            // The activity may not be in a state where a permission request
            // can be launched; the card simply keeps its fallback text.
        }
    }

    BackHandler {
        vm.stop()
        onBack()
    }
    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }
    LaunchedEffect(Unit) { vm.load() }

    ToolScaffold(
        title = "Connection Info",
        subtitle = "Local network, public IP and Wi-Fi",
        onBack = onBack,
        actions = {
            IconButton(onClick = vm::load, enabled = !ui.loading) {
                if (ui.loading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp
                    )
                } else {
                    Icon(
                        Icons.Outlined.Refresh,
                        contentDescription = "Refresh connection info"
                    )
                }
            }
        }
    ) {
        ui.error?.let { ErrorBanner(it) }

        val connection = ui.connection
        when {
            connection == null && ui.loading -> SectionCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = accent
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "Reading network interfaces…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            connection == null -> EmptyState(
                icon = Icons.Outlined.WifiOff,
                title = "No connection data",
                body = "Network details could not be read. Use refresh to try again."
            )
            else -> {
                ConnectionCard(connection = connection, accent = accent)
                PublicIpCard(ui = ui)
                WifiCard(
                    connection = connection,
                    accent = accent,
                    permissionGranted = wifiDetailsAllowed,
                    onRequestLocation = requestLocation
                )
            }
        }
    }
}

@Composable
private fun ConnectionCard(connection: ConnectionInfo, accent: Color) {
    SectionCard(title = "Connection") {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(44.dp)
                    .background(accent.copy(alpha = 0.14f), RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    connectionIcon(connection.connectionType),
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(22.dp)
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(connection.connectionType, style = MaterialTheme.typography.titleLarge)
                Text(
                    if (connection.isVpn) "VPN active" else "Active network",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (connection.isVpn) {
                Pill("VPN", PillTone.Info)
            }
        }

        CopyOrDash("Local IPv4", connection.localIpv4)
        CopyOrDash("Local IPv6", connection.localIpv6)
        CopyOrDash("Gateway", connection.gateway)

        if (connection.dnsServers.isEmpty()) {
            DataRow("DNS", "—")
        } else {
            connection.dnsServers.forEachIndexed { index, server ->
                CopyableRow(
                    label = if (connection.dnsServers.size == 1) "DNS" else "DNS ${index + 1}",
                    value = server
                )
            }
        }

        connection.mobileOperator?.takeIf { it.isNotBlank() }?.let { operator ->
            DataRow("Mobile operator", operator, mono = false)
        }
    }
}

@Composable
private fun PublicIpCard(ui: ConnectionUiState) {
    SectionCard(title = "Public IP") {
        if (ui.publicLoading) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    strokeWidth = 2.dp
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    if (ui.publicInfo == null) "Looking up public IP…" else "Refreshing…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        val error = ui.publicError
        val info = ui.publicInfo
        val offline = ui.connection?.connectionType == "Offline"
        if (error != null) {
            if (offline) {
                Row(verticalAlignment = Alignment.Top) {
                    Icon(
                        Icons.Outlined.WifiOff,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Column {
                        Text("Offline", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Public IP is unavailable without an internet connection.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                ErrorBanner(error)
                Text(
                    "The lookup service could not be reached. Check your connection and refresh.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else if (info != null) {
            CopyOrDash("Public IP", info.ip)
            DataRow("ISP", info.isp ?: "—")
            DataRow("ASN", info.asn ?: "—")
            DataRow("City", info.city ?: "—")
            DataRow("Region", info.region ?: "—")
            val country = listOfNotNull(
                info.country?.takeIf { it.isNotBlank() },
                info.countryCode?.takeIf { it.isNotBlank() }
            ).joinToString(" · ")
            DataRow("Country", country.ifBlank { "—" })
            DataRow("Timezone", info.timezone ?: "—")
        } else if (!ui.publicLoading) {
            Text(
                "Public IP information is unavailable.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun WifiCard(
    connection: ConnectionInfo,
    accent: Color,
    permissionGranted: Boolean,
    onRequestLocation: () -> Unit
) {
    val wifi = connection.wifi
    val onWifi = connection.connectionType == "Wi-Fi" || wifi != null

    SectionCard(title = "Wi-Fi") {
        if (!onWifi) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Outlined.WifiOff,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text("Unavailable", style = MaterialTheme.typography.titleSmall)
            }
            Text(
                "Connect to a Wi-Fi network to see SSID, signal and link details.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            CopyOrUnavailable("SSID", wifi?.ssid)
            CopyOrUnavailable("BSSID", wifi?.bssid)
            DataRow("Signal", wifi?.rssiDbm?.let { "$it dBm" } ?: "Unavailable")
            DataRow("Link speed", wifi?.linkSpeedMbps?.let { "$it Mbps" } ?: "Unavailable")
            DataRow("Frequency", wifi?.frequencyMhz?.let { "$it MHz" } ?: "Unavailable")

            if (wifi?.ssid == null) {
                Row(verticalAlignment = Alignment.Top) {
                    Icon(
                        Icons.Outlined.LocationOn,
                        contentDescription = null,
                        tint = accent,
                        modifier = Modifier.size(17.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (permissionGranted) {
                            "This Android version is restricting the network name."
                        } else {
                            "Android hides the network name unless you allow Wi-Fi and location access."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (!permissionGranted) {
                    SecondaryButton(
                        text = "Allow Wi-Fi access",
                        onClick = onRequestLocation,
                        modifier = Modifier.fillMaxWidth(),
                        icon = Icons.Outlined.LocationOn
                    )
                }
            }
        }
    }
}

@Composable
private fun CopyOrDash(label: String, value: String?) {
    if (value.isNullOrBlank()) {
        DataRow(label, "—")
    } else {
        CopyableRow(label, value)
    }
}

@Composable
private fun CopyOrUnavailable(label: String, value: String?) {
    if (value.isNullOrBlank()) {
        DataRow(label, "Unavailable")
    } else {
        CopyableRow(label, value)
    }
}

private fun connectionIcon(type: String): ImageVector = when (type) {
    "Wi-Fi" -> Icons.Outlined.Wifi
    "Cellular" -> Icons.Outlined.SignalCellularAlt
    "Ethernet" -> Icons.Outlined.Lan
    "VPN" -> Icons.Outlined.VpnKey
    "Bluetooth" -> Icons.Outlined.Bluetooth
    "Offline" -> Icons.Outlined.WifiOff
    else -> Icons.Outlined.Router
}
