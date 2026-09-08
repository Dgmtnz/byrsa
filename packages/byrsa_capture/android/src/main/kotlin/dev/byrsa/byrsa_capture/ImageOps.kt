// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

package dev.byrsa.byrsa_capture

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import androidx.exifinterface.media.ExifInterface
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/** Focus and exposure measures, and the perspective warp. */
object ImageOps {

    /**
     * Relative focus measure: mean absolute Laplacian over a subsampled grid,
     * mapped to 0..1.
     *
     * Only comparable between frames of the same scene, which is all
     * auto-capture needs — it is deciding "sharper than a moment ago", not
     * "sharp in absolute terms".
     */
    fun sharpness(luma: ByteArray, width: Int, height: Int, rowStride: Int): Double {
        val step = max(1, width / 160)
        var total = 0.0
        var count = 0
        var y = step
        while (y < height - step) {
            var x = step
            while (x < width - step) {
                val centre = (luma[y * rowStride + x].toInt() and 0xFF) * 4
                val neighbours = (luma[y * rowStride + x - step].toInt() and 0xFF) +
                    (luma[y * rowStride + x + step].toInt() and 0xFF) +
                    (luma[(y - step) * rowStride + x].toInt() and 0xFF) +
                    (luma[(y + step) * rowStride + x].toInt() and 0xFF)
                total += abs(centre - neighbours)
                count++
                x += step
            }
            y += step
        }
        if (count == 0) return 0.0
        // 40 grey levels of mean Laplacian is already a crisp document edge.
        return ((total / count) / 40.0).coerceIn(0.0, 1.0)
    }

    /** Mean luma, 0..1. */
    fun brightness(luma: ByteArray, width: Int, height: Int, rowStride: Int): Double {
        val step = max(1, width / 120)
        var total = 0L
        var count = 0
        var y = 0
        while (y < height) {
            var x = 0
            while (x < width) {
                total += luma[y * rowStride + x].toInt() and 0xFF
                count++
                x += step
            }
            y += step
        }
        return if (count == 0) 0.0 else total.toDouble() / count / 255.0
    }

    /**
     * Rotates a point in normalised coordinates so that buffer coordinates
     * become upright display coordinates.
     *
     * The analysis buffer arrives in sensor orientation while the preview is
     * upright, and forgetting this transform is the classic reason an overlay
     * tracks the page perfectly in landscape and is nonsense in portrait.
     */
    fun rotateNormalised(x: Float, y: Float, degrees: Int): FloatArray = when (degrees) {
        90 -> floatArrayOf(1f - y, x)
        180 -> floatArrayOf(1f - x, 1f - y)
        270 -> floatArrayOf(y, 1f - x)
        else -> floatArrayOf(x, y)
    }

    /**
     * Warps the quadrilateral [corners] of [source] into an upright rectangle.
     *
     * Uses `Matrix.setPolyToPoly`, which is the platform's own four-point
     * perspective transform: there is no reason to hand-roll a homography and
     * a resampler when the framework ships one that is hardware-accelerated and
     * already correct at the edges.
     *
     * @param corners eight floats, TL, TR, BR, BL, in normalised coordinates
     * @param targetAspectRatio width/height of the physical page, when known
     */
    fun warp(source: Bitmap, corners: FloatArray, targetAspectRatio: Double?): Bitmap {
        require(corners.size == 8) { "A quad is four x,y pairs" }
        val sourcePoints = FloatArray(8)
        for (i in 0 until 4) {
            sourcePoints[i * 2] = corners[i * 2] * source.width
            sourcePoints[i * 2 + 1] = corners[i * 2 + 1] * source.height
        }

        fun distance(a: Int, b: Int) = hypot(
            (sourcePoints[a * 2] - sourcePoints[b * 2]).toDouble(),
            (sourcePoints[a * 2 + 1] - sourcePoints[b * 2 + 1]).toDouble(),
        )

        val width = max(distance(0, 1), distance(3, 2))
        val heightFromSides = max(distance(0, 3), distance(1, 2))
        val height = if (targetAspectRatio != null && targetAspectRatio > 0) {
            width / targetAspectRatio
        } else {
            heightFromSides
        }

        val outWidth = width.roundToInt().coerceIn(16, 8000)
        val outHeight = height.roundToInt().coerceIn(16, 8000)
        val destination = floatArrayOf(
            0f, 0f,
            outWidth.toFloat(), 0f,
            outWidth.toFloat(), outHeight.toFloat(),
            0f, outHeight.toFloat(),
        )

        val matrix = Matrix()
        matrix.setPolyToPoly(sourcePoints, 0, destination, 0, 4)

        val output = Bitmap.createBitmap(outWidth, outHeight, Bitmap.Config.ARGB_8888)
        Canvas(output).drawBitmap(
            source,
            matrix,
            Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
        )
        return output
    }

    /** Applies a JPEG's EXIF orientation, so pixel coordinates mean what they look like. */
    fun applyExifRotation(bitmap: Bitmap, path: String): Bitmap {
        val orientation = ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
