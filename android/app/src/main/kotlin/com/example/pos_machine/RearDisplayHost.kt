package com.example.pos_machine

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

object RearDisplayHost {
    const val HOST_CHANNEL = "pos_machine/rear_display_host"
    private const val REAR_CHANNEL = "pos_machine/rear_display_channel"
    private const val FRONT_CHANNEL = "pos_machine/front_display_channel"
    private const val TAG = "RearDisplayHost"

    private var activeDisplayId: Int? = null
    private var activeEngineId: String? = null
    private var activePresentation: RearDisplayPresentation? = null
    private var frontBinaryMessenger: BinaryMessenger? = null

    fun attachFrontBinaryMessenger(binaryMessenger: BinaryMessenger) {
        frontBinaryMessenger = binaryMessenger
    }

    fun listPresentationDisplays(activity: Activity): List<Map<String, Any>> {
        val displayManager =
            activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
                ?: return emptyList()

        return displayManager
            .getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .map { display ->
                mapOf(
                    "displayId" to display.displayId,
                    "name" to display.name,
                    "flags" to display.flags,
                    "rotation" to display.rotation,
                )
            }
    }

    fun openRearDisplay(
        activity: Activity,
        displayId: Int,
        engineId: String,
    ): Boolean {
        val displayManager =
            activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
                ?: return false

        val display = displayManager.getDisplay(displayId) ?: return false

        return try {
            activePresentation?.dismiss()

            val flutterEngine = ensureRearEngine(activity.applicationContext, engineId)
            activeDisplayId = displayId
            activeEngineId = engineId

            activePresentation = RearDisplayPresentation(
                context = activity,
                display = display,
                engineId = engineId,
                flutterEngine = flutterEngine,
            ).also { presentation ->
                presentation.show()
            }

            Log.i(TAG, "Opened rear presentation on displayId=$displayId engineId=$engineId")
            true
        } catch (error: Exception) {
            Log.e(TAG, "Unable to open rear display presentation", error)
            false
        }
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

    fun startActivityOnRearDisplay(intent: Intent): Boolean {
        val presentation = activePresentation ?: return false

        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            presentation.context.startActivity(intent)
            Log.i(TAG, "Started activity from rear presentation context")
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
        Log.i(TAG, "Transferred data to rear display engineId=$engineId")

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
        GeneratedPluginRegistrant.registerWith(flutterEngine)
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
