package com.pinchiu.pingtools.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.SettingsBrightness
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.content.Intent
import android.net.Uri
import com.pinchiu.pingtools.BuildConfig
import com.pinchiu.pingtools.ui.components.DataRow
import com.pinchiu.pingtools.ui.components.MonoText
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.ToolScaffold
import com.pinchiu.pingtools.ui.theme.AccentCyan

@Composable
fun AboutScreen(
    onBack: () -> Unit,
    themeMode: Int,
    onThemeModeChange: (Int) -> Unit
) {
    val context = LocalContext.current
    var showLicenses by remember { mutableStateOf(false) }

    ToolScaffold(title = "About", subtitle = "PingTools Network Utilities", onBack = onBack) {
        SectionCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Outlined.Info,
                    contentDescription = null,
                    tint = AccentCyan,
                    modifier = Modifier.width(28.dp)
                )
                Spacer(Modifier.width(12.dp))
                Column {
                    Text("PingTools", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Network Utilities · v${BuildConfig.VERSION_NAME}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                "A focused network toolkit: ping, geolocation, traceroute, port scanning, DNS, WHOIS, subnet discovery, Wake-on-LAN and HTTP inspection. No ads, no trackers, no account.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        SectionCard(title = "Appearance") {
            ThemeOption("Follow system", Icons.Outlined.SettingsBrightness, themeMode == 0) {
                onThemeModeChange(0)
            }
            ThemeOption("Light", Icons.Outlined.LightMode, themeMode == 1) {
                onThemeModeChange(1)
            }
            ThemeOption("Dark", Icons.Outlined.DarkMode, themeMode == 2) {
                onThemeModeChange(2)
            }
        }

        SectionCard(title = "How it works") {
            DataRow("ICMP", "Runs the system ping binary; falls back to TCP-connect timing when the kernel blocks raw ICMP for apps.")
            DataRow("Geo", "Public IP geolocation via ipwho.is, with ipapi.co as fallback. City-level accuracy only.")
            DataRow("DNS", "Queries are sent to the resolver you pick (or the system resolver).")
            DataRow("WHOIS", "Direct port-43 queries following IANA referrals.")
        }

        SectionCard(title = "Notes") {
            Text(
                "Some mobile carriers block ICMP or port 43. Results may vary by network. Use these tools only on networks and devices you are authorized to test.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        SectionCard(title = "Open source") {
            Text(
                "Source code, issues and releases live on GitHub.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            TextButton(onClick = {
                context.startActivity(
                    Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("https://github.com/pinchiu/pingtools-network-utilities")
                    )
                )
            }) {
                Icon(Icons.Outlined.Code, contentDescription = null, modifier = Modifier.width(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("pinchiu/pingtools-network-utilities")
            }
            TextButton(onClick = { showLicenses = true }) {
                Text("Third-party licenses")
            }
        }

        MonoText(
            "© 2026 PingTools contributors · Apache-2.0",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            size = 11.sp,
            modifier = Modifier.padding(vertical = 6.dp)
        )
    }

    if (showLicenses) {
        AlertDialog(
            onDismissRequest = { showLicenses = false },
            title = { Text("Licenses") },
            text = {
                Text(
                    "Jetpack Compose, AndroidX, Kotlin & Kotlin Coroutines — Apache 2.0\n" +
                        "OkHttp — Apache 2.0\n" +
                        "dnsjava — BSD 3-Clause\n" +
                        "Material Symbols — Apache 2.0",
                    style = MaterialTheme.typography.bodySmall
                )
            },
            confirmButton = {
                TextButton(onClick = { showLicenses = false }) { Text("Close") }
            }
        )
    }
}

@Composable
private fun ThemeOption(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onSelect: () -> Unit
) {
    Row(
        Modifier
            .fillMaxWidth()
            .selectable(selected = selected, onClick = onSelect, role = androidx.compose.ui.semantics.Role.RadioButton)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        RadioButton(selected = selected, onClick = onSelect)
    }
}
