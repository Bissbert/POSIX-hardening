#!/usr/bin/env python3
"""make_media.py - render captured terminal output as animated GIFs.

The input is a capture file produced by one of the capture-*.sh tools in this
directory. Nothing is typed, staged or re-ordered here: the script reads the
file line by line and draws it. If a line is not in the capture, it does not
appear in the GIF.

Only Pillow is required, which STYLE.md permits for image generation.

Usage:
    python3 tools/make_media.py media/captures/ssh-watchdog.log \\
        media/ssh-watchdog.gif --title "tools/capture-ssh-watchdog.sh"
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

# GitHub dark-theme terminal colours, so the frames read on both themes.
BG = (13, 17, 23)
FG = (201, 209, 217)
DIM = (110, 118, 129)
CHROME = (33, 38, 45)
COLOURS = {
    "info": (88, 166, 255),     # blue   #58a6ff
    "ok": (63, 185, 80),        # green  #3fb950
    "warn": (210, 153, 34),     # amber  #d29922
    "err": (248, 81, 73),       # red    #f85149
    "hl": (188, 140, 255),      # purple #bc8cff
}

FONT_CANDIDATES = [
    "/System/Library/Fonts/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
    "/Library/Fonts/Courier New.ttf",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def classify(line):
    """Pick a colour for a captured line from the text the tool actually wrote."""
    low = line.lower()
    if "[error]" in low or "cannot stat" in low or "not restored" in low \
            or "not responding" in low or low.startswith("result: ") \
            and "not" in low:
        return COLOURS["err"]
    if "[warn]" in low or "rolling back" in low:
        return COLOURS["warn"]
    if line.lstrip().startswith("==") or line.lstrip().startswith("--"):
        return COLOURS["hl"]
    if "[info]" in low:
        return COLOURS["info"]
    if line.lstrip().startswith(("✓", "✔")) or "success" in low \
            or low.startswith("result: ") or "restored" in low:
        return COLOURS["ok"]
    return FG


def wrap(line, width):
    if len(line) <= width:
        return [line]
    out = []
    while line:
        out.append(line[:width])
        line = line[width:]
    return out


def render(lines, out_path, title, cols=98, rows=26, size=13, ms=190,
           hold=2600):
    font = load_font(size)
    bbox = font.getbbox("M")
    cw = bbox[2] - bbox[0]
    ch = int((bbox[3] - bbox[1]) * 1.85) or size + 6
    pad = 14
    bar = 26
    w = cols * cw + pad * 2
    h = rows * ch + pad * 2 + bar

    def frame(visible):
        img = Image.new("RGB", (w, h), BG)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, w, bar], fill=CHROME)
        for i, dot in enumerate(((248, 81, 73), (210, 153, 34), (63, 185, 80))):
            d.ellipse([12 + i * 16, 9, 20 + i * 16, 17], fill=dot)
        d.text((72, 7), title, font=font, fill=DIM)
        for row, line in enumerate(visible[-rows:]):
            d.text((pad, bar + pad + row * ch), line, font=font,
                   fill=classify(line))
        return img

    frames, visible = [], []
    for line in lines:
        for piece in wrap(line.rstrip("\n"), cols):
            visible.append(piece)
            frames.append(frame(visible))
    if not frames:
        sys.exit("nothing to render: the capture is empty")

    durations = [ms] * len(frames)
    durations[-1] = hold
    frames[0].save(out_path, save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, optimize=True)
    return out_path, len(frames), w, h


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("capture")
    ap.add_argument("output")
    ap.add_argument("--title", default="")
    ap.add_argument("--start", type=int, default=0,
                    help="first capture line to include (0-based)")
    ap.add_argument("--end", type=int, default=None,
                    help="last capture line to include, exclusive")
    ap.add_argument("--cols", type=int, default=98)
    ap.add_argument("--rows", type=int, default=26)
    ap.add_argument("--ms", type=int, default=190)
    args = ap.parse_args()

    with open(args.capture, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    lines = lines[args.start:args.end]

    title = args.title or os.path.basename(args.capture)
    path, n, w, h = render(lines, args.output, title, cols=args.cols,
                           rows=args.rows, ms=args.ms)
    print(f"{path}: {n} frames, {w}x{h}px, "
          f"{os.path.getsize(path) / 1024:.0f} KB, "
          f"source {args.capture} lines {args.start}-"
          f"{args.end if args.end is not None else 'end'}")


if __name__ == "__main__":
    main()
