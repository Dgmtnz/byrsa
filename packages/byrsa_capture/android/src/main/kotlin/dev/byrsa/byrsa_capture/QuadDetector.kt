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
 * it scans inwards, records the **outermost** dark-outside-to-bright-inside
 * step on every scan line, fits a straight line through those points while
 * throwing out the ones that disagree, and intersects the four lines.
 *
 * Outermost and signed, not strongest: see [fitEdge]. The strongest step on a
 * scan line down a printed page is the title, not the paper edge.
 *
 * TODO: this is a baseline, and its ceiling is documented rather than
 * hidden. It requires the page to be brighter than what surrounds it and to
 * roughly fill the frame — which is what the capture UI asks the user to do.
 * Brighter is now a requirement rather than a preference: a dark document on a
 * bright table returns no quad at all, measured, where the old unsigned rule
 * returned a good one. That is the price of not latching onto the title, and
 * the capture UI already falls back to the full frame. It will also miss a
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

    /**
     * Minimum **signed rise**, out of 255, that counts as an edge: how much
     * brighter the inside of a step has to be than the outside. A fall of any
     * size is not an edge at all, whatever its magnitude — that is the whole
     * point, and it is why this is not a plain threshold on `abs`.
     */
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

    /**
     * Where one side of the page is, as a line fitted over every scan line.
     *
     * The rule is **the outermost step that goes from dark outside to bright
     * inside, and stop there**. Both halves of that were wrong before and they
     * compounded: the loop kept the argmax over the whole search depth — half
     * the image — and the step was `abs(a - b)`, which cannot tell paper from
     * ink. Printed ink on white paper is a far stronger step than white paper
     * against any normal desk, so the top edge latched onto the title and the
     * bottom onto the footer. On a real harness page composited onto a desk
     * that cut 24.5% off the top and 33.3% off the bottom of the page.
     *
     * `a` is always sampled one position further out than `b`, on all four
     * sides, so `b - a` is positive exactly for a dark-outside/bright-inside
     * transition and the sign does the discriminating for free.
     *
     * Rejected, all four measured rather than argued:
     *  - strongest step within the outer 20%: the title still wins.
     *  - outermost `abs` step over the threshold, the tempting simplification
     *    of this one: a page casts a shadow on its desk, so going inward you
     *    meet desk→shadow (a fall) before shadow→paper (a rise); it stops one
     *    transition early and swallows the shadow band. Measured at 2.9% too
     *    large by the shadow scene in `QuadDetectorTest`, which exists to catch
     *    exactly this — the scene that reproduces the user's bug does not.
     *  - requiring the darker side to stay dark out to the frame edge: correct,
     *    but a second pass and a uniformity threshold for no measured gain.
     *
     * No safety margin, deliberately. The double 3-tap blur spreads an edge
     * over ~4 work px and the first qualifying `d` lands on the outer end of
     * that ramp, so the quad already comes out 0.31–0.84% *outside* the true
     * edge on [QuadDetectorTest]'s two scenes. A margin would only hide
     * whether this rule is right, and on those two scenes the failure
     * direction is the harmless one: the old rule failed by cutting content,
     * which forces a rescan, this one by including a sliver of desk, which
     * the corner editor fixes. That is not universal, though: a single
     * least-squares fit per side, refit once after dropping the worst
     * quarter of residuals, is not proof against a bright patch on part of
     * the desk near an edge (a lamp reflection, uneven daylight). That can
     * tilt the fitted line and pull the far corner of the same edge inward,
     * into the page, instead — synthetic, measured, see `DECISIONS.md`
     * D-052.
     */
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
            for (d in 1 until depth) {
                val (a, b) = when (side) {
                    Side.LEFT -> sample(image, w, d - 1, scan) to sample(image, w, d + 1, scan)
                    Side.RIGHT -> sample(image, w, w - d, scan) to sample(image, w, w - d - 2, scan)
                    Side.TOP -> sample(image, w, scan, d - 1) to sample(image, w, scan, d + 1)
                    Side.BOTTOM -> sample(image, w, scan, h - d) to sample(image, w, scan, h - d - 2)
                }
                val step = b - a
                if (step > MIN_STEP) {
                    bestPosition = when (side) {
                        Side.LEFT, Side.TOP -> d
                        Side.RIGHT -> w - d - 1
                        Side.BOTTOM -> h - d - 1
                    }
                    break
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
