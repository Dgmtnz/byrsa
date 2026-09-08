<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Evaluation harness

Claiming to match a commercial scanner means nothing without evidence. This is
the evidence: **50 real documents**, a fixed scoring script, and reports that
anyone who clones the repository can reproduce.

Fifty is a fixed number. It is the same fifty in the plan, in milestone M2 and
in the funding application.

## Two halves, on purpose

Running the pipeline needs a phone. Scoring does not. So they are separate:

```
device  ──►  run.json  ──►  dart run harness/bin/harness.dart score  ──►  report.md / .csv / .json
```

A run is produced on a device (or on a desktop, for the classical baseline) and
writes a JSON file. Everything downstream is pure Dart and runs in Linux CI
today. One implementation of the arithmetic, two places it can be fed from.
See `DECISIONS.md` D-019.

## Commands

```
dart run harness/bin/harness.dart validate                       # dataset is complete and consistent
dart run harness/bin/harness.dart score --results out/run.json   # score a run, write the report
dart run harness/bin/harness.dart score --results out/run.json --strict   # don't collapse whitespace
```

Try it without waiting for the fifty documents:

```
dart run harness/bin/harness.dart score \
  --dataset harness/example/dataset \
  --results harness/example/run.json \
  --out harness/example/out
```

Those are invented documents and invented timings — see
[`example/README.md`](example/README.md). They exist to show the file formats
and what a report looks like, including what it looks like when a run misses a
document entirely.

## What gets reported

- **Character error rate** and **word error rate**, aggregated by total edit
  distance over total reference length — not as an average of per-document
  averages, which flatters short documents.
- **Median and 90th-percentile** time per document. The tail is what a user
  feels.
- Per-stage timings, including stages that were **skipped** and why.
- CER per category, so "it is bad at whiteboards" is visible rather than
  averaged away.
- The **worst ten documents**, in a table that is allowed to look bad.

A document the run produced nothing for counts as a complete failure. It is not
dropped from the average.

Every report prints the **platform it was measured on**, at the top. Numbers do
not transfer between platforms and no report here implies that they do.

## Run file format

```json
{
  "run": {
    "id": "pixel6a-2026-09-20",
    "device": "Pixel 6a, Android 14",
    "platform": "android",
    "build": "byrsa 0.1.0+3, release",
    "startedAt": "2026-09-20T10:14:00Z",
    "pipeline": ["capture", "restore", "ocr"]
  },
  "documents": [
    {
      "id": "receipt-01",
      "text": "recognised text, exactly as the pipeline produced it",
      "outputBytes": 481203,
      "stages": [
        {"name": "restore", "milliseconds": 312, "peakMemoryBytes": 184549376},
        {"name": "ocr", "milliseconds": 702}
      ]
    }
  ]
}
```

A stage that could not run is recorded, not omitted:

```json
{"name": "restore", "milliseconds": 0, "skipped": true, "skipReason": "model not downloaded"}
```

## The dataset

See [`dataset/README.md`](dataset/README.md) for the shot list and the rules on
personal data. Short version: identity documents and personal invoices are
annotated privately and published only as synthetic equivalents. `private/` is
git-ignored and `dart run harness/bin/harness.dart validate` fails if a private document is
marked publishable.

## Publishing unfavourable results

Every result gets published, including the ones that are worse than a
proprietary scanner. A benchmark that only ever looks good is not a benchmark,
and a reviewer can tell the difference.
