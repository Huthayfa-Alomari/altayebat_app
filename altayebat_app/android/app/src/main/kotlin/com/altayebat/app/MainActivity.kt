package com.altayebat.app

import android.content.Intent
import android.os.Build
import com.sunmi.peripheral.printer.InnerPrinterCallback
import com.sunmi.peripheral.printer.InnerPrinterManager
import com.sunmi.peripheral.printer.SunmiPrinterService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DRIVER_CHANNEL = "com.altayebat.app/driver_deep_link"
        private const val SUNMI_CHANNEL = "com.altayebat.app/sunmi_printer"
    }

    private var driverChannel: MethodChannel? = null
    private var sunmiChannel: MethodChannel? = null
    private var pendingInitialLink: String? = null
    private var printerService: SunmiPrinterService? = null

    private val printerCallback = object : InnerPrinterCallback() {
        override fun onConnected(service: SunmiPrinterService) {
            printerService = service
        }

        override fun onDisconnected() {
            printerService = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (pendingInitialLink == null) {
            pendingInitialLink = intent?.dataString
        }

        driverChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DRIVER_CHANNEL
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

        bindSunmiPrinter()
        sunmiChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SUNMI_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSunmiDevice" -> result.success(isSunmiDevice())
                    "isPrinterReady" -> result.success(printerService != null)
                    "printerInfo" -> result.success(printerInfo())
                    "printReceipt" -> {
                        val receipt = call.argument<String>("receipt")?.trim().orEmpty()
                        val qr = call.argument<String>("qr")?.trim().orEmpty()
                        if (receipt.isEmpty()) {
                            result.error("INVALID_RECEIPT", "Receipt is empty", null)
                        } else {
                            try {
                                printReceipt(receipt, qr)
                                result.success(true)
                            } catch (error: Exception) {
                                result.error("PRINT_FAILED", error.message ?: "Printing failed", null)
                            }
                        }
                    }
                    "printTest" -> {
                        try {
                            printReceipt("أسواق الطيبات\nSUNMI printer ready\n", "")
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("PRINT_FAILED", error.message ?: "Printing failed", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun isSunmiDevice(): Boolean {
        val maker = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase()
        return maker.contains("sunmi") || printerService != null
    }

    private fun bindSunmiPrinter() {
        try {
            InnerPrinterManager.getInstance().bindService(this, printerCallback)
        } catch (_: Exception) {
            printerService = null
        }
    }

    private fun printerInfo(): Map<String, Any?> {
        val service = printerService
        if (service == null) {
            return mapOf(
                "ready" to false,
                "sunmi" to isSunmiDevice(),
                "manufacturer" to Build.MANUFACTURER,
                "device" to Build.MODEL,
            )
        }

        return try {
            mapOf(
                "ready" to true,
                "sunmi" to true,
                "manufacturer" to Build.MANUFACTURER,
                "device" to Build.MODEL,
                "printerModel" to service.printerModal,
                "printerVersion" to service.printerVersion,
                "serial" to service.printerSerialNo,
                "paper" to if (service.printerPaper == 1) "58mm" else "80mm",
            )
        } catch (_: Exception) {
            mapOf(
                "ready" to true,
                "sunmi" to true,
                "manufacturer" to Build.MANUFACTURER,
                "device" to Build.MODEL,
            )
        }
    }

    private fun printReceipt(receipt: String, qr: String) {
        val service = printerService
            ?: throw IllegalStateException("SUNMI printer service is not connected")

        service.printerInit(null)
        service.setAlignment(2, null)
        service.printTextWithFont(receipt + "\n", null, 24f, null)

        if (qr.isNotEmpty()) {
            service.setAlignment(1, null)
            service.printQRCode(qr, 5, 1, null)
            service.printText("\n", null)
        }

        service.lineWrap(4, null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val link = intent.dataString ?: return
        val channel = driverChannel

        if (channel != null) {
            channel.invokeMethod("onDeepLink", link)
        } else {
            pendingInitialLink = link
        }
    }

    override fun onDestroy() {
        driverChannel?.setMethodCallHandler(null)
        driverChannel = null
        sunmiChannel?.setMethodCallHandler(null)
        sunmiChannel = null

        try {
            InnerPrinterManager.getInstance().unBindService(this, printerCallback)
        } catch (_: Exception) {
            // The printer may never have bound (for example on a normal phone).
        }
        printerService = null
        super.onDestroy()
    }
}
