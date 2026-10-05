#!/usr/bin/env python3
# ObjcMarkdown
# SPDX-License-Identifier: GPL-2.0-or-later
"""Writes MarkdownViewer's symbolic icons to Resources/icons/.

One monochrome set, named <name>-symbolic.png so themes that tint template
images (the Adwaita theme) draw them in the colour of the text around
them; GNUstep's default theme draws them as they are, in black. Only the
shape (alpha) matters.

- The toolbar and copy icons come from the artwork in Resources/ (their
  alpha): toolbar icons cropped to the drawing and fitted into 22x22
  with a 2-point margin, the copy icon scaled to 16x16.
- The other small icons (formatting bar, chevron, explorer, copied
  check) are drawn here at 16x16 with cairo, y pointing up as in AppKit.

Needs python3-cairo and python3-pil. Run from anywhere:
    tools/icons/make-symbolic-icons.py
"""

import math
import os

import cairo
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RESOURCES = os.path.join(ROOT, "Resources")
OUT = os.path.join(RESOURCES, "icons")

SMALL = 16
TOOLBAR = 22
TOOLBAR_INSET = 2
STROKE = 1.5

# Artwork -> (symbolic name, size, margin, crop to the drawing).
ARTWORK_ICONS = {
    "toolbar-explorer-toggle.png": ("omd-sidebar-show-symbolic", TOOLBAR, TOOLBAR_INSET, True),
    "toolbar-open.png": ("omd-document-open-symbolic", TOOLBAR, TOOLBAR_INSET, True),
    "toolbar-saveas.png": ("omd-document-save-symbolic", TOOLBAR, TOOLBAR_INSET, True),
    "toolbar-export.png": ("omd-document-export-symbolic", TOOLBAR, TOOLBAR_INSET, True),
    "toolbar-print.png": ("omd-document-print-symbolic", TOOLBAR, TOOLBAR_INSET, True),
    "toolbar-preferences.png": ("omd-preferences-symbolic", TOOLBAR, TOOLBAR_INSET, True),
    "code-copy-icon.png": ("omd-edit-copy-symbolic", SMALL, 0, False),
}


