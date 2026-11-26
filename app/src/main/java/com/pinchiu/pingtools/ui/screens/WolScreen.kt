package com.pinchiu.pingtools.ui.screens

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.PowerSettingsNew
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinchiu.pingtools.core.data.HistoryStore
import com.pinchiu.pingtools.core.model.WolDevice
import com.pinchiu.pingtools.core.net.WolEngine
import com.pinchiu.pingtools.core.util.isValidIpv4
import com.pinchiu.pingtools.core.util.normalizeMac
import com.pinchiu.pingtools.ui.Routes
import com.pinchiu.pingtools.ui.Tools
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ErrorBanner
import com.pinchiu.pingtools.ui.components.LabeledField
import com.pinchiu.pingtools.ui.components.MonoText
import com.pinchiu.pingtools.ui.components.PrimaryButton
import com.pinchiu.pingtools.ui.components.SecondaryButton
import com.pinchiu.pingtools.ui.components.SectionCard
import com.pinchiu.pingtools.ui.components.ToolScaffold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class WolMessage(val text: String, val success: Boolean)

data class WolUiState(
    val devices: List<WolDevice> = emptyList(),
    val name: String = "",
    val mac: String = "",
    val broadcast: String = "255.255.255.255",
    val port: String = "9",
    val saveDevice: Boolean = true,
    val sending: Boolean = false,
    val sendingMac: String? = null,
    val formError: String? = null,
    val message: WolMessage? = null
)

class WolViewModel(app: Application) : AndroidViewModel(app) {
    var ui by mutableStateOf(WolUiState())
        private set

    private var sendJob: Job? = null

    init {
        viewModelScope.launch { refreshDevices() }
    }

    fun updateName(value: String) {
        ui = ui.copy(name = value, formError = null)
    }

    fun updateMac(value: String) {
        ui = ui.copy(mac = value, formError = null)
    }

    fun updateBroadcast(value: String) {
        ui = ui.copy(broadcast = value, formError = null)
    }

    fun updatePort(value: String) {
        ui = ui.copy(port = value.filter { it.isDigit() }.take(5), formError = null)
    }

    fun setSaveDevice(value: Boolean) {
        ui = ui.copy(saveDevice = value, formError = null)
    }

    fun sendForm() {
        if (ui.sending) return

        val save = ui.saveDevice
        val name = ui.name.trim()
        if (save && name.isEmpty()) {
            ui = ui.copy(formError = "Enter a device name")
            return
        }
        val mac = normalizeMac(ui.mac)
        if (mac == null) {
            ui = ui.copy(formError = "Enter a valid MAC address, for example AA:BB:CC:DD:EE:FF")
            return
        }
        val broadcast = ui.broadcast.trim()
        if (broadcast.isEmpty()) {
            ui = ui.copy(formError = "Enter a broadcast address")
            return
        }
        if (broadcast.all { it.isDigit() || it == '.' } && !isValidIpv4(broadcast)) {
            ui = ui.copy(formError = "Enter a valid IPv4 broadcast address or hostname")
            return
        }
        val port = ui.port.trim().toIntOrNull()
        if (port == null || port !in 1..65535) {
            ui = ui.copy(formError = "Port must be between 1 and 65535")
            return
        }

        ui = ui.copy(mac = mac, port = port.toString(), formError = null)
        val deviceToSave = if (save) {
            WolDevice(name = name, mac = mac, broadcast = broadcast, port = port)
        } else {
            null
        }
        performSend(mac = mac, broadcast = broadcast, port = port, deviceToSave = deviceToSave)
    }

    fun sendSaved(device: WolDevice) {
        if (ui.sending) return
        performSend(
            mac = device.mac,
            broadcast = device.broadcast,
            port = device.port,
            deviceToSave = null
        )
    }

    fun deleteDevice(device: WolDevice) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                HistoryStore.removeDevice(getApplication(), device.mac)
            }
            refreshDevices()
        }
    }

    fun consumeMessage() {
        ui = ui.copy(message = null)
    }

    private fun performSend(
        mac: String,
        broadcast: String,
        port: Int,
        deviceToSave: WolDevice?
    ) {
        sendJob?.cancel()
        ui = ui.copy(
            sending = true,
            sendingMac = mac,
            formError = null,
            message = null
        )
        sendJob = viewModelScope.launch {
            try {
                if (deviceToSave != null) {
                    withContext(Dispatchers.IO) {
                        HistoryStore.saveDevice(getApplication(), deviceToSave)
                    }
                    refreshDevices()
                }

                val result = WolEngine.wake(mac = mac, broadcast = broadcast, port = port)
                result.fold(
                    onSuccess = { outcome ->
                        ui = ui.copy(
                            sending = false,
                            sendingMac = null,
                            message = WolMessage(
                                text = "Sent ${outcome.packetsSent} magic packets to " +
                                    "${outcome.mac} via ${outcome.address}:${outcome.port}",
                                success = true
                            )
                        )
                    },
                    onFailure = { error ->
                        ui = ui.copy(
                            sending = false,
                            sendingMac = null,
                            message = WolMessage(
                                text = error.message?.trim().takeUnless { it.isNullOrEmpty() }
                                    ?: "Could not send the magic packet",
                                success = false
                            )
                        )
                    }
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                ui = ui.copy(
                    sending = false,
                    sendingMac = null,
                    message = WolMessage(
                        text = e.message?.trim().takeUnless { it.isNullOrEmpty() }
                            ?: "Could not send the magic packet",
                        success = false
                    )
                )
            }
        }
    }

    private suspend fun refreshDevices() {
        val devices = withContext(Dispatchers.IO) {
            HistoryStore.savedDevices(getApplication())
        }
        ui = ui.copy(devices = devices)
    }

    fun stop() {
        sendJob?.cancel()
    }

    override fun onCleared() {
        stop()
        super.onCleared()
    }
}

