package com.pinchiu.pingtools.ui.screens

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Router
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.LanHost
import com.pinchiu.pingtools.core.model.SubnetConfig
import com.pinchiu.pingtools.core.model.SubnetInfo
import com.pinchiu.pingtools.core.model.SubnetScanEvent
import com.pinchiu.pingtools.core.net.SubnetScanner
import com.pinchiu.pingtools.core.util.fmtLatency
import com.pinchiu.pingtools.core.util.fmtPercent
import com.pinchiu.pingtools.core.util.formatDuration
import com.pinchiu.pingtools.core.util.ipv4ToLong
import com.pinchiu.pingtools.core.util.parseSubnetInput
import com.pinchiu.pingtools.core.util.serviceNameForPort
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.InlineAction
import com.pinchiu.pingtools.ui.components.KeyValueChip
import com.pinchiu.pingtools.ui.components.LabeledField
import com.pinchiu.pingtools.ui.components.MonoText
import com.pinchiu.pingtools.ui.components.Pill
import com.pinchiu.pingtools.ui.components.PillTone
import com.pinchiu.pingtools.ui.components.PrimaryButton
import com.pinchiu.pingtools.ui.components.ResultCountRow
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.ToolScaffold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

data class SubnetUiState(
    val cidr: String = "",
    val detecting: Boolean = true,
    val localInfo: SubnetInfo? = null,
    val includePorts: Boolean = true,
    val scanning: Boolean = false,
    val scanned: Int = 0,
    val total: Int = 0,
    val hosts: List<LanHost> = emptyList(),
    val durationMs: Long? = null,
    val finished: Boolean = false,
    val error: String? = null,
    val history: List<String> = emptyList()
)

class SubnetScannerViewModel(app: Application) : AndroidViewModel(app) {

    var ui by mutableStateOf(
        SubnetUiState(history = HistoryStore.recent(app, "subnet", 6))
    )
        private set

    private var scanJob: Job? = null
    private var detectJob: Job? = null

    init {
        detectLocalNetwork()
    }

    fun setCidr(value: String) {
        if (ui.scanning) return
        ui = ui.copy(cidr = value, error = null)
    }

    fun useHistory(value: String) {
        if (ui.scanning) return
        ui = ui.copy(cidr = value, error = null)
    }

    fun setIncludePorts(value: Boolean) {
        if (ui.scanning) return
        ui = ui.copy(includePorts = value)
    }

