package dev.doclens.doclens

/**
 * Decides which of the four 90° rotations makes a page's text read upright,
 * from the pixels alone.
 *
 * No model, no download, no Play services — and no Android types, so every
 * decision below is unit-testable on a laptop. [TextOrientationDetector] is the
 * thin Bitmap wrapper around it.
 *
 * ## How it works
 *
 * Two observations do all the work.
 *
 * **Lines of text make a spiky projection profile.** Summing ink along the
 * rows of a page whose text runs horizontally gives a strong alternation —
 * dense where a line sits, near-empty in the leading between lines. Summing
 * along the rows of the same page turned sideways gives something nearly flat,
 * because every row now crosses every line. So the axis is settled by which
 * profile is peakier, and peakiness is just variance.
 *
 * **Latin text has more ink above the x-height band than below it.** Ascenders
 * and capitals — b, d, f, h, k, l, t, and every capital — are far more common
 * than descenders — g, j, p, q, y. Measuring the ink just above each dense band
 * against the ink just below it tells upright from upside-down, which the
 * variance alone cannot: a page and the same page rotated 180° have identical
 * profiles read in opposite directions.
 *
 * Which is why only two profiles are computed for four rotations. Rotating the
 * page a quarter turn swaps rows for columns; rotating it a half turn reads the
 * same profile backwards. The reversal is not an optimisation, it is the same
 * arithmetic the asymmetry test needs.
 *
 * ## What it deliberately does not do
 *
 * It does not read. It has no opinion about words, languages or scripts — it
 * measures where ink sits. That makes it work on any script whose lines run
 * horizontally with an asymmetric body, and makes it useless on one that does
 * not; see [uprightness] for what happens then, which is nothing.
 */
internal object TextOrientationScorer {

    /**
     * Clockwise quarter turns that make [luma] read upright, `0..3`.
     *
     * `0` whenever the evidence is weak, which is most of the ways this can go
     * wrong: a blank page, a photograph, a diagram, a script this does not suit.
     * Leaving a page alone is always the safe answer — an unrotated scan is
     * readable and a wrongly rotated one is not.
     */
    fun bestClockwiseTurns(luma: ByteArray, width: Int, height: Int): Int {
        if (width <= 0 || height <= 0 || luma.size < width * height) return 0

        val threshold = otsuThreshold(luma, width * height)
        val rows = IntArray(height)
        val columns = IntArray(width)
        for (y in 0 until height) {
            val base = y * width
            for (x in 0 until width) {
                // Ink is dark, and the threshold is the top of the dark
                // class, so it belongs to the ink. `luma` is unsigned in a byte.
                if ((luma[base + x].toInt() and 0xFF) <= threshold) {
                    rows[y]++
                    columns[x]++
                }
            }
        }

        // A quarter turn clockwise makes columns into rows; a half turn reads a
        // profile backwards. Four rotations, two profiles.
        val scores = doubleArrayOf(
            score(rows, width),                 // 0°
            score(columns, height),             // 90° clockwise
            score(rows.reversedCopy(), width),  // 180°
            score(columns.reversedCopy(), height), // 270° clockwise
        )

        var best = 0
        for (turns in 1..3) if (scores[turns] > scores[best]) best = turns
        if (best == 0) return 0

        // Biased toward leaving the page as it is, and the bias is not
        // timidity. Upside-down text scores *something* on every measure here,
        // so a flipped page can edge out the upright one on a page with few
        // ascenders. A scan left alone is merely not improved; a scan turned
        // the wrong way is worse than what the camera saw.
        val asIs = scores[0]
        return if (scores[best] >= MIN_CONFIDENCE && scores[best] >= asIs * MIN_ROTATE_MARGIN) {
            best
        } else {
            0
        }
    }

    /** A non-zero rotation must beat the as-is score by this factor to win. */
    private const val MIN_ROTATE_MARGIN = 1.30

    /**
     * And clear this on its own, so a rotation cannot win merely by both
     * scores being noise.
     *
     * Measured against the synthetic pages in `TextOrientationScorerTest`:
     * the correct rotation scores 0.21 to 0.41 across every case there, from a
     * single line to fifty, and every wrong hypothesis scores at most 0.008.
     * This sits twelve times above the noise and twice below the weakest
     * correct answer.
     *
     * Those are drawn pages, not photographs. If real captures land lower this
     * is the number to move, and those test pages are where to argue about it.
     */
    private const val MIN_CONFIDENCE = 0.10

    /**
     * How strongly this profile looks like upright lines of text.
     *
     * The product of two independent things: whether there are lines at all,
     * and whether they are the right way up. Either being zero makes the whole
     * score zero, which is the behaviour that matters — a page with no line
     * structure never gets rotated, however asymmetric its ink happens to be.
     */
    private fun score(profile: IntArray, span: Int): Double {
        if (!alternates(profile)) return 0.0
        val peaky = peakiness(profile, span)
        if (peaky <= 0.0) return 0.0
        return peaky * uprightness(profile)
    }

