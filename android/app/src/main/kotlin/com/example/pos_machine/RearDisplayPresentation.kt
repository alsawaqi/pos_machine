package com.example.pos_machine

import android.app.Presentation
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

class RearDisplayPresentation(
    context: android.content.Context,
    display: Display,
    private val engineId: String,
    private val flutterEngine: FlutterEngine,
) : Presentation(context, display) {
    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val container = FrameLayout(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(Color.BLACK)
        }

        window?.decorView?.setBackgroundColor(Color.BLACK)
        setContentView(container)

        val textureView = FlutterTextureView(context)
        flutterView = FlutterView(context, textureView).apply {
            setBackgroundColor(Color.BLACK)
            addOnFirstFrameRenderedListener(
                object : FlutterUiDisplayListener {
                    override fun onFlutterUiDisplayed() {
                        Log.i(TAG, "Rear Flutter UI rendered first frame for engineId=$engineId")
                    }

                    override fun onFlutterUiNoLongerDisplayed() = Unit
                }
            )
            attachToFlutterEngine(flutterEngine)
        }

        container.addView(
            flutterView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        Log.i(TAG, "Rear presentation attached engineId=$engineId")
    }

    override fun dismiss() {
        cleanup()
        super.dismiss()
    }

    override fun onStop() {
        cleanup()
        super.onStop()
    }

    private fun cleanup() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
    }

    companion object {
        private const val TAG = "RearDisplayPresentation"
    }
}
