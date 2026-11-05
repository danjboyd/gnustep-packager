#!/usr/bin/env python3
#
# Import selected stock Adwaita Xcursor assets into GNUstep theme image
# resources. The generated TIFF files are loaded by Cocoa-style application
# code through NSImage imageNamed: and then wrapped in NSCursor objects.

import argparse
import struct
from pathlib import Path

from PIL import Image


XCURSOR_MAGIC = 0x72756358
XCURSOR_IMAGE_TYPE = 0xFFFD0002

CURSORS = {
    "nwse-resize": "GSFrameResizeNWSECursor.tiff",
    "nesw-resize": "GSFrameResizeNESWCursor.tiff",
}


def read_xcursor_image(path, preferred_size):
    data = path.read_bytes()
    magic, header_size, _version, toc_count = struct.unpack_from("<IIII", data, 0)
    if magic != XCURSOR_MAGIC:
        raise ValueError(f"{path} is not an Xcursor file")

    entries = []
    for index in range(toc_count):
        chunk_type, subtype, position = struct.unpack_from("<III", data, header_size + index * 12)
        if chunk_type == XCURSOR_IMAGE_TYPE:
            entries.append((subtype, position))
    if not entries:
        raise ValueError(f"{path} does not contain cursor images")

    subtype, position = min(entries, key=lambda entry: abs(entry[0] - preferred_size))
    chunk_header = struct.unpack_from("<IIIIIIIII", data, position)
    header_length, chunk_type, chunk_subtype, _chunk_version, width, height, _xhot, _yhot, _delay = chunk_header
    if chunk_type != XCURSOR_IMAGE_TYPE or chunk_subtype != subtype:
        raise ValueError(f"{path} has an invalid cursor image chunk")

    pixels = []
    pixel_offset = position + header_length
    for pixel_index in range(width * height):
        argb = struct.unpack_from("<I", data, pixel_offset + pixel_index * 4)[0]
        alpha = (argb >> 24) & 0xFF
        red = (argb >> 16) & 0xFF
        green = (argb >> 8) & 0xFF
        blue = argb & 0xFF
        pixels.append((red, green, blue, alpha))

    image = Image.new("RGBA", (width, height))
    image.putdata(pixels)
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", default="/usr/share/icons/Adwaita/cursors")
    parser.add_argument("--output-dir", default="Resources/ThemeImages")
    parser.add_argument("--size", type=int, default=24)
    args = parser.parse_args()

    source_dir = Path(args.source_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    for source_name, output_name in CURSORS.items():
        image = read_xcursor_image(source_dir / source_name, args.size)
        output_path = output_dir / output_name
        image.save(output_path)
        print(f"wrote {output_path}")


if __name__ == "__main__":
    main()
