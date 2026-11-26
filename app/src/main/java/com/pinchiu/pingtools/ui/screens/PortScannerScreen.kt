package com.pinchiu.pingtools.ui.screens

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Scanner
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.PortResult
import com.pinchiu.pingtools.core.model.PortScanConfig
import com.pinchiu.pingtools.core.model.PortScanEvent
import com.pinchiu.pingtools.core.model.PortState
import com.pinchiu.pingtools.core.net.PortScanner
import com.pinchiu.pingtools.core.util.PORT_PRESETS
import com.pinchiu.pingtools.core.util.formatDuration
import com.pinchiu.pingtools.core.util.normalizeHost
import com.pinchiu.pingtools.core.util.parsePortSpec
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.LabeledField
import com.pinchiu.pingtools.ui.components.MonoText
import com.pinchiu.pingtools.ui.components.Pill
import com.pinchiu.pingtools.ui.components.PillTone
import com.pinchiu.pingtools.ui.components.PrimaryButton
import com.pinchiu.pingtools.ui.components.SecondaryButton
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.StatTile
import com.pinchiu.pingtools.ui.components.ToolScaffold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

private const val PORT_HISTORY_KEY = "ports"

data class PortScannerUiState(
    val host: String = "1.1.1.1",
    val portSpec: String = PORT_PRESETS.first().second,
    val running: Boolean = false,
    val finished: Boolean = false,
    val stopped: Boolean = false,
    val resolvedIp: String? = null,
    val scanned: Int = 0,
    val total: Int = 0,
    val open: List<PortResult> = emptyList(),
    val results: List<PortResult> = emptyList(),
    val durationMs: Long = 0L,
    val error: String? = null,
    val recentHosts: List<String> = emptyList()
) {
    val hasRun: Boolean get() = running || finished
}

class PortScannerViewModel(app: Application) : AndroidViewModel(app) {

    var ui by mutableStateOf(PortScannerUiState()); private set
    private var job: Job? = null
    private var runId = 0

    init {
        ui = ui.copy(recentHosts = HistoryStore.recent(app, PORT_HISTORY_KEY, 6))
    }

    fun setHost(value: String) {
        if (!ui.running) ui = ui.copy(host = value, error = null)
    }

    fun setPortSpec(value: String) {
        if (!ui.running) ui = ui.copy(portSpec = value, error = null)
    }

