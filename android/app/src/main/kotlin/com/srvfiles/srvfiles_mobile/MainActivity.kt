package com.srvfiles.srvfiles_mobile

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.srvfiles/disk_space"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFreeDiskSpace" -> {
                    try {
                        val stat = StatFs(filesDir.absolutePath)
                        val freeMb = stat.availableBlocksLong * stat.blockSizeLong / (1024.0 * 1024.0)
                        result.success(freeMb)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", e.message, null)
                    }
                }
                "getTotalDiskSpace" -> {
                    try {
                        val stat = StatFs(filesDir.absolutePath)
                        val totalMb = stat.blockCountLong * stat.blockSizeLong / (1024.0 * 1024.0)
                        result.success(totalMb)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
