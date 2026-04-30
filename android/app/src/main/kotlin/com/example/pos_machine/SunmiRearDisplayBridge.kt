package com.example.pos_machine

import android.content.Context
import android.content.Intent
import android.graphics.Point
import android.hardware.display.DisplayManager
import android.util.Log
import android.view.Display

object SunmiRearDisplayBridge {
    private const val TAG = "SunmiRearDisplay"
    private const val SUNMI_DISPLAY_PREFIX = "Sunmi-USBDisplay-"
    private const val SUNMI_USB_SCREEN_PACKAGE = "com.sunmi.usbscreen"
    private const val ACTION_SET_CONTROL = "com.sunmi.usbscreen.ACTION_SET_CONTROL"
    private const val EXTRA_SN = "sn"
    private const val EXTRA_TYPE = "type"
    private const val EXTRA_KEY = "key"
    private const val EXTRA_VALUE = "value"
    private const val EXTRA_STR = "str"
    private const val TYPE_DISPLAY_CONTROL = 1
    private const val KEY_SCREEN_SWITCH = 2
    private const val KEY_TOUCH_SWITCH = 7
    private const val VALUE_ENABLED = 1

    fun listPresentationDisplays(displayManager: DisplayManager): List<Map<String, Any>> =
        candidateDisplays(displayManager).map { candidate ->
            val display = candidate.display
            buildMap {
                put("displayId", display.displayId)
                put("name", display.name)
                put("flags", display.flags)
                put("rotation", display.rotation)
                put("isDefaultDisplay", display.displayId == Display.DEFAULT_DISPLAY)
                put("isPresentationCategory", candidate.isPresentationCategory)

                val serial = extractSerial(display)
                if (!serial.isNullOrBlank()) {
                    put("serial", serial)
                }

                val size = Point()
                @Suppress("DEPRECATION")
                display.getRealSize(size)
                put("width", size.x)
                put("height", size.y)

                put("isSunmiUsbDisplay", isSunmiUsbDisplay(display))
            }
        }

    fun prepareDisplay(
        context: Context,
        displayManager: DisplayManager,
        requestedDisplayId: Int?,
    ): Map<String, Any> {
        val display = resolveDisplay(
            displayManager = displayManager,
            requestedDisplayId = requestedDisplayId,
            preferredSerial = null,
        ) ?: return mapOf(
            "prepared" to false,
            "reason" to "no_non_default_display",
        )

        val serial = extractSerial(display)
        val isSunmiDisplay = !serial.isNullOrBlank()

        if (!isSunmiDisplay) {
            return mapOf(
                "prepared" to false,
                "displayId" to display.displayId,
                "isSunmiUsbDisplay" to false,
                "reason" to "non_sunmi_display",
            )
        }

        sendControl(context, serial, KEY_SCREEN_SWITCH, VALUE_ENABLED)
        sendControl(context, serial, KEY_TOUCH_SWITCH, VALUE_ENABLED)

        val resolvedDisplay = resolveDisplay(
            displayManager = displayManager,
            requestedDisplayId = display.displayId,
            preferredSerial = serial,
        )

        return buildMap {
            put("prepared", true)
            put("serial", serial)
            put("displayId", resolvedDisplay?.displayId ?: display.displayId)
            put("isSunmiUsbDisplay", true)
        }
    }

    fun resolveDisplay(
        displayManager: DisplayManager,
        requestedDisplayId: Int?,
        preferredSerial: String?,
    ): Display? {
        val candidates = candidateDisplays(displayManager).map { it.display }

        if (!preferredSerial.isNullOrBlank()) {
            candidates.firstOrNull { extractSerial(it) == preferredSerial }?.let { return it }
        }

        if (requestedDisplayId != null && requestedDisplayId != Display.DEFAULT_DISPLAY) {
            candidates.firstOrNull { it.displayId == requestedDisplayId }?.let { return it }
        }

        return candidates.firstOrNull()
    }

    fun extractSerial(display: Display): String? {
        val name = display.name ?: return null
        if (!name.startsWith(SUNMI_DISPLAY_PREFIX)) {
            return null
        }

        return name.removePrefix(SUNMI_DISPLAY_PREFIX).trim().ifBlank { null }
    }

    private fun isSunmiUsbDisplay(display: Display): Boolean = extractSerial(display) != null

    private data class DisplayCandidate(
        val display: Display,
        val isPresentationCategory: Boolean,
    )

    /**
     * SUNMI firmware variants do not always expose the customer-facing screen through
     * DISPLAY_CATEGORY_PRESENTATION on the first query. Prefer true presentation displays,
     * but fall back to every non-default display so the rear screen is not left in mirror mode.
     */
    private fun candidateDisplays(displayManager: DisplayManager): List<DisplayCandidate> {
        val candidatesById = linkedMapOf<Int, DisplayCandidate>()

        val presentationDisplays = sortDisplays(
            displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
                .filter { it.displayId != Display.DEFAULT_DISPLAY }
                .toTypedArray(),
        )
        for (display in presentationDisplays) {
            candidatesById[display.displayId] = DisplayCandidate(
                display = display,
                isPresentationCategory = true,
            )
        }

        val otherDisplays = sortDisplays(
            displayManager.getDisplays()
                .filter { it.displayId != Display.DEFAULT_DISPLAY }
                .toTypedArray(),
        )
        for (display in otherDisplays) {
            candidatesById.putIfAbsent(
                display.displayId,
                DisplayCandidate(
                    display = display,
                    isPresentationCategory = false,
                ),
            )
        }

        return candidatesById.values.toList()
    }

    private fun sortDisplays(displays: Array<Display>): List<Display> =
        displays.sortedWith(
            compareByDescending<Display> { isSunmiUsbDisplay(it) }
                .thenByDescending { it.displayId },
        )

    private fun sendControl(
        context: Context,
        serial: String,
        key: Int,
        value: Int,
    ) {
        val intent = Intent(ACTION_SET_CONTROL).apply {
            setPackage(SUNMI_USB_SCREEN_PACKAGE)
            addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            putExtra(EXTRA_SN, serial)
            putExtra(EXTRA_TYPE, TYPE_DISPLAY_CONTROL)
            putExtra(EXTRA_KEY, key)
            putExtra(EXTRA_VALUE, value)
            putExtra(EXTRA_STR, "")
        }

        try {
            context.sendBroadcast(intent)
            Log.i(TAG, "Sent Sunmi rear-display control key=$key value=$value serial=$serial")
        } catch (error: Exception) {
            Log.w(TAG, "Unable to send Sunmi rear-display control", error)
        }
    }
}
