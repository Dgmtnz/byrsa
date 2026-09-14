// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

package dev.byrsa.byrsa_capture

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.LifecycleOwner
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import android.util.Size

/**
 * One CameraX session: preview into a Flutter texture, live detection, stills.
 *
 * The frames never cross into Dart. Detection happens here and four corners go
 * over the channel, which is the difference between a scanner that runs for
 * twenty minutes and one that cooks the phone in five (see the plan's §4.1).
 */
class CaptureSession(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
) {

    fun interface DetectionSink {
        fun onDetection(payload: Map<String, Any?>)
    }

    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var provider: ProcessCameraProvider? = null
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var imageCapture: ImageCapture? = null
    private var camera: androidx.camera.core.Camera? = null

    private var lastDetectionAt = 0L
    private var minimumIntervalMs = 125L
    private var lastQuad: FloatArray? = null

    /** Starts the camera and returns the Flutter texture id to display. */
    @SuppressLint("UnsafeOptInUsageError")
    fun start(
        owner: LifecycleOwner,
        detectionsPerSecond: Int,
        torch: Boolean,
        sink: DetectionSink,
    ): Long {
        minimumIntervalMs = (1000L / detectionsPerSecond.coerceIn(1, 30))

        val producer = textureRegistry.createSurfaceProducer()
        surfaceProducer = producer

        val cameraProvider = ProcessCameraProvider.getInstance(context).get()
        provider = cameraProvider
        cameraProvider.unbindAll()

        val preview = Preview.Builder().build().also {
            it.setSurfaceProvider { request ->
                producer.setSize(request.resolution.width, request.resolution.height)
                previewWidth = request.resolution.width
                previewHeight = request.resolution.height
                // CameraX writes frames in sensor orientation and reports the
                // rotation that makes them upright rather than applying it. The
                // analysis path already rotates its corners by the same amount,
                // so a preview that ignores this puts the image and the outline
                // in two different coordinate systems — which is exactly what
                // the first run on a device looked like: a stretched picture
                // with an outline that appeared mirrored.
                request.setTransformationInfoListener(analysisExecutor) { info ->
                    previewRotation = info.rotationDegrees
                    main.post { sink.onDetection(geometryOnly()) }
                }
                request.provideSurface(producer.surface, analysisExecutor) { }
            }
        }

        val analysis = ImageAnalysis.Builder()
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setResolutionStrategy(
                        ResolutionStrategy(
                            Size(960, 720),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                        ),
                    )
                    .build(),
            )
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
        analysis.setAnalyzer(analysisExecutor) { image -> analyse(image, sink) }

        val capture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()
        imageCapture = capture

        camera = cameraProvider.bindToLifecycle(
            owner,
            CameraSelector.DEFAULT_BACK_CAMERA,
            preview,
            analysis,
            capture,
        )
        if (torch) setTorch(true)
        return producer.id()
    }

    /** Reported to Dart so the preview can be rotated and shaped correctly. */
    private var previewWidth = 0
    private var previewHeight = 0
    private var previewRotation = 0

    /**
     * A payload carrying only the preview geometry.
     *
     * Sent as soon as CameraX knows it, because the preview cannot be laid out
     * before then and waiting for the first detection would leave the texture
     * visibly wrong for as long as detection throttling takes.
     */
    private fun geometryOnly(): HashMap<String, Any?> {
        val payload = HashMap<String, Any?>()
        addGeometry(payload)
        payload["hint"] = "noDocument"
        return payload
    }

    private fun addGeometry(payload: HashMap<String, Any?>) {
        if (previewWidth <= 0 || previewHeight <= 0) return
        payload["previewWidth"] = previewWidth
        payload["previewHeight"] = previewHeight
        payload["previewRotation"] = previewRotation
    }

    private fun analyse(image: ImageProxy, sink: DetectionSink) {
        try {
            val now = System.currentTimeMillis()
            if (now - lastDetectionAt < minimumIntervalMs) return
            lastDetectionAt = now

            val plane = image.planes[0]
            val buffer = plane.buffer
            val luma = ByteArray(buffer.remaining())
            buffer.get(luma)

            val width = image.width
            val height = image.height
            val rowStride = plane.rowStride
            val rotation = image.imageInfo.rotationDegrees

            val quad = QuadDetector.detect(luma, width, height, rowStride)
            val sharpness = ImageOps.sharpness(luma, width, height, rowStride)
            val brightness = ImageOps.brightness(luma, width, height, rowStride)

            val rotated = quad?.let {
                val out = FloatArray(8)
                for (i in 0 until 4) {
                    val p = ImageOps.rotateNormalised(
                        it.points[i * 2],
                        it.points[i * 2 + 1],
                        rotation,
                    )
                    out[i * 2] = p[0]
                    out[i * 2 + 1] = p[1]
                }
                out
            }
            lastQuad = rotated

            val payload = HashMap<String, Any?>()
            payload["quad"] = rotated?.let { cornersToList(it) }
            payload["sharpness"] = sharpness
            payload["brightness"] = brightness
            // Stability and the user-facing hint are decided in Dart, where they
            // are unit-tested on a laptop instead of on a phone.
            payload["hint"] = if (rotated == null) "noDocument" else "moving"
            addGeometry(payload)
            main.post { sink.onDetection(payload) }
        } finally {
            image.close()
        }
    }

    /** Takes a still and, when asked, warps it with the last detected corners. */
    fun capture(
        rectifyOnCapture: Boolean,
        onResult: (Map<String, Any?>) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        val capture = imageCapture ?: run {
            onError("not-started", "The camera session is not running.")
            return
        }
        val file = File(context.cacheDir, "byrsa-${System.currentTimeMillis()}.jpg")
        capture.takePicture(
            ImageCapture.OutputFileOptions.Builder(file).build(),
            analysisExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    try {
                        onResult(finishCapture(file, rectifyOnCapture))
                    } catch (error: Throwable) {
                        onError("capture-failed", error.message ?: "$error")
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    onError("capture-failed", exception.message ?: "$exception")
                }
            },
        )
    }

    private fun finishCapture(file: File, rectify: Boolean): Map<String, Any?> {
        val original = ImageOps.applyExifRotation(
            BitmapFactory.decodeFile(file.absolutePath),
            file.absolutePath,
        )
        val quad = lastQuad ?: FULL_FRAME
        var rectifiedPath: String? = null
        if (rectify) {
            val warped = ImageOps.warp(original, quad, null)
            rectifiedPath = writeJpeg(warped, "${file.absolutePath}.page.jpg")
            warped.recycle()
        }
        val result = HashMap<String, Any?>()
        result["originalPath"] = file.absolutePath
        result["rectifiedPath"] = rectifiedPath
        result["quad"] = cornersToList(quad)
        result["width"] = original.width
        result["height"] = original.height
        original.recycle()
        return result
    }

    /** Re-warps an existing file. Always from the original, never from a warp. */
    fun rectify(imagePath: String, corners: FloatArray, targetAspectRatio: Double?): String {
        val source = ImageOps.applyExifRotation(BitmapFactory.decodeFile(imagePath), imagePath)
        val warped = ImageOps.warp(source, corners, targetAspectRatio)
        val out = writeJpeg(warped, "$imagePath.page.jpg")
        source.recycle()
        warped.recycle()
        return out
    }

    fun setTorch(on: Boolean) {
        camera?.cameraControl?.enableTorch(on)
    }

    fun stop() {
        provider?.unbindAll()
        provider = null
        camera = null
        imageCapture = null
        surfaceProducer?.release()
        surfaceProducer = null
        lastQuad = null
    }

    fun dispose() {
        stop()
        analysisExecutor.shutdown()
    }

    private fun writeJpeg(bitmap: Bitmap, path: String): String {
        FileOutputStream(path).use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 92, stream)
        }
        return path
    }

    private fun cornersToList(corners: FloatArray): List<Map<String, Double>> =
        (0 until 4).map {
            mapOf(
                "x" to corners[it * 2].toDouble(),
                "y" to corners[it * 2 + 1].toDouble(),
            )
        }

    private companion object {
        val FULL_FRAME = floatArrayOf(0f, 0f, 1f, 0f, 1f, 1f, 0f, 1f)
    }
}
