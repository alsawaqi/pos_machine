package com.example.pos_machine

import android.app.Activity
import android.app.Presentation
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

class RearDisplayPresentation(
    private val ownerActivity: Activity,
    display: Display,
    private val engineId: String,
    private val flutterEngine: FlutterEngine,
) : Presentation(presentationContext(ownerActivity, display), display) {
    private var flutterView: FlutterView? = null

    companion object {
        private const val TAG = "RearDisplayPresentation"

        /** WindowManager.LayoutParams FLAG_NOT_FOCUS_MODAL (0x20) for SDKs where the symbol is absent. */
        private const val WM_FLAG_NOT_FOCUS_MODAL = 0x00000020

        private fun presentationContext(activity: Activity, display: Display): android.content.Context {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.createDisplayContext(display)
            } else {
                activity
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        super.onCreate(savedInstanceState)

        setOwnerActivity(ownerActivity)
        setCanceledOnTouchOutside(false)

        val container = FrameLayout(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(Color.BLACK)
            isClickable = true
            isFocusable = true
            isFocusableInTouchMode = true
        }

        window?.decorView?.setBackgroundColor(Color.BLACK)
        setContentView(container)
        applyPresentationWindowBehavior()

        val surfaceView = FlutterSurfaceView(context)
        flutterView = FlutterView(context, surfaceView).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            isFocusable = true
            isFocusableInTouchMode = true
            addOnFirstFrameRenderedListener(
                object : FlutterUiDisplayListener {
                    override fun onFlutterUiDisplayed() {
                        Log.i(TAG, "Rear Flutter UI rendered first frame for engineId=$engineId")
                    }

                    override fun onFlutterUiNoLongerDisplayed() = Unit
                },
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

    override fun show() {
        super.show()
        applyPresentationWindowBehavior()
        flutterView?.apply {
            requestFocus()
            bringToFront()
        }
    }

    /**
     * Secondary Presentation windows often default to FLAG_NOT_FOCUS_MODAL. On some devices
     * that lets pointer events fall through to the main Activity on the primary display — touches
     * on the customer screen then activate the staff POS. Force a fullscreen, touch-modal window.
     */
    private fun applyPresentationWindowBehavior() {
        window?.let { w ->
            w.clearFlags(
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WM_FLAG_NOT_FOCUS_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            )
            w.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            w.setFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
            )
            w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            hideSystemBars(w)
            val attrs = w.attributes
            attrs.gravity = Gravity.FILL
            w.attributes = attrs
        }
    }

    private fun hideSystemBars(window: Window) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val decorView = window.peekDecorView() ?: return
            decorView.windowInsetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
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
}
