package com.example.pos_machine

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
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

    /**
     * The 10.1" USB customer panel (SUNMI NP521) is a separate USB-HID touch device whose touches
     * the firmware delivers to the MAIN display (this Activity), scaled — so a customer tap lands on
     * the staff UI. We can't re-associate it to the customer display (system-only permission), so
     * instead we intercept those events here by hardware id, consume them (so the staff UI does NOT
     * react), and forward normalized coordinates to the customer Flutter engine, which replays them
     * as a tap on the customer screen. Real staff touches (different input device) pass through.
     */
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (RearDisplayHost.hasActiveRearDisplay() && isCustomerPanelEvent(event)) {
            forwardCustomerTouch(event)
            return true
        }
        return super.dispatchTouchEvent(event)
    }

    private fun isCustomerPanelEvent(event: MotionEvent): Boolean {
        val device = event.device ?: return false
        val isTouchscreen =
            (device.sources and InputDevice.SOURCE_TOUCHSCREEN) == InputDevice.SOURCE_TOUCHSCREEN
        if (!isTouchscreen) return false
        return device.vendorId == SUNMI_CUSTOMER_TOUCH_VENDOR_ID ||
            device.name == SUNMI_CUSTOMER_TOUCH_DEVICE_NAME
    }

    private fun forwardCustomerTouch(event: MotionEvent) {
        val action = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> "down"
            MotionEvent.ACTION_MOVE -> "move"
            MotionEvent.ACTION_UP -> "up"
            MotionEvent.ACTION_CANCEL -> "cancel"
            else -> return
        }

        val width: Float
        val height: Float
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            width = bounds.width().toFloat()
            height = bounds.height().toFloat()
        } else {
            val metrics = resources.displayMetrics
            width = metrics.widthPixels.toFloat()
            height = metrics.heightPixels.toFloat()
        }

        val nx = (event.rawX / width.coerceAtLeast(1f)).coerceIn(0f, 1f)
        val ny = (event.rawY / height.coerceAtLeast(1f)).coerceIn(0f, 1f)

        val forwarded = RearDisplayHost.forwardTouchToRear(action, nx.toDouble(), ny.toDouble())
        if (action == "down" || action == "up") {
            Log.i(
                "CustomerTouch",
                "intercepted action=$action raw=(${event.rawX},${event.rawY}) norm=($nx,$ny) forwarded=$forwarded",
            )
        }
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

        // SUNMI NP521 = the 10.1" USB customer-display touch panel (vendor 0x324f).
        private const val SUNMI_CUSTOMER_TOUCH_VENDOR_ID = 0x324f
        private const val SUNMI_CUSTOMER_TOUCH_DEVICE_NAME = "SUNMI NP521"
    }
}
