package com.pinchiu.pingtools.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.pinchiu.pingtools.ui.screens.AboutScreen
import com.pinchiu.pingtools.ui.screens.ConnectionInfoScreen
import com.pinchiu.pingtools.ui.screens.DnsScreen
import com.pinchiu.pingtools.ui.screens.GeoPingScreen
import com.pinchiu.pingtools.ui.screens.HomeScreen
import com.pinchiu.pingtools.ui.screens.HttpInspectorScreen
import com.pinchiu.pingtools.ui.screens.PingScreen
import com.pinchiu.pingtools.ui.screens.PortScannerScreen
import com.pinchiu.pingtools.ui.screens.SubnetScannerScreen
import com.pinchiu.pingtools.ui.screens.TraceScreen
import com.pinchiu.pingtools.ui.screens.WhoisScreen
import com.pinchiu.pingtools.ui.screens.WolScreen
import com.pinchiu.pingtools.ui.theme.PingToolsTheme
import com.pinchiu.pingtools.ui.theme.ThemeStore

@Composable
fun PingToolsApp() {
    val context = LocalContext.current
    var themeMode by remember { mutableStateOf(ThemeStore.read(context)) }
    val darkTheme = when (themeMode) {
        1 -> false
        2 -> true
        else -> isSystemInDarkTheme()
    }

    PingToolsTheme(darkTheme = darkTheme) {
        val navController = rememberNavController()
        NavHost(navController = navController, startDestination = Routes.HOME) {
            composable(Routes.HOME) {
                HomeScreen(
                    onOpenTool = { route -> navController.navigate(route) },
                    onOpenAbout = { navController.navigate(Routes.ABOUT) }
                )
            }
            composable(Routes.PING) {
                PingScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.GEO_PING) {
                GeoPingScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.TRACE) {
                TraceScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.PORTS) {
                PortScannerScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.DNS) {
                DnsScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.WHOIS) {
                WhoisScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.SUBNET) {
                SubnetScannerScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.WOL) {
                WolScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.CONNECTION) {
                ConnectionInfoScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.HTTP) {
                HttpInspectorScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.ABOUT) {
                AboutScreen(
                    onBack = { navController.popBackStack() },
                    themeMode = themeMode,
                    onThemeModeChange = { mode ->
                        themeMode = mode
                        ThemeStore.write(context, mode)
                    }
                )
            }
        }
    }
}
