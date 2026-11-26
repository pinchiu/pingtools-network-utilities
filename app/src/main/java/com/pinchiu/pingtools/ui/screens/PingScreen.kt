package com.pinchiu.pingtools.ui.screens

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.NetworkCheck
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.PingConfig
import com.pinchiu.pingtools.core.model.PingEvent
import com.pinchiu.pingtools.core.model.PingMode
import com.pinchiu.pingtools.core.model.PingReply
import com.pinchiu.pingtools.core.model.PingSummary
import com.pinchiu.pingtools.core.net.PingEngine
import com.pinchiu.pingtools.core.util.fmtLatency
import com.pinchiu.pingtools.core.util.fmtPercent
import com.pinchiu.pingtools.core.util.normalizeHost
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.DataRow
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
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt

private const val PING_HISTORY_KEY = "ping"
private const val PING_LOG_CAP = 80
private const val PING_SAMPLE_CAP = 60
private const val PING_FINITE_COUNT = 10

data class PingLogEntry(
    val seq: Int,
    val text: String,
    val timedOut: Boolean
)

data class PingUiState(
    val host: String = "1.1.1.1",
    val continuous: Boolean = true,
    val running: Boolean = false,
    val target: String? = null,
    val resolvedIp: String? = null,
    val mode: PingMode? = null,
    val note: String? = null,
    val sent: Int = 0,
    val received: Int = 0,
    val lossPercent: Double = 0.0,
    val lastRttMs: Double? = null,
    val minMs: Double = 0.0,
    val avgMs: Double = 0.0,
    val maxMs: Double = 0.0,
    val jitterMs: Double = 0.0,
    val samples: List<Double> = emptyList(),
    val log: List<PingLogEntry> = emptyList(),
    val summary: PingSummary? = null,
    val stopped: Boolean = false,
    val error: String? = null,
    val recentHosts: List<String> = emptyList()
) {
    val hasRun: Boolean get() = sent > 0 || summary != null || running
}

class PingViewModel(app: Application) : AndroidViewModel(app) {

    var ui by mutableStateOf(PingUiState()); private set
    private var job: Job? = null
    private var runId = 0
    private val rtts = mutableListOf<Double>()

    init {
        ui = ui.copy(recentHosts = HistoryStore.recent(app, PING_HISTORY_KEY, 6))
    }

    fun setHost(value: String) {
        if (!ui.running) ui = ui.copy(host = value, error = null)
    }

    fun setContinuous(value: Boolean) {
        if (!ui.running) ui = ui.copy(continuous = value)
    }

