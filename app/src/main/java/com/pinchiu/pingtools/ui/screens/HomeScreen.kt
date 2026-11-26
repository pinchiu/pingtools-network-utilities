package com.pinchiu.pingtools.ui.screens

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Construction
import androidx.compose.runtime.Composable
import com.pinchiu.pingtools.ui.components.EmptyState
import com.pinchiu.pingtools.ui.components.ToolScaffold

@Composable
fun HomeScreen(onOpenTool: (String) -> Unit, onOpenAbout: () -> Unit) {
    ToolScaffold(title = "PingTools", onBack = onOpenAbout) {
        EmptyState(
            icon = Icons.Outlined.Construction,
            title = "Coming online",
            body = "The dashboard is being implemented."
        )
    }
}