    /**
     * Whether the profile goes up and down rather than simply along.
     *
     * Variance alone cannot tell lines of text from a gradient: a photograph
     * lit from one corner produces a clean ramp, which has plenty of variance
     * and — read backwards — plenty of apparent ascender asymmetry, because its
     * one "band" sits at an end with all the ink on one side. Measured on such
     * a page it scored 0.52, higher than any real page of text here.
     *
     * Text is an alternation, so its profile crosses its own mean twice per
     * line: twenty-four times on a twelve-line page, twice on a single line. A
     * monotonic ramp crosses once. Two is the whole test, and it is the
     * difference between a document and a photograph of a wall.
     */
    private fun alternates(profile: IntArray): Boolean {
        if (profile.size < 3) return false
        var sum = 0.0
        for (count in profile) sum += count
        val mean = sum / profile.size
        var crossings = 0
        for (i in 1 until profile.size) {
            if ((profile[i - 1] - mean) * (profile[i] - mean) < 0.0) crossings++
            if (crossings >= 2) return true
        }
        return false
    }

    /**
     * Variance of the profile, scaled so it does not depend on how much ink is
     * on the page.
     *
     * For fractions in `0..1` with mean `m`, the largest variance achievable is
     * `m(1 - m)` — all-or-nothing rows. Dividing by it gives a figure that
     * means the same on a dense contract and a sparse note, which a raw
     * variance does not.
     */
    private fun peakiness(profile: IntArray, span: Int): Double {
        if (profile.isEmpty() || span <= 0) return 0.0
        var sum = 0.0
        for (count in profile) sum += count.toDouble() / span
        val mean = sum / profile.size
        // An empty page and a solid black one are both featureless.
        if (mean <= 1e-6 || mean >= 1.0 - 1e-6) return 0.0

        var variance = 0.0
        for (count in profile) {
            val delta = count.toDouble() / span - mean
            variance += delta * delta
        }
        variance /= profile.size
        return (variance / (mean * (1.0 - mean))).coerceIn(0.0, 1.0)
    }

    /**
     * How much the ink leans the way upright Latin text leans, `0..1`.
     *
     * Each dense band is taken to be a line's x-height. The ink in a band's own
     * height above it is ascenders and capitals; the ink the same distance
     * below is descenders. More above than below means upright.
     *
     * Returns `0` when the two are equal, which is both the honest answer for a
     * symmetric script and the answer that stops this from rotating anything it
     * does not understand.
     */
    private fun uprightness(profile: IntArray): Double {
        var peak = 0
        for (count in profile) if (count > peak) peak = count
        if (peak == 0) return 0.0

        val dense = peak / 2
        var above = 0.0
        var below = 0.0
        var index = 0
        while (index < profile.size) {
            if (profile[index] <= dense) {
                index++
                continue
            }
            val start = index
            while (index < profile.size && profile[index] > dense) index++
            val bandHeight = index - start

            for (offset in 1..bandHeight) {
                val up = start - offset
                if (up >= 0 && profile[up] <= dense) above += profile[up].toDouble()
                val down = index - 1 + offset
                if (down < profile.size && profile[down] <= dense) {
                    below += profile[down].toDouble()
                }
            }
        }

        val total = above + below
        if (total <= 0.0) return 0.0
        // 0.5 is no evidence either way, and maps to zero rather than a half.
        return (2.0 * (above / total) - 1.0).coerceAtLeast(0.0)
    }

    /**
     * Otsu's threshold: the grey level that best separates the histogram into
     * two groups.
     *
     * A fixed threshold would work on the flattened crops this normally sees
     * and fail on everything else, and the caller cannot promise the crop was
     * enhanced first.
     */
    private fun otsuThreshold(luma: ByteArray, count: Int): Int {
        val histogram = IntArray(256)
        for (i in 0 until count) histogram[luma[i].toInt() and 0xFF]++

        var total = 0.0
        for (level in 0..255) total += level.toDouble() * histogram[level]

        var backgroundSum = 0.0
        var backgroundCount = 0
        var bestVariance = -1.0
        var best = 128
        for (level in 0..255) {
            backgroundCount += histogram[level]
            if (backgroundCount == 0) continue
            val foregroundCount = count - backgroundCount
            if (foregroundCount == 0) break

            backgroundSum += level.toDouble() * histogram[level]
            val backgroundMean = backgroundSum / backgroundCount
            val foregroundMean = (total - backgroundSum) / foregroundCount
            val delta = backgroundMean - foregroundMean
            val between = backgroundCount.toDouble() * foregroundCount * delta * delta
            if (between > bestVariance) {
                bestVariance = between
                best = level
            }
        }
        return best
    }

    private fun IntArray.reversedCopy(): IntArray {
        val out = IntArray(size)
        for (i in indices) out[i] = this[size - 1 - i]
        return out
    }
}
