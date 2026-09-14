package dev.doclens.doclens

import android.graphics.Bitmap
import kotlin.math.max

/**
 * Detects the dominant text direction of a (already dewarped) document crop so
 * the caller can rotate it upright.
 *
 * Classical image statistics over the crop's own pixels: no model, no download,
 * no Play services, and nothing to be unavailable. [TextOrientationScorer]
 * holds the arithmetic and is unit-tested on the JVM; this is the Bitmap
 * wrapper around it.
 *
 * It keeps the behaviour the recognizer-based version had: the crop is judged
 * at each of the four 90° rotations, the best wins, and a weak result leaves
 * the crop untouched rather than guessing.
 *
 * Unlike the recognizer, it does not read, so it is not tied to a script. A
 * page whose lines run horizontally and whose ink sits asymmetrically about the
 * baseline is handled whatever alphabet it is written in — and a page where
 * that does not hold is left alone rather than rotated on a coin flip.
 *
 * Safe on any thread; it does no I/O and blocks on nothing.
 */
object TextOrientationDetector {

    /**
     * Number of clockwise 90° turns to apply to [bitmap] so its dominant text
     * reads upright (`0..3`). Returns `0` when no confident text orientation is
     * found — a blank or graphical page, or one this cannot judge.
     */
    fun bestClockwiseTurns(bitmap: Bitmap): Int {
        val small = downscale(bitmap, ANALYSIS_MAX_DIMENSION)
        return try {
            val width = small.width
            val height = small.height
            if (width <= 0 || height <= 0) return 0

            val pixels = IntArray(width * height)
            small.getPixels(pixels, 0, width, 0, 0, width, height)

            // Rec. 601 luma, in integers. The exact coefficients do not matter
            // here — this feeds a threshold, not a colour conversion — but
            // weighting green is what keeps blue ink dark instead of pale.
            val luma = ByteArray(pixels.size)
            for (i in pixels.indices) {
                val pixel = pixels[i]
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                luma[i] = ((r * 77 + g * 150 + b * 29) shr 8).toByte()
            }

            TextOrientationScorer.bestClockwiseTurns(luma, width, height)
        } finally {
            if (small !== bitmap) small.recycle()
        }
    }

    /**
     * Longest side the analysis runs on. Unchanged from the recognizer-based
     * version, and for a measured reason rather than caution.
     *
     * What this needs is not resolution enough to read a glyph but enough for
     * the gap between two text lines to survive downscaling. Measured on the
     * synthetic pages: the decision holds down to about **19 pixels per text
     * line** and collapses by 16, whatever the line count. A dense A4 page runs
     * to fifty lines, so 1000 leaves 20 per line and 640 would leave 13 — on
     * the wrong side of that edge, and it is the densest pages, the contracts
     * and the terms and conditions, that would silently stop being corrected.
     */
    private const val ANALYSIS_MAX_DIMENSION = 1000

    private fun downscale(src: Bitmap, maxDimension: Int): Bitmap {
        val maxDim = max(src.width, src.height)
        if (maxDim <= maxDimension) return src
        val scale = maxDimension.toFloat() / maxDim
        val w = max(1, (src.width * scale).toInt())
        val h = max(1, (src.height * scale).toInt())
        return Bitmap.createScaledBitmap(src, w, h, true)
    }
}
