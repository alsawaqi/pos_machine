package com.example.pos_machine

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Hosts a bank intent on the caller-selected display; all protocol logic stays in the core. */
class RearPaymentProxyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Restoring a proxy must never dispatch the bank intent again.
        if (savedInstanceState != null) return
        @Suppress("DEPRECATION")
        val target = intent.getParcelableExtra<Intent>(EXTRA_BANK_INTENT)
        val requestCode = intent.getIntExtra(EXTRA_REQUEST_CODE, -1)
        if (target == null || requestCode < 0) {
            MosambeeBridge.cancelPendingOperation()
            finish()
            return
        }
        try {
            startActivityForResult(target, requestCode)
        } catch (_: Exception) {
            MosambeeBridge.cancelPendingOperation()
            finish()
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!MosambeeBridge.handleActivityResult(this, requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
        if (data?.hasExtra("sessionId") != true) finish()
    }
    companion object {
        const val EXTRA_BANK_INTENT = "bank_intent"
        const val EXTRA_REQUEST_CODE = "bank_request_code"
    }
}
