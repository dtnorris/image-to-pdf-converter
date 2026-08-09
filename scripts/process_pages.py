#!/usr/bin/env python3
"""Conservative crop-only preprocessing for photographed book pages.

This helper intentionally does *not* perspective-warp or dewarp text. It detects
plausible outer page edges, trims only trustworthy edges with an outward safety
margin, and pads every result onto one common white canvas without resizing.
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import cv2
    import numpy as np
    from PIL import Image, ImageDraw, ImageOps
except ImportError as exc:  # pragma: no cover - exercised by dependency failures
    print(
        f"Missing Python dependency: {exc}. Run `pip install -r requirements.txt`.",
        file=sys.stderr,
    )
    raise SystemExit(2)

SIDES = ("top", "right", "bottom", "left")


@dataclass
class SideDetection:
    side: str
    reliable: bool
    line: Tuple[float, float, float, float]
    distance_fraction: float
    length_fraction: float
    median_contrast: float
    score: float


@dataclass
class PageDetection:
    path: Path
    width: int
    height: int
    sides: Dict[str, SideDetection]
    crop: Tuple[int, int, int, int]  # left, top, right-exclusive, bottom-exclusive

    @property
    def reliable_side_count(self) -> int:
        return sum(1 for side in self.sides.values() if side.reliable)

    @property
    def confidence(self) -> str:
        if self.reliable_side_count == 4:
            return "high"
        if self.reliable_side_count >= 2:
            return "medium"
        return "low"


def load_oriented_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        oriented = ImageOps.exif_transpose(image).convert("RGB")
        return np.array(oriented)


def normalize_angle(degrees: float) -> float:
    while degrees > 90:
        degrees -= 180
    while degrees < -90:
        degrees += 180
    return degrees


def color_contrast_score(lab: np.ndarray, line: Tuple[float, float, float, float]) -> Tuple[float, float, float]:
    x1, y1, x2, y2 = line
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    if length < 1:
        return 0.0, 0.0, 0.0

    nx, ny = -dy / length, dx / length
    samples = np.linspace(0.08, 0.92, 120, dtype=np.float32)
    xs, ys = x1 + dx * samples, y1 + dy * samples
    height, width = lab.shape[:2]
    offsets = []
    for distance in (4.0, 8.0, 12.0):
        xa = np.clip(np.rint(xs + nx * distance).astype(np.int32), 0, width - 1)
        ya = np.clip(np.rint(ys + ny * distance).astype(np.int32), 0, height - 1)
        xb = np.clip(np.rint(xs - nx * distance).astype(np.int32), 0, width - 1)
        yb = np.clip(np.rint(ys - ny * distance).astype(np.int32), 0, height - 1)
        offsets.append(np.linalg.norm(lab[ya, xa] - lab[yb, xb], axis=1))

    difference = np.mean(np.stack(offsets), axis=0)
    return (
        float(np.median(difference)),
        float(np.mean(difference)),
        float(np.mean(difference > 12.0)),
    )


def frame_line(side: str, width: int, height: int) -> Tuple[float, float, float, float]:
    if side == "top":
        return (0.0, 0.0, float(width - 1), 0.0)
    if side == "bottom":
        return (0.0, float(height - 1), float(width - 1), float(height - 1))
    if side == "left":
        return (0.0, 0.0, 0.0, float(height - 1))
    return (float(width - 1), 0.0, float(width - 1), float(height - 1))


def detect_sides(rgb: np.ndarray, detect_width: int = 1000) -> Dict[str, SideDetection]:
    height, width = rgb.shape[:2]
    scale = min(1.0, detect_width / float(width))
    small_width = max(1, int(round(width * scale)))
    small_height = max(1, int(round(height * scale)))
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    small = cv2.resize(bgr, (small_width, small_height), interpolation=cv2.INTER_AREA)
    gray = cv2.GaussianBlur(cv2.cvtColor(small, cv2.COLOR_BGR2GRAY), (5, 5), 0)
    edges = cv2.Canny(gray, 20, 80)
    lab = cv2.cvtColor(small, cv2.COLOR_BGR2LAB).astype(np.float32)

    lines = cv2.HoughLinesP(
        edges,
        1,
        np.pi / 360.0,
        threshold=80,
        minLineLength=int(0.25 * small_width),
        maxLineGap=80,
    )

    candidates: Dict[str, List[Tuple[float, float, float, float, Tuple[float, float, float, float]]]] = {
        side: [] for side in SIDES
    }

    if lines is not None:
        for raw in lines[:, 0, :]:
            x1, y1, x2, y2 = map(float, raw)
            dx, dy = x2 - x1, y2 - y1
            length = math.hypot(dx, dy)
            angle = normalize_angle(math.degrees(math.atan2(dy, dx)))
            midpoint_x, midpoint_y = (x1 + x2) / 2.0, (y1 + y2) / 2.0
            side: Optional[str] = None
            axis_dimension = 1.0
            reference_length = 1.0
            distance = 0.0

            if abs(angle) <= 8.0 and length >= 0.28 * small_width:
                reference_length = small_width
                axis_dimension = small_height
                if midpoint_y <= 0.12 * small_height:
                    side, distance = "top", midpoint_y
                elif midpoint_y >= 0.88 * small_height:
                    side, distance = "bottom", small_height - midpoint_y
            elif abs(abs(angle) - 90.0) <= 8.0 and length >= 0.28 * small_height:
                reference_length = small_height
                axis_dimension = small_width
                if midpoint_x <= 0.12 * small_width:
                    side, distance = "left", midpoint_x
                elif midpoint_x >= 0.88 * small_width:
                    side, distance = "right", small_width - midpoint_x

            if side is None:
                continue

            median, mean, contrast_fraction = color_contrast_score(lab, (x1, y1, x2, y2))
            length_fraction = min(1.2, length / reference_length)
            distance_fraction = max(0.0, distance / axis_dimension)
            proximity = math.exp(-distance_fraction / 0.045)
            contrast = median + 0.30 * mean + 15.0 * contrast_fraction
            score = contrast * length_fraction * proximity
            candidates[side].append(
                (score, median, length_fraction, distance_fraction, (x1, y1, x2, y2))
            )

    output: Dict[str, SideDetection] = {}
    for side in SIDES:
        values = sorted(candidates[side], key=lambda value: value[0], reverse=True)
        if values:
            score, median, length_fraction, distance_fraction, small_line = values[0]
            reliable = (
                distance_fraction <= 0.055
                and length_fraction >= 0.32
                and median >= 18.0
                and score >= 8.0
            )
            if reliable:
                inverse = 1.0 / scale
                line = tuple(value * inverse for value in small_line)
            else:
                line = frame_line(side, width, height)
        else:
            score = median = length_fraction = distance_fraction = 0.0
            reliable = False
            line = frame_line(side, width, height)

        output[side] = SideDetection(
            side=side,
            reliable=reliable,
            line=line,
            distance_fraction=distance_fraction,
            length_fraction=length_fraction,
            median_contrast=median,
            score=score,
        )

    return output


def safe_crop(sides: Dict[str, SideDetection], width: int, height: int) -> Tuple[int, int, int, int]:
    # One isolated detected edge is not enough evidence to alter a page at all.
    if sum(1 for side in sides.values() if side.reliable) < 2:
        return (0, 0, width, height)

    margin_x = max(8, int(round(width * 0.006)))
    margin_y = max(8, int(round(height * 0.006)))
    left, top, right, bottom = 0, 0, width, height

    if sides["left"].reliable:
        left = max(0, int(math.floor(min(sides["left"].line[0], sides["left"].line[2]) - margin_x)))
    if sides["right"].reliable:
        right = min(width, int(math.ceil(max(sides["right"].line[0], sides["right"].line[2]) + margin_x)))
    if sides["top"].reliable:
        top = max(0, int(math.floor(min(sides["top"].line[1], sides["top"].line[3]) - margin_y)))
    if sides["bottom"].reliable:
        bottom = min(height, int(math.ceil(max(sides["bottom"].line[1], sides["bottom"].line[3]) + margin_y)))

    crop_width = right - left
    crop_height = bottom - top
    # Reject unexpectedly aggressive detections. Conservative false negatives are
    # preferable to clipping source content.
    if crop_width < 0.84 * width or crop_height < 0.84 * height:
        return (0, 0, width, height)

    return (left, top, right, bottom)


def detect(path: Path) -> Tuple[PageDetection, np.ndarray]:
    rgb = load_oriented_rgb(path)
    height, width = rgb.shape[:2]
    sides = detect_sides(rgb)
    crop = safe_crop(sides, width, height)
    return PageDetection(path=path, width=width, height=height, sides=sides, crop=crop), rgb


def diagnostic_image(rgb: np.ndarray, detection: PageDetection) -> Image.Image:
    image = Image.fromarray(rgb.copy())
    draw = ImageDraw.Draw(image)
    thickness = max(4, detection.width // 500)
    for side in SIDES:
        found = detection.sides[side]
        color = (20, 190, 20) if found.reliable else (255, 165, 0)
        draw.line(found.line, fill=color, width=thickness)

    left, top, right, bottom = detection.crop
    draw.rectangle((left, top, right - 1, bottom - 1), outline=(255, 0, 0), width=thickness + 2)
    return image


def read_manifest(path: Path) -> List[Path]:
    images = [Path(line.strip()) for line in path.read_text().splitlines() if line.strip()]
    if not images:
        raise ValueError("Manifest contains no images")
    missing = [str(image) for image in images if not image.is_file()]
    if missing:
        raise ValueError(f"Manifest references missing image(s): {', '.join(missing[:3])}")
    return images


def process(images: List[Path], output_dir: Path, report_path: Path, diagnostics: bool) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    diagnostic_dir = output_dir.parent / "diagnostics"
    if diagnostics:
        diagnostic_dir.mkdir(parents=True, exist_ok=True)

    detections: List[PageDetection] = []
    source_images: Dict[Path, np.ndarray] = {}
    for path in images:
        detection, rgb = detect(path)
        detections.append(detection)
        source_images[path] = rgb

    crop_sizes = [(d.crop[2] - d.crop[0], d.crop[3] - d.crop[1]) for d in detections]
    target_width = max(width for width, _ in crop_sizes)
    target_height = max(height for _, height in crop_sizes)
    target_width += target_width % 2
    target_height += target_height % 2

    rows = []
    for detection in detections:
        rgb = source_images[detection.path]
        left, top, right, bottom = detection.crop
        cropped = Image.fromarray(rgb[top:bottom, left:right])
        canvas = Image.new("RGB", (target_width, target_height), "white")
        paste_x = (target_width - cropped.width) // 2
        paste_y = (target_height - cropped.height) // 2
        canvas.paste(cropped, (paste_x, paste_y))

        output_path = output_dir / detection.path.name
        canvas.save(output_path, "JPEG", quality=95, subsampling=0, dpi=(300, 300))

        if diagnostics:
            diagnostic_image(rgb, detection).save(
                diagnostic_dir / detection.path.name,
                "JPEG",
                quality=88,
            )

        row = {
            "file": detection.path.name,
            "confidence": detection.confidence,
            "reliable_sides": detection.reliable_side_count,
            "input_width": detection.width,
            "input_height": detection.height,
            "crop_left": left,
            "crop_top": top,
            "crop_right": right,
            "crop_bottom": bottom,
            "crop_width": right - left,
            "crop_height": bottom - top,
            "crop_applied": "yes" if (left, top, right, bottom) != (0, 0, detection.width, detection.height) else "no",
            "output_width": target_width,
            "output_height": target_height,
        }
        for side in SIDES:
            found = detection.sides[side]
            row[f"{side}_detected"] = "yes" if found.reliable else "fallback"
            row[f"{side}_distance_pct"] = f"{100 * found.distance_fraction:.2f}"
            row[f"{side}_contrast"] = f"{found.median_contrast:.1f}"
        rows.append(row)

    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(f"Processed {len(images)} image(s)")
    print(f"Normalized canvas: {target_width}x{target_height}")
    for detection in detections:
        crop = detection.crop
        changed = crop != (0, 0, detection.width, detection.height)
        print(
            f"{detection.path.name}: {detection.confidence} "
            f"({detection.reliable_side_count}/4 sides), crop={'yes' if changed else 'no'}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--diagnostics", action="store_true")
    args = parser.parse_args()

    try:
        images = read_manifest(args.manifest)
        process(images, args.output_dir, args.report, args.diagnostics)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
