<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# The 50-document evaluation set

This is the most valuable asset in the project, and the only deliverable that
does not depend on anything compiling. Shoot it first.

## Shot list

Fifty photographs, taken with the phone, of documents that are actually hard.
The distribution matters more than the exact count in any one row: the set has
to contain the failures, not just the easy wins.

| # | Category | `category` | Conditions to include |
|---|---|---|---|
| 8 | Crumpled receipts | `receipt` | thermal paper, folds, faded ink, curl |
| 8 | Invoices and payslips | `invoice` | dense small type, tables, staples |
| 8 | Book and magazine pages | `book-page` | **page curvature**, gutter shadow, tight binding |
| 6 | Handwritten notes | `handwriting` | ruled paper, ballpoint, pencil |
| 5 | Whiteboards and posters | `whiteboard` | glare, non-frontal angle, reflections |
| 5 | Forms and contracts | `form` | boxes, signatures, stamps |
| 5 | Identity documents | `id-card` | **synthetic or anonymised only — see below** |
| 5 | Deliberately awful | `adversarial` | hand shadow across the page, one finger over a corner, low light, mixed colour temperature, motion blur |

Across the whole set, make sure these conditions appear at least three times
each, tagged in `conditions`:

`crumpled` · `curved` · `hand-shadow` · `finger-in-frame` · `low-light` ·
`glare` · `skewed` · `motion-blur` · `mixed-light` · `dense-text`

Languages: mostly `es`, with at least three documents each in `en`, `fr`, `de`,
`it` and `pt` — those are the six languages milestone M5 measures.

## Personal data

Non-negotiable, and it is in the plan (§5):

- Identity documents and your own invoices are **photographed, annotated and
  kept out of the repository**. They live in `private/`, which is git-ignored.
- What gets published for those categories is a **synthetic equivalent**: a
  realistic-looking document with invented data, photographed under the same
  conditions.
- `dart run harness/bin/harness.dart validate` fails if a document under `private/` is marked
  `"publish": true`. That check exists so a tired evening cannot leak a DNI.

## Ground truth

For each document, a `.txt` file with what a human reads on it, typed by hand,
in reading order. Line breaks do not matter — scoring collapses whitespace
unless run with `--strict`.

Type the text as it appears, including typos that are on the paper. The ground
truth is what the document says, not what it should have said.

## Manifest

`manifest.json`, one entry per document:

```json
{
  "version": 1,
  "documents": [
    {
      "id": "receipt-01",
      "file": "images/receipt-01.jpg",
      "groundTruth": "ground_truth/receipt-01.txt",
      "category": "receipt",
      "language": "es",
      "conditions": ["crumpled", "low-light"],
      "publish": true,
      "license": "CC-BY-4.0"
    }
  ]
}
```

Photographs you took yourself and may publish are `CC-BY-4.0`. Anything you did
not author, or that contains someone else's data, is `"publish": false` and
lives in `private/`.
