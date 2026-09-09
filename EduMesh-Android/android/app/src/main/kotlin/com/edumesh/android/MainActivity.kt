package com.edumesh.android

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.edumesh.android/storage"
    private val ICON_CHANNEL = "com.edumesh.android/app_icon"
    private val PIP_CHANNEL = "com.edumesh.android/pip"
    private var pipMethodChannel: MethodChannel? = null

    private val PIP_ACTION = "com.edumesh.android.PIP_ACTION"
    private val PIP_REQUEST_PLAY_PAUSE = 0
    private val PIP_REQUEST_FORWARD = 1

    private var pipActionReceiver: BroadcastReceiver? = null

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifi.createMulticastLock("edumesh_mdns")
        lock.setReferenceCounted(true)
        lock.acquire()
        multicastLock = lock

        pipActionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val action = intent.getStringExtra("action") ?: return
                pipMethodChannel?.invokeMethod("onPiPAction", action)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipActionReceiver, IntentFilter(PIP_ACTION), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipActionReceiver, IntentFilter(PIP_ACTION))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        pipActionReceiver?.let { unregisterReceiver(it) }
        pipActionReceiver = null
        pipMethodChannel = null
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        pipMethodChannel?.invokeMethod("onPiPModeChanged", isInPictureInPictureMode)
    }

    private fun buildPipParams(width: Int, height: Int, isPlaying: Boolean): PictureInPictureParams {
        val playPauseIcon = Icon.createWithResource(
            this,
            if (isPlaying) R.drawable.ic_pip_pause else R.drawable.ic_pip_play
        )
        val playPauseIntent = Intent(PIP_ACTION)
            .setPackage(packageName)
            .putExtra("action", "play_pause")
        val playPauseAction = RemoteAction(
            playPauseIcon,
            if (isPlaying) "Pause" else "Play",
            if (isPlaying) "Pause video" else "Play video",
            PendingIntent.getBroadcast(
                this, PIP_REQUEST_PLAY_PAUSE, playPauseIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        val forwardIntent = Intent(PIP_ACTION)
            .setPackage(packageName)
            .putExtra("action", "forward")
        val forwardAction = RemoteAction(
            Icon.createWithResource(this, R.drawable.ic_pip_forward),
            "Forward 10s",
            "Forward 10 seconds",
            PendingIntent.getBroadcast(
                this, PIP_REQUEST_FORWARD, forwardIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(width, height))
            .setActions(listOf(playPauseAction, forwardAction))
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setAutoEnterEnabled(false)
                }
            }
            .build()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPiP" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val width = call.argument<Int>("width") ?: 16
                        val height = call.argument<Int>("height") ?: 9
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                        val params = buildPipParams(width, height, isPlaying)
                        result.success(enterPictureInPictureMode(params))
                    } else {
                        @Suppress("DEPRECATION")
                        result.success(enterPictureInPictureMode())
                    }
                }
                "updatePiPActions" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val width = call.argument<Int>("width") ?: 16
                        val height = call.argument<Int>("height") ?: 9
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                        val params = buildPipParams(width, height, isPlaying)
                        setPictureInPictureParams(params)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "exitPiP" -> result.success(true)
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getStorageInfo") {
                val path = Environment.getDataDirectory()
                val stat = StatFs(path.path)
                val blockSize = stat.blockSizeLong
                val totalBlocks = stat.blockCountLong
                val availableBlocks = stat.availableBlocksLong
                val apkFile = java.io.File(applicationInfo.sourceDir)
                val apkSize = if (apkFile.exists()) apkFile.length() else 0L
                result.success(mapOf(
                    "totalBytes" to totalBlocks * blockSize,
                    "availableBytes" to availableBlocks * blockSize,
                    "apkSize" to apkSize
                ))
            } else {
                result.notImplemented()
            }
        }

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
