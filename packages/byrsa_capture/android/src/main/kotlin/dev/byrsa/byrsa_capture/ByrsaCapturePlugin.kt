// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

package dev.byrsa.byrsa_capture

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

/** Android side of `byrsa_capture`. No Google Play Services anywhere below. */
class ByrsaCapturePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var context: Context
    private lateinit var textureRegistry: TextureRegistry

    private var session: CaptureSession? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null

    /// A `start` call parked while the user answers the permission dialog.
    private var pendingStart: Pair<MethodCall, MethodChannel.Result>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        methods = MethodChannel(binding.binaryMessenger, "dev.byrsa/capture")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "dev.byrsa/capture/detections")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        session?.dispose()
        session = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = Unit

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        session?.stop()
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    /**
     * Delivers the user's answer to the camera permission dialog.
     *
     * A denial is reported as `permission-denied`, and separately as
     * `permission-denied-permanently` when the system will no longer show the
     * dialog — the two need different interfaces, because in the second case
     * asking again does nothing and only Settings will help.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        val (call, result) = pendingStart ?: return true
        pendingStart = null

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startSession(call, result)
        } else {
            val activity = activityBinding?.activity
            val canAskAgain =
                activity?.shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) == true
            result.error(
                if (canAskAgain) "permission-denied" else "permission-denied-permanently",
                "Byrsa needs the camera to scan a document.",
                null,
            )
        }
        return true
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
            )

            "permissionStatus" -> {
                val activity = activityBinding?.activity
                val granted = activity != null &&
                    activity.checkSelfPermission(Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
                result.success(
                    when {
                        granted -> "granted"
                        activity == null -> "notAsked"
                        // Android has no "was it ever asked" flag. If the system
                        // would no longer show a rationale and it is not
                        // granted, asking again is a no-op — which is the only
                        // distinction an interface actually needs.
                        activity.shouldShowRequestPermissionRationale(
                            Manifest.permission.CAMERA,
                        ) -> "notAsked"
                        else -> "deniedPermanently"
                    },
                )
            }

            "start" -> start(call, result)
            "stop" -> {
                session?.stop()
                result.success(null)
            }

            "capture" -> {
                val session = this.session
                if (session == null) {
                    result.error("not-started", "The camera session is not running.", null)
                    return
                }
                session.capture(
                    rectifyOnCapture = call.argument<Boolean>("rectifyOnCapture") ?: true,
                    onResult = { result.success(it) },
                    onError = { code, message -> result.error(code, message, null) },
                )
            }

            "rectify" -> {
                val session = this.session ?: CaptureSession(context, textureRegistry)
                try {
                    result.success(
                        session.rectify(
                            call.argument<String>("imagePath")!!,
                            cornersFrom(call.argument<List<Map<String, Any?>>>("quad")!!),
                            call.argument<Double>("targetAspectRatio"),
                        ),
                    )
                } catch (error: Throwable) {
                    result.error("rectify-failed", error.message ?: "$error", null)
                }
            }

            "setTorch" -> {
                session?.setTorch(call.argument<Boolean>("on") ?: false)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Asks for the camera permission if it is not already granted, then starts.
     *
     * Declaring `CAMERA` in the manifest is not enough on Android 6 and later,
     * and forgetting the runtime request is the kind of bug that never shows up
     * on a developer's phone — where the permission was granted weeks ago — and
     * fails for every new user on first launch.
     */
    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error(
                "no-activity",
                "byrsa_capture needs a FlutterActivity to bind the camera lifecycle to.",
                null,
            )
            return
        }
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingStart != null) {
                result.error(
                    "permission-pending",
                    "A camera permission request is already on screen.",
                    null,
                )
                return
            }
            pendingStart = call to result
            activity.requestPermissions(
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST,
            )
            return
        }
        startSession(call, result)
    }

    private fun startSession(call: MethodCall, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity !is LifecycleOwner) {
            result.error(
                "no-activity",
                "byrsa_capture needs a FlutterActivity to bind the camera lifecycle to.",
                null,
            )
            return
        }
        try {
            val session = this.session ?: CaptureSession(context, textureRegistry).also {
                this.session = it
            }
            val textureId = session.start(
                owner = activity,
                detectionsPerSecond = call.argument<Int>("detectionsPerSecond") ?: 8,
                torch = call.argument<Boolean>("torch") ?: false,
                sink = { payload -> eventSink?.success(payload) },
            )
            result.success(textureId)
        } catch (error: Throwable) {
            result.error("start-failed", error.message ?: "$error", null)
        }
    }

    private fun cornersFrom(quad: List<Map<String, Any?>>): FloatArray {
        require(quad.size == 4) { "A quad is four points" }
        val out = FloatArray(8)
        quad.forEachIndexed { index, point ->
            out[index * 2] = (point["x"] as Number).toFloat()
            out[index * 2 + 1] = (point["y"] as Number).toFloat()
        }
        return out
    }

    private companion object {
        const val CAMERA_PERMISSION_REQUEST = 0x627A
    }
}
