package com.example.pos_machine

import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

object ManagerBiometricBridge {
    const val CHANNEL = "com.example.manager_biometrics"

    private var pendingResult: MethodChannel.Result? = null
    private var cancellationSignal: CancellationSignal? = null

    fun configure(activity: FlutterActivity, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "authenticate" -> {
                    val arguments = call.arguments as? Map<*, *>
                    authenticate(activity, arguments, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun authenticate(
        activity: FlutterActivity,
        arguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error(
                "UNAVAILABLE",
                "Biometric authentication requires Android 9 or newer.",
                null,
            )
            return
        }

        if (pendingResult != null) {
            result.error("BUSY", "A biometric prompt is already active.", null)
            return
        }

        val title = arguments?.get("title") as? String ?: "Manager Approval Required"
        val subtitle = arguments?.get("subtitle") as? String ?: ""
        val description = arguments?.get("description") as? String ?: "Place your fingerprint."
        val negativeButton = arguments?.get("negativeButton") as? String ?: "Cancel"

        val signal = CancellationSignal()
        pendingResult = result
        cancellationSignal = signal

        val prompt = BiometricPrompt.Builder(activity)
            .setTitle(title)
            .setDescription(description)
            .setNegativeButton(negativeButton, activity.mainExecutor) { _, _ ->
                complete(false)
            }
            .apply {
                if (subtitle.isNotBlank()) {
                    setSubtitle(subtitle)
                }
            }
            .build()

        prompt.authenticate(
            signal,
            activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                    complete(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    complete(false)
                }
            },
        )
    }

    @Synchronized
    private fun complete(success: Boolean) {
        val result = pendingResult ?: return
        pendingResult = null
        cancellationSignal = null
        result.success(success)
    }
}
