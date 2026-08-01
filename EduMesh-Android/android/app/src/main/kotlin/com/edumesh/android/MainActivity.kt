package com.edumesh.android

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.edumesh.android/storage"
    private val ICON_CHANNEL = "com.edumesh.android/app_icon"

    // Held for the app's lifetime so mDNS multicast packets reach the app.
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifi.createMulticastLock("edumesh_mdns")
        lock.setReferenceCounted(true)
        lock.acquire()
        multicastLock = lock
    }

    override fun onDestroy() {
        super.onDestroy()
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Storage info channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getStorageInfo") {
                val path = Environment.getDataDirectory()
                val stat = StatFs(path.path)
                val blockSize = stat.blockSizeLong
                val totalBlocks = stat.blockCountLong
                val availableBlocks = stat.availableBlocksLong

                val apkFile = java.io.File(applicationInfo.sourceDir)
                val apkSize = if (apkFile.exists()) apkFile.length() else 0L

                val storageInfo = mapOf(
                    "totalBytes" to totalBlocks * blockSize,
                    "availableBytes" to availableBlocks * blockSize,
                    "apkSize" to apkSize
                )
                result.success(storageInfo)
            } else {
                result.notImplemented()
            }
        }

        // App icon switching channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ICON_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAppIcon" -> {
                    val useDark = call.argument<Boolean>("useDark") ?: false
                    setAppIcon(useDark)
                    result.success(true)
                }
                "isDarkIcon" -> {
                    val pm = packageManager
                    val state = pm.getComponentEnabledSetting(
                        ComponentName(this, "$packageName.MainActivityDark")
                    )
                    result.success(state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setAppIcon(useDark: Boolean) {
        val pm = packageManager
        val main = ComponentName(this, "$packageName.MainActivity")
        val dark = ComponentName(this, "$packageName.MainActivityDark")

        if (useDark) {
            pm.setComponentEnabledSetting(main, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            pm.setComponentEnabledSetting(dark, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        } else {
            pm.setComponentEnabledSetting(dark, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            pm.setComponentEnabledSetting(main, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        }
    }
}
