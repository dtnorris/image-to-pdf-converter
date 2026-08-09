#!/usr/bin/env python3
"""Fallback JPEG -> PDF assembler used only when img2pdf is unavailable."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import fitz
    from PIL import Image
except ImportError as exc:
    print(
        f"Missing PDF fallback dependency: {exc}. Install img2pdf or run `pip install -r requirements.txt`.",
        file=sys.stderr,
    )
    raise SystemExit(2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("images", nargs="+", type=Path)
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    document = fitz.open()
    try:
        for image_path in args.images:
            with Image.open(image_path) as image:
                width, height = image.size
                dpi = image.info.get("dpi", (300, 300))
                x_dpi = float(dpi[0] or 300)
                y_dpi = float(dpi[1] or 300)
            page = document.new_page(width=width / x_dpi * 72.0, height=height / y_dpi * 72.0)
            page.insert_image(page.rect, filename=str(image_path))
        document.save(str(args.output), garbage=4, deflate=False)
    finally:
        document.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