    fun start() {
        val host = normalizeHost(ui.host)
        if (host.isBlank()) {
            ui = ui.copy(error = "Enter a host name or IP address")
            return
        }

        job?.cancel()
        runId += 1
        val id = runId
        rtts.clear()

        val application = getApplication<Application>()
        HistoryStore.add(application, PING_HISTORY_KEY, host)
        val history = HistoryStore.recent(application, PING_HISTORY_KEY, 6)

        ui = ui.copy(
            host = host,
            running = true,
            target = null,
            resolvedIp = null,
            mode = null,
            note = null,
            sent = 0,
            received = 0,
            lossPercent = 0.0,
            lastRttMs = null,
            minMs = 0.0,
            avgMs = 0.0,
            maxMs = 0.0,
            jitterMs = 0.0,
            samples = emptyList(),
            log = emptyList(),
            summary = null,
            stopped = false,
            error = null,
            recentHosts = history
        )

        val config = PingConfig(
            host = host,
            count = if (ui.continuous) 0 else PING_FINITE_COUNT
        )
        job = viewModelScope.launch {
            try {
                PingEngine.ping(config).collect { event ->
                    if (id != runId) return@collect
                    when (event) {
                        is PingEvent.Started -> ui = ui.copy(
                            target = event.target,
                            resolvedIp = event.resolvedIp,
                            mode = event.mode
                        )

                        is PingEvent.Reply -> onReply(event.reply)
                        is PingEvent.Timeout -> onTimeout(event.seq)
                        is PingEvent.Note -> ui = ui.copy(note = event.message)
                        is PingEvent.Finished -> onFinished(event.summary)
                        is PingEvent.Failed -> ui = ui.copy(
                            running = false,
                            stopped = ui.sent > 0,
                            error = event.message,
                            summary = buildLocalSummary()
                        )
                    }
                }
                if (id == runId && ui.running) {
                    ui = ui.copy(
                        running = false,
                        stopped = true,
                        summary = buildLocalSummary()
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (id == runId) {
                    ui = ui.copy(
                        running = false,
                        error = e.message ?: "Ping failed",
                        summary = buildLocalSummary()
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
            ui = ui.copy(
                running = false,
                stopped = true,
                summary = buildLocalSummary()
            )
        }
    }

    override fun onCleared() {
        runId += 1
        job?.cancel()
        job = null
        super.onCleared()
    }

    // ------------------------------------------------------------------
    // Event handling
    // ------------------------------------------------------------------

    private fun onReply(reply: PingReply) {
        rtts += reply.rttMs
        val sent = ui.sent + 1
        val received = ui.received + 1
        val entry = PingLogEntry(
            seq = reply.seq,
            text = String.format(
                Locale.US,
                "#%03d  %8s  ttl %-3s  %d B  %s",
                reply.seq,
                fmtLatency(reply.rttMs),
                reply.ttl?.toString() ?: "--",
                reply.bytes,
                reply.from
            ),
            timedOut = false
        )
        ui = ui.copy(
            sent = sent,
            received = received,
            lossPercent = lossPercent(sent, received),
            lastRttMs = reply.rttMs,
            minMs = rtts.minOrNull() ?: 0.0,
            avgMs = rtts.average(),
            maxMs = rtts.maxOrNull() ?: 0.0,
            samples = (ui.samples + reply.rttMs).takeLast(PING_SAMPLE_CAP),
            log = (ui.log + entry).takeLast(PING_LOG_CAP)
        )
    }

    private fun onTimeout(seq: Int) {
        val sent = ui.sent + 1
        val entry = PingLogEntry(
            seq = seq,
            text = String.format(Locale.US, "#%03d  %8s", seq, "timeout"),
            timedOut = true
        )
        ui = ui.copy(
            sent = sent,
            lossPercent = lossPercent(sent, ui.received),
            log = (ui.log + entry).takeLast(PING_LOG_CAP)
        )
    }

    private fun onFinished(summary: PingSummary) {
        ui = ui.copy(
            running = false,
            stopped = false,
            sent = summary.sent,
            received = summary.received,
            lossPercent = summary.lossPercent,
            minMs = summary.minMs,
            avgMs = summary.avgMs,
            maxMs = summary.maxMs,
            jitterMs = summary.jitterMs,
            lastRttMs = ui.lastRttMs ?: rtts.lastOrNull(),
            summary = summary
        )
    }

    private fun buildLocalSummary(): PingSummary? {
        val sent = ui.sent
        if (sent == 0) return null
        val received = rtts.size
        val loss = lossPercent(sent, received)
        if (rtts.isEmpty()) {
            return PingSummary(
                sent = sent,
                received = 0,
                lossPercent = loss,
                minMs = 0.0,
                avgMs = 0.0,
                maxMs = 0.0,
                jitterMs = 0.0,
                stdDevMs = 0.0
            )
        }
        val avg = rtts.average()
        val jitter = if (rtts.size > 1) {
            rtts.zipWithNext { a, b -> abs(b - a) }.average()
        } else {
            0.0
        }
        val variance = rtts.map { value ->
            val delta = value - avg
            delta * delta
        }.average()
        return PingSummary(
            sent = sent,
            received = received,
            lossPercent = loss,
            minMs = rtts.min(),
            avgMs = avg,
            maxMs = rtts.max(),
            jitterMs = jitter,
            stdDevMs = sqrt(variance)
        )
    }

    private fun lossPercent(sent: Int, received: Int): Double =
        if (sent > 0) (sent - received).coerceAtLeast(0) * 100.0 / sent else 0.0
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PingScreen(onBack: () -> Unit) {
    val vm: PingViewModel = viewModel()
    val ui = vm.ui
    val tool = Tools.byRoute(Routes.PING)
    val accent = tool?.accent ?: MaterialTheme.colorScheme.primary

    BackHandler {
        vm.stop()
        onBack()
    }
    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }

    ToolScaffold(
        title = tool?.title ?: "Ping",
        subtitle = tool?.subtitle ?: "ICMP latency, loss & jitter",
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Continuous", style = MaterialTheme.typography.titleSmall)
                    Text(
                        if (ui.continuous) {
                            "Ping until stopped"
                        } else {
                            "Run exactly $PING_FINITE_COUNT packets"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = ui.continuous,
                    onCheckedChange = vm::setContinuous,
                    enabled = !ui.running
                )
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
                icon = Icons.Outlined.NetworkCheck,
                title = "Ready to ping",
                body = "Enter a host and press Start. ICMP is used when the device permits it; " +
                    "otherwise TCP connect latency to ports 443, 80 or 53 is measured."
            )
        } else {
            PingHeroCard(ui = ui, accent = accent)

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile(
                        label = "Sent",
                        value = ui.sent.toString(),
                        modifier = Modifier.weight(1f)
                    )
                    StatTile(
                        label = "Received",
                        value = ui.received.toString(),
                        modifier = Modifier.weight(1f),
                        accent = accent
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile(
                        label = "Loss",
                        value = if (ui.sent > 0) fmtPercent(ui.lossPercent) else "--",
                        modifier = Modifier.weight(1f),
                        accent = if (ui.lossPercent > 0.0) MaterialTheme.colorScheme.error else null
                    )
                    StatTile(
                        label = "Avg RTT",
                        value = if (ui.received > 0) fmtLatency(ui.avgMs) else "--",
                        modifier = Modifier.weight(1f),
                        accent = accent
                    )
                }
            }

            SectionCard(title = "Latency trend") {
                LatencySparkline(
                    samples = ui.samples,
                    accent = accent,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(96.dp)
                )
                val sampleMin = ui.samples.minOrNull()
                val sampleMax = ui.samples.maxOrNull()
                Text(
                    when {
                        ui.samples.isEmpty() -> "Waiting for replies — the last 60 samples are charted."
                        sampleMin != null && sampleMax != null ->
                            "${ui.samples.size}/${PING_SAMPLE_CAP} samples · " +
                                "min ${fmtLatency(sampleMin)} · max ${fmtLatency(sampleMax)}"
                        else -> "${ui.samples.size}/${PING_SAMPLE_CAP} samples"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            val summary = ui.summary
            if (summary != null) {
                SectionCard(
                    title = if (ui.stopped) "Run summary · stopped early" else "Run summary"
                ) {
                    val hasReplies = summary.received > 0
                    DataRow("Packets", "${summary.sent} sent · ${summary.received} received")
                    DataRow(
                        "Loss",
                        fmtPercent(summary.lossPercent),
                        valueColor = if (summary.lossPercent > 0.0) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                    DataRow("Min", if (hasReplies) fmtLatency(summary.minMs) else "--")
                    DataRow("Average", if (hasReplies) fmtLatency(summary.avgMs) else "--")
                    DataRow("Max", if (hasReplies) fmtLatency(summary.maxMs) else "--")
                    DataRow("Jitter", if (hasReplies) fmtLatency(summary.jitterMs) else "--")
                    DataRow("Std dev", if (hasReplies) fmtLatency(summary.stdDevMs) else "--")
                }
            }

            if (ui.log.isNotEmpty() || ui.running) {
                SectionCard(title = "Reply log · newest first") {
                    if (ui.log.isEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = accent
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "Waiting for the first reply…",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        val normalColor = MaterialTheme.colorScheme.onSurface
                        val timeoutColor = MaterialTheme.colorScheme.onSurfaceVariant
                        val logText = buildAnnotatedString {
                            ui.log.asReversed().forEachIndexed { index, entry ->
                                if (index > 0) append('\n')
                                withStyle(
                                    SpanStyle(
                                        color = if (entry.timedOut) timeoutColor else normalColor
                                    )
                                ) {
                                    append(entry.text)
                                }
                            }
                        }
                        Text(
                            text = logText,
                            style = TextStyle(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 12.sp,
                                lineHeight = 17.sp
                            )
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PingHeroCard(ui: PingUiState, accent: Color) {
    SectionCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(
                    "LATEST RTT",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    ui.lastRttMs?.let { fmtLatency(it) } ?: "--",
                    style = MaterialTheme.typography.headlineLarge.copy(
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.SemiBold
                    ),
                    color = accent,
                    maxLines = 1
                )
            }
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    when (ui.mode) {
                        PingMode.ICMP -> Pill("ICMP", PillTone.Success)
                        PingMode.TCP -> Pill("TCP fallback", PillTone.Warning)
                        null -> Unit
                    }
                    Pill(
                        when {
                            ui.running -> "Live"
                            ui.summary != null -> "Complete"
                            else -> "Idle"
                        },
                        if (ui.running) PillTone.Info else PillTone.Neutral
                    )
                }
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            MonoText(ui.target ?: ui.host, size = 13.sp)
            val resolved = ui.resolvedIp
            if (resolved != null && resolved != ui.target) {
                Text(
                    "resolved $resolved",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (ui.running && ui.mode == null) {
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = accent
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Resolving target and checking ICMP support…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else if (ui.running && ui.sent == 0) {
                Text(
                    "Waiting for the first reply…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        val note = ui.note
        if (note != null) {
            Text(
                note,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.tertiary
            )
        }
    }
}

@Composable
private fun LatencySparkline(samples: List<Double>, accent: Color, modifier: Modifier = Modifier) {
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val emptyColor = MaterialTheme.colorScheme.outlineVariant

    Canvas(modifier) {
        if (samples.isEmpty()) {
            drawLine(
                color = emptyColor,
                start = Offset(0f, size.height * 0.6f),
                end = Offset(size.width, size.height * 0.6f),
                strokeWidth = 1.dp.toPx()
            )
            return@Canvas
        }

        val maxValue = samples.max()
        val minValue = samples.min()
        val span = (maxValue - minValue).let { if (it < 0.5) 0.5 else it }
        val top = minValue - span * 0.18
        val bottom = maxValue + span * 0.18
        val range = (bottom - top).coerceAtLeast(0.001)

        // Subtle horizontal guides.
        for (fraction in listOf(0.25f, 0.5f, 0.75f)) {
            val y = size.height * fraction
            drawLine(
                color = gridColor,
                start = Offset(0f, y),
                end = Offset(size.width, y),
                strokeWidth = 1.dp.toPx()
            )
        }

        val denominator = (samples.size - 1).coerceAtLeast(1)
        fun xAt(index: Int): Float =
            if (samples.size == 1) size.width else size.width * index / denominator

        fun yAt(value: Double): Float =
            (size.height - ((value - top) / range).toFloat() * size.height)
                .coerceIn(0f, size.height)

        if (samples.size == 1) {
            drawCircle(accent, radius = 3.dp.toPx(), center = Offset(xAt(0), yAt(samples[0])))
            return@Canvas
        }

        val line = Path()
        samples.forEachIndexed { index, value ->
            val point = Offset(xAt(index), yAt(value))
            if (index == 0) line.moveTo(point.x, point.y) else line.lineTo(point.x, point.y)
        }

        val fill = Path().apply {
            addPath(line)
            lineTo(size.width, size.height)
            lineTo(0f, size.height)
            close()
        }
        drawPath(
            path = fill,
            brush = Brush.verticalGradient(
                colors = listOf(accent.copy(alpha = 0.30f), accent.copy(alpha = 0f)),
                startY = 0f,
                endY = size.height
            )
        )
        drawPath(
            path = line,
            color = accent,
            style = Stroke(
                width = 2.dp.toPx(),
                cap = StrokeCap.Round,
                join = StrokeJoin.Round
            )
        )
        drawCircle(
            color = accent,
            radius = 3.dp.toPx(),
            center = Offset(xAt(samples.lastIndex), yAt(samples.last()))
        )
    }
}
