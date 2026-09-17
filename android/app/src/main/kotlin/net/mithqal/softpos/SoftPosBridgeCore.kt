package net.mithqal.softpos

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Shared bank protocol. App adapters own display routing; only this core owns operations. */
class SoftPosBridgeCore(
    private val launch: (Activity, Intent, Int, String) -> Unit =
        { activity, intent, requestCode, _ -> activity.startActivityForResult(intent, requestCode) },
) {
    companion object {
        const val CHANNEL = "com.example.mosambee"
        private const val ACTIVITY_RESULT_WATCHDOG_MS = 90_000L
        private const val SESSION_TTL_MS = 5 * 60_000L
        private const val PASSWORD_TOKEN_AES_KEY_HEX =
            "C9DDC0BB57179060D9F2E01BE71D65C71D222A063F4DDA858FDC467B173BD146"
    }

    private var result: MethodChannel.Result? = null
    private var owner: Activity? = null
    private var requestCode: Int? = null
    private var stage = ""
    private var operation = ""
    private var args: Map<String, Any?> = emptyMap()
    private var retryCount = 0
    private var paymentDispatched = false
    private var preparedSession: String? = null
    private var preparedAt = 0L
    private var preparedIdentity = ""
    private var nextCode = 20_000
    private val retired = mutableSetOf<Int>()
    private val handler = Handler(Looper.getMainLooper())
    private var watchdog: Runnable? = null

    fun configure(activity: Activity, channel: MethodChannel) {
        if (result != null && owner !== activity) cancelPendingOperation()
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "hasPreparedSession" -> reply.success(freshSession() != null)
                "clearPreparedSession" -> { clearSession(); reply.success(true) }
                "cancelPendingOperation", "cancelPendingPayment" -> reply.success(cancelPendingOperation())
                "prepareLogin", "payWithPreparedSession", "loginAndPay",
                "voidTransaction", "refundTransaction", "healthCheck" -> {
                    if (result != null) {
                        reply.error("BUSY", "A bank operation is already in progress", null)
                    } else {
                        val input = call.arguments as? Map<*, *>
                        if (input == null) {
                            reply.error("BAD_ARGS", "Arguments must be a map", null)
                        } else {
                            args = input.entries.associate { it.key.toString() to it.value }
                            result = reply
                            owner = activity
                            retryCount = 0
                            paymentDispatched = false
                            operation = when (call.method) {
                                "prepareLogin" -> "login"
                                "voidTransaction" -> "void"
                                "refundTransaction" -> "refund"
                                "healthCheck" -> "healthcheck"
                                else -> "payment"
                            }
                            val identity = identity(args)
                            if (identity != preparedIdentity) clearSession()
                            when (call.method) {
                                "healthCheck" -> startHealth(activity)
                                "prepareLogin" -> {
                                    val session = freshSession()
                                    if (session != null) complete(json("login", "approved")
                                        .put("responseCode", "00").put("sessionId", session).put("sessionReady", true))
                                    else startLogin(activity)
                                }
                                "loginAndPay" -> { clearSession(); startLogin(activity) }
                                else -> {
                                    val needsSession = operation == "payment" || args["needsSession"] == true
                                    val session = if (needsSession) {
                                        val fresh = freshSession().orEmpty()
                                        val supplied = args.text("sessionId")
                                        if (supplied.isEmpty() || supplied == fresh) fresh else ""
                                    } else ""
                                    clearSession()
                                    if (needsSession && session.isEmpty()) {
                                        complete(json(operation, "uncertain").put("code", "NO_SESSION")
                                            .put("dispatchFailed", true))
                                    } else startOperation(activity, session)
                                }
                            }
                        }
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }

    private fun identity(input: Map<String, Any?>): String =
        sha256Hex(input.text("packageName") + "\u0000" + input.text("userName") + "\u0000" + input.text("pin"))

    private fun clearSession() { preparedSession = null; preparedAt = 0; preparedIdentity = "" }
    private fun freshSession(): String? {
        if (android.os.SystemClock.elapsedRealtime() - preparedAt >= SESSION_TTL_MS) clearSession()
        return preparedSession
    }

    private fun startLogin(activity: Activity) {
        clearSession()
        val userName = args.text("userName")
        val pin = args.text("pin")
        if (args.text("packageName").isEmpty() || userName.isEmpty() || pin.isEmpty()) {
            complete(json("login", "uncertain").put("code", "NO_TERMINAL_CREDENTIALS")
                .put("dispatchFailed", true))
            return
        }
        val intent = Intent("com.mosambee.softpos.login").apply {
            setPackage(args.text("packageName"))
            putExtra("userName", userName)
            putExtra("password", generatePasswordToken(userName, pin))
            args.text("partnerId").takeIf { it.isNotEmpty() }?.let { putExtra("partnerId", it) }
        }
        dispatch(activity, intent, "login")
    }

    private fun startHealth(activity: Activity) {
        val packageName = args.text("packageName")
        if (packageName.isEmpty()) {
            complete(json("healthcheck", "uncertain").put("code", "PACKAGE_MISSING"))
            return
        }
        try {
            activity.packageManager.getPackageInfo(packageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            complete(json("healthcheck", "uncertain").put("code", "SOFTPOS_NOT_INSTALLED")
                .put("dispatchFailed", true))
            return
        }
        val intent = Intent("com.mosambee.softpos.healthcheck").setPackage(packageName)
        if (intent.resolveActivity(activity.packageManager) == null) {
            complete(json("healthcheck", "uncertain").put("code", "SOFTPOS_ACTIVITY_NOT_VISIBLE")
                .put("dispatchFailed", true))
            return
        }
        dispatch(activity, intent, "healthcheck")
    }

    private fun startOperation(activity: Activity, session: String) {
        val amountBaisas = args.text("amountBaisas").toLongOrNull()
        val amount = if (amountBaisas != null && amountBaisas in 1..Long.MAX_VALUE) {
            amountBaisas.toString()
        } else if (args.containsKey("amountBaisas")) "" else args.text("amount")
        val transactionId = args.text("transactionId")
        val badAmount = operation != "void" &&
            (amount.toLongOrNull()?.let { it <= 0 } != false)
        if (args.text("packageName").isEmpty() || badAmount ||
            (operation == "void" && transactionId.isEmpty()) ||
            (operation == "refund" && args["needsTransactionId"] == true && transactionId.isEmpty())) {
            complete(json(operation, "uncertain").put("code", "BAD_ARGS").put("dispatchFailed", true))
            return
        }
        val intent = Intent("com.mosambee.softpos." + operation).apply {
            setPackage(args.text("packageName"))
            if (session.isNotEmpty()) putExtra("sessionId", session)
            if (operation != "void") putExtra("amount", amount)
            if (transactionId.isNotEmpty()) putExtra("transactionId", transactionId)
            if (args["sendCurrency"] != false) {
                args.text("currency").ifEmpty { "0512" }.let { putExtra("currency", it) }
            }
            args.text("description").takeIf { it.isNotEmpty() }?.let { putExtra("description", it) }
            args.text("mobNo").takeIf { it.isNotEmpty() }?.let { putExtra("mobNo", it) }
        }
        dispatch(activity, intent, operation)
    }

    private fun dispatch(activity: Activity, intent: Intent, nextStage: String) {
        cancelWatchdog()
        val code = allocateCode()
        if (code == null) {
            complete(json(nextStage, "uncertain").put("code", "REQUEST_CODE_EXHAUSTED")
                .put("dispatchFailed", true))
            return
        }
        stage = nextStage
        owner = activity
        requestCode = code
        try {
            // Retain this across the one permitted expired-session login retry.
            // A launch exception can occur after dispatch, so mark before calling Android.
            if (nextStage in listOf("payment", "void", "refund")) paymentDispatched = true
            launch(activity, intent, code, nextStage)
            val timer = Runnable { if (requestCode == code && result != null) cancelPendingOperation() }
            watchdog = timer
            handler.postDelayed(timer, ACTIVITY_RESULT_WATCHDOG_MS)
        } catch (_: ActivityNotFoundException) {
            complete(json(nextStage, "uncertain").put("code", "SOFTPOS_NOT_FOUND").put("dispatchFailed", true))
        } catch (_: SecurityException) {
            complete(json(nextStage, "uncertain").put("code", "SOFTPOS_LAUNCH_REFUSED").put("dispatchFailed", true))
        } catch (_: Exception) {
            // Other launch failures may occur after dispatch: do not assert that no card was read.
            complete(json(nextStage, "uncertain").put("code", "LAUNCH_FAILED"))
        }
    }

    fun handleActivityResult(activity: Activity, code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return retired.remove(code)
        if (result == null) return true
        cancelWatchdog()
        requestCode = null
        val receiptRaw = data?.getStringExtra("receiptResponse")
        val receipt = try { JSONObject(receiptRaw ?: "{}") } catch (_: Exception) { JSONObject() }
        val responseCode = data?.getStringExtra("paymentResponseCode")?.trim().orEmpty()
            .ifEmpty { data?.getStringExtra("responseCode")?.trim().orEmpty() }
            .ifEmpty { receipt.optString("responseCode", "").trim() }
        val description = data?.getStringExtra("description")?.trim().orEmpty()
            .ifEmpty { data?.getStringExtra("paymentDescription")?.trim().orEmpty() }
        val session = data?.getStringExtra("sessionId")?.trim().orEmpty()
        val approved = responseCode.isApprovedCode() && (stage != "login" || session.isNotEmpty())
        val declined = !approved && !responseCode.isApprovedCode() &&
            resultCode == Activity.RESULT_OK && responseCode.isNotEmpty() &&
            !responseCode.equals("NA", ignoreCase = true)
        val explicitCancel = resultCode == Activity.RESULT_CANCELED && description.isEmpty() &&
            data?.getStringExtra("status") in listOf("cancelled", "canceled") && !approved && !declined
        val payload = json(stage, if (approved) "approved" else if (declined) "declined" else if (explicitCancel) "cancelled" else "uncertain")
            .put("responseCode", responseCode).put("paymentResponseCode", responseCode)
            .put("description", description).put("paymentDescription", description)
            .put("receiptResponse", receipt).put("resultCode", resultCode)

        if (stage == "login") {
            if (!approved) { clearSession(); complete(payload); return true }
            if (operation == "login") {
                preparedSession = session
                preparedAt = android.os.SystemClock.elapsedRealtime()
                preparedIdentity = identity(args)
                complete(payload.put("sessionId", session).put("sessionReady", true))
            } else startOperation(activity, session)
        } else if (stage != "healthcheck" && declined && responseCode == "99" && retryCount == 0) {
            // Only an authoritative expired-session response authorizes a single retry.
            retryCount = 1
            startLogin(activity)
        } else {
            if (stage == "healthcheck" && declined) payload.put("code", "SOFTPOS_HEALTH_REFUSED")
            complete(payload)
        }
        return true
    }

    fun cancelPendingOperation(): Boolean {
        if (result == null) return false
        val activity = owner
        val code = requestCode
        if (code != null) retired.add(code)
        clearSession()
        complete(json(stage.ifEmpty { operation }, "uncertain").put("code", "SOFTPOS_NOT_RESPONDING")
            .put("description", "The bank application did not return a confirmed outcome"))
        if (activity != null && code != null) {
            try { activity.finishActivity(code) } catch (_: Exception) { }
        }
        return true
    }

    private fun complete(payload: JSONObject) {
        payload.put("paymentDispatched", paymentDispatched)
        val reply = result
        cancelWatchdog()
        result = null
        owner = null
        requestCode = null
        stage = ""
        operation = ""
        args = emptyMap()
        retryCount = 0
        reply?.success(payload.toString())
    }
    private fun cancelWatchdog() { watchdog?.let(handler::removeCallbacks); watchdog = null }
    private fun allocateCode(): Int? {
        repeat(1000) {
            val code = nextCode
            nextCode = if (code == 20_999) 20_000 else code + 1
            if (code !in retired && code != requestCode) return code
        }
        return null
    }
    private fun Map<String, Any?>.text(key: String): String = this[key]?.toString()?.trim().orEmpty()
    private fun String.isApprovedCode(): Boolean = this == "0" || this == "00"
    private fun json(stage: String, status: String): JSONObject =
        JSONObject().put("stage", stage).put("status", status)


    private fun generatePasswordToken(userName: String, pin: String): String {
        val pinHash = sha256Hex(pin)
        val userHash = sha256Hex(userName)
        return aesEncryptAppendIvHex(PASSWORD_TOKEN_AES_KEY_HEX, xorHex(pinHash, userHash))
    }

    private fun sha256Hex(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(input.toByteArray(Charsets.UTF_8))
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
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        val iv = ByteArray(cipher.blockSize)
        SecureRandom().nextBytes(iv)
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(hexToBytes(keyHex), "AES"),
            IvParameterSpec(iv),
        )
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return bytesToHexUpper(encrypted) + bytesToHexUpper(iv)
    }

    private fun hexToBytes(hex: String): ByteArray {
        val clean = hex.trim()
        val output = ByteArray(clean.length / 2)
        var index = 0
        while (index < clean.length) {
            output[index / 2] = clean.substring(index, index + 2).toInt(16).toByte()
            index += 2
        }
        return output
    }

    private fun bytesToHexUpper(bytes: ByteArray): String =
        bytes.joinToString(separator = "") { "%02X".format(it) }
}
