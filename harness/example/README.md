<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# A worked example

Two invented documents and one invented run, so the harness can be tried
without waiting for the real fifty to be photographed.

```
dart run harness/bin/harness.dart score \
  --dataset harness/example/dataset \
  --results harness/example/run.json \
  --out harness/example/out
```

**These are not results.** The texts are made up, the timings are made up, and
the numbers this produces mean nothing about the pipeline. It exists to show
the file formats and what the report looks like — including what it looks like
when a run misses a document entirely, which is the case the example
deliberately includes.
