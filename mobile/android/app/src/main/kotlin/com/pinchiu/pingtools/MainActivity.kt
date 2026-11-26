package com.pinchiu.pingtools

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connectionInfo" -> result.success(
                        ConnectionInfoHelper.collect(applicationContext)
                    )
                    "appVersion" -> result.success(
                        ConnectionInfoHelper.appVersion(applicationContext)
                    )
                    "requestWifiPermissions" -> requestWifiPermissions(result)
                    "openUrl" -> openUrl(call.argument<String>("url"), result)
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestWifiPermissions(result: MethodChannel.Result) {
        val permissions = buildList {
            add(android.Manifest.permission.ACCESS_FINE_LOCATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(android.Manifest.permission.NEARBY_WIFI_DEVICES)
            }
        }.toTypedArray()

        val allGranted = permissions.all {
            checkSelfPermission(it) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) {
            result.success(true)
            return
        }

        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        try {
            requestPermissions(permissions, WIFI_PERMISSION_REQUEST)
        } catch (_: Exception) {
            pendingPermissionResult = null
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == WIFI_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun openUrl(url: String?, result: MethodChannel.Result) {
        if (url.isNullOrBlank()) {
            result.success(false)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.success(mapOf("status" to "error", "message" to "Missing APK path"))
            return
        }
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            result.success(mapOf("status" to "error", "message" to "APK file not found"))
            return
        }

        if (!canInstallPackages()) {
            openUnknownSourcesSettings()
            result.success(
                mapOf(
                    "status" to "permissionRequired",
                    "message" to "Allow PingTools to install unknown apps, then retry."
                )
            )
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(mapOf("status" to "launched"))
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to (e.message ?: "Could not start the installer")
                )
            )
        }
    }

    private fun openUnknownSourcesSettings() {
        val intents = listOf(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ),
            Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (_: Exception) {
                // Try the next settings screen.
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.pinchiu.pingtools/native"
        private const val WIFI_PERMISSION_REQUEST = 4101
    }
}