    fun detectLocalNetwork() {
        detectJob?.cancel()
        ui = ui.copy(detecting = true)
        detectJob = viewModelScope.launch {
            val info = try {
                SubnetScanner.detectLocalSubnet(getApplication())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            val current = ui
            if (current.scanning) {
                ui = current.copy(detecting = false)
                return@launch
            }
            ui = current.copy(
                detecting = false,
                localInfo = info,
                cidr = if (current.cidr.isBlank() && info != null) info.cidr else current.cidr
            )
        }
    }

    fun start() {
        if (ui.scanning) return
        val cidr = ui.cidr.trim()
        if (cidr.isEmpty()) {
            ui = ui.copy(error = "Enter a subnet (CIDR) or an IP range")
            return
        }
        val info = parseSubnetInput(cidr)
        if (info == null) {
            ui = ui.copy(
                error = "Use a CIDR like 192.168.1.0/24 or a range like 192.168.1.10-192.168.1.60"
            )
            return
        }
        if (info.totalHosts > MAX_HOSTS) {
            ui = ui.copy(error = "Subnet is too large — maximum $MAX_HOSTS hosts")
            return
        }
        val hostCount = SubnetScanner.hostsFor(info).size
        if (hostCount == 0) {
            ui = ui.copy(error = "No usable host addresses in this range")
            return
        }

        val app = getApplication<Application>()
        HistoryStore.add(app, "subnet", cidr)
        val includePorts = ui.includePorts
        ui = ui.copy(
            scanning = true,
            error = null,
            scanned = 0,
            total = hostCount,
            hosts = emptyList(),
            durationMs = null,
            finished = false,
            history = HistoryStore.recent(app, "subnet", 6)
        )

        scanJob?.cancel()
        scanJob = viewModelScope.launch {
            try {
                SubnetScanner.scan(
                    SubnetConfig(
                        cidr = cidr,
                        includePortProbe = includePorts
                    )
                ).collect { event ->
                    when (event) {
                        is SubnetScanEvent.Started -> {
                            if (event.info.totalHosts > 0) {
                                ui = ui.copy(total = maxOf(ui.total, event.info.totalHosts))
                            }
                        }

                        is SubnetScanEvent.Progress -> {
                            ui = ui.copy(
                                scanned = event.scanned,
                                total = event.total,
                                hosts = event.found
                            )
                        }

                        is SubnetScanEvent.Finished -> {
                            val total = if (ui.total > 0) ui.total else event.hosts.size
                            ui = ui.copy(
                                scanning = false,
                                finished = true,
                                scanned = total,
                                total = total,
                                hosts = event.hosts,
                                durationMs = event.durationMs
                            )
                        }

                        is SubnetScanEvent.Failed -> {
                            ui = ui.copy(scanning = false, error = event.message)
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                ui = ui.copy(
                    scanning = false,
                    error = e.message?.takeUnless { it.isBlank() } ?: "Subnet scan failed"
                )
            }
        }
    }

    /** Cancels the running scan but keeps any hosts already found on screen. */
    fun stopScan() {
        scanJob?.cancel()
        scanJob = null
        if (ui.scanning) {
            ui = ui.copy(scanning = false, finished = false)
        }
    }

    fun stop() {
        scanJob?.cancel()
        detectJob?.cancel()
        scanJob = null
        detectJob = null
        if (ui.scanning) ui = ui.copy(scanning = false)
    }

    override fun onCleared() {
        stop()
        super.onCleared()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SubnetScannerScreen(onBack: () -> Unit) {
    val vm: SubnetScannerViewModel = viewModel()
    val ui = vm.ui
    val accent = Tools.byRoute(Routes.SUBNET)?.accent ?: MaterialTheme.colorScheme.primary
    val clipboard = LocalClipboardManager.current

    val sortedHosts = remember(ui.hosts) { sortHosts(ui.hosts) }
    val shownHosts = remember(sortedHosts) { sortedHosts.take(MAX_RENDERED_HOSTS) }

    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }
    BackHandler {
        if (ui.scanning) vm.stopScan() else onBack()
    }

    ToolScaffold(
        title = "Subnet Scanner",
        subtitle = "Discover live devices on your local network",
        onBack = onBack
    ) {
        SectionCard(title = "Network") {
            LabeledField(
                label = "CIDR or IP range",
                value = ui.cidr,
                onValueChange = vm::setCidr,
                placeholder = "192.168.1.0/24",
                enabled = !ui.scanning,
                keyboardType = KeyboardType.Uri
            )

            when {
                ui.detecting -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = accent
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "Detecting your network…",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                ui.localInfo != null -> {
                    val info = ui.localInfo
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        KeyValueChip("This device", info.localIp)
                        KeyValueChip("Gateway", info.gateway ?: "--")
                        KeyValueChip("Usable", info.totalHosts.toString())
                    }
                    if (info.cidr != ui.cidr && !ui.scanning) {
                        InlineAction(
                            text = "Use detected subnet ${info.cidr}",
                            onClick = { vm.setCidr(info.cidr) }
                        )
                    }
                }

                else -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "Local subnet not detected — enter it manually.",
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        InlineAction(
                            text = "Retry",
                            onClick = { vm.detectLocalNetwork() }
                        )
                    }
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Probe common ports", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "22, 80, 443, 445, 3389, 8080",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = ui.includePorts,
                    onCheckedChange = vm::setIncludePorts,
                    enabled = !ui.scanning
                )
            }

            Text(
                "Android 10+ may hide MAC addresses from apps; live hosts and open ports are still detected.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (ui.scanning) {
                PrimaryButton(
                    text = "Stop",
                    onClick = vm::stopScan,
                    modifier = Modifier.fillMaxWidth(),
                    icon = Icons.Outlined.Stop
                )
            } else {
                PrimaryButton(
                    text = "Scan",
                    onClick = vm::start,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !ui.detecting || ui.cidr.isNotBlank(),
                    icon = Icons.Outlined.Search
                )
            }
        }

        if (ui.history.isNotEmpty()) {
            Column {
                Text(
                    "RECENT",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(4.dp))
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ui.history.forEach { value ->
                        AssistChip(
                            onClick = { vm.useHistory(value) },
                            label = { Text(value, maxLines = 1) },
                            enabled = !ui.scanning
                        )
                    }
                }
            }
        }

        if (ui.error != null) {
            ErrorBanner(ui.error!!)
        }

        if (ui.scanning || (ui.finished && ui.total > 0)) {
            SectionCard(title = if (ui.scanning) "Scanning" else "Summary") {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        ui.hosts.size.toString(),
                        style = MaterialTheme.typography.headlineMedium,
                        color = accent
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (ui.hosts.size == 1) "host found" else "hosts found",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 3.dp)
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        "${ui.scanned} / ${ui.total}",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                val fraction = if (ui.total > 0) {
                    (ui.scanned.toFloat() / ui.total).coerceIn(0f, 1f)
                } else {
                    0f
                }
                LinearProgressIndicator(
                    progress = { fraction },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(6.dp),
                    color = accent,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest
                )

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        when {
                            !ui.scanning -> "Scan complete"
                            ui.total > 0 && ui.scanned >= ui.total ->
                                if (ui.includePorts) {
                                    "Resolving names and probing ports…"
                                } else {
                                    "Resolving hostnames…"
                                }
                            else -> "Probing addresses…"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        fmtPercent(fraction * 100.0, 0),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (ui.durationMs != null) {
                        Text(
                            " · ${formatDuration(ui.durationMs)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        if (shownHosts.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ResultCountRow(
                    count = ui.hosts.size,
                    label = if (ui.hosts.size == 1) "host found" else "hosts found",
                    modifier = Modifier.weight(1f)
                )
                Spacer(Modifier.width(8.dp))
                TextButton(
                    onClick = {
                        clipboard.setText(AnnotatedString(hostListText(sortedHosts)))
                    }
                ) {
                    Icon(
                        Icons.Outlined.ContentCopy,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Copy list", style = MaterialTheme.typography.labelMedium, maxLines = 1)
                }
            }

            shownHosts.forEach { host ->
                HostCard(host, accent)
            }

            if (sortedHosts.size > shownHosts.size) {
                Text(
                    "Showing the first ${shownHosts.size} of ${sortedHosts.size} hosts. Copy the list to export all of them.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (!ui.detecting && !ui.scanning && !ui.finished && ui.hosts.isEmpty() &&
            ui.error == null
        ) {
            SectionCard {
                EmptyState(
                    icon = Icons.Outlined.Router,
                    title = "Ready to scan",
                    body = "Confirm the subnet above, then start the scan. Every usable address is probed with ICMP."
                )
            }
        }

        if (ui.finished && ui.hosts.isEmpty() && ui.error == null) {
            SectionCard {
                EmptyState(
                    icon = Icons.Outlined.Search,
                    title = "No hosts responded",
                    body = "None of the ${ui.total} probed addresses answered. Guest and public networks often block ICMP."
                )
            }
        }
    }
}

private const val MAX_HOSTS = 4096
private const val MAX_RENDERED_HOSTS = 200

// ---------------------------------------------------------------------------
// Host cards
// ---------------------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HostCard(host: LanHost, accent: Color) {
    val clipboard = LocalClipboardManager.current

    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.outlinedCardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    ) {
        Column(
            Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (host.isGateway) {
                        Icons.Outlined.Router
                    } else {
                        Icons.Outlined.Computer
                    },
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                MonoText(
                    text = host.ip,
                    modifier = Modifier.weight(1f),
                    color = accent,
                    size = 15.sp,
                    weight = FontWeight.SemiBold,
                    maxLines = 1
                )
                if (host.isGateway) {
                    Pill("Gateway", PillTone.Success)
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    text = host.rttMs?.let { fmtLatency(it) } ?: "--",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "Hostname",
                    modifier = Modifier.width(78.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = host.hostname ?: "--",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "MAC",
                    modifier = Modifier.width(78.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                MonoText(
                    text = host.mac ?: "--",
                    modifier = Modifier.weight(1f),
                    size = 12.sp
                )
                if (host.mac != null) {
                    IconButton(
                        onClick = { clipboard.setText(AnnotatedString(host.mac)) },
                        modifier = Modifier.size(32.dp)
                    ) {
                        Icon(
                            Icons.Outlined.ContentCopy,
                            contentDescription = "Copy MAC address",
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            if (host.openPorts.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    host.openPorts.forEach { port ->
                        val service = serviceNameForPort(port)
                        Pill(
                            text = if (service.isEmpty()) port.toString() else "$port · $service",
                            tone = PillTone.Info
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

private fun sortHosts(hosts: List<LanHost>): List<LanHost> =
    hosts.sortedWith(
        compareBy<LanHost> { ipv4ToLong(it.ip) ?: Long.MAX_VALUE }
            .thenBy { it.ip }
    )

private fun hostListText(hosts: List<LanHost>): String = buildString {
    appendLine("PingTools subnet scan - ${hosts.size} hosts")
    appendLine("IP\tRTT\tHostname\tMAC\tOpen ports\tGateway")
    hosts.forEach { host ->
        append(host.ip)
        append('\t').append(host.rttMs?.let { fmtLatency(it) } ?: "--")
        append('\t').append(host.hostname ?: "--")
        append('\t').append(host.mac ?: "--")
        append('\t').append(if (host.openPorts.isEmpty()) "--" else host.openPorts.joinToString(", "))
        append('\t').append(if (host.isGateway) "yes" else "no")
        appendLine()
    }
}
