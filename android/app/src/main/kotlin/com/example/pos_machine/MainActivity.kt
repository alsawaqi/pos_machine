package com.example.pos_machine

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RearDisplayHost.attachFrontBinaryMessenger(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RearDisplayHost.HOST_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPresentationDisplays" -> {
                    result.success(RearDisplayHost.listPresentationDisplays(this))
                }

                "openRearDisplay" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val displayId = (arguments?.get("displayId") as? Number)?.toInt()
                    val engineId = arguments?.get("engineId") as? String

                    if (displayId == null || engineId.isNullOrBlank()) {
                        result.error(
                            "INVALID_ARGS",
                            "displayId and engineId are required.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    result.success(
                        RearDisplayHost.openRearDisplay(
                            activity = this,
                            displayId = displayId,
                            engineId = engineId
                        )
                    )
                }

                "hideRearDisplay" -> {
                    result.success(RearDisplayHost.hideRearDisplay())
                }

                "transferDataToRear" -> {
                    result.success(RearDisplayHost.transferDataToRear(call.arguments))
                }

                else -> result.notImplemented()
            }
        }

        MosambeeBridge.configure(
            activity = this,
            channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                MosambeeBridge.CHANNEL,
            ),
        )
    }

    @Deprecated("Uses the legacy startActivityForResult payment flow.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (MosambeeBridge.handleActivityResult(this, requestCode, resultCode, data)) {
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }
}
