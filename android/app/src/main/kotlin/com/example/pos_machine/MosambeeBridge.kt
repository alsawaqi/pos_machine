package com.example.pos_machine

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

object MosambeeBridge {
    const val CHANNEL = "com.example.mosambee"

    private const val TAG = "MosambeeBridge"
    private const val ACTION_LOGIN = "com.mosambee.softpos.login"
    private const val ACTION_PAYMENT = "com.mosambee.softpos.payment"
    private const val LOGIN_REQUEST_CODE = 5101
    private const val PAYMENT_REQUEST_CODE = 5102

    // Same AES key used by the working charity app integration.
    private const val PASSWORD_TOKEN_AES_KEY_HEX =
        "C9DDC0BB57179060D9F2E01BE71D65C71D222A063F4DDA858FDC467B173BD146"

    private var pendingResult: MethodChannel.Result? = null
    private var paymentRequestData: Map<String, Any?>? = null
    private var launchSurface: String = "front"
    private var flutterChannel: MethodChannel? = null

    fun configure(activity: Activity, channel: MethodChannel) {
        flutterChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "loginAndPay" -> handleLoginAndPay(activity, call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
    }

    fun handleActivityResult(
        activity: Activity,
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        return when (requestCode) {
            LOGIN_REQUEST_CODE -> {
                handleLoginResult(activity, resultCode, data)
                true
            }

            PAYMENT_REQUEST_CODE -> {
                handlePaymentResult(resultCode, data)
                true
            }

            else -> false
        }
    }

    private fun handleLoginAndPay(
        activity: Activity,
        arguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        val args = arguments ?: run {
            result.error("BAD_ARGS", "Arguments must be a map", null)
            return
        }

        if (pendingResult != null) {
            result.error("BUSY", "A transaction is already in progress", null)
            return
        }

        val packageName = args["packageName"]?.toString()?.trim().orEmpty()
        val userName = args["userName"]?.toString()?.trim().orEmpty()
        val partnerId = args["partnerId"]?.toString()?.trim().orEmpty()
        val pin = args["pin"]?.toString()
        val passwordFromDart = args["password"]?.toString()

        if (packageName.isEmpty() || userName.isEmpty()) {
            result.error("BAD_ARGS", "packageName and userName are required", null)
            return
        }

        val passwordToken = when {
            !pin.isNullOrBlank() -> generatePasswordToken(userName, pin)
            !passwordFromDart.isNullOrBlank() -> passwordFromDart
            else -> {
                result.error(
                    "BAD_ARGS",
                    "Either pin or password(token) must be provided",
                    null,
                )
                return
            }
        }

        val loginIntent = Intent().apply {
            setPackage(packageName)
            action = ACTION_LOGIN
            putExtra("userName", userName)
            putExtra("password", passwordToken)
            if (partnerId.isNotEmpty()) {
                putExtra("partnerId", partnerId)
            }
        }

        pendingResult = result
        paymentRequestData = args.entries.associate { (key, value) ->
            key.toString() to value
        }

        try {
            // The charity prompt should only change the amount. Keep the actual
            // Mosambee launch on the same direct activity flow that already
            // works for ordinary card payments.
            launchSurface = startForResultOnPreferredDisplay(
                activity = activity,
                intent = loginIntent,
                requestCode = LOGIN_REQUEST_CODE,
            )
            notifyLaunchState(stage = "login_started", surface = launchSurface)
            Log.i(TAG, "Started Mosambee login on $launchSurface display")
        } catch (error: ActivityNotFoundException) {
            deliverAndReset(
                JSONObject()
                    .put("stage", "login")
                    .put("status", "failed")
                    .put("message", "Mosambee application is not installed.")
                    .put("error", error.toString())
                    .put("launchSurface", launchSurface)
                    .toString(),
            )
        } catch (error: Exception) {
            deliverAndReset(
                JSONObject()
                    .put("stage", "login")
                    .put("status", "failed")
                    .put("message", "Unable to launch Mosambee login.")
                    .put("error", error.toString())
                    .put("launchSurface", launchSurface)
                    .toString(),
            )
        }
    }

    fun completeFromRearProxy(payload: String) {
        deliverAndReset(payload)
    }

    fun notifyLaunchState(
        stage: String,
        surface: String,
        detail: String? = null,
    ) {
        try {
            flutterChannel?.invokeMethod(
                "paymentLaunchState",
                mapOf(
                    "stage" to stage,
                    "surface" to surface,
                    "detail" to detail,
                ),
            )
            Log.i(TAG, "Sent payment launch state: stage=$stage surface=$surface")
        } catch (error: Exception) {
            Log.w(TAG, "Unable to send payment launch state to Flutter", error)
        }
    }

    private fun handleLoginResult(
        activity: Activity,
        resultCode: Int,
        data: Intent?,
    ) {
        val sessionId = data?.getStringExtra("sessionId")?.trim().orEmpty()

        if (sessionId.isEmpty()) {
            val status = if (resultCode == Activity.RESULT_CANCELED) {
                "canceled"
            } else {
                "failed"
            }
            val message = if (status == "canceled") {
                "Payment login was canceled."
            } else {
                "Payment login failed."
            }

            deliverAndReset(
                JSONObject()
                    .put("stage", "login")
                    .put("status", status)
                    .put("message", message)
                    .put("resultCode", resultCode)
                    .put("launchSurface", launchSurface)
                    .toString(),
            )
            return
        }

        val args = paymentRequestData ?: run {
            deliverAndReset(
                JSONObject()
                    .put("stage", "login")
                    .put("status", "failed")
                    .put("message", "Missing pending payment request.")
                    .put("launchSurface", launchSurface)
                    .toString(),
            )
            return
        }

        val packageName = args["packageName"]?.toString()?.trim().orEmpty()
        val amount = args["amount"]?.toString()?.trim().orEmpty()
        val mobNo = args["mobNo"]?.toString()?.trim().orEmpty()
        val description = args["description"]?.toString()?.trim().orEmpty()

        val paymentIntent = Intent().apply {
            setPackage(packageName)
            action = ACTION_PAYMENT
            putExtra("sessionId", sessionId)
            putExtra("amount", amount)
            if (mobNo.isNotEmpty()) {
                putExtra("mobNo", mobNo)
            }
            if (description.isNotEmpty()) {
                putExtra("description", description)
            }
        }

        try {
            launchSurface = startForResultOnPreferredDisplay(
                activity = activity,
                intent = paymentIntent,
                requestCode = PAYMENT_REQUEST_CODE,
            )
            notifyLaunchState(stage = "payment_started", surface = launchSurface)
            Log.i(TAG, "Started Mosambee payment on $launchSurface display")
        } catch (error: ActivityNotFoundException) {
            deliverAndReset(
                JSONObject()
                    .put("stage", "payment")
                    .put("status", "failed")
                    .put("message", "Mosambee payment activity was not found.")
                    .put("error", error.toString())
                    .put("launchSurface", launchSurface)
                    .toString(),
            )
        } catch (error: Exception) {
            deliverAndReset(
                JSONObject()
                    .put("stage", "payment")
                    .put("status", "failed")
                    .put("message", "Unable to launch Mosambee payment.")
                    .put("error", error.toString())
                    .put("launchSurface", launchSurface)
                    .toString(),
            )
        }
    }

    private fun handlePaymentResult(resultCode: Int, data: Intent?) {
        val receiptString = data?.getStringExtra("receiptResponse") ?: "{}"
        val paymentResponseCode = data?.getStringExtra("paymentResponseCode")?.trim().orEmpty()
        val paymentDescription = data?.getStringExtra("paymentDescription")?.trim().orEmpty()

        val receiptJson = try {
            JSONObject(receiptString)
        } catch (error: Exception) {
            JSONObject().put("raw", receiptString)
        }

        val receiptResponseCode = receiptJson.optString("responseCode", "").trim()
        val receiptResult = receiptJson.optString("result", "").trim().lowercase()
        val normalizedCode = paymentResponseCode.ifEmpty { receiptResponseCode }

        val isSuccess =
            normalizedCode == "0" ||
                normalizedCode == "00" ||
                receiptResult == "success"
        val isCanceled =
            resultCode == Activity.RESULT_CANCELED &&
                !isSuccess &&
                (paymentDescription.contains("cancel", ignoreCase = true) ||
                    paymentDescription.isBlank())

        val status = when {
            isSuccess -> "success"
            isCanceled -> "canceled"
            else -> "failed"
        }

        val message = when {
            paymentDescription.isNotBlank() -> paymentDescription
            isSuccess -> "Payment approved."
            isCanceled -> "Payment was canceled."
            else -> "Payment failed."
        }

        deliverAndReset(
            JSONObject()
                .put("stage", "payment")
                .put("status", status)
                .put("message", message)
                .put("paymentResponseCode", normalizedCode)
                .put("paymentDescription", paymentDescription)
                .put("receiptResponse", receiptJson)
                .put("resultCode", resultCode)
                .put("launchSurface", launchSurface)
                .toString(),
        )
    }

    private fun startForResultOnPreferredDisplay(
        activity: Activity,
        intent: Intent,
        requestCode: Int,
    ): String {
        // Bank Dhofar SoftPOS is installed and its intent actions resolve
        // correctly on this device, but Android denies cross-display launches
        // when we request launchDisplayId for the rear presentation screen.
        // Use the default activity launch path so the existing payment flow
        // keeps working after the charity prompt.
        activity.startActivityForResult(intent, requestCode)
        return "front"
    }

    private fun deliverAndReset(payload: String) {
        pendingResult?.success(payload)
        pendingResult = null
        paymentRequestData = null
        launchSurface = "front"
    }

    private fun generatePasswordToken(userName: String, pin: String): String {
        val pinHash = sha256Hex(pin)
        val userHash = sha256Hex(userName)
        val token = xorHex(pinHash, userHash)
        return aesEncryptAppendIvHex(PASSWORD_TOKEN_AES_KEY_HEX, token)
    }

    private fun sha256Hex(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return digest.joinToString(separator = "") { "%02x".format(it) }
    }

    private fun xorHex(left: String, right: String): String {
        val leftBytes = hexToBytes(left)
        val rightBytes = hexToBytes(right)
        val output = ByteArray(leftBytes.size)

        for (index in leftBytes.indices) {
            output[index] = (leftBytes[index].toInt() xor rightBytes[index].toInt()).toByte()
        }

        return bytesToHexUpper(output)
    }

    private fun aesEncryptAppendIvHex(keyHex: String, value: String): String {
        val keyBytes = hexToBytes(keyHex)
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        val iv = ByteArray(cipher.blockSize)
        SecureRandom().nextBytes(iv)

        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(keyBytes, "AES"),
            IvParameterSpec(iv),
        )

        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return bytesToHexUpper(encrypted) + bytesToHexUpper(iv)
    }

    private fun hexToBytes(hex: String): ByteArray {
        val cleanHex = hex.trim()
        val output = ByteArray(cleanHex.length / 2)
        var index = 0

        while (index < cleanHex.length) {
            output[index / 2] = cleanHex.substring(index, index + 2).toInt(16).toByte()
            index += 2
        }

        return output
    }

    private fun bytesToHexUpper(bytes: ByteArray): String =
        bytes.joinToString(separator = "") { "%02X".format(it) }
}
