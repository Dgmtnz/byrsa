<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# The synthetic corpus — fifty documents, half of them badly photographed

Generated, seeded and reproducible. Regenerate identical bytes with:

```
python3 tool/make_corpus.py harness/dataset/synthetic/content.json \
        --out harness/dataset/synthetic --damaged 25
```

## What this is NOT

**It is not the fifty photographs.** Nothing here has paper grain, real optics,
a real sensor, rolling shutter, or the lighting of an actual room. D-039 (does
any shadow network earn its 120 MB) and D-042 (does intrusion removal get turned
on) are waiting on real pages measured by character error rate, and this corpus
does not close either of them. Neither does it let the funding application quote
a CER figure as though it came from real captures.

Anyone tempted to treat these numbers as the real ones should read
[`DECISIONS.md`](../../../DECISIONS.md) D-039, which records the project already
measuring a neural stage against synthetic shadows and finding the test biased.

## What it IS, and why it was worth building

**It has exact ground-truth text.** That is the thing the fifty photographs will
never have without someone typing all fifty out by hand. So character error rate
is measurable automatically, on every commit, starting now — and until this
existed the harness had no text to score against at all, which is why
`harness synth` wrote empty ground-truth files on purpose.

It also gives every restoration change a numeric regression guard against a known
clean original, and it means that when the real photographs arrive the tooling
has already been debugged.

## The shape of it

| | |
|---|---|
| Documents | 50 |
| Damaged / clean | 25 / 25 |
| Languages | es 29 · pt 5 · en 4 · de 4 · fr 4 · it 4 |
| Categories | receipt 8 · invoice 8 · book-page 8 · handwriting 6 · whiteboard 5 · form 5 · id-card 5 · adversarial 5 |
| Each physical condition | at least 3 documents |

**The twenty-five clean pages are not a filler half.** They are the regression
guard nobody had: a pipeline that damages ordinary good input would pass every
test in this repository today. They still go through a lens blur, sensor noise
and JPEG, because a clean *photograph* is not a scan.

## The damage, and why each one is modelled the way it is

| Condition | What it models |
|---|---|
| `hand-shadow` | Attenuation **plus** ambient fill **plus** the blue cast a real shadow has. Deliberately not purely multiplicative — dividing by an estimated background inverts a multiplicative shadow exactly, which flatters the classical pipeline. D-039 records that finding; this keeps the corpus honest |
| `curved` | A vertical cylinder with edge foreshortening: a book that will not lie flat |
| `crumpled` | Local displacement along fold lines, with the shading a crease casts |
| `finger-in-frame` | A fingertip over one corner with its contact shadow, drawn in **six widely different skin tones on purpose**. D-042 removes intrusions by finding an object that does not belong, explicitly not by detecting skin colour, and a detector that quietly learned one tone should fail here |
| `glare` | A specular highlight that clips to white — information genuinely destroyed, not merely darkened |
| `low-light` | Gain below half, with the sensor noise that comes with it |
| `mixed-light` | Daylight on one side, tungsten on the other. Breaks a single global white balance |
| `motion-blur` | Directional smear from an unsteady hand |
| `skewed` | The page not square to the camera |

## Identity documents

The five `id-card` documents are **invented specimens** and are published on
purpose. Every one names a country that does not exist — Altravia, Marbelia,
Ejemplolandia, Valdorina, Sobreirinha — carries a "MUESTRA · SIN VALIDEZ" mark
or its equivalent in the document's language, and contains no real person's data.
They exist to test OCR on short label-value text and nothing else. They are not
modelled on any real country's document and must never be edited to become so.

This is the synthetic equivalent the dataset README promises for the categories
that cannot be published from real life.

## How the text was written, and checked

Content was drafted per category and then proofread per language by a separate
pass, because this corpus exists largely to measure whether OCR recovers `ñ`,
`á`, `ü`, `ç`, `ã`, `¿` and `¡` — text with the accents missing would measure
nothing. Fifty corrections came out of that second pass.

The renderer refuses silently-dropped characters: before writing, every
character of the ground truth is probed against the font, and anything the face
cannot draw is reported. A ground truth containing a character the image does
not show would produce an error rate that blames the OCR engine for the corpus's
own gap.

Legibility was then checked rather than assumed — see
[`docs/measurements.md`](../../../docs/measurements.md), 2026-09-14.

## Licence

`CC0-1.0`. Everything here is invented; there is nothing to attribute and no
personal data to protect.
