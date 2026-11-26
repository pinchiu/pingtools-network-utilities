package com.pinchiu.pingtools.ui.screens

import android.app.Application
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.AltRoute
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.TraceConfig
import com.pinchiu.pingtools.core.model.TraceEvent
import com.pinchiu.pingtools.core.model.TraceHop
import com.pinchiu.pingtools.core.net.TracerouteEngine
import com.pinchiu.pingtools.core.util.fmtLatency
import com.pinchiu.pingtools.core.util.formatDuration
import com.pinchiu.pingtools.core.util.normalizeHost
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.DataRow
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.InlineAction
import com.pinchiu.pingtools.ui.components.LabeledField
import com.pinchiu.pingtools.ui.components.MonoText
import com.pinchiu.pingtools.ui.components.Pill
import com.pinchiu.pingtools.ui.components.PillTone
import com.pinchiu.pingtools.ui.components.PrimaryButton
import com.pinchiu.pingtools.ui.components.SecondaryButton
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.ToolScaffold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

private const val TRACE_HISTORY_KEY = "trace"
private const val TRACE_MAX_HOPS = 30
private const val TRACE_PROBES_PER_HOP = 3
private const val TRACE_RENDER_CAP = 40

data class TraceUiState(
    val host: String = "github.com",
    val running: Boolean = false,
    val finished: Boolean = false,
    val target: String? = null,
    val resolvedIp: String? = null,
    val hops: List<TraceHop> = emptyList(),
    val reachedTarget: Boolean = false,
    val elapsedMs: Long = 0L,
    val error: String? = null,
    val recentHosts: List<String> = emptyList()
) {
    val hasRun: Boolean get() = running || finished
}

class TraceViewModel(app: Application) : AndroidViewModel(app) {

    var ui by mutableStateOf(TraceUiState()); private set
    private var job: Job? = null
    private var tickerJob: Job? = null
    private var runId = 0
    private var startedAt = 0L

    init {
        ui = ui.copy(recentHosts = HistoryStore.recent(app, TRACE_HISTORY_KEY, 6))
    }

    fun setHost(value: String) {
        if (!ui.running) ui = ui.copy(host = value, error = null)
    }

