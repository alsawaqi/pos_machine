package com.example.pos_machine

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val softPosRuntimePermissions = arrayOf(
        Manifest.permission.CAMERA,
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.READ_PHONE_STATE,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestSoftPosRuntimePermissions()
    }

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

                "prepareRearDisplay" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val displayId = (arguments?.get("displayId") as? Number)?.toInt()

                    result.success(
                        RearDisplayHost.prepareRearDisplay(
                            activity = this,
                            displayId = displayId,
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

        ManagerBiometricBridge.configure(
            activity = this,
            channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                ManagerBiometricBridge.CHANNEL,
            ),
        )
    }

    private fun requestSoftPosRuntimePermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        val missingPermissions = softPosRuntimePermissions.filter { permission ->
            checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED
        }

        if (missingPermissions.isNotEmpty()) {
            requestPermissions(missingPermissions.toTypedArray(), SOFTPOS_PERMISSION_REQUEST_CODE)
        }
    }

    @Deprecated("Uses the legacy startActivityForResult payment flow.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (MosambeeBridge.handleActivityResult(this, requestCode, resultCode, data)) {
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val SOFTPOS_PERMISSION_REQUEST_CODE = 6201
    }
}
