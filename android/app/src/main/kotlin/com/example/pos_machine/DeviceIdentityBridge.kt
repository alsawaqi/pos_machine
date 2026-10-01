package com.example.pos_machine

import android.annotation.SuppressLint
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/**
 * LAUNCH-P1 decision 1a — tells the server which physical device is
 * activating, so an enrollment code only works on the device it was made for.
 *
 * Channel `mithqal/device_identity`:
 *  - `getHardwareSerial` → the serial printed on the device sticker, or null.
 *  - `getBuildInfo` → `{manufacturer, model}` from [Build].
 *
 * Values are trimmed only; the server normalises them. Every failure is a
 * null, never an exception: the server decides what an unreadable serial means.
 */
object DeviceIdentityBridge {
    const val CHANNEL = "mithqal/device_identity"

    fun configure(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareSerial" -> result.success(readSerial())
                "getBuildInfo" -> result.success(
                    mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Sunmi (T3) publishes the sticker serial as `ro.sunmi.serial`, readable
     * by ordinary apps. `ro.serialno` is the generic fallback where the
     * platform lets apps read it (it usually does not on Android 8+).
     */
    fun readSerial(): String? =
        systemProperty("ro.sunmi.serial") ?: systemProperty("ro.serialno")

    @SuppressLint("PrivateApi")
    private fun systemProperty(key: String): String? = runCatching {
        val get = Class.forName("android.os.SystemProperties")
            .getMethod("get", String::class.java)
        clean(get.invoke(null, key) as? String)
    }.getOrNull()

    private fun clean(value: String?): String? {
        val trimmed = value?.trim() ?: return null
        if (trimmed.isEmpty() || trimmed.equals(Build.UNKNOWN, ignoreCase = true)) {
            return null
        }
        return trimmed
    }
}
