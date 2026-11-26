package com.pinchiu.pingtools.ui.screens

import android.app.Application
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
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Http
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.HttpInfo
import com.pinchiu.pingtools.core.net.HttpEngine
import com.pinchiu.pingtools.core.util.formatBytes
import com.pinchiu.pingtools.core.util.formatDuration
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.CopyableRow
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
import com.pinchiu.pingtools.ui.components.ToolScaffold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

data class HttpUiState(
    val url: String = "https://example.com",
    val followRedirects: Boolean = true,
    val loading: Boolean = false,
    val info: HttpInfo? = null,
    val error: String? = null,
    val history: List<String> = emptyList()
)

class HttpInspectorViewModel(app: Application) : AndroidViewModel(app) {
    var ui by mutableStateOf(HttpUiState(history = HistoryStore.recent(app, "http", 5)))
        private set

    private var job: Job? = null

    fun updateUrl(value: String) {
        ui = ui.copy(url = value, error = null)
    }

    fun setFollowRedirects(value: Boolean) {
        ui = ui.copy(followRedirects = value)
    }

    fun inspect() {
        val target = ui.url.trim()
        if (target.isEmpty()) {
            ui = ui.copy(error = "Enter a URL to inspect")
            return
        }
        val followRedirects = ui.followRedirects
        job?.cancel()
        ui = ui.copy(loading = true, info = null, error = null)
        HistoryStore.add(getApplication(), "http", target)
        ui = ui.copy(history = HistoryStore.recent(getApplication(), "http", 5))

        job = viewModelScope.launch {
            val result = try {
                HttpEngine.inspect(target, followRedirects = followRedirects)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                HttpInfo(
                    url = target,
                    error = e.message?.trim().takeUnless { it.isNullOrEmpty() }
                        ?: "Request failed"
                )
            }

            if (result.error != null) {
                ui = ui.copy(loading = false, info = null, error = result.error)
            } else {
                ui = ui.copy(loading = false, info = result, error = null)
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HttpInspectorScreen(onBack: () -> Unit) {
    val vm: HttpInspectorViewModel = viewModel()
    val ui = vm.ui
    val accent = Tools.byRoute(Routes.HTTP)?.accent ?: MaterialTheme.colorScheme.primary

    BackHandler {
        vm.stop()
        onBack()
    }
    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }

    ToolScaffold(
        title = "HTTP Inspector",
        subtitle = "Status, headers and TLS details",
        onBack = onBack
    ) {
        SectionCard(title = "Request") {
            LabeledField(
                label = "URL",
                value = ui.url,
                onValueChange = vm::updateUrl,
                placeholder = "https://example.com",
                enabled = !ui.loading,
                keyboardType = KeyboardType.Uri
            )

            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Follow redirects", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "Show the final URL after 3xx responses",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = ui.followRedirects,
                    onCheckedChange = vm::setFollowRedirects,
                    enabled = !ui.loading
                )
            }

            if (ui.history.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ui.history.forEach { recent ->
                        AssistChip(
                            onClick = { vm.updateUrl(recent) },
                            label = { Text(recent) }
                        )
                    }
                }
            }

            PrimaryButton(
                text = "Inspect",
                onClick = vm::inspect,
                modifier = Modifier.fillMaxWidth(),
                loading = ui.loading,
                icon = Icons.Outlined.Search
            )
        }

        ui.error?.let { ErrorBanner(it) }

        val info = ui.info
        when {
            info != null -> {
                StatusCard(info = info)
                MetaCard(info = info)
                SecurityCard(info = info)
                HeadersCard(info = info)
            }
            ui.error != null -> EmptyState(
                icon = Icons.Outlined.CloudOff,
                title = "No response",
                body = "Check the URL and your connection, then try again."
            )
            ui.loading -> SectionCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = accent
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "Contacting server…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            else -> EmptyState(
                icon = Icons.Outlined.Http,
                title = "Inspect any URL",
                body = "Status, redirects, TLS and security headers — the response body is never downloaded."
            )
        }
    }
}

@Composable
private fun StatusCard(info: HttpInfo) {
    val tone = statusTone(info.statusCode)
    val statusColor = when (tone) {
        PillTone.Success -> MaterialTheme.colorScheme.secondary
        PillTone.Warning -> MaterialTheme.colorScheme.tertiary
        PillTone.Danger -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurface
    }

    SectionCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = info.statusCode.toString(),
                style = MaterialTheme.typography.headlineLarge.copy(
                    fontFamily = FontFamily.Monospace
                ),
                color = statusColor
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    info.statusMessage.ifBlank { "HTTP response" },
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    "HTTP status",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Pill(statusLabel(info.statusCode), tone)
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        CopyableRow("Final URL", info.finalUrl)
    }
}

@Composable
private fun MetaCard(info: HttpInfo) {
    SectionCard(title = "Response") {
        DataRow(
            "Duration",
            if (info.durationMs > 0) formatDuration(info.durationMs) else "—"
        )
        DataRow("Protocol", info.protocol.ifBlank { "—" })
        DataRow("TLS", info.tlsVersion ?: "—")
        DataRow("Cipher", info.tlsCipher ?: "—")
        DataRow("Server", info.server ?: "—")
        DataRow("Content type", info.contentType ?: "—")
        DataRow(
            "Content length",
            info.contentLength?.let { formatBytes(it) } ?: "—"
        )
    }
}

@Composable
private fun SecurityCard(info: HttpInfo) {
    SectionCard(title = "Security checks") {
        if (info.security.isEmpty()) {
            Text(
                "No security header information was returned.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                info.security.forEach { (check, value) ->
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            check,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodySmall
                        )
                        Pill(value, securityTone(check, value))
                    }
                }
            }
        }
    }
}

@Composable
private fun HeadersCard(info: HttpInfo) {
    val clipboard = LocalClipboardManager.current
    val headersText = info.headers.joinToString("\n") { "${it.first}: ${it.second}" }

    SectionCard(title = "Headers · ${info.headers.size}") {
        if (info.headers.isEmpty()) {
            Text(
                "No response headers were returned.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                info.headers.take(120).forEach { header ->
                    Column {
                        Text(
                            header.first,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.height(2.dp))
                        SelectionContainer {
                            MonoText(header.second, size = 12.sp)
                        }
                    }
                }
            }
            if (info.headers.size > 120) {
                Text(
                    "Showing the first 120 of ${info.headers.size} headers.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            SecondaryButton(
                text = "Copy all headers",
                onClick = { clipboard.setText(AnnotatedString(headersText)) },
                modifier = Modifier.fillMaxWidth(),
                icon = Icons.Outlined.ContentCopy
            )
        }
    }
}

private fun statusTone(code: Int): PillTone = when (code / 100) {
    2 -> PillTone.Success
    3 -> PillTone.Warning
    4, 5 -> PillTone.Danger
    else -> PillTone.Neutral
}

private fun statusLabel(code: Int): String = when (code / 100) {
    1 -> "Informational"
    2 -> "Success"
    3 -> "Redirect"
    4 -> "Client error"
    5 -> "Server error"
    else -> "Unknown status"
}

private fun securityTone(check: String, value: String): PillTone {
    val normalized = value.lowercase()
    return when {
        check.equals("Cleartext", ignoreCase = true) ->
            if (normalized == "no") PillTone.Success else PillTone.Danger
        normalized == "on" || normalized == "present" -> PillTone.Success
        normalized == "off" || normalized == "absent" -> PillTone.Warning
        else -> PillTone.Neutral
    }
}
