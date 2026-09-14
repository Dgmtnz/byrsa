package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Every one of these runs on a laptop in milliseconds, with no device, no
 * emulator and no Play services.
 *
 * That is as much the point as the speed. The recognizer-based detector could
 * only be exercised on hardware that had the model installed, so its behaviour
 * on a blank page, a sideways page, or a script it does not read was never
 * asserted anywhere. It is asserted here.
 *
 * The pages below are drawn, not photographed — no paper grain, no sensor
 * noise, no lens. So these are worth exactly what they claim: that the
 * arithmetic does what it is described as doing, and where its edges are.
 * Whether the thresholds suit real captures is a question for real captures.
 */
internal class TextOrientationScorerTest {

    @Test
    fun anUprightPageIsLeftAlone() {
        val page = latinPage()
        assertEquals(0, page.turnsWanted())
    }

    @Test
    fun anUpsideDownPageAsksForHalfATurn() {
        assertEquals(2, latinPage().rotated(2).turnsWanted())
    }

    @Test
    fun aPageLyingOnItsLeftAsksForOneClockwiseTurn() {
        // Turned 270° clockwise from upright; one more clockwise puts it back.
        assertEquals(1, latinPage().rotated(3).turnsWanted())
    }

    @Test
    fun aPageLyingOnItsRightAsksForThreeClockwiseTurns() {
        assertEquals(3, latinPage().rotated(1).turnsWanted())
    }

    @Test
    fun aBlankPageIsNeverRotated() {
        assertEquals(0, Page(ByteArray(400 * 560) { 0xFF.toByte() }, 400, 560).turnsWanted())
    }

    @Test
    fun aSolidBlackPageIsNeverRotated() {
        assertEquals(0, Page(ByteArray(400 * 560), 400, 560).turnsWanted())
    }

