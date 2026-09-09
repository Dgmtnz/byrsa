package dev.byrsa.byrsa

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * The application's own platform channel, for the one thing Dart is bad at.
 *
 * Encoding a JPEG in pure Dart costs about 900 ms for a 6.8 MP page. The
 * platform encoder does it in a fraction of that, and it is already on every
 * device. That is the whole reason this file is not the three lines Flutter
 * generates.
 *
 * It lives in the application rather than in a package on purpose. A capture
 * plugin has no business owning an image codec, `byrsa_restore` is deliberately
 * free of native code (DECISIONS.md D-020, and D-037 is what happens when a
 * package brings its own), and a package for eighty lines with one consumer is
 * a package nobody asked for. If a second consumer appears it is a file move.
 */
class MainActivity : FlutterActivity() {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "encodeJpeg" -> encodeJpeg(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    /**
     * Encodes interleaved 8-bit RGB into a JPEG file.
     *
     * Three channels, never one: a grayscale page is expanded on the Dart side,
     * because handing a single-channel buffer to an encoder produces a
     * three-component JPEG anyway and, measured, a file twice the size.
     */
    private fun encodeJpeg(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val rgb = call.argument<ByteArray>("rgb")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val quality = call.argument<Int>("quality") ?: 92
        val path = call.argument<String>("path")

        if (rgb == null || width == null || height == null || path == null) {
            result.error("bad-arguments", "encodeJpeg needs rgb, width, height and path.", null)
            return
        }
        if (rgb.size < width * height * 3) {
            result.error(
                "bad-arguments",
                "Expected ${width * height * 3} bytes for ${width}x$height, got ${rgb.size}.",
                null,
            )
            return
        }

        // Off the platform thread: this is tens of milliseconds of work and the
        // interface is still drawing.
        executor.execute {
            var bitmap: Bitmap? = null
            try {
                val pixels = IntArray(width * height)
                for (i in pixels.indices) {
                    val base = i * 3
                    pixels[i] = (0xFF shl 24) or
                        ((rgb[base].toInt() and 0xFF) shl 16) or
                        ((rgb[base + 1].toInt() and 0xFF) shl 8) or
                        (rgb[base + 2].toInt() and 0xFF)
                }
                bitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)

                val file = File(path)
                file.parentFile?.mkdirs()
                FileOutputStream(file).use { stream ->
                    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)) {
                        throw IllegalStateException("The platform encoder refused the bitmap.")
                    }
                }
                main.post { result.success(path) }
            } catch (error: Throwable) {
                main.post {
                    result.error("encode-failed", error.message ?: "$error", null)
                }
            } finally {
                bitmap?.recycle()
            }
        }
    }

    private companion object {
        const val CHANNEL = "dev.byrsa/codec"
    }
}
