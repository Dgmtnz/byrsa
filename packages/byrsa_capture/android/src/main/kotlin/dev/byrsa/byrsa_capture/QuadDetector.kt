// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

package dev.byrsa.byrsa_capture

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Finds the four corners of a page in a luminance image.
 *
 * The approach is deliberately classical and small: for each side of the frame
 * it scans inwards, records where the strongest brightness step is on every
 * scan line, fits a straight line through those points while throwing out the
 * ones that disagree, and intersects the four lines.
 *
 * TODO: this is a baseline, and its ceiling is documented rather than
 * hidden. It assumes the page is the dominant bright region and roughly fills
 * the frame — which is what the capture UI asks the user to do. It will miss a
 * small page on a busy desk, and it does not follow a curved edge. The upgrade
 * path is contour extraction, or a small segmentation network in
 * `byrsa_restore`; the milestone benchmark is what decides whether that is
 * worth its size.
 *
 * No OpenCV and no Play Services: the whole detector is a few hundred lines of
 * arithmetic over a downscaled byte array, which keeps the plugin installable
 * from F-Droid and the APK small.
 */
object QuadDetector {

    /** Corners in normalised 0..1 coordinates, in TL, TR, BR, BL order. */
    class Quad(val points: FloatArray) {
        init {
            require(points.size == 8) { "A quad is four x,y pairs" }
        }
    }

    /** Width the detector works at. Detail beyond this does not help find an edge. */
    private const val WORK_WIDTH = 240

    /** Fraction of each scan line ignored at the ends, where corners confuse the fit. */
    private const val MARGIN = 0.12f

    /** Minimum brightness step, out of 255, that counts as an edge. */
    private const val MIN_STEP = 12

    /** Fraction of scan lines that must agree for a side to be believed. */
    private const val MIN_INLIER_RATIO = 0.45f

    /**
     * @param luma row-major luminance, 8-bit
     * @param width pixels per row in [luma]
     * @param height rows in [luma]
     * @param rowStride bytes per row, which is not always [width] on Android
     */
    fun detect(luma: ByteArray, width: Int, height: Int, rowStride: Int): Quad? {
        val scale = max(1, width / WORK_WIDTH)
        val w = width / scale
        val h = height / scale
        if (w < 32 || h < 32) return null

        val small = ByteArray(w * h)
        for (y in 0 until h) {
            val source = y * scale * rowStride
            val target = y * w
            for (x in 0 until w) {
                small[target + x] = luma[source + x * scale]
            }
        }
        blurInPlace(small, w, h)

        // Left and right are fitted as x = a*y + b; top and bottom as y = a*x + b.
        val left = fitEdge(small, w, h, Side.LEFT) ?: return null
        val right = fitEdge(small, w, h, Side.RIGHT) ?: return null
        val top = fitEdge(small, w, h, Side.TOP) ?: return null
        val bottom = fitEdge(small, w, h, Side.BOTTOM) ?: return null

        val tl = intersect(left, top) ?: return null
        val tr = intersect(right, top) ?: return null
        val br = intersect(right, bottom) ?: return null
        val bl = intersect(left, bottom) ?: return null

        val points = floatArrayOf(
            tl[0] / w, tl[1] / h,
            tr[0] / w, tr[1] / h,
            br[0] / w, br[1] / h,
            bl[0] / w, bl[1] / h,
        )
        // A corner far outside the frame means two edges that never really met.
        for (value in points) {
            if (value.isNaN() || value < -0.25f || value > 1.25f) return null
        }
        return Quad(points)
    }

    private enum class Side { LEFT, RIGHT, TOP, BOTTOM }

    /** A fitted line, as `primary = slope * secondary + offset`. */
    private class Line(val slope: Float, val offset: Float, val vertical: Boolean)

    /** Three-tap box blur, twice, which is close enough to a Gaussian here. */
    private fun blurInPlace(image: ByteArray, w: Int, h: Int) {
        val scratch = ByteArray(image.size)
        repeat(2) {
            for (y in 0 until h) {
                val row = y * w
                for (x in 0 until w) {
                    val a = image[row + max(0, x - 1)].toInt() and 0xFF
                    val b = image[row + x].toInt() and 0xFF
                    val c = image[row + min(w - 1, x + 1)].toInt() and 0xFF
                    scratch[row + x] = ((a + b + c) / 3).toByte()
                }
            }
            for (x in 0 until w) {
                for (y in 0 until h) {
                    val a = scratch[max(0, y - 1) * w + x].toInt() and 0xFF
                    val b = scratch[y * w + x].toInt() and 0xFF
                    val c = scratch[min(h - 1, y + 1) * w + x].toInt() and 0xFF
                    image[y * w + x] = ((a + b + c) / 3).toByte()
                }
            }
        }
    }

