package com.pinchiu.pingtools.ui.screens

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.WhoisField
import com.pinchiu.pingtools.core.model.WhoisResult
import com.pinchiu.pingtools.core.net.WhoisEngine
import com.pinchiu.pingtools.core.util.formatBytes
import com.pinchiu.pingtools.core.util.formatDuration
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.DataRow
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.InlineAction
import com.pinchiu.pingtools.ui.components.KeyValueChip
import com.pinchiu.pingtools.ui.components.LabeledField
import com.pinchiu.pingtools.ui.components.MonoText
import com.pinchiu.pingtools.ui.components.PrimaryButton
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.ToolScaffold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.util.Locale

data class WhoisUiState(
    val query: String = "example.com",
    val loading: Boolean = false,
    val result: WhoisResult? = null,
    val error: String? = null,
    val history: List<String> = emptyList(),
    val rawExpanded: Boolean = false,
    val showAllFields: Boolean = false
)

class WhoisViewModel(app: Application) : AndroidViewModel(app) {

    var ui by mutableStateOf(
        WhoisUiState(history = HistoryStore.recent(app, "whois", 6))
    )
        private set

    private var job: Job? = null

    fun setQuery(value: String) {
        ui = ui.copy(query = value, error = null)
    }

    fun useHistory(value: String) {
        ui = ui.copy(query = value, error = null)
    }

    fun toggleRaw() {
        ui = ui.copy(rawExpanded = !ui.rawExpanded)
    }

    fun setShowAllFields(show: Boolean) {
        ui = ui.copy(showAllFields = show)
    }

