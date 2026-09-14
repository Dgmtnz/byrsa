# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
"""Renders the synthetic evaluation corpus: 50 documents, half of them damaged.

    python3 tool/make_corpus.py content.json --out harness/dataset/synthetic

Why this is Python and not Dart, in a repository that is otherwise Dart: the
corpus has to be readable in six languages, and `package:image`'s bundled bitmap
fonts are ASCII-only — they render "Ñandú, cigüeña" as " and , cig e a". A
ground truth the renderer cannot draw is not a ground truth. Pillow with the
Liberation faces covers Latin-1 and Latin Extended-A, which is every character
the six target languages need. `tool/gen_font_metrics.py` set the precedent that
a build-time asset tool may be Python.

WHAT THIS IS NOT. It is not the fifty photographs. Real captures carry paper
grain, lens blur, sensor noise, rolling shutter and lighting no formula
reproduces, and D-039 and D-042 are explicitly waiting on real pages measured by
CER. What this IS: a corpus with exact ground-truth text, which the photographs
will never have without hand annotation — so it can measure character error rate
automatically, today, on every commit.

Everything is seeded. The same content file produces the same bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import unicodedata
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# --------------------------------------------------------------------- fonts

FONT_DIR = Path("/usr/share/fonts/liberation")
FACES = {
    "sans": FONT_DIR / "LiberationSans-Regular.ttf",
    "sans-bold": FONT_DIR / "LiberationSans-Bold.ttf",
    "serif": FONT_DIR / "LiberationSerif-Regular.ttf",
    "serif-bold": FONT_DIR / "LiberationSerif-Bold.ttf",
    "mono": FONT_DIR / "LiberationMono-Regular.ttf",
    "mono-bold": FONT_DIR / "LiberationMono-Bold.ttf",
}

# Each category picks a face and a page shape, because a receipt that looks like
# a book page tests nothing a book page did not already test.
STYLE = {
    #                face     width height  base  margin
    "receipt":      ("mono",   760, 1800,   21,   46),
    "invoice":      ("sans",  1240, 1754,   20,   72),
    "book-page":    ("serif", 1240, 1754,   23,  110),
    "handwriting":  ("serif", 1100, 1500,   30,   80),
    "whiteboard":   ("sans",  1600, 1100,   38,   70),
    "form":         ("sans",  1240, 1754,   21,   78),
    "id-card":      ("sans",  1080,  680,   24,   44),
    "adversarial":  ("sans",  1240, 1754,   16,   60),
}

DENSITY_SCALE = {"sparse": 1.22, "normal": 1.0, "dense": 0.84}

_font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


def font(face: str, size: int) -> ImageFont.FreeTypeFont:
    key = (face, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(str(FACES[face]), size)
    return _font_cache[key]


def assert_renderable(text: str, where: str) -> list[str]:
    """Characters the Liberation faces cannot draw would silently become boxes.

    A ground truth containing a character the image does not show is a
    measurement bug that looks like an OCR failure, so it is caught here rather
    than discovered in a CER number nobody can explain.
    """
    bad = []
    probe = font("sans", 20)
    for ch in sorted(set(text)):
        if ch in "\n\t " or ch.isspace():
            continue
        if probe.getmask(ch).getbbox() is None and not ch.isspace():
            bad.append(f"{where}: U+{ord(ch):04X} {unicodedata.name(ch, '?')!r} ({ch!r})")
    return bad


# ------------------------------------------------------------------ layout

def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, width: int) -> list[str]:
    """Greedy wrap on measured width, not on a character count guess."""
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = f"{line} {w}".strip()
        if draw.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def render_page(doc: dict, rng: random.Random) -> tuple[Image.Image, str]:
    """Draws one clean page and returns it with the exact text it shows.

    Ground truth is produced HERE, from what was actually drawn, rather than
    taken from the content file. If a line is dropped for lack of room it is
    dropped from both, so the two cannot drift apart.
    """
    cat = doc["category"]
    face, W, H, base, margin = STYLE[cat]
    base = max(11, int(base * DENSITY_SCALE[doc.get("density", "normal")]))

    page = Image.new("RGB", (W, H), (252, 251, 247))
    draw = ImageDraw.Draw(page)
    inner = W - 2 * margin
    truth: list[str] = []
    y = margin

    def room(h: int) -> bool:
        return y + h < H - margin

    for block in doc["blocks"]:
        kind = block.get("kind")

        if kind == "spacer":
            y += base
            continue

        if kind == "rule":
            if not room(base):
                break
            draw.line([(margin, y + base // 2), (W - margin, y + base // 2)],
                      fill=(120, 120, 128), width=1)
            y += base
            continue

        if kind == "heading":
            fnt = font(f"{face}-bold" if f"{face}-bold" in FACES else face, int(base * 1.5))
            for line in wrap(draw, block.get("text", ""), fnt, inner):
                h = int(base * 1.9)
                if not room(h):
                    break
                draw.text((margin, y), line, font=fnt, fill=(16, 16, 22))
                truth.append(line)
                y += h
            y += base // 2
            continue

        if kind == "paragraph":
            fnt = font(face, base)
            for line in wrap(draw, block.get("text", ""), fnt, inner):
                h = int(base * 1.5)
                if not room(h):
                    break
                draw.text((margin, y), line, font=fnt, fill=(22, 22, 28))
                truth.append(line)
                y += h
            y += base // 2
            continue

        if kind == "kv":
            fnt = font(face, base)
            label, value = block.get("label", ""), block.get("value", "")
            h = int(base * 1.6)
            if not room(h):
                break
            draw.text((margin, y), label, font=fnt, fill=(60, 60, 68))
            vw = draw.textlength(value, font=fnt)
            draw.text((W - margin - vw, y), value, font=fnt, fill=(16, 16, 22))
            truth.append(f"{label} {value}".strip())
            y += h
            continue

        if kind == "table":
            rows = block.get("rows") or []
            if not rows:
                continue
            fnt = font(face, base)
            cols = max(len(r) for r in rows)
            # Column widths from the widest cell, so nothing overlaps.
            widths = [
                max((draw.textlength(str(r[c]), font=fnt) for r in rows if c < len(r)), default=0)
                for c in range(cols)
            ]
            total = sum(widths) or 1
            if total > inner:  # shrink proportionally rather than overflow
                widths = [w * inner / total for w in widths]
            for r in rows:
                h = int(base * 1.5)
                if not room(h):
                    break
                x = margin
                cells = []
                for c in range(cols):
                    cell = str(r[c]) if c < len(r) else ""
                    # Numbers right-align, like every real invoice.
                    if c > 0 and cell[:1].isdigit() or cell[:1] in "-€$":
                        draw.text((x + widths[c] - draw.textlength(cell, font=fnt), y),
                                  cell, font=fnt, fill=(22, 22, 28))
                    else:
                        draw.text((x, y), cell, font=fnt, fill=(22, 22, 28))
                    cells.append(cell)
                    x += widths[c] + base // 2
                truth.append(" ".join(c for c in cells if c))
                y += h
            y += base // 2
            continue

    # Trim the sheet to what was actually written, plus a margin. A photograph
    # is framed to the document, and a half-empty page teaches the pipeline that
    # most of a document is blank — which is exactly the wrong prior for a
    # detector that segments paper from desk. Receipts get their natural
    # variable length out of this for free.
    used = min(H, max(int(H * 0.22), y + margin))
    if used < H:
        page = page.crop((0, 0, W, used))

    return page, "\n".join(truth)


# -------------------------------------------------------------- degradation
#
# Each of these models something a camera and a room actually do. They are
# applied to the clean page, never to each other's assumptions, and every one
# is seeded.

def deg_skew(im: Image.Image, rng: random.Random) -> Image.Image:
    angle = rng.uniform(-7, 7)
    return im.rotate(angle, resample=Image.BICUBIC, expand=False,
                     fillcolor=(238, 236, 231))


def deg_curved(im: Image.Image, rng: random.Random) -> Image.Image:
    """A page that does not lie flat: vertical cylinder, like an open book."""
    W, H = im.size
    src = im.load()
    out = Image.new("RGB", (W, H), (250, 249, 245))
    dst = out.load()
    depth = rng.uniform(0.10, 0.22)
    for x in range(W):
        u = (x / W) * 2 - 1                       # -1 .. 1
        shift = depth * H * 0.12 * (1 - u * u)    # bulge in the middle
        squeeze = 1 - depth * 0.35 * abs(u)       # foreshortening at the edges
        for y in range(H):
            sy = (y - shift) / squeeze + shift
            iy = int(sy)
            if 0 <= iy < H:
                dst[x, y] = src[x, iy]
    return out


def deg_crumpled(im: Image.Image, rng: random.Random) -> Image.Image:
    """Creases: local displacement plus the shading a fold casts."""
    W, H = im.size
    src = im.load()
    out = im.copy()
    dst = out.load()
    folds = [(rng.uniform(0.15, 0.85), rng.uniform(-1, 1)) for _ in range(rng.randint(3, 5))]
    for y in range(H):
        for x in range(W):
            dx = 0.0
            shade = 1.0
            for pos, dirn in folds:
                d = (y / H) - pos
                g = math.exp(-(d * d) / 0.0009)
                dx += dirn * 3.2 * g
                shade *= 1 - 0.20 * g * (1 if dirn > 0 else -1) * 0.5
            sx = int(x + dx)
            if 0 <= sx < W:
                r, g_, b = src[sx, y]
                k = max(0.55, min(1.15, shade))
                dst[x, y] = (int(r * k), int(g_ * k), int(b * k))
    return out


def deg_hand_shadow(im: Image.Image, rng: random.Random) -> Image.Image:
    """A hard-edged shadow with ambient fill and the blue cast a real one has.

    Deliberately NOT purely multiplicative: dividing by an estimated background
    inverts a multiplicative shadow exactly, which flatters the classical
    pipeline. D-039 records that finding; this keeps the corpus honest.
    """
    W, H = im.size
    src, out = im.load(), im.copy()
    dst = out.load()
    edge = rng.uniform(0.30, 0.65)
    slope = rng.uniform(0.2, 0.6)
    soft = rng.uniform(0.012, 0.05)
    for y in range(H):
        v = y / H
        for x in range(W):
            u = x / W
            t = max(-1.0, min(1.0, ((u + slope * v - edge) / soft)))
            pen = 0.5 - 0.5 * t
            if pen <= 0.002:
                continue
            r, g, b = src[x, y]
            k = 1 - 0.58 * pen
            amb = 13.0 * pen
            dst[x, y] = (
                min(255, int(r * k * (1 - 0.10 * pen) + amb)),
                min(255, int(g * k * (1 - 0.04 * pen) + amb)),
                min(255, int(b * k * (1 + 0.07 * pen) + amb)),
            )
    return out


def deg_finger(im: Image.Image, rng: random.Random) -> Image.Image:
    """A fingertip over one corner, with its contact shadow.

    Skin is drawn as a warm ellipse. D-042 removes intrusions by finding an
    object that does not belong, explicitly NOT by detecting skin colour, so the
    tone here is varied widely on purpose — a detector tuned to one skin tone is
    the failure this corpus should expose.
    """
    W, H = im.size
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    corner = rng.choice(["bl", "br", "tl", "tr"])
    w, h = int(W * rng.uniform(0.13, 0.20)), int(H * rng.uniform(0.09, 0.15))
    x0 = -w // 3 if corner in ("bl", "tl") else W - int(w * 0.7)
    y0 = H - int(h * 0.8) if corner in ("bl", "br") else -h // 3
    tone = rng.choice([(232, 194, 163), (198, 148, 110), (141, 95, 62),
                       (92, 60, 42), (247, 220, 194), (60, 40, 30)])
    d.ellipse([x0 - 8, y0 - 8, x0 + w + 8, y0 + h + 8], fill=(0, 0, 0, 70))
    over = over.filter(ImageFilter.GaussianBlur(9))
    d = ImageDraw.Draw(over)
    d.ellipse([x0, y0, x0 + w, y0 + h], fill=tone + (255,))
    d.ellipse([x0 + w // 5, y0 + h // 6, x0 + w // 2, y0 + h // 2],
              fill=tuple(min(255, c + 22) for c in tone) + (120,))
    return Image.alpha_composite(im.convert("RGBA"), over).convert("RGB")


def deg_low_light(im: Image.Image, rng: random.Random) -> Image.Image:
    gain = rng.uniform(0.34, 0.52)
    im = Image.eval(im, lambda v: int(v * gain))
    return add_noise(im, rng, sigma=rng.uniform(5.0, 11.0))


def deg_glare(im: Image.Image, rng: random.Random) -> Image.Image:
    """A specular highlight: blown-out pixels, where information is gone."""
    W, H = im.size
    cx, cy = rng.uniform(0.25, 0.75) * W, rng.uniform(0.2, 0.7) * H
    rx, ry = W * rng.uniform(0.13, 0.24), H * rng.uniform(0.07, 0.16)
    src, out = im.load(), im.copy()
    dst = out.load()
    for y in range(H):
        for x in range(W):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d > 2.2:
                continue
            s = math.exp(-d * 1.6)
            r, g, b = src[x, y]
            dst[x, y] = (min(255, int(r + 215 * s)), min(255, int(g + 213 * s)),
                         min(255, int(b + 205 * s)))
    return out


def deg_mixed_light(im: Image.Image, rng: random.Random) -> Image.Image:
    """Daylight on one side, tungsten on the other. Breaks a global white balance."""
    W, H = im.size
    src, out = im.load(), im.copy()
    dst = out.load()
    for y in range(H):
        for x in range(W):
            u = x / W
            r, g, b = src[x, y]
            dst[x, y] = (
                min(255, int(r * (0.96 + 0.16 * u))),
                min(255, int(g * (0.99 + 0.02 * u))),
                min(255, int(b * (1.10 - 0.24 * u))),
            )
    return out


def deg_motion_blur(im: Image.Image, rng: random.Random) -> Image.Image:
    angle = rng.uniform(0, math.pi)
    n = rng.randint(5, 10)
    acc = Image.new("RGB", im.size)
    for i in range(n):
        off = i - n // 2
        acc = Image.blend(
            acc,
            im.transform(im.size, Image.AFFINE,
                         (1, 0, off * math.cos(angle), 0, 1, off * math.sin(angle)),
                         resample=Image.BILINEAR, fillcolor=(245, 244, 240)),
            1.0 / (i + 1),
        )
    return acc


def add_noise(im: Image.Image, rng: random.Random, sigma: float = 3.0) -> Image.Image:
    px = im.load()
    W, H = im.size
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            n = rng.gauss(0, sigma)
            px[x, y] = (max(0, min(255, int(r + n))),
                        max(0, min(255, int(g + n))),
                        max(0, min(255, int(b + n))))
    return im


DEGRADATIONS = {
    "skewed": deg_skew,
    "curved": deg_curved,
    "crumpled": deg_crumpled,
    "hand-shadow": deg_hand_shadow,
    "finger-in-frame": deg_finger,
    "low-light": deg_low_light,
    "glare": deg_glare,
    "mixed-light": deg_mixed_light,
    "motion-blur": deg_motion_blur,
}


def capture(im: Image.Image, rng: random.Random, clean: bool) -> Image.Image:
    """What every photograph gets, damaged or not: a lens, a sensor, a codec.

    Even the twenty-five clean pages go through this. A "clean" document in this
    corpus means an undamaged page photographed competently, not a scan — if the
    clean half were pristine PNGs the corpus would never catch a pipeline that
    damages ordinary good input, which is the regression this half exists for.
    """
    im = im.filter(ImageFilter.GaussianBlur(0.6 if clean else rng.uniform(0.7, 1.5)))
    im = add_noise(im, rng, sigma=1.6 if clean else rng.uniform(2.0, 4.5))
    return im


# -------------------------------------------------------------- the damage plan

# Which damage suits which document. A book page bends at the gutter; a till
# receipt is crumpled in a pocket; a whiteboard has glare on it. Matching them
# keeps the corpus plausible instead of merely varied.
AFFINITY = {
    "receipt":     ["crumpled", "low-light", "motion-blur", "skewed"],
    "invoice":     ["hand-shadow", "skewed", "mixed-light", "crumpled"],
    "book-page":   ["curved", "hand-shadow", "mixed-light", "glare"],
    "handwriting": ["skewed", "low-light", "crumpled", "finger-in-frame"],
    "whiteboard":  ["glare", "mixed-light", "skewed", "motion-blur"],
    "form":        ["finger-in-frame", "hand-shadow", "skewed", "curved"],
    "id-card":     ["glare", "finger-in-frame", "low-light", "motion-blur"],
    "adversarial": ["low-light", "motion-blur", "hand-shadow", "crumpled",
                    "curved", "finger-in-frame", "glare", "mixed-light", "skewed"],
}

MIN_PER_CONDITION = 3


def category_of(doc_id: str) -> str:
    """`book-page-04` -> `book-page`. The trailing number is the only separator."""
    head = doc_id.rsplit("-", 1)[0]
    return head if head in STYLE else doc_id


def assign_conditions(docs: list[dict], damaged_target: int, seed: int) -> None:
    """Marks exactly `damaged_target` documents, covering every condition >= 3 times.

    Deterministic given the seed. Adversarial pages are always damaged — that is
    what makes them adversarial — and absorb the leftover conditions as second
    hits, which is also the most realistic place for two things to go wrong at
    once.
    """
    rng = random.Random(seed)
    for d in docs:
        d.setdefault("category", category_of(d["id"]))
        d["conditions"] = []

    adversarial = [d for d in docs if d["category"] == "adversarial"]
    others = [d for d in docs if d["category"] != "adversarial"]
    rng.shuffle(others)
    damaged = adversarial + others[: max(0, damaged_target - len(adversarial))]

    # Guarantee the floor first, then fill the rest by affinity.
    pool = [c for c in DEGRADATIONS for _ in range(MIN_PER_CONDITION)]
    rng.shuffle(pool)

    for cond in pool:
        # Prefer a still-empty document whose category suits this damage.
        best = [d for d in damaged if not d["conditions"] and cond in AFFINITY[d["category"]]]
        if not best:
            best = [d for d in damaged if not d["conditions"]]
        if not best:  # everyone has one: stack onto an adversarial page
            best = [d for d in damaged if len(d["conditions"]) < 2
                    and cond not in d["conditions"]
                    and d["category"] == "adversarial"] or \
                   [d for d in damaged if len(d["conditions"]) < 2 and cond not in d["conditions"]]
        if best:
            rng.choice(best)["conditions"].append(cond)

    for d in damaged:
        if not d["conditions"]:
            d["conditions"].append(rng.choice(AFFINITY[d["category"]]))


# ------------------------------------------------------------------- driver

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("content", help="JSON with the document text (from the content workflow)")
    ap.add_argument("--out", default="harness/dataset/synthetic")
    ap.add_argument("--seed", type=int, default=20260914)
    ap.add_argument("--damaged", type=int, default=25,
                    help="how many of the documents are photographed badly")
    args = ap.parse_args()

    content = json.loads(Path(args.content).read_text(encoding="utf-8"))
    docs = content["documents"]
    assign_conditions(docs, args.damaged, args.seed)

    out = Path(args.out)
    (out / "images").mkdir(parents=True, exist_ok=True)
    (out / "ground_truth").mkdir(parents=True, exist_ok=True)
    (out / "ground_truth_image").mkdir(parents=True, exist_ok=True)

    manifest, problems, applied = [], [], {}
    for doc in docs:
        rng = random.Random(args.seed ^ int(hashlib.sha256(doc["id"].encode()).hexdigest()[:8], 16))
        conditions = list(doc.get("conditions") or [])

        page, truth = render_page(doc, rng)
        problems += assert_renderable(truth, doc["id"])

        (out / "ground_truth_image" / f"{doc['id']}.png").write_bytes(b"")
        page.save(out / "ground_truth_image" / f"{doc['id']}.png")

        shot = page
        for cond in conditions:
            fn = DEGRADATIONS.get(cond)
            if fn:
                shot = fn(shot, rng)
                applied[cond] = applied.get(cond, 0) + 1
        if doc.get("density") == "dense":
            applied["dense-text"] = applied.get("dense-text", 0) + 1
            if "dense-text" not in conditions:
                conditions.append("dense-text")

        shot = capture(shot, rng, clean=not conditions or conditions == ["dense-text"])
        shot.save(out / "images" / f"{doc['id']}.jpg", quality=88, subsampling=2)
        (out / "ground_truth" / f"{doc['id']}.txt").write_text(truth + "\n", encoding="utf-8")

        manifest.append({
            "id": doc["id"],
            "file": f"images/{doc['id']}.jpg",
            "groundTruth": f"ground_truth/{doc['id']}.txt",
            "groundTruthImage": f"ground_truth_image/{doc['id']}.png",
            "category": doc["category"],
            "language": doc["language"],
            "conditions": conditions,
            "publish": True,
            "license": "CC0-1.0",
        })

    (out / "manifest.json").write_text(json.dumps({
        "version": 1,
        "comment": (
            "Synthetic. Generated by tool/make_corpus.py, seeded and reproducible. "
            "NOT the fifty photographs: no paper grain, no real optics, no sensor. "
            "It exists because it has exact ground-truth text, so character error rate "
            "is measurable automatically today. D-039 and D-042 still need real pages."
        ),
        "documents": manifest,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    damaged = sum(1 for m in manifest if [c for c in m["conditions"] if c != "dense-text"])
    print(f"{len(manifest)} documentos  ·  {damaged} dañados  ·  {len(manifest) - damaged} limpios")
    print("condiciones aplicadas:", dict(sorted(applied.items())))
    langs = {}
    for m in manifest:
        langs[m["language"]] = langs.get(m["language"], 0) + 1
    print("idiomas:", dict(sorted(langs.items())))
    if problems:
        print(f"\nAVISO: {len(problems)} caracteres que la fuente no dibuja "
              f"(la verdad-terreno diría algo que la imagen no muestra):")
        for p in problems[:15]:
            print("  ", p)


if __name__ == "__main__":
    main()
