#!/usr/bin/env python3
"""Make the app icon files from Resources/markdown_icon.png.

The icon was drawn on a white background with no alpha channel, so it showed
on a white square on dark backgrounds (About in dark mode, docks, the
Windows taskbar). Given such an image, this gives it an alpha channel:
everything outside the dark plate (the white canvas, the plate's soft
shadow and its anti-aliased rim) is unblended from white, so the canvas
becomes transparent and the shadow partly transparent. The plate and the
white page on it stay opaque. An image that already has an alpha channel is
used as it is.

Writes:
  Resources/markdown_icon.png                          1024 x 1024, RGBA
  Resources/markdown_icon.ico                          16-256 px
  packaging/flatpak/io.github.danjboyd.MarkdownViewer.png  512 x 512
macOS makes MarkdownViewer.icns from markdown_icon.png at build time.

Usage: tools/icons/make-app-icons.py [repo root]
"""

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

# The plate is about #31-#46: its pixels are darker than PLATE_MAX. Closing
# that mask and filling its holes takes in the page and the plate's lighter
# specks; everything outside it is canvas or shadow.
PLATE_MAX = 0x60
CLOSE_PX = 3
# The anti-aliased rim just inside the plate mask, unblended like the shadow.
EDGE_PX = 2
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def add_alpha(image):
    rgb = np.asarray(image.convert("RGB")).astype(np.float64)
    darkest = rgb.min(axis=2)
    h, w = darkest.shape
    plate = ndimage.binary_closing(darkest < PLATE_MAX, iterations=CLOSE_PX)
    plate = ndimage.binary_fill_holes(plate)
    outside = ~plate
    edge = ndimage.binary_dilation(outside, iterations=EDGE_PX) & (darkest >= PLATE_MAX)
    background = outside | edge

    # Unblend from white: c = a * colour + (1 - a) * 255. The least alpha
    # that explains every channel is the largest (255 - c) / 255.
    white = 255.0
    alpha = ((white - rgb) / white).max(axis=2)
    alpha = np.clip(alpha, 0.0, 1.0)
    colour = np.zeros_like(rgb)
    visible = alpha > 0.0
    colour[visible] = (rgb[visible] - (1.0 - alpha[visible][:, None]) * white) / alpha[visible][:, None]
    colour = np.clip(colour, 0.0, 255.0)

    # The near-white canvas (#FEFEFE) is noise, not shadow.
    alpha[alpha < 2.0 / 255.0] = 0.0

    out = np.dstack([rgb, np.full((h, w), 255.0)])
    out[background, :3] = colour[background]
    out[background, 3] = alpha[background] * 255.0
    return Image.fromarray(np.round(out).astype(np.uint8), "RGBA")


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
    source = os.path.join(root, "Resources", "markdown_icon.png")
    image = Image.open(source)
    if image.mode != "RGBA":
        image = add_alpha(image)
    image = image.resize((1024, 1024), Image.LANCZOS) if image.size != (1024, 1024) else image
    image.save(source, optimize=True)
    image.resize((512, 512), Image.LANCZOS).save(
        os.path.join(root, "packaging", "flatpak", "io.github.danjboyd.MarkdownViewer.png"), optimize=True)
    image.save(os.path.join(root, "Resources", "markdown_icon.ico"),
               sizes=[(s, s) for s in ICO_SIZES])


if __name__ == "__main__":
    main()
