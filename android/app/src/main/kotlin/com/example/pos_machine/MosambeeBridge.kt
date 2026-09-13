package com.example.pos_machine

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import net.mithqal.softpos.SoftPosBridgeCore

/** Display adapter; bank state, parsing and watchdogs live in the shared core. */
object MosambeeBridge {
    const val CHANNEL = SoftPosBridgeCore.CHANNEL
    private var channel: MethodChannel? = null
    private val core = SoftPosBridgeCore { activity, intent, code, stage ->
        activity.startActivityForResult(intent, code)
        channel?.invokeMethod("paymentLaunchState", mapOf(
            "stage" to stage, "launchSurface" to "front", "dispatched" to true))
    }
    fun configure(activity: Activity, channel: MethodChannel) {
        this.channel = channel
        core.configure(activity, channel)
    }
    fun handleActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        core.handleActivityResult(activity, requestCode, resultCode, data)
    fun cancelPendingOperation(): Boolean = core.cancelPendingOperation()
}
