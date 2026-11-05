#!/usr/bin/env python3
#
# Renders the theme's GNOME symbolic icons (Resources/ThemeImages) from
# adwaita-icon-theme's SVGs as two-representation TIFFs: 16px at 72 dpi
# and 32px at 144 dpi, both 16 points, so libs-gui draws the 32px one at
# GSScaleFactor 2 (NSImage matches the device resolution) instead of
# scaling the 16px one up. Needs librsvg (gi Rsvg 2.0), pycairo and
# ImageMagick. The cursors are 1x only: see THIRD-PARTY-NOTICES.
import argparse
import subprocess
import tempfile
from pathlib import Path

import cairo
import gi
gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg

ICONS = {
    "common_Home": "user-home-symbolic",
    "common_Mount": "drive-removable-media-symbolic",
    "common_Unmount": "media-eject-symbolic",
    "GnomeThemeStarred-symbolic": "starred-symbolic",
    "GnomeThemeNonStarred-symbolic": "non-starred-symbolic",
    "NSAscendingSortIndicator": "pan-up-symbolic",
    "NSDescendingSortIndicator": "pan-down-symbolic",
    "GnomeThemeBranch-symbolic": "pan-end-symbolic",
}


def find_svg(icon_dir, name):
    found = sorted(icon_dir.rglob(name + ".svg"))
    if not found:
        raise SystemExit(f"{name}.svg not found under {icon_dir}")
    return found[0]


def render(svg, size, out):
    handle = Rsvg.Handle.new_from_file(str(svg))
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    viewport = Rsvg.Rectangle()
    viewport.x, viewport.y, viewport.width, viewport.height = 0, 0, size, size
    handle.render_document(cairo.Context(surface), viewport)
    surface.write_to_png(str(out))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--icons", default="/usr/share/icons/Adwaita/symbolic", type=Path)
    parser.add_argument("--out", default=Path(__file__).resolve().parents[2] / "Resources/ThemeImages", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for image, icon in ICONS.items():
            svg = find_svg(args.icons, icon)
            pages = []
            for size, dpi in ((16, 72), (32, 144)):
                png = tmp / f"{image}-{size}.png"
                page = tmp / f"{image}-{size}.tiff"
                render(svg, size, png)
                subprocess.run(["convert", str(png), "-units", "PixelsPerInch", "-density", str(dpi), str(page)], check=True)
                pages.append(str(page))
            subprocess.run(["convert", *pages, "-compress", "zip", str(args.out / f"{image}.tiff")], check=True)
            print(f"{image}.tiff from {svg.name}")


if __name__ == "__main__":
    main()
