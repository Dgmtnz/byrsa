// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

package dev.byrsa.byrsa_capture

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The scene that broke: a user scanned a plain sheet and the crop cut off the
 * title at the top and the footer at the bottom, left and right fine.
 *
 * The scenes below are synthetic pages on a synthetic desk, which is the only
 * thing a JVM unit test can be — but they are the situations that decided the
 * detection rule, and **no one of them alone guards it**. Measured by putting
 * each wrong rule back and re-running:
 *
 *  - keeping the strongest step over the whole search depth, which is what
 *    shipped: top edge lands on the title, +4.69% into the page. Both bright
 *    scenes catch it.
 *  - keeping the outermost step by magnitude, the tempting simplification of
 *    the fix: the title scene **passes**, and the shadow scene catches it at
 *    -2.92%, the width of the shadow band. Only the sign of the step tells the
 *    desk→shadow fall from the shadow→paper rise.
 *  - dropping the sign check entirely: a document darker than its background
 *    would get a plausible-looking quad instead of the `null` the fix now
 *    requires. Only the dark-document scene catches that.
 *
 * So the obvious test — the one that reproduces the bug the user reported —
 * cannot by itself tell the right rule from either near-miss. Delete the
 * shadow scene or the dark-document scene and this file stops guarding
 * something that matters.
 */
class QuadDetectorTest {

    /**
     * Within 1% of the frame, and the headroom is thin on purpose: the worst
     * measured error is -0.84% on the left, which is two pixels at the
     * detector's 240-pixel working width. The double 3-tap blur spreads an edge
     * over ~4 work pixels and the first qualifying sample lands on the outer
     * end of that ramp, so all four sides come out *outside* the paper — the
     * harmless direction, a sliver of desk in the crop rather than a lost line
     * of text.
     */
    private val tolerance = 0.010f

    @Test
    fun `the crop follows the paper, not the title and the footer`() {
        assertPageEdges(scene(shadow = false), "plain page on a desk")
    }

    @Test
    fun `the crop follows the paper, not the shadow the page casts`() {
        assertPageEdges(scene(shadow = true), "page casting a shadow")
    }

    @Test
    fun `the crop refuses a document darker than its background`() {
        assertNull(
            QuadDetector.detect(scene(darkDoc = true), frameWidth, frameHeight, frameWidth),
            "a document darker than its background should return no quad, not a wrong one",
        )
    }

    // --- the scene ------------------------------------------------------

    // 480x640 makes the detector downscale by 2, so the test runs the same
    // work-resolution path a phone frame does.
    private val frameWidth = 480
    private val frameHeight = 640

    // The page fills 85% of each dimension, which is what the capture UI asks
    // the user to do.
    private val pageLeft = 0.075f
    private val pageRight = 0.925f
    private val pageTop = 0.075f
    private val pageBottom = 0.925f

    private val desk = 185
    private val shadowBand = 150
    private val paper = 235
    private val ink = 60

    /**
     * @param shadow adds the darker ring a sheet casts on the surface under it,
     *   2.5% of the frame wide. Going inwards you meet desk→shadow, a fall,
     *   before shadow→paper, a rise: a rule that stops at the outermost step by
     *   magnitude stops on the wrong one.
     * @param darkDoc swaps the page and the desk luminance, so the page is
     *   darker than what surrounds it. `fitEdge` requires a signed rise
     *   (dark outside, bright inside) on every side, so this must find none
     *   and `detect` must return `null` rather than a wrong quad.
     */
    private fun scene(shadow: Boolean = false, darkDoc: Boolean = false): ByteArray {
        val pageColor = if (darkDoc) desk else paper
        val surfaceColor = if (darkDoc) paper else desk
        val image = ByteArray(frameWidth * frameHeight)
        for (y in 0 until frameHeight) {
            val ny = (y + 0.5f) / frameHeight
            for (x in 0 until frameWidth) {
                val nx = (x + 0.5f) / frameWidth
                val onPage = nx >= pageLeft && nx <= pageRight &&
                    ny >= pageTop && ny <= pageBottom
                val inShadow = shadow && !onPage &&
                    nx >= pageLeft - 0.025f && nx <= pageRight + 0.025f &&
                    ny >= pageTop - 0.025f && ny <= pageBottom + 0.025f
                val value = when {
                    // A full-width title band 5% below the top of the page, and
                    // a footer rule 3% above the bottom of it. Ink on white is
                    // a step of 175; paper against this desk is a step of 50.
                    // Left out for darkDoc: ink darker than the page would put
                    // a second, spurious rise back in at the far edge of each
                    // band (dark ink -> light page again), which is exactly
                    // the kind of candidate this scene exists to have none of.
                    onPage && !darkDoc && ny >= 0.125f && ny <= 0.165f -> ink
                    onPage && !darkDoc && ny >= 0.885f && ny <= 0.897f -> ink
                    // The same two bands, mirrored onto columns instead of
                    // rows: without them nothing ever gives a LEFT/RIGHT scan
                    // line a second, deeper step to wrongly prefer, so the
                    // outermost-step rule was only ever exercised top/bottom.
                    onPage && !darkDoc && nx >= 0.125f && nx <= 0.165f -> ink
                    onPage && !darkDoc && nx >= 0.885f && nx <= 0.897f -> ink
                    onPage -> pageColor
                    inShadow -> shadowBand
                    else -> surfaceColor
                }
                image[y * frameWidth + x] = value.toByte()
            }
        }
        return image
    }

    // --- the assertion --------------------------------------------------

    private fun assertPageEdges(image: ByteArray, what: String) {
        val quad = assertNotNull(
            QuadDetector.detect(image, frameWidth, frameHeight, frameWidth),
            "$what: the detector found no quad at all",
        )
        val p = quad.points
        // TL, TR, BR, BL.
        near(what, "top-left x", pageLeft, p[0])
        near(what, "top-left y", pageTop, p[1])
        near(what, "top-right x", pageRight, p[2])
        near(what, "top-right y", pageTop, p[3])
        near(what, "bottom-right x", pageRight, p[4])
        near(what, "bottom-right y", pageBottom, p[5])
        near(what, "bottom-left x", pageLeft, p[6])
        near(what, "bottom-left y", pageBottom, p[7])
    }

    private fun near(what: String, corner: String, expected: Float, actual: Float) {
        val error = actual - expected
        assertTrue(
            abs(error) <= tolerance,
            "$what: $corner is $actual, expected $expected " +
                "(off by ${"%+.4f".format(error)}, tolerance $tolerance)",
        )
    }
}
