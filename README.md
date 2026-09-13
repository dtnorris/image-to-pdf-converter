# book-photo-to-pdf

Small Ruby CLI for turning sequential smartphone photographs of physical book pages into a normalized image-only PDF for downstream OCR.

The tool is intentionally conservative. It removes obvious surrounding background when it can identify a page edge confidently, but it does **not** perspective-warp, dewarp, sharpen, threshold, OCR, or otherwise reinterpret the photographed page.

## Why this exists

The target workflow is:

```text
physical book
    ↓
smartphone JPGs
    ↓
book-photo-to-pdf
    ↓
normalized image-only PDF
    ↓
pdf-to-llm-md-converter
    ↓
LLM Edition Markdown
```

A Ravenloft test batch showed that aggressive perspective correction could improve some OCR/layout errors while introducing serious new text distortion on other pages. v0.1 therefore uses the safer middle ground: **conservative crop only + common canvas size**.

## Behavior

For each top-level `.jpg` / `.jpeg` file in the input directory, case-insensitively:

1. natural-sort filenames (`IMG_0009` before `IMG_0010`);
2. honor EXIF orientation;
3. detect plausible outer page edges;
4. crop only edges that pass conservative confidence checks;
5. if fewer than two edges are trustworthy, leave the image uncropped;
6. reject unexpectedly aggressive crop rectangles;
7. pad every cropped page onto one common white canvas **without resizing the page image**;
8. save high-quality processed JPEGs;
9. write a CSV QA report;
10. assemble the processed JPEGs into one image-only PDF.

Source photographs are never overwritten.

## Requirements

- Ruby 3.2+ (tested with Ruby 3.3; expected to work with the project's Ruby 4.x environment)
- Python 3
- `img2pdf` (preferred PDF assembler)
- Python packages in `requirements.txt`

On macOS:

```bash
brew install img2pdf
bin/setup
source .venv/bin/activate
```

`bin/setup` is the repository-owned, idempotent dependency setup entry point. It
installs the bundled Ruby dependencies, creates `.venv` with Python 3 when
needed, and installs the checked-in `requirements.txt` into that repo-local
environment. It does not install Homebrew/system packages or global Python
packages.

`img2pdf` is preferred because it embeds the already-processed JPEGs without an additional JPEG re-encode. If the executable is not available, the CLI falls back to PyMuPDF from `requirements.txt`.

If the desired Python is not `python3`, either use `--python` or set:

```bash
export BOOK_PHOTO_PYTHON=/path/to/python
```

## Usage

From the repository:

```bash
bin/book-photo-to-pdf /path/to/book-photos
```

For an input directory named `ravenloft-test`, the default output is:

```text
ravenloft-test/
├── IMG_0006.JPG
├── IMG_0007.JPG
├── ...
└── build/
    ├── input-manifest.txt
    ├── processed/
    │   ├── IMG_0006.JPG
    │   ├── IMG_0007.JPG
    │   └── ...
    ├── processing-report.csv
    └── ravenloft-test.pdf
```

The input manifest records the exact page order used for the run.

Useful options:

```bash
bin/book-photo-to-pdf --diagnostics /path/to/book-photos
bin/book-photo-to-pdf --no-pdf /path/to/book-photos
bin/book-photo-to-pdf --build-dir /tmp/book-build /path/to/book-photos
bin/book-photo-to-pdf --output /tmp/my-book.pdf /path/to/book-photos
```

`--diagnostics` additionally writes copies of the source photographs with detected/fallback edge lines and the final crop rectangle overlaid.

## QA report

`processing-report.csv` records, per image:

- confidence (`high`, `medium`, `low`);
- number of reliable page edges;
- source dimensions;
- crop rectangle and whether a crop was applied;
- normalized output dimensions;
- per-edge detection/fallback state;
- per-edge distance and contrast signals.

A numeric filename gap is printed as a warning, not treated as a fatal error. This makes skipped-page review explicit without assuming every photo sequence must be contiguous.

## Ravenloft regression run

The initial 12-photo batch (`IMG_0006` through `IMG_0017`) is intentionally **not committed** because the originals are about 55 MB. It was used as an external regression set.

With v0.1 crop-only processing:

- 12/12 images processed in filename order;
- no numeric filename gaps;
- 6 high-confidence pages;
- 5 medium-confidence pages;
- 1 low-confidence page;
- 11 pages received at least one conservative crop;
- the low-confidence page remained uncropped;
- all processed pages were normalized to `3024 × 4032` without rescaling;
- the resulting PDF contained 12 equal-sized pages.

To retain a local private regression fixture without committing it, place it under `test/fixtures/private/`; that path is gitignored.

## Tests

```bash
rake test
```

The committed tests cover:

- mixed `.JPG` / `.jpg` discovery;
- natural numeric ordering;
- filename-gap reporting;
- conservative low-confidence fallback;
- identical normalized output dimensions;
- source-photo immutability;
- safe behavior even if the input directory is explicitly used as the build directory;
- end-to-end PDF creation.

## Non-goals for v0.1

Deliberately out of scope:

- OCR;
- Markdown conversion;
- perspective correction;
- curved-page dewarping;
- sharpening/contrast enhancement;
- grayscale or threshold conversion;
- generative cleanup;
- automatic deletion or replacement of source photos.

Those should only be added if measured downstream OCR results justify the extra processing.