    fun start() {
        if (ui.running) return

        val host = normalizeHost(ui.host)
        if (host.isBlank()) {
            ui = ui.copy(error = "Enter a host name or IP address")
            return
        }

        val ports = try {
            parsePortSpec(ui.portSpec)
        } catch (e: IllegalArgumentException) {
            ui = ui.copy(error = e.message ?: "Invalid port list")
            return
        } catch (e: Exception) {
            ui = ui.copy(error = "Invalid port list")
            return
        }

        job?.cancel()
        runId += 1
        val id = runId

        val application = getApplication<Application>()
        HistoryStore.add(application, PORT_HISTORY_KEY, host)
        val history = HistoryStore.recent(application, PORT_HISTORY_KEY, 6)

        ui = ui.copy(
            host = host,
            running = true,
            finished = false,
            stopped = false,
            resolvedIp = null,
            scanned = 0,
            total = ports.size,
            open = emptyList(),
            results = emptyList(),
            durationMs = 0L,
            error = null,
            recentHosts = history
        )

        val config = PortScanConfig(host = host, ports = ports)
        job = viewModelScope.launch {
            try {
                PortScanner.scan(config).collect { event ->
                    if (id != runId) return@collect
                    when (event) {
                        is PortScanEvent.Started -> ui = ui.copy(
                            resolvedIp = event.resolvedIp,
                            total = event.total
                        )

                        is PortScanEvent.Progress -> ui = ui.copy(
                            scanned = event.progress.scanned,
                            total = event.progress.total,
                            open = event.progress.open.sortedBy { it.port }
                        )

                        is PortScanEvent.Finished -> {
                            val ordered = event.results.sortedBy { it.port }
                            ui = ui.copy(
                                running = false,
                                finished = true,
                                stopped = false,
                                scanned = ordered.size,
                                total = ordered.size,
                                results = ordered,
                                open = ordered.filter { it.state == PortState.OPEN },
                                durationMs = event.durationMs,
                                error = null
                            )
                        }

                        is PortScanEvent.Failed -> ui = ui.copy(
                            running = false,
                            finished = true,
                            stopped = false,
                            error = event.message
                        )
                    }
                }
                if (id == runId && ui.running) {
                    ui = ui.copy(running = false, finished = true)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (id == runId) {
                    ui = ui.copy(
                        running = false,
                        finished = true,
                        error = e.message ?: "Port scan failed"
                    )
                }
            }
        }
    }

    fun stop() {
        runId += 1
        job?.cancel()
        job = null
        if (ui.running) {
            ui = ui.copy(running = false, finished = true, stopped = true)
        }
    }

    override fun onCleared() {
        runId += 1
        job?.cancel()
        job = null
        super.onCleared()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PortScannerScreen(onBack: () -> Unit) {
    val vm: PortScannerViewModel = viewModel()
    val ui = vm.ui
    val tool = Tools.byRoute(Routes.PORTS)
    val accent = tool?.accent ?: MaterialTheme.colorScheme.primary

    BackHandler {
        vm.stop()
        onBack()
    }
    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }

    ToolScaffold(
        title = tool?.title ?: "Port Scanner",
        subtitle = tool?.subtitle ?: "TCP ports & service banners",
        onBack = {
            vm.stop()
            onBack()
        }
    ) {
        SectionCard {
            LabeledField(
                label = "Host",
                value = ui.host,
                onValueChange = vm::setHost,
                placeholder = "1.1.1.1 or example.com",
                enabled = !ui.running,
                keyboardType = KeyboardType.Uri
            )
            LabeledField(
                label = "Ports",
                value = ui.portSpec,
                onValueChange = vm::setPortSpec,
                placeholder = "22,80,443 or 8000-8010",
                enabled = !ui.running,
                singleLine = true
            )
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "PRESETS",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    PORT_PRESETS.forEach { (label, spec) ->
                        val selected = ui.portSpec == spec
                        AssistChip(
                            onClick = { vm.setPortSpec(spec) },
                            enabled = !ui.running,
                            label = { Text(label) },
                            leadingIcon = if (selected) {
                                {
                                    Icon(
                                        Icons.Outlined.Check,
                                        contentDescription = null,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            } else {
                                null
                            }
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (ui.running) {
                    SecondaryButton(
                        text = "Stop",
                        onClick = vm::stop,
                        modifier = Modifier.weight(1f),
                        icon = Icons.Outlined.Stop
                    )
                } else {
                    PrimaryButton(
                        text = "Start scan",
                        onClick = vm::start,
                        modifier = Modifier.weight(1f),
                        icon = Icons.Outlined.PlayArrow
                    )
                }
            }
            Text(
                "TCP connect scan · up to 4,096 ports · 900 ms per port timeout",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (ui.recentHosts.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "RECENT HOSTS",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ui.recentHosts.forEach { host ->
                        AssistChip(
                            onClick = { vm.setHost(host) },
                            label = { Text(host) },
                            enabled = !ui.running
                        )
                    }
                }
            }
        }

        if (ui.error != null) {
            ErrorBanner(ui.error)
        }

        if (!ui.hasRun) {
            EmptyState(
                icon = Icons.Outlined.Scanner,
                title = "Scan TCP ports",
                body = "Choose a preset or enter a port list, then start scanning. " +
                    "Open ports are listed with their service name and banner when available."
            )
        } else {
            if (ui.running) {
                val fraction = if (ui.total > 0) {
                    (ui.scanned.toFloat() / ui.total).coerceIn(0f, 1f)
                } else {
                    0f
                }
                SectionCard(title = "Progress") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "Scanning ${ui.resolvedIp ?: ui.host}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Spacer(Modifier.weight(1f))
                        MonoText(
                            "${ui.scanned}/${ui.total}",
                            size = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    LinearProgressIndicator(
                        progress = { fraction },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp),
                        color = accent,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest
                    )
                    Text(
                        "${(fraction * 100).toInt()}% complete",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            val openCount = if (ui.finished && ui.results.isNotEmpty()) {
                ui.results.count { it.state == PortState.OPEN }
            } else {
                ui.open.size
            }
            val countsKnown = ui.results.isNotEmpty()
            val closedCount = if (countsKnown) {
                ui.results.count { it.state == PortState.CLOSED }.toString()
            } else {
                "--"
            }
            val filteredCount = if (countsKnown) {
                ui.results.count { it.state == PortState.FILTERED }.toString()
            } else {
                "--"
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(
                    label = "Open",
                    value = openCount.toString(),
                    modifier = Modifier.weight(1f),
                    accent = accent
                )
                StatTile(
                    label = "Closed",
                    value = closedCount,
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "Filtered",
                    value = filteredCount,
                    modifier = Modifier.weight(1f)
                )
            }

            val statusText = when {
                ui.error != null -> null
                ui.running -> "Scanning ${ui.scanned} of ${ui.total} ports…"
                ui.stopped -> "Stopped after ${ui.scanned} of ${ui.total} ports."
                ui.finished -> "Scanned ${ui.total} ports in ${formatDuration(ui.durationMs)}."
                else -> null
            }
            if (statusText != null) {
                Text(
                    statusText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            val openPorts = ui.open.sortedBy { it.port }
            when {
                openPorts.isNotEmpty() -> {
                    SectionCard(title = "Open ports · ${openPorts.size}") {
                        openPorts.forEach { result ->
                            key(result.port) {
                                OpenPortRow(result = result, accent = accent)
                            }
                        }
                    }
                }

                ui.running -> {
                    SectionCard(title = "Open ports") {
                        Text(
                            if (ui.scanned == 0) {
                                "Starting scan…"
                            } else {
                                "No open ports found yet."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                else -> {
                    if (ui.error != null) {
                        SectionCard(title = "Open ports") {
                            Text(
                                "Scan did not complete, so there are no port results to show.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        EmptyState(
                            icon = Icons.Outlined.Lock,
                            title = "No open ports",
                            body = if (ui.stopped) {
                                "The scan stopped after checking ${ui.scanned} of ${ui.total} ports; " +
                                    "no open ports were found in that range."
                            } else {
                                "All ${ui.total} scanned TCP ports refused the connection or were filtered."
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun OpenPortRow(result: PortResult, accent: Color) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                MaterialTheme.colorScheme.surfaceContainerHigh,
                RoundedCornerShape(12.dp)
            )
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                MonoText(
                    text = result.port.toString(),
                    size = 20.sp,
                    weight = FontWeight.SemiBold,
                    color = accent
                )
                if (result.service.isNotBlank()) {
                    Spacer(Modifier.width(8.dp))
                    Pill(result.service, PillTone.Info)
                }
            }
            val banner = result.banner
            if (!banner.isNullOrBlank()) {
                Spacer(Modifier.height(3.dp))
                MonoText(
                    text = banner,
                    size = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        Pill("OPEN", PillTone.Success)
    }
}