    fun start() {
        val host = normalizeHost(ui.host)
        if (host.isBlank()) {
            ui = ui.copy(error = "Enter a host name or IP address")
            return
        }

        job?.cancel()
        tickerJob?.cancel()
        runId += 1
        val id = runId
        startedAt = SystemClock.elapsedRealtime()

        val application = getApplication<Application>()
        HistoryStore.add(application, TRACE_HISTORY_KEY, host)
        val history = HistoryStore.recent(application, TRACE_HISTORY_KEY, 6)

        ui = ui.copy(
            host = host,
            running = true,
            finished = false,
            target = null,
            resolvedIp = null,
            hops = emptyList(),
            reachedTarget = false,
            elapsedMs = 0L,
            error = null,
            recentHosts = history
        )

        tickerJob = viewModelScope.launch {
            while (id == runId && ui.running) {
                delay(500L)
                if (id != runId || !ui.running) break
                ui = ui.copy(
                    elapsedMs = (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0L)
                )
            }
        }

        val config = TraceConfig(
            host = host,
            maxHops = TRACE_MAX_HOPS,
            probesPerHop = TRACE_PROBES_PER_HOP
        )
        job = viewModelScope.launch {
            try {
                TracerouteEngine.trace(config).collect { event ->
                    if (id != runId) return@collect
                    when (event) {
                        is TraceEvent.Started -> ui = ui.copy(
                            target = event.target,
                            resolvedIp = event.resolvedIp
                        )

                        is TraceEvent.HopFound -> ui = ui.copy(
                            hops = (ui.hops + event.hop).take(TRACE_RENDER_CAP),
                            elapsedMs = (SystemClock.elapsedRealtime() - startedAt)
                                .coerceAtLeast(0L)
                        )

                        is TraceEvent.Finished -> {
                            tickerJob?.cancel()
                            ui = ui.copy(
                                running = false,
                                finished = true,
                                hops = event.hops.take(TRACE_RENDER_CAP),
                                reachedTarget = event.reachedTarget,
                                elapsedMs = (SystemClock.elapsedRealtime() - startedAt)
                                    .coerceAtLeast(0L),
                                error = null
                            )
                        }

                        is TraceEvent.Failed -> {
                            tickerJob?.cancel()
                            ui = ui.copy(
                                running = false,
                                finished = true,
                                error = event.message,
                                elapsedMs = (SystemClock.elapsedRealtime() - startedAt)
                                    .coerceAtLeast(0L)
                            )
                        }
                    }
                }
                if (id == runId && ui.running) {
                    ui = ui.copy(
                        running = false,
                        finished = true,
                        elapsedMs = (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0L)
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (id == runId) {
                    ui = ui.copy(
                        running = false,
                        finished = true,
                        error = e.message ?: "Traceroute failed",
                        elapsedMs = (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0L)
                    )
                }
            }
        }
    }

    fun stop() {
        runId += 1
        job?.cancel()
        job = null
        tickerJob?.cancel()
        tickerJob = null
        if (ui.running) {
            ui = ui.copy(
                running = false,
                finished = true,
                elapsedMs = (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(ui.elapsedMs)
            )
        }
    }

    override fun onCleared() {
        runId += 1
        job?.cancel()
        tickerJob?.cancel()
        job = null
        tickerJob = null
        super.onCleared()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TraceScreen(onBack: () -> Unit) {
    val vm: TraceViewModel = viewModel()
    val ui = vm.ui
    val tool = Tools.byRoute(Routes.TRACE)
    val accent = tool?.accent ?: MaterialTheme.colorScheme.primary
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }

    LaunchedEffect(copied) {
        if (copied) {
            delay(1_600L)
            copied = false
        }
    }

    val copyRoute: () -> Unit = {
        clipboard.setText(AnnotatedString(buildTraceText(ui)))
        copied = true
    }

    BackHandler {
        vm.stop()
        onBack()
    }
    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }

    ToolScaffold(
        title = tool?.title ?: "Traceroute",
        subtitle = tool?.subtitle ?: "Hop-by-hop network path",
        onBack = {
            vm.stop()
            onBack()
        },
        actions = {
            IconButton(
                onClick = copyRoute,
                enabled = ui.hops.isNotEmpty()
            ) {
                Icon(
                    Icons.Outlined.ContentCopy,
                    contentDescription = "Copy traceroute"
                )
            }
        }
    ) {
        SectionCard {
            LabeledField(
                label = "Host",
                value = ui.host,
                onValueChange = vm::setHost,
                placeholder = "github.com or 1.1.1.1",
                enabled = !ui.running,
                keyboardType = KeyboardType.Uri
            )
            val target = ui.target
            val resolved = ui.resolvedIp
            if (target != null || resolved != null) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (target != null) {
                        DataRow("Target", target)
                    }
                    if (resolved != null) {
                        DataRow("Resolved", resolved)
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
                        text = "Start",
                        onClick = vm::start,
                        modifier = Modifier.weight(1f),
                        icon = Icons.Outlined.PlayArrow
                    )
                }
            }
            Text(
                "Up to $TRACE_MAX_HOPS hops · $TRACE_PROBES_PER_HOP probes per hop · requires ICMP",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (ui.recentHosts.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "RECENT TARGETS",
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
                icon = Icons.AutoMirrored.Outlined.AltRoute,
                title = "Map a network path",
                body = "Enter a host and press Start. Each hop is probed " +
                    "$TRACE_PROBES_PER_HOP times; unresponsive hops are shown as \"*\"."
            )
        } else {
            SectionCard(title = "Route") {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Pill(
                        text = "${ui.hops.size} hops",
                        tone = PillTone.Info
                    )
                    if (ui.reachedTarget) {
                        Pill("Target reached", PillTone.Success)
                    }
                    Spacer(Modifier.weight(1f))
                    InlineAction(
                        text = if (copied) "Copied" else "Copy all",
                        onClick = copyRoute,
                        enabled = ui.hops.isNotEmpty()
                    )
                }
                Text(
                    if (ui.running) {
                        "Elapsed ${formatDuration(ui.elapsedMs)} · probing next hop"
                    } else {
                        "Elapsed ${formatDuration(ui.elapsedMs)} · max $TRACE_MAX_HOPS hops"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                if (ui.hops.isEmpty()) {
                    if (ui.running) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = accent
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "Probing hop 1…",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        Text(
                            "No hops reported. The trace stopped before any router replied.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    ui.hops.take(TRACE_RENDER_CAP).forEach { hop ->
                        key(hop.hop) {
                            TraceHopRow(
                                hop = hop,
                                targetIp = ui.resolvedIp,
                                accent = accent
                            )
                        }
                    }

                    if (ui.finished) {
                        Text(
                            if (ui.reachedTarget) {
                                "Destination reached in ${ui.hops.size} hops."
                            } else {
                                "Trace ended after ${ui.hops.size} hops without a destination reply."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else if (ui.running) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(14.dp),
                                strokeWidth = 2.dp,
                                color = accent
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "Probing hop ${ui.hops.size + 1}…",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TraceHopRow(hop: TraceHop, targetIp: String?, accent: Color) {
    val isTarget = hop.address != null && targetIp != null && hop.address == targetIp
    val dimmed = hop.address == null
    val background = if (isTarget) accent.copy(alpha = 0.09f) else Color.Transparent

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(background, RoundedCornerShape(10.dp))
            .padding(horizontal = 6.dp, vertical = 6.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .background(
                    if (isTarget) accent.copy(alpha = 0.22f)
                    else MaterialTheme.colorScheme.surfaceContainerHigh,
                    CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                hop.hop.toString(),
                style = MaterialTheme.typography.labelMedium.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold
                ),
                color = if (isTarget) accent else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(Modifier.width(10.dp))

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val name = hop.hostname?.takeIf { it.isNotBlank() }
                    ?: hop.address
                    ?: "No response"
                MonoText(
                    text = name,
                    modifier = Modifier.weight(1f),
                    size = 13.sp,
                    weight = FontWeight.Medium,
                    maxLines = 1,
                    color = if (dimmed) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.onSurface
                )
                if (isTarget) {
                    Spacer(Modifier.width(8.dp))
                    Pill("Target", PillTone.Success)
                }
            }

            val hostname = hop.hostname
            val address = hop.address
            if (!hostname.isNullOrBlank() && address != null) {
                Text(
                    address,
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontFamily = FontFamily.Monospace
                    ),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Text(
                formatRtts(hop),
                style = MaterialTheme.typography.bodySmall.copy(
                    fontFamily = FontFamily.Monospace
                ),
                color = if (dimmed) MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.onSurface
            )
        }
    }
}

private fun formatRtts(hop: TraceHop): String =
    (0 until TRACE_PROBES_PER_HOP).joinToString("   ") { index ->
        hop.rtts.getOrNull(index)?.let { fmtLatency(it) } ?: "*"
    }

private fun buildTraceText(ui: TraceUiState): String {
    val target = ui.target ?: normalizeHost(ui.host).ifBlank { ui.host }
    val ip = ui.resolvedIp
    val header = if (ip != null) {
        "traceroute to $target ($ip), $TRACE_MAX_HOPS hops max, $TRACE_PROBES_PER_HOP probes per hop"
    } else {
        "traceroute to $target, $TRACE_MAX_HOPS hops max, $TRACE_PROBES_PER_HOP probes per hop"
    }
    val lines = ui.hops.map { hop ->
        val name = hop.hostname?.takeIf { it.isNotBlank() } ?: hop.address ?: "*"
        val suffix = if (hop.hostname != null && hop.address != null) " (${hop.address})" else ""
        String.format(
            Locale.US,
            "%2d  %s%s  %s",
            hop.hop,
            name,
            suffix,
            formatRtts(hop)
        )
    }
    val footer = when {
        !ui.finished -> null
        ui.reachedTarget -> "Destination reached in ${ui.hops.size} hops."
        else -> "Trace ended after ${ui.hops.size} hops."
    }
    return (listOf(header) + lines + listOfNotNull(footer)).joinToString("\n")
}