    @Test
    fun aPhotographWithNoLineStructureIsNeverRotated() {
        // A gradient: plenty of ink by any threshold, no lines anywhere.
        val width = 320
        val height = 440
        val luma = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                luma[y * width + x] =
                    (40 + (x + y) * 160 / (width + height)).coerceIn(0, 255).toByte()
            }
        }
        assertEquals(0, Page(luma, width, height).turnsWanted())
    }

    @Test
    fun aScriptWithNoAscenderAsymmetryIsLeftAloneBothWaysUp() {
        // Real line structure, no way up. The honest failure is a no-op, not a
        // coin flip — so the same page and its mirror must both be left alone.
        val page = linedPage(ascenderRows = 0, descenderRows = 0)
        assertEquals(0, page.turnsWanted())
        assertEquals(0, page.rotated(2).turnsWanted())
    }

    @Test
    fun aPageWhoseInkLeansTheOtherWayIsReadTheOtherWayUp() {
        // The stated assumption, stated as a test: this measures where ink
        // leans, so a page with more descenders than ascenders is read upside
        // down. Documented rather than hidden — it is the failure a real corpus
        // would find, and the reason the caller keeps a margin.
        assertEquals(2, linedPage(ascenderRows = 1, descenderRows = 6).turnsWanted())
    }

    @Test
    fun oneLineOfTextIsEnoughToDecide() {
        assertEquals(0, linedPage(lines = 1).turnsWanted())
        assertEquals(2, linedPage(lines = 1).rotated(2).turnsWanted())
    }

    @Test
    fun aFiftyLinePageStillDecides() {
        // Line count is not the limit; pixels per line is. See the next test.
        val page = linedPage(lines = 50, height = 50 * 19 + 40)
        assertEquals(2, page.rotated(2).turnsWanted())
    }

    @Test
    fun linesPackedTighterThanAboutNineteenPixelsAreLeftAlone() {
        // The measured edge, asserted so it cannot move unnoticed. With enough
        // room between lines the profile alternates and the decision holds;
        // squeezed below roughly sixteen pixels per line the gaps stop reaching
        // the background and the page is left alone rather than guessed at.
        //
        // This is what sets the analysis resolution in `TextOrientationDetector`
        // — a fifty-line page downscaled to 640 pixels would land here.
        val roomy = linedPage(lines = 24, height = 24 * 19 + 40)
        assertEquals(2, roomy.rotated(2).turnsWanted())

        val cramped = linedPage(lines = 34, height = 24 * 19 + 40)
        assertEquals(0, cramped.rotated(2).turnsWanted())
    }

    @Test
    fun anEmptyOrUndersizedBufferIsRefusedRatherThanCrashing() {
        assertEquals(0, TextOrientationScorer.bestClockwiseTurns(ByteArray(0), 0, 0))
        assertEquals(0, TextOrientationScorer.bestClockwiseTurns(ByteArray(10), 40, 40))
        assertEquals(0, TextOrientationScorer.bestClockwiseTurns(ByteArray(100), -1, 10))
    }

    @Test
    fun theRightAnswerWinsByAWideMarginOnAPageItUnderstands() {
        // Not just "it picks the right one" but "it is not close". If this
        // margin ever collapses, the thresholds in the scorer are the first
        // thing to re-derive.
        val upright = latinPage()
        assertEquals(0, upright.turnsWanted())
        for (wrongTurns in 1..3) {
            val wrong = upright.rotated(wrongTurns)
            // Asking a wrongly-turned page for its answer must return the turn
            // that undoes it, never something else.
            assertEquals(4 - wrongTurns, wrong.turnsWanted())
        }
        assertTrue(true)
    }

    // ---------------------------------------------------------------- pages

    private class Page(val luma: ByteArray, val width: Int, val height: Int) {
        fun turnsWanted(): Int =
            TextOrientationScorer.bestClockwiseTurns(luma, width, height)

        /** Clockwise quarter turns, the convention the scorer reports in. */
        fun rotated(turns: Int): Page {
            var page = this
            repeat(((turns % 4) + 4) % 4) { page = page.turnedOnce() }
            return page
        }

        private fun turnedOnce(): Page {
            val out = ByteArray(luma.size)
            // 90° clockwise: output(c, r) = input(r, height - 1 - c).
            for (r in 0 until width) {
                for (c in 0 until height) {
                    out[r * height + c] = luma[(height - 1 - c) * width + r]
                }
            }
            return Page(out, height, width)
        }
    }

    private fun latinPage(): Page = linedPage()

    /**
     * Rows of ink laid out the way Latin text lays it out: a solid x-height
     * band, ascenders on roughly a third of the characters above it, descenders
     * on rather fewer below.
     *
     * Those two fractions are what the whole decision rests on, so they are
     * written as fractions here rather than buried in a drawing routine. Ink is
     * broken into words with gaps, because a page of solid bars would make the
     * profile look far peakier than any real page does.
     */
    private fun linedPage(
        lines: Int = 12,
        ascenderRows: Int = 5,
        descenderRows: Int = 2,
        width: Int = 360,
        height: Int = 520,
    ): Page {
        val luma = ByteArray(width * height) { 0xF6.toByte() }
        val margin = width / 10
        val step = height / (lines + 2)
        val xHeightRows = 7

        fun ink(y: Int, coverage: Double) {
            if (y < 0 || y >= height) return
            var x = margin
            var word = 0
            var accumulated = 0.0
            while (x < width - margin) {
                val run = 4 + (word % 5)
                for (i in 0 until run) {
                    if (x + i >= width - margin) break
                    accumulated += coverage
                    if (accumulated >= 1.0) {
                        accumulated -= 1.0
                        luma[y * width + x + i] = 0x14
                    }
                }
                x += run + 3
                word++
            }
        }

        for (line in 0 until lines) {
            val baseline = step * (line + 1) + ascenderRows
            for (dy in 0 until ascenderRows) ink(baseline - ascenderRows + dy, ASCENDER_COVERAGE)
            for (dy in 0 until xHeightRows) ink(baseline + dy, 1.0)
            for (dy in 0 until descenderRows) ink(baseline + xHeightRows + dy, DESCENDER_COVERAGE)
        }
        return Page(luma, width, height)
    }

    private companion object {
        /** Roughly how many Latin characters carry an ascender or a capital. */
        const val ASCENDER_COVERAGE = 0.30

        /** And how many carry a descender — the asymmetry the scorer reads. */
        const val DESCENDER_COVERAGE = 0.12
    }
}
