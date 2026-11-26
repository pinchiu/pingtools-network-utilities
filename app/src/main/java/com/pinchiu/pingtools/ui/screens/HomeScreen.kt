package com.pinchiu.pingtools.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bluetooth
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Router
import androidx.compose.material.icons.outlined.SignalCellularAlt
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.pinchiu.pingtools.BuildConfig
import com.pinchiu.pingtools.core.model.ConnectionInfo
import com.pinchiu.pingtools.core.model.PublicIpInfo
import com.pinchiu.pingtools.core.net.IpInfoEngine
import com.pinchiu.pingtools.ui.ToolInfo
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.MonoText
import com.pinchiu.pingtools.ui.components.Pill
import com.pinchiu.pingtools.ui.components.PillTone
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(onOpenTool: (String) -> Unit, onOpenAbout: () -> Unit) {
    val context = LocalContext.current
    var connection by remember { mutableStateOf<ConnectionInfo?>(null) }
    var publicInfo by remember { mutableStateOf<PublicIpInfo?>(null) }
    var connectionLoading by remember { mutableStateOf(true) }
    var publicLoading by remember { mutableStateOf(true) }
    var refreshKey by remember { mutableIntStateOf(0) }

    LaunchedEffect(refreshKey) {
        connectionLoading = true
        publicLoading = true
        val local = try {
            withContext(Dispatchers.IO) {
                IpInfoEngine.connectionInfo(context)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            ConnectionInfo(connectionType = "Unknown")
        }
        connection = local
        connectionLoading = false

        if (local.connectionType == "Offline") {
            publicInfo = null
            publicLoading = false
        } else {
            val remote = try {
                IpInfoEngine.publicIp()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PublicIpInfo(
                    error = e.message?.trim().takeUnless { it.isNullOrEmpty() }
                        ?: "Network error"
                )
            }
            publicInfo = remote
            publicLoading = false
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        var seenFirstResume = false
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (seenFirstResume) {
                    refreshKey++
                } else {
                    seenFirstResume = true
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("PingTools", style = MaterialTheme.typography.titleLarge)
                        Text(
                            "Network utilities",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onOpenAbout) {
                        Icon(
                            Icons.Outlined.Info,
                            contentDescription = "About PingTools",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.onBackground
                )
            )
        }
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            HeroCard(
                connection = connection,
                publicInfo = publicInfo,
                connectionLoading = connectionLoading,
                publicLoading = publicLoading,
                onRefresh = { refreshKey++ }
            )

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel(count = Tools.all.size)
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Tools.all.chunked(2).forEach { rowTools ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .height(IntrinsicSize.Min),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            rowTools.forEach { tool ->
                                ToolCard(
                                    tool = tool,
                                    modifier = Modifier
                                        .weight(1f)
                                        .fillMaxHeight(),
                                    onClick = { onOpenTool(tool.route) }
                                )
                            }
                            if (rowTools.size == 1) {
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }

            Footer(onOpenAbout = onOpenAbout)
        }
    }
}

@Composable
private fun HeroCard(
    connection: ConnectionInfo?,
    publicInfo: PublicIpInfo?,
    connectionLoading: Boolean,
    publicLoading: Boolean,
    onRefresh: () -> Unit
) {
    val primary = MaterialTheme.colorScheme.primary
    val shape = RoundedCornerShape(20.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        primary.copy(alpha = 0.20f),
                        MaterialTheme.colorScheme.surfaceContainerHigh
                    )
                )
            )
            .border(1.dp, primary.copy(alpha = 0.28f), shape)
    ) {
        Column(
            Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(42.dp)
                        .background(primary.copy(alpha = 0.16f), RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        connectionIcon(connection?.connectionType),
                        contentDescription = null,
                        tint = primary,
                        modifier = Modifier.size(22.dp)
                    )
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        "CONNECTION",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        when {
                            connection != null -> connection.connectionType
                            connectionLoading -> "Checking…"
                            else -> "—"
                        },
                        style = MaterialTheme.typography.titleLarge
                    )
                }
                if (connection?.isVpn == true) {
                    Pill("VPN", PillTone.Info)
                    Spacer(Modifier.width(6.dp))
                }
                IconButton(onClick = onRefresh, enabled = !connectionLoading) {
                    if (connectionLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(
                            Icons.Outlined.Refresh,
                            contentDescription = "Refresh network status",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            HorizontalDivider(color = primary.copy(alpha = 0.15f))

            Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(
                        "LOCAL IPV4",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(3.dp))
                    MonoText(
                        connection?.localIpv4 ?: "—",
                        size = 16.sp,
                        weight = FontWeight.SemiBold
                    )
                }
                Column(Modifier.weight(1f)) {
                    Text(
                        "PUBLIC IP",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(3.dp))
                    MonoText(
                        publicInfo?.ip ?: "—",
                        size = 16.sp,
                        weight = FontWeight.SemiBold
                    )
                }
            }

            when {
                connection?.connectionType == "Offline" -> Text(
                    "Offline — connect to a network to see public details.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                publicInfo?.error != null -> Text(
                    "Public IP unavailable: ${publicInfo?.error}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                !publicInfo?.isp.isNullOrBlank() -> Text(
                    publicInfo?.isp.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                !publicInfo?.org.isNullOrBlank() -> Text(
                    publicInfo?.org.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                publicInfo?.city != null || publicInfo?.country != null -> Text(
                    listOfNotNull(publicInfo?.city, publicInfo?.country)
                        .filter { it.isNotBlank() }
                        .joinToString(", "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                publicLoading -> Text(
                    "Looking up public IP and ISP…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                publicInfo != null -> Text(
                    "Public IP details loaded. ISP not reported.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                else -> Text(
                    "Public IP details unavailable.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun SectionLabel(count: Int) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            "TOOLS",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.width(10.dp))
        HorizontalDivider(
            Modifier.weight(1f),
            color = MaterialTheme.colorScheme.outlineVariant
        )
        Spacer(Modifier.width(10.dp))
        Text(
            "$count utilities",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun ToolCard(
    tool: ToolInfo,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val shape = RoundedCornerShape(16.dp)
    OutlinedCard(
        modifier = modifier
            .clip(shape)
            .clickable(role = Role.Button, onClick = onClick),
        shape = shape,
        colors = CardDefaults.outlinedCardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.outlineVariant
        )
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(38.dp)
                        .background(tool.accent.copy(alpha = 0.15f), RoundedCornerShape(11.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        tool.icon,
                        contentDescription = null,
                        tint = tool.accent,
                        modifier = Modifier.size(20.dp)
                    )
                }
                Spacer(Modifier.weight(1f))
                tool.tag?.let { tag ->
                    Text(
                        tag,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier
                            .background(tool.accent.copy(alpha = 0.18f), RoundedCornerShape(50))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(
                tool.title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(3.dp))
            Text(
                tool.subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun Footer(onOpenAbout: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Spacer(Modifier.height(16.dp))
        Text(
            "PingTools ${BuildConfig.VERSION_NAME}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "No ads · No trackers · On-device",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        TextButton(onClick = onOpenAbout) {
            Text("About PingTools")
        }
    }
}

private fun connectionIcon(type: String?): ImageVector = when (type) {
    "Wi-Fi" -> Icons.Outlined.Wifi
    "Cellular" -> Icons.Outlined.SignalCellularAlt
    "Ethernet" -> Icons.Outlined.Lan
    "VPN" -> Icons.Outlined.VpnKey
    "Bluetooth" -> Icons.Outlined.Bluetooth
    "Offline" -> Icons.Outlined.WifiOff
    else -> Icons.Outlined.Router
}
