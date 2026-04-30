package com.example.pos_machine

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.util.Log
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class RearPaymentProxyActivity : Activity() {
    private var flowStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (savedInstanceState == null) {
            startLoginFlow()
        } else {
            flowStarted = true
        }
    }

    @Deprecated("Uses the legacy startActivityForResult payment flow.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            LOGIN_REQUEST_CODE -> handleLoginResult(resultCode, data)
            PAYMENT_REQUEST_CODE -> handlePaymentResult(resultCode, data)
        }
    }

    private fun startLoginFlow() {
        if (flowStarted) return
        flowStarted = true

        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME)?.trim().orEmpty()
        val userName = intent.getStringExtra(EXTRA_USER_NAME)?.trim().orEmpty()
        val partnerId = intent.getStringExtra(EXTRA_PARTNER_ID)?.trim().orEmpty()
        val pin = intent.getStringExtra(EXTRA_PIN)?.trim().orEmpty()
        val password = intent.getStringExtra(EXTRA_PASSWORD)?.trim().orEmpty()

        if (packageName.isEmpty() || userName.isEmpty()) {
            deliverAndFinish(
                JSONObject()
                    .put("stage", "login")
                    .put("status", "failed")
                    .put("message", "Missing package name or terminal ID for rear payment.")
                    .put("launchSurface", "rear")
                    .toString(),
            )
            return
        }

        val passwordToken = when {
            pin.isNotEmpty() -> generatePasswordToken(userName, pin)
            password.isNotEmpty() -> password
            else -> {
                deliverAndFinish(
                    JSONObject()
                        .put("stage", "login")
                        .put("status", "failed")
                        .put("message", "Missing Mosambee login PIN.")
                        .put("launchSurface", "rear")
                        .toString(),
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

        try {
            startActivityForResult(loginIntent, LOGIN_REQUEST_CODE)
            MosambeeBridge.notifyLaunchState(
                stage = "login_started",
                surface = "rear",
            )
            Log.i(TAG, "Started Mosambee login from rear proxy activity")
        } catch (error: ActivityNotFoundException) {
            deliverAndFinish(
                JSONObject()
                    .put("stage", "login")
                    .put("status", "failed")
                    .put("message", "Mosambee application is not installed.")
                    .put("error", error.toString())
                    .put("launchSurface", "rear")
                    .toString(),
            )
        } catch (error: Exception) {
            deliverAndFinish(
                JSONObject()
                    .put("stage", "login")
                    .put("status", "failed")
                    .put("message", "Unable to launch Mosambee on the rear display.")
                    .put("error", error.toString())
                    .put("launchSurface", "rear")
                    .toString(),
            )
        }
    }

    private fun handleLoginResult(resultCode: Int, data: Intent?) {
        val sessionId = data?.getStringExtra("sessionId")?.trim().orEmpty()

        if (sessionId.isEmpty()) {
            val status = if (resultCode == RESULT_CANCELED) "canceled" else "failed"
            val message = if (status == "canceled") {
                "Payment login was canceled."
            } else {
                "Payment login failed."
            }

            deliverAndFinish(
                JSONObject()
                    .put("stage", "login")
                    .put("status", status)
                    .put("message", message)
                    .put("resultCode", resultCode)
                    .put("launchSurface", "rear")
                    .toString(),
            )
            return
        }

        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME)?.trim().orEmpty()
        val amount = intent.getStringExtra(EXTRA_AMOUNT)?.trim().orEmpty()
        val mobNo = intent.getStringExtra(EXTRA_MOB_NO)?.trim().orEmpty()
        val description = intent.getStringExtra(EXTRA_DESCRIPTION)?.trim().orEmpty()

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
            startActivityForResult(paymentIntent, PAYMENT_REQUEST_CODE)
            MosambeeBridge.notifyLaunchState(
                stage = "payment_started",
                surface = "rear",
            )
            Log.i(TAG, "Started Mosambee payment from rear proxy activity")
        } catch (error: ActivityNotFoundException) {
            deliverAndFinish(
                JSONObject()
                    .put("stage", "payment")
                    .put("status", "failed")
                    .put("message", "Mosambee payment activity was not found.")
                    .put("error", error.toString())
                    .put("launchSurface", "rear")
                    .toString(),
            )
        } catch (error: Exception) {
            deliverAndFinish(
                JSONObject()
                    .put("stage", "payment")
                    .put("status", "failed")
                    .put("message", "Unable to continue payment on the rear display.")
                    .put("error", error.toString())
                    .put("launchSurface", "rear")
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
            resultCode == RESULT_CANCELED &&
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

        deliverAndFinish(
            JSONObject()
                .put("stage", "payment")
                .put("status", status)
                .put("message", message)
                .put("paymentResponseCode", normalizedCode)
                .put("paymentDescription", paymentDescription)
                .put("receiptResponse", receiptJson)
                .put("resultCode", resultCode)
                .put("launchSurface", "rear")
                .toString(),
        )
    }

    private fun deliverAndFinish(payload: String) {
        MosambeeBridge.completeFromProxy(payload)
        finish()
        overridePendingTransition(0, 0)
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

    companion object {
        private const val TAG = "RearPaymentProxy"
        private const val ACTION_LOGIN = "com.mosambee.softpos.login"
        private const val ACTION_PAYMENT = "com.mosambee.softpos.payment"
        private const val LOGIN_REQUEST_CODE = 6101
        private const val PAYMENT_REQUEST_CODE = 6102
        private const val PASSWORD_TOKEN_AES_KEY_HEX =
            "C9DDC0BB57179060D9F2E01BE71D65C71D222A063F4DDA858FDC467B173BD146"

        const val EXTRA_PACKAGE_NAME = "packageName"
        const val EXTRA_USER_NAME = "userName"
        const val EXTRA_PARTNER_ID = "partnerId"
        const val EXTRA_PIN = "pin"
        const val EXTRA_PASSWORD = "password"
        const val EXTRA_AMOUNT = "amount"
        const val EXTRA_MOB_NO = "mobNo"
        const val EXTRA_DESCRIPTION = "description"
    }
}