    fun lookup() {
        val query = ui.query.trim()
        if (query.isEmpty()) {
            ui = ui.copy(error = "Enter a domain name or IP address")
            return
        }
        if (query.any { it.isWhitespace() }) {
            ui = ui.copy(error = "Remove spaces from the query")
            return
        }

        job?.cancel()
        ui = ui.copy(loading = true, error = null, rawExpanded = false, showAllFields = false)
        job = viewModelScope.launch {
            val result = try {
                WhoisEngine.lookup(query)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                WhoisResult(
                    query = query,
                    server = "",
                    error = e.message?.takeUnless { it.isBlank() } ?: "Whois lookup failed"
                )
            }

            val app = getApplication<Application>()
            HistoryStore.add(app, "whois", query)
            ui = ui.copy(
                loading = false,
                result = result,
                error = result.error,
                history = HistoryStore.recent(app, "whois", 6)
            )
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        if (ui.loading) ui = ui.copy(loading = false)
    }

    override fun onCleared() {
        job?.cancel()
        super.onCleared()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WhoisScreen(onBack: () -> Unit) {
    val vm: WhoisViewModel = viewModel()
    val ui = vm.ui
    val accent = Tools.byRoute(Routes.WHOIS)?.accent ?: MaterialTheme.colorScheme.primary
    val clipboard = LocalClipboardManager.current

    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }
    BackHandler(enabled = ui.loading) { vm.stop() }

    ToolScaffold(
        title = "WHOIS",
        subtitle = "Domain and IP registration over port 43",
        onBack = onBack
    ) {
        SectionCard(title = "Query") {
            LabeledField(
                label = "Domain or IP address",
                value = ui.query,
                onValueChange = vm::setQuery,
                placeholder = "example.com",
                enabled = !ui.loading,
                keyboardType = KeyboardType.Uri
            )
            PrimaryButton(
                text = "Lookup",
                onClick = vm::lookup,
                modifier = Modifier.fillMaxWidth(),
                enabled = !ui.loading,
                loading = ui.loading,
                icon = Icons.Outlined.Search
            )
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
                            enabled = !ui.loading
                        )
                    }
                }
            }
        }

        if (ui.error != null) {
            ErrorBanner(ui.error!!)
        }

        if (ui.loading) {
            SectionCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = accent
                    )
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text("Contacting WHOIS server", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Following IANA referrals — this can take a few seconds.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        val result = ui.result
        if (result != null && !ui.loading) {
            SectionCard {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    KeyValueChip("Query", result.query.ifBlank { "--" })
                    KeyValueChip("Server", result.server.ifBlank { "--" })
                    KeyValueChip("Duration", formatDuration(result.durationMs))
                    KeyValueChip("Fields", result.fields.size.toString())
                }
            }

            val summary = remember(result) { summarizeWhoisFields(result.fields) }
            val registrationFields = summary.first
            val remainingFields = summary.second

            if (result.fields.isNotEmpty()) {
                SectionCard(title = "Registration summary") {
                    registrationFields.forEachIndexed { index, field ->
                        if (index > 0) {
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        }
                        HighlightGroup(field.label, field.values, accent)
                    }
                }
            } else if (result.raw.isNotBlank()) {
                SectionCard(title = "Registration summary") {
                    Text(
                        "The response did not contain parseable key/value fields. See the raw response below.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (remainingFields.isNotEmpty()) {
                SectionCard(title = "All fields (${remainingFields.size})") {
                    val limit = 12
                    val visible = if (ui.showAllFields) remainingFields else remainingFields.take(limit)
                    visible.forEach { field ->
                        DataRow(
                            label = field.key,
                            value = field.value.ifBlank { "--" },
                            mono = false
                        )
                    }
                    if (remainingFields.size > limit) {
                        InlineAction(
                            text = if (ui.showAllFields) {
                                "Show fewer"
                            } else {
                                "Show all ${remainingFields.size} fields"
                            },
                            onClick = { vm.setShowAllFields(!ui.showAllFields) }
                        )
                    }
                }
            }

            if (result.raw.isNotBlank()) {
                val lineCount = remember(result.raw) { result.raw.count { it == '\n' } + 1 }
                SectionCard(title = "Raw response") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                "${formatBytes(result.raw.length.toLong())} · $lineCount lines",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        IconButton(
                            onClick = { clipboard.setText(AnnotatedString(result.raw)) }
                        ) {
                            Icon(
                                Icons.Outlined.ContentCopy,
                                contentDescription = "Copy raw WHOIS response",
                                modifier = Modifier.size(17.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        TextButton(onClick = vm::toggleRaw) {
                            Text(
                                if (ui.rawExpanded) "Hide" else "Show",
                                style = MaterialTheme.typography.labelMedium
                            )
                        }
                    }

                    if (ui.rawExpanded) {
                        val preview = remember(result.raw) {
                            result.raw.lineSequence().take(MAX_RAW_LINES).joinToString("\n")
                        }
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .background(
                                    MaterialTheme.colorScheme.surfaceContainerHigh,
                                    RoundedCornerShape(10.dp)
                                )
                                .padding(12.dp)
                        ) {
                            MonoText(preview, size = 11.sp)
                        }
                        if (lineCount > MAX_RAW_LINES) {
                            Text(
                                "Showing the first $MAX_RAW_LINES of $lineCount lines. Copy the raw response for everything.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }

        if (!ui.loading && result == null) {
            SectionCard {
                EmptyState(
                    icon = Icons.Outlined.Search,
                    title = "Look up a registration",
                    body = "Enter a domain or IP address. WHOIS data is queried live from IANA referrals and shown field by field."
                )
            }
        }
    }
}

private const val MAX_RAW_LINES = 250

// ---------------------------------------------------------------------------
// Highlighted fields
// ---------------------------------------------------------------------------

@Composable
private fun HighlightGroup(label: String, values: List<String>, accent: Color) {
    val clipboard = LocalClipboardManager.current
    val shown = values.ifEmpty { listOf("--") }
    val copyable = values.joinToString("\n")

    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                label.uppercase(Locale.US),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.labelSmall,
                color = accent
            )
            if (values.isNotEmpty()) {
                IconButton(
                    onClick = { clipboard.setText(AnnotatedString(copyable)) },
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        Icons.Outlined.ContentCopy,
                        contentDescription = "Copy $label",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        shown.forEach { value ->
            MonoText(
                text = value,
                size = 13.sp,
                color = if (values.isEmpty()) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                }
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Field matching
// ---------------------------------------------------------------------------

private data class HighlightSpec(val label: String, val matches: (String) -> Boolean)

private data class SummaryField(val label: String, val values: List<String>)

private val CREATION_KEYS = setOf(
    "creationdate", "created", "createdon", "createddate", "registrationtime",
    "registeredon", "registrationdate", "domainregistrationdate", "registrationcreated"
)

private val UPDATED_KEYS = setOf(
    "updateddate", "updated", "lastupdated", "lastupdatedon", "lastmodified",
    "lastmodifieddate", "modified", "changed", "lastupdate"
)

private val EXPIRY_KEYS = setOf(
    "expirydate", "expirationdate", "expirationtime", "registryexpirydate",
    "expires", "expireson", "paidtill", "domainexpirationdate",
    "registrarregistrationexpirationdate", "renewaldate"
)

private val HIGHLIGHT_SPECS: List<HighlightSpec> = listOf(
    HighlightSpec("Registrar") { key ->
        key == "registrar" || key == "registrarname" || key == "sponsoringregistrar" ||
            key == "registrarcompanyname"
    },
    HighlightSpec("Creation Date") { key -> key in CREATION_KEYS },
    HighlightSpec("Updated Date") { key -> key in UPDATED_KEYS },
    HighlightSpec("Expiry Date") { key -> key in EXPIRY_KEYS },
    HighlightSpec("Name Server(s)") { key ->
        key == "ns" || key.startsWith("nameserver") || key.startsWith("nserver")
    },
    HighlightSpec("Domain Status") { key ->
        key == "status" || key == "domainstatus" || key == "state" || key == "domainstate"
    },
    HighlightSpec("Registrant Organization") { key ->
        key.startsWith("registrantorganization") || key.startsWith("registrantorganisation") ||
            key == "registrantorg"
    }
)

private fun normalizeWhoisKey(key: String): String =
    key.lowercase(Locale.US).filter { it.isLetterOrDigit() }

/**
 * Returns the seven highlighted fields (in display order, empty values when
 * absent) plus every field that was not consumed by a highlight.
 */
private fun summarizeWhoisFields(
    fields: List<WhoisField>
): Pair<List<SummaryField>, List<WhoisField>> {
    val consumed = BooleanArray(fields.size)
    val summary = HIGHLIGHT_SPECS.map { spec ->
        val values = mutableListOf<String>()
        fields.forEachIndexed { index, field ->
            if (consumed[index]) return@forEachIndexed
            if (!spec.matches(normalizeWhoisKey(field.key))) return@forEachIndexed
            val value = field.value.trim()
            if (value.isEmpty()) return@forEachIndexed
            consumed[index] = true
            if (values.none { it.equals(value, ignoreCase = true) }) {
                values.add(value)
            }
        }
        SummaryField(spec.label, values)
    }
    val remaining = fields.filterIndexed { index, _ -> !consumed[index] }
    return summary to remaining
}
