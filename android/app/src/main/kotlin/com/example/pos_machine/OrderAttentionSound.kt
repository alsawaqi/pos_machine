package com.example.pos_machine

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Foreground attention only. Never changes system volume or bypasses DND. */
class OrderAttentionSound(private val context: Context, messenger: BinaryMessenger) {
    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private val stopSound = Runnable { stop() }

    init {
        MethodChannel(messenger, "mithqal/order_attention").setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> result.success(play())
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun play(): Boolean {
        stop()
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0) return false
            val uri = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_NOTIFICATION)
                ?: return false
            val sound = RingtoneManager.getRingtone(context, uri) ?: return false
            sound.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringtone = sound
            sound.play()
            handler.postDelayed(stopSound, 2000)
            true // Request accepted, not proof that hardware was audible.
        } catch (_: Exception) {
            stop()
            false
        }
    }

    fun stop() {
        handler.removeCallbacks(stopSound)
        try {
            ringtone?.stop()
        } catch (_: Exception) {
            // Notification failure must not interfere with POS lifecycle.
        }
        ringtone = null
    }
}