    private fun fitEdge(image: ByteArray, w: Int, h: Int, side: Side): Line? {
        val vertical = side == Side.LEFT || side == Side.RIGHT
        val scanCount = if (vertical) h else w
        val depth = (if (vertical) w else h) / 2
        val first = (scanCount * MARGIN).toInt()
        val last = scanCount - first
        if (last - first < 8 || depth < 4) return null

        val secondary = ArrayList<Float>(last - first)
        val primary = ArrayList<Float>(last - first)

        for (scan in first until last) {
            var bestPosition = -1
            var bestStep = MIN_STEP
            for (d in 1 until depth) {
                val (a, b) = when (side) {
                    Side.LEFT -> sample(image, w, d - 1, scan) to sample(image, w, d + 1, scan)
                    Side.RIGHT -> sample(image, w, w - d, scan) to sample(image, w, w - d - 2, scan)
                    Side.TOP -> sample(image, w, scan, d - 1) to sample(image, w, scan, d + 1)
                    Side.BOTTOM -> sample(image, w, scan, h - d) to sample(image, w, scan, h - d - 2)
                }
                val step = abs(a - b)
                if (step > bestStep) {
                    bestStep = step
                    bestPosition = when (side) {
                        Side.LEFT, Side.TOP -> d
                        Side.RIGHT -> w - d - 1
                        Side.BOTTOM -> h - d - 1
                    }
                }
            }
            if (bestPosition >= 0) {
                secondary.add(scan.toFloat())
                primary.add(bestPosition.toFloat())
            }
        }

        if (secondary.size < (last - first) * MIN_INLIER_RATIO) return null
        return fitRobust(secondary, primary, vertical, (last - first) * MIN_INLIER_RATIO)
    }

    private fun sample(image: ByteArray, w: Int, x: Int, y: Int): Int =
        image[y * w + x].toInt() and 0xFF

    /**
     * Least squares, then one round of dropping the worst quarter and refitting.
     *
     * A full RANSAC would be more robust; one trimmed refit removes the
     * dominant failure — a few scan lines that latched onto a shadow or a
     * neighbouring sheet — for a tenth of the code.
     */
    private fun fitRobust(
        xs: List<Float>,
        ys: List<Float>,
        vertical: Boolean,
        minimumInliers: Float,
    ): Line? {
        var line = leastSquares(xs, ys, vertical) ?: return null
        val residuals = xs.indices.map { abs(ys[it] - (line.slope * xs[it] + line.offset)) }
        val cutoff = residuals.sorted()[(residuals.size * 3) / 4]
        val keptX = ArrayList<Float>()
        val keptY = ArrayList<Float>()
        for (i in xs.indices) {
            if (residuals[i] <= max(cutoff, 1.5f)) {
                keptX.add(xs[i])
                keptY.add(ys[i])
            }
        }
        if (keptX.size < minimumInliers) return null
        line = leastSquares(keptX, keptY, vertical) ?: line
        return line
    }

    private fun leastSquares(xs: List<Float>, ys: List<Float>, vertical: Boolean): Line? {
        val n = xs.size
        if (n < 2) return null
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumXX = 0.0
        for (i in 0 until n) {
            sumX += xs[i]
            sumY += ys[i]
            sumXY += xs[i].toDouble() * ys[i]
            sumXX += xs[i].toDouble() * xs[i]
        }
        val denominator = n * sumXX - sumX * sumX
        if (abs(denominator) < 1e-6) return null
        val slope = (n * sumXY - sumX * sumY) / denominator
        val offset = (sumY - slope * sumX) / n
        return Line(slope.toFloat(), offset.toFloat(), vertical)
    }

    /**
     * Intersects a vertical-ish line (`x = a*y + b`) with a horizontal-ish one
     * (`y = c*x + d`).
     */
    private fun intersect(vertical: Line, horizontal: Line): FloatArray? {
        val denominator = 1f - vertical.slope * horizontal.slope
        if (abs(denominator) < 1e-6f) return null
        val x = (vertical.offset + vertical.slope * horizontal.offset) / denominator
        val y = horizontal.slope * x + horizontal.offset
        return floatArrayOf(x, y)
    }
}
