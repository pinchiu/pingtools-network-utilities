package com.pinchiu.pingtools.ui.screens

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.PingConfig
import com.pinchiu.pingtools.core.model.PingEvent
import com.pinchiu.pingtools.core.model.PingMode
import com.pinchiu.pingtools.core.model.PingSummary
import com.pinchiu.pingtools.core.model.PublicIpInfo
import com.pinchiu.pingtools.core.net.IpInfoEngine
import com.pinchiu.pingtools.core.net.PingEngine
import com.pinchiu.pingtools.core.util.fmtLatency
import com.pinchiu.pingtools.core.util.fmtPercent
import com.pinchiu.pingtools.core.util.normalizeHost
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.CopyableRow
import com.pinchiu.pingtools.ui.components.DataRow
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.LabeledField
import com.pinchiu.pingtools.ui.components.Pill
import com.pinchiu.pingtools.ui.components.PillTone
import com.pinchiu.pingtools.ui.components.PrimaryButton
import com.pinchiu.pingtools.ui.components.SecondaryButton
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.StatTile
import com.pinchiu.pingtools.ui.components.ToolScaffold
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

private const val GEO_PING_COUNT = 4

data class GeoUiState(
    val host: String = "8.8.8.8",
    val busy: Boolean = false,
    val resolvedIp: String? = null,
    val mode: PingMode? = null,
    val note: String? = null,
    val summary: PingSummary? = null,
    val sentSoFar: Int = 0,
    val receivedSoFar: Int = 0,
    val geo: PublicIpInfo? = null,
    val geoLoading: Boolean = false,
    val error: String? = null,
    val history: List<String> = emptyList()
)

class GeoPingViewModel(app: Application) : AndroidViewModel(app) {
    var ui by mutableStateOf(GeoUiState(history = HistoryStore.recent(app, "geo", 5)))
        private set

    private var pingJob: Job? = null
    private var geoJob: Job? = null

    fun updateHost(value: String) {
        ui = ui.copy(host = value, error = null)
    }

