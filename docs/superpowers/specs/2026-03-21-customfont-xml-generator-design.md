# Custom Font XML Generator — Design Spec

**Date:** 2026-03-21
**Status:** Approved

## Overview

Generate BMFont-format XML index files for `TaipanStandardFont.png` and `TaipanThickFont.png` so they can be used as custom fonts in the Taipan Roblox game. The game simulates an Apple II terminal, so all characters must be rendered at a fixed, uniform size — no per-glyph bounding boxes.

## Font Sheet Structure

Both PNGs share identical grid geometry, discovered by pixel analysis:

| Parameter | Value |
|---|---|
| Cell content width | 14px |
| Cell content height | 16px |
| Separator width | 2px |
| Cell pitch (horizontal) | 16px (14 + 2) |
| Row pitch (vertical) | 18px (16 + 2) |
| Pixel values | `61` = gray separator, `0` = cell background, `255` = glyph |

Cell at grid position `(col, row)` has its top-left content corner at:
- `x = 2 + col * 16`
- `y = 2 + row * 18`

### Per-font layout

| Font | Image size | Chars per row | Rows used |
|---|---|---|---|
| TaipanStandardFont.png | 258×110 | 16 | 6 |
| TaipanThickFont.png | 514×110 | 32 | 3 (rows 3–5 contain ship image, ignored) |

## Character Set

Standard ASCII printable characters: codes 32–126 (space through `~`), 95 characters total.

Characters are laid out in ascending ASCII order, left-to-right, top-to-bottom, starting at code 32 (space) in cell (col=0, row=0).

For a character with ASCII code `c`:
- `char_idx = c - 32`
- `col = char_idx % chars_per_row`
- `row = char_idx // chars_per_row`

The Thick font's rows 3–5 (positions 96–191) contain ship image artwork and are never reached when iterating ASCII 32–126, so no special handling is needed.

## XML Output Format

BMFont XML format, one file per font. Example `<char>` entry:

```xml
<char id="65" x="2" y="2" width="14" height="16" xoffset="0" yoffset="0" xadvance="16" page="0" chnl="15" />
```

All characters use identical `width`, `height`, `xoffset`, `yoffset`, and `xadvance` values — fixed-width rendering for Apple II terminal simulation.

### Font-level metrics

```xml
<common lineHeight="18" base="16" scaleW="<image_width>" scaleH="<image_height>" pages="1" packed="0" />
```

- `lineHeight=18`: full row pitch including 2px separator, keeps lines evenly spaced
- `base=16`: baseline at bottom of cell (no descender allowance needed)
- `xadvance=16`: full cell pitch including 2px separator, preserves natural inter-character gap
- `scaleW`/`scaleH`: actual image dimensions (258×110 for Standard, 514×110 for Thick)

## Script

**File:** `customfonts/generate_font_xml.py`

Single Python script, no dependencies beyond the standard library. Generates both XML files when run.

### Algorithm

```
for each font in [Standard, Thick]:
    open image, read width/height from PNG header
    write XML header, <info>, <common>, <pages>
    for c in range(32, 127):
        char_idx = c - 32
        col = char_idx % chars_per_row
        row = char_idx // chars_per_row
        x = 2 + col * 16
        y = 2 + row * 18
        write <char> element
    write </chars></font>
```

No PIL required — image dimensions are read directly from the PNG IHDR chunk (8 bytes at known offsets).

### Output files

- `customfonts/TaipanStandardFont.xml`
- `customfonts/TaipanThickFont.xml`

Both files reference their respective PNG by filename in the `<pages>` element.

## Out of Scope

- Per-glyph tight bounding boxes (not needed for fixed-width rendering)
- Characters outside ASCII 32–126
- The ship image data in TaipanThickFont rows 3–5
- Wiring the fonts into the Roblox game UI (separate task)