def artwork_icon(source, name, size, inset, crop):
    image = Image.open(os.path.join(RESOURCES, source)).convert("RGBA")
    alpha = image.getchannel("A")
    box = alpha.point(lambda a: 255 if a > 2 else 0).getbbox()
    if crop and box is not None:
        alpha = alpha.crop(box)
    side = size - 2 * inset
    scale = min(side / alpha.width, side / alpha.height)
    fitted = (max(1, round(alpha.width * scale)), max(1, round(alpha.height * scale)))
    alpha = alpha.resize(fitted, Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    mask.paste(alpha, ((size - fitted[0]) // 2, (size - fitted[1]) // 2))
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.putalpha(mask)
    icon.save(os.path.join(OUT, name + ".png"))


# Small icons: each function draws on a cairo context whose y axis points
# up (origin bottom left), in black.

def line(cr, x1, y1, x2, y2, width=STROKE):
    cr.set_line_width(width)
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.move_to(x1, y1)
    cr.line_to(x2, y2)
    cr.stroke()


def polyline(cr, points, width=STROKE):
    cr.set_line_width(width)
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)
    cr.move_to(*points[0])
    for point in points[1:]:
        cr.line_to(*point)
    cr.stroke()


def rounded_rect(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def frame(cr, x, y, w, h, r, width=STROKE):
    rounded_rect(cr, x, y, w, h, r)
    cr.set_line_width(width)
    cr.stroke()


def dot(cr, x, y, r):
    cr.arc(x, y, r, 0, 2 * math.pi)
    cr.fill()


def text(cr, string, size, bold, x=None, y_center=None):
    """Draws string centred in the icon, or at x with its middle at y_center."""
    cr.save()
    # Glyphs in cairo's own y-down space.
    cr.identity_matrix()
    cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL,
                        cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(size)
    extents = cr.text_extents(string)
    if x is None:
        x = (SMALL - extents.width) / 2 - extents.x_bearing
    middle = SMALL - (SMALL / 2 if y_center is None else y_center)
    cr.move_to(x, middle - extents.y_bearing - extents.height / 2)
    cr.show_text(string)
    cr.restore()


def text_lines(cr, x, ys, last_end=None):
    for index, y in enumerate(ys):
        end = last_end if (last_end is not None and index == len(ys) - 1) else 14.5
        line(cr, x, y, end, y)


def bold(cr):
    text(cr, "B", 13, True)


def italic(cr):
    line(cr, 7.0, 13.0, 13.0, 13.0)
    line(cr, 3.0, 3.0, 9.0, 3.0)
    line(cr, 10.0, 13.0, 6.0, 3.0)


def strikethrough(cr):
    text(cr, "S", 13, False)
    line(cr, 2.0, 8.0, 14.0, 8.0)


def inline_code(cr):
    polyline(cr, [(6.0, 3.5), (1.5, 8.0), (6.0, 12.5)])
    polyline(cr, [(10.0, 3.5), (14.5, 8.0), (10.0, 12.5)])


def code_block(cr):
    frame(cr, 1.5, 2.0, 13.0, 12.0, 2.0)
    polyline(cr, [(6.5, 5.5), (4.5, 8.0), (6.5, 10.5)])
    polyline(cr, [(9.5, 5.5), (11.5, 8.0), (9.5, 10.5)])


def link(cr):
    # Two chain links on a diagonal.
    cr.save()
    cr.translate(8.0, 8.0)
    cr.rotate(math.radians(45.0))
    cr.translate(-8.0, -8.0)
    frame(cr, 0.5, 5.75, 8.5, 4.5, 2.25)
    frame(cr, 7.0, 5.75, 8.5, 4.5, 2.25)
    cr.restore()


def image(cr):
    frame(cr, 1.5, 2.0, 13.0, 12.0, 1.5)
    cr.move_to(3.0, 3.5)
    cr.line_to(6.5, 8.0)
    cr.line_to(9.0, 5.5)
    cr.line_to(10.5, 7.0)
    cr.line_to(13.0, 3.5)
    cr.close_path()
    cr.fill()
    dot(cr, 10.8, 10.6, 1.4)


def list_bullet(cr):
    ys = [12.5, 8.0, 3.5]
    for y in ys:
        dot(cr, 2.5, y, 1.4)
    text_lines(cr, 6.0, ys)


def list_ordered(cr):
    ys = [12.5, 8.0, 3.5]
    for digit, y in zip("123", ys):
        text(cr, digit, 5.5, True, x=1.0, y_center=y)
    text_lines(cr, 6.0, ys)


def list_task(cr):
    cr.set_line_width(1.2)
    cr.rectangle(1.5, 9.0, 4.5, 4.5)
    cr.stroke()
    cr.rectangle(1.5, 2.5, 4.5, 4.5)
    cr.stroke()
    polyline(cr, [(2.5, 11.4), (3.6, 10.2), (5.4, 12.6)], width=1.2)
    text_lines(cr, 8.5, [11.25, 4.75])


def block_quote(cr):
    cr.rectangle(1.5, 2.5, 2.0, 11.0)
    cr.fill()
    text_lines(cr, 6.5, [12.5, 8.0, 3.5], last_end=11.0)


def table(cr):
    frame(cr, 1.5, 2.0, 13.0, 12.0, 1.5)
    line(cr, 1.5, 6.0, 14.5, 6.0)
    line(cr, 1.5, 10.0, 14.5, 10.0)
    line(cr, 6.0, 2.0, 6.0, 14.0)
    line(cr, 10.0, 2.0, 10.0, 14.0)


def horizontal_rule(cr):
    line(cr, 1.5, 8.0, 14.5, 8.0, width=2.0)
    cr.set_source_rgba(0, 0, 0, 0.45)
    line(cr, 3.0, 12.5, 13.0, 12.5)
    line(cr, 3.0, 3.5, 13.0, 3.5)


def pan_down(cr):
    polyline(cr, [(4.5, 10.0), (8.0, 6.5), (11.5, 10.0)])


def go_up(cr):
    # The explorer's parent-folder arrow, as it has always been drawn.
    line(cr, 12.5, 12.0, 5.2, 4.7, width=2.0)
    polyline(cr, [(5.2, 9.1), (5.2, 4.7), (9.6, 4.7)], width=2.0)


def check(cr):
    polyline(cr, [(3.2, 8.2), (6.5, 4.8), (12.8, 11.2)], width=2.0)


SMALL_ICONS = {
    "omd-format-text-bold-symbolic": bold,
    "omd-format-text-italic-symbolic": italic,
    "omd-format-text-strikethrough-symbolic": strikethrough,
    "omd-format-code-symbolic": inline_code,
    "omd-format-code-block-symbolic": code_block,
    "omd-insert-link-symbolic": link,
    "omd-insert-image-symbolic": image,
    "omd-view-list-bullet-symbolic": list_bullet,
    "omd-view-list-ordered-symbolic": list_ordered,
    "omd-view-list-task-symbolic": list_task,
    "omd-format-quote-symbolic": block_quote,
    "omd-insert-table-symbolic": table,
    "omd-insert-rule-symbolic": horizontal_rule,
    "omd-pan-down-symbolic": pan_down,
    "omd-go-up-symbolic": go_up,
    "omd-object-select-symbolic": check,
}


def small_icon(name, draw):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, SMALL, SMALL)
    cr = cairo.Context(surface)
    cr.translate(0, SMALL)
    cr.scale(1, -1)
    cr.set_source_rgb(0, 0, 0)
    draw(cr)
    surface.flush()
    surface.write_to_png(os.path.join(OUT, name + ".png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    for source, (name, size, inset, crop) in ARTWORK_ICONS.items():
        artwork_icon(source, name, size, inset, crop)
    for name, draw in SMALL_ICONS.items():
        small_icon(name, draw)
    print("wrote %d icons to %s" % (len(ARTWORK_ICONS) + len(SMALL_ICONS), os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