    fun start(input: String) {
        val normalized = normalizeHost(input)
        if (normalized.isBlank()) {
            ui = ui.copy(error = "Enter a host name or IP address")
            return
        }

        pingJob?.cancel()
        geoJob?.cancel()
        HistoryStore.add(getApplication(), "geo", normalized)
        ui = GeoUiState(
            host = normalized,
            busy = true,
            history = HistoryStore.recent(getApplication(), "geo", 5)
        )

        pingJob = viewModelScope.launch {
            try {
                PingEngine.ping(
                    PingConfig(
                        host = normalized,
                        count = GEO_PING_COUNT,
                        intervalMs = 700L,
                        timeoutMs = 1_500
                    )
                ).collect { event ->
                    when (event) {
                        is PingEvent.Started -> {
                            ui = ui.copy(resolvedIp = event.resolvedIp, mode = event.mode)
                            event.resolvedIp?.let(::startGeoLookup)
                        }
                        is PingEvent.Reply -> ui = ui.copy(
                            sentSoFar = ui.sentSoFar + 1,
                            receivedSoFar = ui.receivedSoFar + 1
                        )
                        is PingEvent.Timeout -> ui = ui.copy(sentSoFar = ui.sentSoFar + 1)
                        is PingEvent.Note -> ui = ui.copy(note = event.message)
                        is PingEvent.Finished -> ui = ui.copy(
                            summary = event.summary,
                            busy = false,
                            sentSoFar = event.summary.sent,
                            receivedSoFar = event.summary.received
                        )
                        is PingEvent.Failed -> ui = ui.copy(busy = false, error = event.message)
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                ui = ui.copy(busy = false, error = e.message ?: "Ping failed")
            }
        }
    }

    private fun startGeoLookup(ip: String) {
        geoJob?.cancel()
        ui = ui.copy(geoLoading = true, geo = null)
        geoJob = viewModelScope.launch {
            val info = try {
                IpInfoEngine.geoLookup(ip)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PublicIpInfo(
                    ip = ip,
                    error = e.message?.trim().takeUnless { it.isNullOrEmpty() } ?: "Lookup failed"
                )
            }
            ui = ui.copy(geo = info, geoLoading = false)
        }
    }

    fun stop() {
        pingJob?.cancel()
        geoJob?.cancel()
    }

    override fun onCleared() {
        stop()
        super.onCleared()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GeoPingScreen(onBack: () -> Unit) {
    val vm: GeoPingViewModel = viewModel()
    val ui = vm.ui
    val context = LocalContext.current
    val accent = Tools.byRoute(Routes.GEO_PING)?.accent ?: MaterialTheme.colorScheme.primary
    var mapError by remember { mutableStateOf<String?>(null) }

    BackHandler {
        vm.stop()
        onBack()
    }
    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }

    ToolScaffold(
        title = "Geo Ping",
        subtitle = "Locate a target and measure latency",
        onBack = onBack
    ) {
        SectionCard(title = "Target") {
            LabeledField(
                label = "Host or IP address",
                value = ui.host,
                onValueChange = vm::updateHost,
                placeholder = "8.8.8.8",
                enabled = !ui.busy,
                keyboardType = KeyboardType.Uri
            )
            if (ui.history.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ui.history.forEach { recent ->
                        AssistChip(
                            onClick = { vm.updateHost(recent) },
                            label = { Text(recent) }
                        )
                    }
                }
            }
            PrimaryButton(
                text = "Locate & ping",
                onClick = {
                    mapError = null
                    vm.start(ui.host)
                },
                modifier = Modifier.fillMaxWidth(),
                loading = ui.busy,
                icon = Icons.Outlined.Public
            )
            if (ui.busy) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = accent
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        progressText(ui),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        ui.error?.let { ErrorBanner(it) }

        LocationCard(
            ui = ui,
            accent = accent,
            onOpenMaps = { lat, lon, label ->
                if (!openMap(context, lat, lon, label)) {
                    mapError = "No map app is available on this device."
                }
            }
        )

        mapError?.let { ErrorBanner(it) }

        LatencyCard(ui = ui, accent = accent)
    }
}

private fun progressText(ui: GeoUiState): String = when {
    ui.sentSoFar > 0 -> "${ui.sentSoFar} of $GEO_PING_COUNT packets sent"
    ui.resolvedIp != null -> "Pinging ${ui.resolvedIp}…"
    else -> "Resolving host…"
}

@Composable
private fun LocationCard(
    ui: GeoUiState,
    accent: Color,
    onOpenMaps: (Double, Double, String?) -> Unit
) {
    SectionCard(title = "Location") {
        when {
            ui.geo != null -> GeoDetails(
                geo = ui.geo,
                resolvedIp = ui.resolvedIp,
                accent = accent,
                onOpenMaps = onOpenMaps
            )
            ui.geoLoading -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = accent
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    "Looking up location…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            else -> Text(
                "Geolocation appears after the host name resolves to a public address.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun GeoDetails(
    geo: PublicIpInfo,
    resolvedIp: String?,
    accent: Color,
    onOpenMaps: (Double, Double, String?) -> Unit
) {
    val error = geo.error
    if (error != null) {
        if (error.contains("private", ignoreCase = true)) {
            Row(verticalAlignment = Alignment.Top) {
                Icon(
                    Icons.Outlined.Lock,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.tertiary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Column {
                    Text("Private address", style = MaterialTheme.typography.titleSmall)
                    Spacer(Modifier.height(2.dp))
                    Text(
                        "This host is on a local network, so public geolocation does not apply. Latency results are still valid.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            CopyableRow("IP address", geo.ip ?: resolvedIp ?: "—")
        } else {
            ErrorBanner(error)
            Text(
                "The public IP lookup needs an internet connection. Latency results are still shown below.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        return
    }

    val flag = flagEmoji(geo.countryCode)
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (flag != null) {
            Text(flag, fontSize = 32.sp)
        } else {
            Icon(
                Icons.Outlined.Public,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(32.dp)
            )
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(
                geo.city ?: geo.region ?: geo.country ?: "—",
                style = MaterialTheme.typography.titleLarge
            )
            val regionCountry = listOfNotNull(
                geo.region?.takeIf { it.isNotBlank() },
                geo.country?.takeIf { it.isNotBlank() }
            ).joinToString(", ")
            Text(
                regionCountry.ifBlank { "—" },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }

    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

    CopyableRow("IP address", geo.ip ?: resolvedIp ?: "—")
    DataRow("Region", geo.region ?: "—")
    DataRow("Country", geo.country ?: geo.countryCode ?: "—")
    DataRow("ISP", geo.isp ?: "—")
    DataRow("ASN", geo.asn ?: "—")
    DataRow("Organization", geo.org ?: "—")

    val lat = geo.lat
    val lon = geo.lon
    val coordinates = if (lat != null && lon != null) {
        String.format(Locale.US, "%.4f, %.4f", lat, lon)
    } else {
        "—"
    }
    DataRow("Coordinates", coordinates)
    DataRow("Timezone", geo.timezone ?: "—")

    SecondaryButton(
        text = "Open in Maps",
        onClick = {
            if (lat != null && lon != null) {
                onOpenMaps(lat, lon, geo.city ?: geo.country ?: geo.ip)
            }
        },
        modifier = Modifier.fillMaxWidth(),
        enabled = lat != null && lon != null,
        icon = Icons.Outlined.Place
    )
}

@Composable
private fun LatencyCard(ui: GeoUiState, accent: Color) {
    SectionCard(title = "Latency") {
        val mode = ui.mode
        if (mode != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Pill(
                    text = if (mode == PingMode.ICMP) "ICMP" else "TCP",
                    tone = PillTone.Info
                )
                ui.resolvedIp?.let { ip ->
                    Spacer(Modifier.width(8.dp))
                    Text(
                        ip,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        ui.note?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        val summary = ui.summary
        if (summary == null) {
            if (ui.busy) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = accent
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Waiting for replies…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                Text(
                    "Run a lookup to measure round-trip time.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            LatencyStats(summary, accent)
        }
    }
}

@Composable
private fun LatencyStats(summary: PingSummary, accent: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        StatTile("Sent", summary.sent.toString(), Modifier.weight(1f))
        StatTile("Received", summary.received.toString(), Modifier.weight(1f))
        StatTile(
            "Loss",
            fmtPercent(summary.lossPercent),
            Modifier.weight(1f),
            accent = if (summary.lossPercent > 0.0) MaterialTheme.colorScheme.error else null
        )
    }
    if (summary.received == 0) {
        Text(
            "No replies. The host may block ICMP/TCP probes or be offline.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatTile("Average", fmtLatency(summary.avgMs), Modifier.weight(1f), accent = accent)
            StatTile("Minimum", fmtLatency(summary.minMs), Modifier.weight(1f))
            StatTile("Maximum", fmtLatency(summary.maxMs), Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatTile("Jitter", fmtLatency(summary.jitterMs), Modifier.weight(1f))
            StatTile("Std dev", fmtLatency(summary.stdDevMs), Modifier.weight(1f))
        }
    }
}

private fun flagEmoji(code: String?): String? {
    val countryCode = code?.trim()?.uppercase(Locale.US) ?: return null
    if (countryCode.length != 2 || countryCode.any { it !in 'A'..'Z' }) return null
    return buildString {
        for (letter in countryCode) {
            append(String(Character.toChars(0x1F1E6 + (letter - 'A'))))
        }
    }
}

private fun openMap(context: Context, lat: Double, lon: Double, label: String?): Boolean {
    val coordinates = String.format(Locale.US, "%.5f,%.5f", lat, lon)
    val query = if (label.isNullOrBlank()) {
        coordinates
    } else {
        "$coordinates(${Uri.encode(label)})"
    }
    return try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("geo:$coordinates?q=$query")))
        true
    } catch (_: Exception) {
        try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/maps?q=$coordinates"))
            )
            true
        } catch (_: Exception) {
            false
        }
    }
}
