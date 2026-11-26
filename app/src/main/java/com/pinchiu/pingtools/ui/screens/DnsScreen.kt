package com.pinchiu.pingtools.ui.screens

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.DnsRecord
import com.pinchiu.pingtools.core.model.DnsResult
import com.pinchiu.pingtools.core.model.DnsType
import com.pinchiu.pingtools.core.net.DnsEngine
import com.pinchiu.pingtools.core.util.formatDuration
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.KeyValueChip
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

data class DnsUiState(
    val query: String = "example.com",
    val type: DnsType = DnsType.A,
    val resolverIndex: Int = 0,
    val loading: Boolean = false,
    val result: DnsResult? = null,
    val error: String? = null,
    val history: List<String> = emptyList()
)

class DnsViewModel(app: Application) : AndroidViewModel(app) {

    var ui by mutableStateOf(
        DnsUiState(history = HistoryStore.recent(app, "dns", 6))
    )
        private set

    private var job: Job? = null

    fun setQuery(value: String) {
        ui = ui.copy(query = value, error = null)
    }

    fun setType(type: DnsType) {
        ui = ui.copy(type = type)
    }

    fun setResolverIndex(index: Int) {
        ui = ui.copy(resolverIndex = index.coerceIn(0, DnsEngine.RESOLVERS.lastIndex))
    }

    fun useHistory(value: String) {
        ui = ui.copy(query = value, error = null)
    }

    fun lookup() = runQuery(reverse = false)

    fun reverse() = runQuery(reverse = true)

