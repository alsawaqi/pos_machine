package com.example.pos_machine

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object RearDisplayHost {
    const val HOST_CHANNEL = "pos_machine/rear_display_host"
    private const val REAR_CHANNEL = "pos_machine/rear_display_channel"
    private const val FRONT_CHANNEL = "pos_machine/front_display_channel"
    private const val TAG = "RearDisplayHost"

    private var activeDisplayId: Int? = null
    private var activeEngineId: String? = null
    private var activePresentation: RearDisplayPresentation? = null
    private var frontBinaryMessenger: BinaryMessenger? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attachFrontBinaryMessenger(binaryMessenger: BinaryMessenger) {
        frontBinaryMessenger = binaryMessenger
    }

    fun listPresentationDisplays(activity: Activity): List<Map<String, Any>> {
        val displayManager =
            activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
                ?: return emptyList()

        return SunmiRearDisplayBridge.listPresentationDisplays(displayManager)
    }

    fun prepareRearDisplay(
        activity: Activity,
        displayId: Int?,
    ): Map<String, Any> {
        val displayManager =
            activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
                ?: return mapOf("prepared" to false)

        return SunmiRearDisplayBridge.prepareDisplay(
            context = activity.applicationContext,
            displayManager = displayManager,
            requestedDisplayId = displayId,
        )
    }

    fun openRearDisplay(
        activity: Activity,
        displayId: Int,
        engineId: String,
    ): Boolean {
        val displayManager =
            activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
                ?: return false

        val display = SunmiRearDisplayBridge.resolveDisplay(
            displayManager = displayManager,
            requestedDisplayId = displayId,
            preferredSerial = displayManager.getDisplay(displayId)?.let(
                SunmiRearDisplayBridge::extractSerial,
            ),
        ) ?: return false

        return try {
            activePresentation?.dismiss()

            val flutterEngine = ensureRearEngine(activity.applicationContext, engineId)
            activeDisplayId = displayId
            activeEngineId = engineId

            activePresentation = RearDisplayPresentation(
                ownerActivity = activity,
                display = display,
                engineId = engineId,
                flutterEngine = flutterEngine,
            ).also { presentation ->
                presentation.show()
            }

            scheduleSunmiTouchEnable(
                context = activity.applicationContext,
                displayManager = displayManager,
                displayId = display.displayId,
            )

            Log.i(TAG, "Opened rear presentation on displayId=${display.displayId} engineId=$engineId")
            true
        } catch (error: Exception) {
            Log.e(TAG, "Unable to open rear display presentation", error)
            false
        }
    }

    private fun scheduleSunmiTouchEnable(
        context: Context,
        displayManager: DisplayManager,
        displayId: Int,
    ) {
        fun send(attempt: Int) {
            val result = SunmiRearDisplayBridge.prepareDisplay(
                context = context,
                displayManager = displayManager,
                requestedDisplayId = displayId,
            )
            Log.i(TAG, "SUNMI rear touch enable attempt=$attempt result=$result")
        }

        send(attempt = 0)
        mainHandler.postDelayed({ send(attempt = 1) }, 350)
        mainHandler.postDelayed({ send(attempt = 2) }, 1200)
    }

    fun hideRearDisplay(): Boolean {
        activeDisplayId = null
        activeEngineId = null
        activePresentation?.dismiss()
        activePresentation = null
        return true
    }

    fun currentDisplayId(): Int? = activeDisplayId

    fun hasActiveRearDisplay(): Boolean = activePresentation != null

    fun startActivityOnRearDisplay(
        intent: Intent,
        hidePresentationAfterLaunch: Boolean = false,
    ): Boolean {
        val presentation = activePresentation ?: return false

        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            presentation.context.startActivity(intent)
            Log.i(TAG, "Started activity from rear presentation context")
            if (hidePresentationAfterLaunch) {
                activeDisplayId = null
                activeEngineId = null
                activePresentation?.dismiss()
                activePresentation = null
                Log.i(TAG, "Dismissed rear presentation while payment activity is active")
            }
            true
        } catch (error: Exception) {
            Log.e(TAG, "Unable to start activity from rear presentation context", error)
            false
        }
    }

    fun transferDataToRear(arguments: Any?): Boolean {
        val engineId = activeEngineId ?: return false
        val flutterEngine = FlutterEngineCache.getInstance().get(engineId) ?: return false

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REAR_CHANNEL)
            .invokeMethod("updateOrder", arguments)

        return true
    }

    /**
     * Forwards a customer-panel touch (intercepted on the main display in MainActivity) to the rear
     * customer engine as a normalized point, which replays it as a synthetic pointer on the customer
     * UI. nx/ny are 0..1 fractions of the panel surface.
     */
    fun forwardTouchToRear(action: String, nx: Double, ny: Double): Boolean {
        val engineId = activeEngineId ?: return false
        val flutterEngine = FlutterEngineCache.getInstance().get(engineId) ?: return false

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REAR_CHANNEL)
            .invokeMethod(
                "syntheticTouch",
                mapOf("action" to action, "nx" to nx, "ny" to ny),
            )

        return true
    }

    fun transferDataToFront(arguments: Any?): Boolean {
        val binaryMessenger = frontBinaryMessenger ?: run {
            Log.w(TAG, "Unable to transfer data to front display because the messenger is missing.")
            return false
        }

        MethodChannel(binaryMessenger, FRONT_CHANNEL)
            .invokeMethod("customerEvent", arguments)
        Log.i(TAG, "Transferred customer event back to the front display")

        return true
    }

    private fun ensureRearEngine(context: Context, engineId: String): FlutterEngine {
        FlutterEngineCache.getInstance().get(engineId)?.let { return it }

        val appContext = context.applicationContext
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        flutterLoader.startInitialization(appContext)
        flutterLoader.ensureInitializationComplete(appContext, null)

        val flutterEngine = FlutterEngine(appContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REAR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "customerEvent" -> {
                        result.success(transferDataToFront(call.arguments))
                    }

                    else -> result.notImplemented()
                }
            }

        val entrypoint = DartExecutor.DartEntrypoint(
            flutterLoader.findAppBundlePath(),
            "secondaryDisplayMain",
        )

        flutterEngine.dartExecutor.executeDartEntrypoint(entrypoint)
        flutterEngine.lifecycleChannel.appIsResumed()
        FlutterEngineCache.getInstance().put(engineId, flutterEngine)

        Log.i(TAG, "Created rear FlutterEngine with engineId=$engineId")
        return flutterEngine
    }
}
