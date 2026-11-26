package com.pinchiu.pingtools.ui.screens

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Construction
import androidx.compose.runtime.Composable
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ToolScaffold

@Composable
fun HttpInspectorScreen(onBack: () -> Unit) {
    ToolScaffold(title = "HTTP Inspector", onBack = onBack) {
        EmptyState(
            icon = Icons.Outlined.Construction,
            title = "Coming online",
            body = "This tool screen is being implemented."
        )
    }
}