    private fun runQuery(reverse: Boolean) {
        val query = ui.query.trim()
        if (query.isEmpty()) {
            ui = ui.copy(error = "Enter a domain name or IP address")
            return
        }
        if (reverse && !isIpLiteral(query)) {
            ui = ui.copy(error = "Reverse PTR needs an IPv4 or IPv6 address")
            return
        }

        val index = ui.resolverIndex.coerceIn(0, DnsEngine.RESOLVERS.lastIndex)
        val resolverAddress = DnsEngine.RESOLVERS[index].second
        val resolverLabel = DnsEngine.RESOLVERS[index].first
        val type = if (reverse) DnsType.PTR else ui.type

        job?.cancel()
        ui = ui.copy(loading = true, error = null, type = type)
        job = viewModelScope.launch {
            val result = try {
                if (reverse) {
                    DnsEngine.reverse(query, resolverAddress)
                } else {
                    DnsEngine.lookup(query, type, resolverAddress)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                DnsResult(
                    query = query,
                    type = type,
                    resolver = resolverLabel,
                    error = e.message?.takeUnless { it.isBlank() } ?: "DNS lookup failed"
                )
            }

            val app = getApplication<Application>()
            HistoryStore.add(app, "dns", query)
            ui = ui.copy(
                loading = false,
                result = result,
                error = result.error,
                history = HistoryStore.recent(app, "dns", 6)
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
fun DnsScreen(onBack: () -> Unit) {
    val vm: DnsViewModel = viewModel()
    val ui = vm.ui
    val accent = Tools.byRoute(Routes.DNS)?.accent ?: MaterialTheme.colorScheme.primary
    val clipboard = LocalClipboardManager.current
    val ipMode = isIpLiteral(ui.query)
    val resolverLabel = DnsEngine.RESOLVERS
        .getOrNull(ui.resolverIndex)
        ?.first
        ?: DnsEngine.RESOLVERS.first().first

    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }
    BackHandler(enabled = ui.loading) { vm.stop() }

    ToolScaffold(
        title = "DNS Lookup",
        subtitle = "Records from the resolver you choose",
        onBack = onBack
    ) {
        SectionCard(title = "Query") {
            LabeledField(
                label = "Name or IP address",
                value = ui.query,
                onValueChange = vm::setQuery,
                placeholder = "example.com",
                enabled = !ui.loading,
                keyboardType = KeyboardType.Uri
            )

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SelectField(
                    label = "Record type",
                    selectedLabel = ui.type.name,
                    options = DnsType.values().map { SelectOption(it.name) },
                    enabled = !ui.loading,
                    modifier = Modifier.weight(1f),
                    onSelect = { index ->
                        DnsType.values().getOrNull(index)?.let(vm::setType)
                    }
                )
                SelectField(
                    label = "Resolver",
                    selectedLabel = resolverLabel,
                    options = DnsEngine.RESOLVERS.map { (label, address) ->
                        SelectOption(
                            label = label,
                            detail = if (address == "system") "Device default" else address
                        )
                    },
                    enabled = !ui.loading,
                    modifier = Modifier.weight(1f),
                    onSelect = vm::setResolverIndex
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                PrimaryButton(
                    text = "Lookup",
                    onClick = vm::lookup,
                    modifier = Modifier.weight(1f),
                    enabled = !ui.loading,
                    loading = ui.loading,
                    icon = Icons.Outlined.Search
                )
                SecondaryButton(
                    text = "Reverse PTR",
                    onClick = vm::reverse,
                    modifier = Modifier.weight(1f),
                    enabled = !ui.loading && ipMode,
                    icon = Icons.Outlined.SwapVert
                )
            }

            Text(
                "Reverse PTR resolves an IP address to its hostname.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
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
                        Text(
                            "Querying ${ui.type.name} records",
                            style = MaterialTheme.typography.titleSmall
                        )
                        Text(
                            "Waiting for the $resolverLabel resolver…",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        val result = ui.result
        if (result != null && !ui.loading) {
            SectionCard(title = "Response") {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    KeyValueChip("Query", result.query.ifBlank { "--" })
                    KeyValueChip("Type", result.type.name)
                    KeyValueChip("Resolver", result.resolver.ifBlank { "--" })
                    KeyValueChip("Duration", formatDuration(result.durationMs))
                    KeyValueChip("Records", result.records.size.toString())
                }

                when {
                    result.records.isNotEmpty() -> RecordsTable(result.records, accent)
                    result.error == null -> EmptyState(
                        icon = Icons.Outlined.Dns,
                        title = "No ${result.type.name} records",
                        body = "The resolver answered for ${result.query} but returned no ${result.type.name} records."
                    )
                    else -> Text(
                        "No records were returned for this query.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        if (!ui.loading && result == null) {
            SectionCard {
                EmptyState(
                    icon = Icons.Outlined.Dns,
                    title = "Ready to resolve",
                    body = "Pick a record type and resolver, then run a lookup. Every row shows its TTL and has a copy action."
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Records table
// ---------------------------------------------------------------------------

@Composable
private fun RecordsTable(records: List<DnsRecord>, accent: Color) {
    val clipboard = LocalClipboardManager.current
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "TYPE",
                modifier = Modifier.width(56.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                "VALUE",
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                "TTL",
                modifier = Modifier.width(38.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End
            )
            Spacer(Modifier.width(48.dp))
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        records.forEach { record ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 7.dp),
                verticalAlignment = Alignment.Top
            ) {
                Box(
                    Modifier
                        .width(56.dp)
                        .padding(end = 6.dp)
                ) {
                    Pill(record.type, PillTone.Info)
                }
                MonoText(
                    text = record.value,
                    modifier = Modifier.weight(1f),
                    size = 12.sp
                )
                Text(
                    text = record.ttl?.let { "${it}s" } ?: "--",
                    modifier = Modifier
                        .width(38.dp)
                        .padding(start = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.End
                )
                IconButton(
                    onClick = { clipboard.setText(AnnotatedString(record.value)) },
                    modifier = Modifier.size(40.dp)
                ) {
                    Icon(
                        Icons.Outlined.ContentCopy,
                        contentDescription = "Copy ${record.type} record",
                        modifier = Modifier.size(15.dp),
                        tint = accent
                    )
                }
            }
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Dropdown selector
// ---------------------------------------------------------------------------

private data class SelectOption(val label: String, val detail: String? = null)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SelectField(
    label: String,
    selectedLabel: String,
    options: List<SelectOption>,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onSelect: (Int) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Column(modifier) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(6.dp))
        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { if (enabled) expanded = !expanded }
        ) {
            OutlinedTextField(
                value = selectedLabel,
                onValueChange = {},
                modifier = Modifier
                    .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                    .fillMaxWidth(),
                readOnly = true,
                enabled = enabled,
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge,
                trailingIcon = {
                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
                },
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh
                )
            )
            ExposedDropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                options.forEachIndexed { index, option ->
                    DropdownMenuItem(
                        text = {
                            Column {
                                Text(option.label)
                                if (option.detail != null) {
                                    Text(
                                        option.detail,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        },
                        onClick = {
                            onSelect(index)
                            expanded = false
                        },
                        contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

private fun isIpLiteral(value: String): Boolean {
    val cleaned = value.trim()
        .removeSurrounding("[", "]")
        .substringBefore('%')
    if (isValidIpv4(cleaned)) return true
    if (!cleaned.contains(':')) return false
    return cleaned.count { it == ':' } >= 2 && cleaned.all { ch ->
        ch.isDigit() || ch.lowercaseChar() in 'a'..'f' || ch == ':' || ch == '.'
    }
}
