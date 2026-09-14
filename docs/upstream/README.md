<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Upstream

Byrsa is built on other people's free software, and the standing rule is that a
problem we find in a dependency goes back to that dependency rather than into a
private fork. A fork solves it for us; a patch solves it for everyone who ever
tries the same thing.

Each file here is an issue or pull request written out in full, with the
evidence attached, ready to post. They are drafted here first so that the
reasoning is versioned alongside the code that depends on it.

**Re-verify before filing, always.** All three were drafted on 2026-09-09 and
re-checked on 2026-09-14. In five days `doclens` shipped three releases, and one
of the four things this repository asked `mobile_ocr` for turned out to already
exist. A claim that was true when drafted is not a claim that is true when filed,
and the cost of finding that out from a maintainer instead of from `HEAD` is paid
in credibility. Each file now carries the date it was last checked and against
which commit.

| # | Project | What | Estado (re-verificado 2026-09-14) |
|---|---|---|---|
| [1](doclens-play-services.md) | `doclens` | Play Services is an unconditional dependency, which makes the plugin unusable for F-Droid. Two pull requests, the first of which removes a dependency without removing a feature | **listo para enviar — enviar primero.** Reafirmado contra 0.0.12; el mantenedor mergeó dos PRs de fuera el 12-sep, así que es el único de los tres con probabilidad real de merge |
| [2](mobile-ocr-pub-dev.md) | `mobile_ocr` | Ahora son dos issues: el primero **aporta** la traza de licencias de los cuatro artefactos y pregunta por una discrepancia medida en `cls.onnx`; el segundo pide pub.dev y avisa del KGP | **listo para enviar.** Una de las cuatro peticiones originales era falsa (el `LICENSE` sí existe) y se ha quitado |
| [3](onnxruntime-flutter-compilesdk.md) | `onnxruntime_flutter` | `compileSdkVersion 33` breaks every release build against current AndroidX, and its vendored `libonnxruntime.so` collides with the official AAR | **listo para enviar, sin esperar respuesta.** La afirmación se sostiene en HEAD, pero el proyecto lleva 21 meses sin commits y 37 issues abiertos. Vale como documentación pública, no como relación |

None of the three is a blocker for Byrsa any more, and all of them are written
that way on purpose. `byrsa_capture` carries its own detector; `byrsa_ocr` keeps
the git dependency quarantined in a separate package; the ONNX collision is
already pinned deterministically on our side. Asking from a position of not
needing the favour makes for a better patch and a better ask — and it means no
milestone depends on a stranger's calendar.

## Filing them

```
tool/upstream_ready.sh
```

writes each draft's postable body to `docs/upstream/out/`, with this
repository's own notes stripped — the `<!-- internal -->` blocks that record
which version was examined and when it was last re-verified, which a maintainer
has no use for. One source, no second copy to drift.

Then, with your own account:

```
gh issue create --repo govindmaheshwari2/doclens \
  --title "ML Kit / Play Services is an unconditional dependency, which rules the plugin out for F-Droid" \
  --body-file docs/upstream/out/doclens-play-services.md

gh issue create --repo ente-io/mobile_ocr \
  --title "Licence audit of the three PP-OCR models, and a question about cls.onnx" \
  --body-file docs/upstream/out/mobile-ocr-pub-dev.md

gh issue create --repo gtbluesky/onnxruntime_flutter \
  --title "compileSdkVersion 33 breaks release builds against current AndroidX" \
  --body-file docs/upstream/out/onnxruntime-flutter-compilesdk.md
```

The `mobile_ocr` draft carries two issues in one file; the second, the pub.dev
request, is worth filing separately once the first has an answer.

The order to file them in is the order of the table. `doclens` first, because it
is the one a maintainer is demonstrably reading; `mobile_ocr` second, leading
with what the licence audit found rather than with the request; the ONNX issue
whenever, since nobody is waiting on the other end.
