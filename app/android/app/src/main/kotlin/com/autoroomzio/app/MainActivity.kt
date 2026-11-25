package com.autoroomzio.app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.autoroomzio.app/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPrimaryAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                else -> result.notImplemented()
            }
        }
    }
}
