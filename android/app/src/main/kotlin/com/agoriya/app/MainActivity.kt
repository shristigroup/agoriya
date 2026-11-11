package com.agoriya.app

import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Hosts the "oem" channel used by OemSettingsService (Dart):
 *  - openSettings(kind)  open the OEM's autostart / battery screen
 *  - backgroundState()   read-only background-restriction signals
 *
 * Android exposes no API to READ whether OEM autostart is enabled, so the
 * app can only open the right screen and ask the user to confirm. The
 * component names below are the commonly documented ones per vendor; each is
 * tried in order and any that doesn't exist on this firmware is skipped, with
 * the app's own details page as the last resort.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.agoriya.app/oem")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "manufacturer" -> result.success(Build.MANUFACTURER.lowercase(Locale.ROOT))
                    "openSettings" -> result.success(openSettings(call.argument<String>("kind") ?: "autostart"))
                    "backgroundState" -> result.success(backgroundState())
                    else -> result.notImplemented()
                }
            }
    }

    private fun component(pkg: String, cls: String) =
        Intent().setComponent(ComponentName(pkg, cls))

    private fun autostartIntents(): List<Intent> {
        return when (Build.MANUFACTURER.lowercase(Locale.ROOT)) {
            "xiaomi", "redmi", "poco" -> listOf(
                component("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
                component("com.miui.securitycenter", "com.miui.powercenter.PowerSettings"),
            )
            "oppo", "realme", "oneplus" -> listOf(
                component("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
                component("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
                component("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
                component("com.coloros.safe", "com.coloros.safe.permission.startup.StartupAppListActivity"),
                component("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
            )
            "vivo", "iqoo" -> listOf(
                component("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
                component("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
                component("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
            )
            "huawei", "honor" -> listOf(
                component("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                component("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
                component("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"),
                component("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                component("com.hihonor.systemmanager", "com.hihonor.systemmanager.optimize.process.ProtectActivity"),
            )
            "samsung" -> listOf(
                component("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"),
                component("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity"),
                component("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
            )
            "infinix", "tecno", "itel" -> listOf(
                component("com.transsion.phonemaster", "com.cyin.himgr.autostart.AutoStartActivity"),
            )
            else -> emptyList()
        }
    }

    /** Xiaomi/HyperOS per-app "Battery saver" screen (the "No restrictions" setting). */
    private fun miuiBatterySaverIntent(): Intent =
        component("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")
            .putExtra("package_name", packageName)
            .putExtra("package_label", applicationInfo.loadLabel(packageManager).toString())

    private fun tryStart(intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    } catch (e: Exception) {
        // ActivityNotFoundException, SecurityException (non-exported component)…
        false
    }

    /** Returns "opened" (a vendor screen), "fallback" (our app-details page) or "failed". */
    private fun openSettings(kind: String): String {
        val candidates = if (kind == "battery") listOf(miuiBatterySaverIntent()) else autostartIntents()
        for (intent in candidates) {
            if (tryStart(intent)) return "opened"
        }
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        return if (tryStart(details)) "fallback" else "failed"
    }

    /** Read-only signals; each is null when unavailable on this Android version. */
    private fun backgroundState(): Map<String, Any?> {
        var restricted: Boolean? = null
        var bucket: Int? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                restricted = am.isBackgroundRestricted
            } catch (e: Exception) { }
            try {
                val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                bucket = usm.appStandbyBucket
            } catch (e: Exception) { }
        }
        return mapOf("backgroundRestricted" to restricted, "standbyBucket" to bucket)
    }
}
