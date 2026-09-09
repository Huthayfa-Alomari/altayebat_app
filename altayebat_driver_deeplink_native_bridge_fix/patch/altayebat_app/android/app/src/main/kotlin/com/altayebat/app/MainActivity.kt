package com.altayebat.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.altayebat.app/driver_deep_link"
    }

    private var methodChannel: MethodChannel? = null
    private var pendingInitialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (pendingInitialLink == null) {
            pendingInitialLink = intent?.dataString
        }

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        val link = pendingInitialLink ?: intent?.dataString
                        pendingInitialLink = null
                        result.success(link)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val link = intent.dataString ?: return
        val channel = methodChannel

        if (channel != null) {
            channel.invokeMethod("onDeepLink", link)
        } else {
            pendingInitialLink = link
        }
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }
}