@Composable
fun WolScreen(onBack: () -> Unit) {
    val vm: WolViewModel = viewModel()
    val ui = vm.ui
    val accent = Tools.byRoute(Routes.WOL)?.accent ?: MaterialTheme.colorScheme.primary
    val snackbarHostState = remember { SnackbarHostState() }

    BackHandler {
        vm.stop()
        onBack()
    }
    DisposableEffect(Unit) {
        onDispose { vm.stop() }
    }

    LaunchedEffect(ui.message) {
        val message = ui.message ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(
            message = message.text,
            duration = if (message.success) SnackbarDuration.Short else SnackbarDuration.Long
        )
        vm.consumeMessage()
    }

    Box(Modifier.fillMaxSize()) {
        ToolScaffold(
            title = "Wake-on-LAN",
            subtitle = "Wake a device with a magic packet",
            onBack = onBack
        ) {
            IntroCard(accent = accent)

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "SAVED DEVICES",
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
                        "${ui.devices.size}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (ui.devices.isEmpty()) {
                    SectionCard {
                        EmptyState(
                            icon = Icons.Outlined.PowerSettingsNew,
                            title = "No saved devices",
                            body = "Add a device below to save it and send its first magic packet."
                        )
                    }
                } else {
                    ui.devices.forEach { device ->
                        DeviceCard(
                            device = device,
                            accent = accent,
                            sending = ui.sending,
                            sendingMac = ui.sendingMac,
                            onSend = { vm.sendSaved(device) },
                            onDelete = { vm.deleteDevice(device) }
                        )
                    }
                }
            }

            SectionCard(title = "Add a device") {
                LabeledField(
                    label = "Device name",
                    value = ui.name,
                    onValueChange = vm::updateName,
                    placeholder = "Living room PC",
                    enabled = !ui.sending
                )
                LabeledField(
                    label = "MAC address",
                    value = ui.mac,
                    onValueChange = vm::updateMac,
                    placeholder = "AA:BB:CC:DD:EE:FF",
                    enabled = !ui.sending
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    LabeledField(
                        label = "Broadcast",
                        value = ui.broadcast,
                        onValueChange = vm::updateBroadcast,
                        modifier = Modifier.weight(1.5f),
                        placeholder = "255.255.255.255",
                        enabled = !ui.sending,
                        keyboardType = KeyboardType.Uri
                    )
                    LabeledField(
                        label = "Port",
                        value = ui.port,
                        onValueChange = vm::updatePort,
                        modifier = Modifier.weight(0.8f),
                        placeholder = "9",
                        enabled = !ui.sending,
                        keyboardType = KeyboardType.Number
                    )
                }

                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { vm.setSaveDevice(!ui.saveDevice) }
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Save this device", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Keep it in the list for one-tap wake-ups",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = ui.saveDevice,
                        onCheckedChange = { vm.setSaveDevice(it) },
                        enabled = !ui.sending
                    )
                }

                ui.formError?.let { ErrorBanner(it) }

                PrimaryButton(
                    text = if (ui.saveDevice) "Save & wake" else "Send magic packet",
                    onClick = vm::sendForm,
                    modifier = Modifier.fillMaxWidth(),
                    loading = ui.sending,
                    icon = Icons.Outlined.PowerSettingsNew
                )
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(16.dp)
        )
    }
}

@Composable
private fun IntroCard(accent: Color) {
    SectionCard {
        Row(verticalAlignment = Alignment.Top) {
            Box(
                Modifier
                    .size(40.dp)
                    .background(accent.copy(alpha = 0.15f), RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Outlined.PowerSettingsNew,
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(22.dp)
                )
            }
            Spacer(Modifier.width(12.dp))
            Column {
                Text("Wake a sleeping device", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(2.dp))
                Text(
                    "The target must be on the same LAN with Wake-on-LAN enabled in its firmware " +
                        "and operating system. Wired Ethernet works best; Wi-Fi wake usually needs " +
                        "extra support.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Text(
            "Three magic packets are sent over UDP broadcast. Sending succeeds even if the " +
                "target is off — this app cannot confirm that the device actually woke.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun DeviceCard(
    device: WolDevice,
    accent: Color,
    sending: Boolean,
    sendingMac: String?,
    onSend: () -> Unit,
    onDelete: () -> Unit
) {
    val isSending = sending && sendingMac.equals(device.mac, ignoreCase = true)
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.outlinedCardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    ) {
        Column(
            Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(38.dp)
                        .background(accent.copy(alpha = 0.15f), RoundedCornerShape(10.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Outlined.PowerSettingsNew,
                        contentDescription = null,
                        tint = accent,
                        modifier = Modifier.size(19.dp)
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(device.name, style = MaterialTheme.typography.titleSmall)
                    MonoText(
                        device.mac,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        size = 12.sp
                    )
                    Text(
                        "UDP ${device.broadcast}:${device.port}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                IconButton(onClick = onDelete, enabled = !sending) {
                    Icon(
                        Icons.Outlined.DeleteOutline,
                        contentDescription = "Delete ${device.name}",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(19.dp)
                    )
                }
            }
            SecondaryButton(
                text = if (isSending) "Sending magic packet…" else "Wake device",
                onClick = onSend,
                modifier = Modifier.fillMaxWidth(),
                enabled = !sending,
                icon = Icons.Outlined.PowerSettingsNew
            )
        }
    }
}
