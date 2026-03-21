# Custom Font XML Generator Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate BMFont XML index files for TaipanStandardFont.png and TaipanThickFont.png so they can be loaded as fixed-width custom fonts in the Taipan Roblox game.

**Architecture:** A single stdlib-only Python script reads each PNG's dimensions from its IHDR header, computes fixed-cell coordinates for ASCII 32–126, and writes a BMFont XML file per font. No image library required. Tests use Python's built-in `unittest` and `xml.etree.ElementTree` to verify the output.

**Tech Stack:** Python 3 (stdlib only — `struct`, `xml.etree.ElementTree`, `unittest`)

---

## Chunk 1: Script and Tests

### Task 1: Create test file with coordinate and header tests

**Files:**
- Create: `customfonts/test_generate_font_xml.py`

- [ ] **Step 1: Create the test file**

```python
# customfonts/test_generate_font_xml.py
import unittest
import xml.etree.ElementTree as ET
import os
import sys

# Import the script under test
sys.path.insert(0, os.path.dirname(__file__))
import generate_font_xml as gfx

SCRIPT_DIR = os.path.dirname(__file__)


class TestCharCoordinates(unittest.TestCase):

    def test_space_is_first_cell_standard(self):
        # ASCII 32 (space): char_idx=0, col=0, row=0
        x, y = gfx.char_cell(32, chars_per_row=16)
        self.assertEqual(x, 2)
        self.assertEqual(y, 2)

    def test_exclamation_standard(self):
        # ASCII 33 (!): char_idx=1, col=1, row=0
        x, y = gfx.char_cell(33, chars_per_row=16)
        self.assertEqual(x, 18)   # 2 + 1*16
        self.assertEqual(y, 2)

    def test_second_row_start_standard(self):
        # ASCII 48 (0): char_idx=16, col=0, row=1
        x, y = gfx.char_cell(48, chars_per_row=16)
        self.assertEqual(x, 2)
        self.assertEqual(y, 20)   # 2 + 1*18

    def test_tilde_last_char_standard(self):
        # ASCII 126 (~): char_idx=94, col=14, row=5
        x, y = gfx.char_cell(126, chars_per_row=16)
        self.assertEqual(x, 226)  # 2 + 14*16
        self.assertEqual(y, 92)   # 2 + 5*18

    def test_space_thick_font(self):
        # ASCII 32 (space): char_idx=0, col=0, row=0 (same regardless of chars_per_row)
        x, y = gfx.char_cell(32, chars_per_row=32)
        self.assertEqual(x, 2)
        self.assertEqual(y, 2)

    def test_tilde_last_char_thick(self):
        # ASCII 126 (~): char_idx=94, col=30, row=2
        x, y = gfx.char_cell(126, chars_per_row=32)
        self.assertEqual(x, 482)  # 2 + 30*16
        self.assertEqual(y, 38)   # 2 + 2*18


class TestPngDimensions(unittest.TestCase):

    def test_standard_font_dimensions(self):
        w, h = gfx.read_png_size(os.path.join(SCRIPT_DIR, 'TaipanStandardFont.png'))
        self.assertEqual(w, 258)
        self.assertEqual(h, 110)

    def test_thick_font_dimensions(self):
        w, h = gfx.read_png_size(os.path.join(SCRIPT_DIR, 'TaipanThickFont.png'))
        self.assertEqual(w, 514)
        self.assertEqual(h, 110)


class TestXmlOutput(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # Generate both XML files before running XML tests
        gfx.main()

    def _parse(self, filename):
        path = os.path.join(SCRIPT_DIR, filename)
        return ET.parse(path).getroot()

    def test_standard_xml_char_count(self):
        root = self._parse('TaipanStandardFont.xml')
        chars = root.find('chars')
        self.assertEqual(chars.attrib['count'], '95')
        self.assertEqual(len(chars.findall('char')), 95)

    def test_thick_xml_char_count(self):
        root = self._parse('TaipanThickFont.xml')
        chars = root.find('chars')
        self.assertEqual(chars.attrib['count'], '95')
        self.assertEqual(len(chars.findall('char')), 95)

    def test_standard_space_char(self):
        root = self._parse('TaipanStandardFont.xml')
        space = next(c for c in root.find('chars') if c.attrib['id'] == '32')
        self.assertEqual(space.attrib['x'], '2')
        self.assertEqual(space.attrib['y'], '2')
        self.assertEqual(space.attrib['width'], '14')
        self.assertEqual(space.attrib['height'], '16')
        self.assertEqual(space.attrib['xoffset'], '0')
        self.assertEqual(space.attrib['yoffset'], '0')
        self.assertEqual(space.attrib['xadvance'], '16')

    def test_all_chars_fixed_dimensions(self):
        # Every char in both fonts must have identical width/height/offsets/advance
        for filename in ['TaipanStandardFont.xml', 'TaipanThickFont.xml']:
            root = self._parse(filename)
            for char in root.find('chars'):
                with self.subTest(file=filename, id=char.attrib['id']):
                    self.assertEqual(char.attrib['width'], '14')
                    self.assertEqual(char.attrib['height'], '16')
                    self.assertEqual(char.attrib['xoffset'], '0')
                    self.assertEqual(char.attrib['yoffset'], '0')
                    self.assertEqual(char.attrib['xadvance'], '16')

    def test_standard_common_metrics(self):
        root = self._parse('TaipanStandardFont.xml')
        common = root.find('common')
        self.assertEqual(common.attrib['lineHeight'], '18')
        self.assertEqual(common.attrib['base'], '16')
        self.assertEqual(common.attrib['scaleW'], '258')
        self.assertEqual(common.attrib['scaleH'], '110')
        self.assertEqual(common.attrib['alphaChnl'], '4')
        self.assertEqual(common.attrib['redChnl'], '0')
        self.assertEqual(common.attrib['greenChnl'], '0')
        self.assertEqual(common.attrib['blueChnl'], '0')

    def test_thick_common_metrics(self):
        root = self._parse('TaipanThickFont.xml')
        common = root.find('common')
        self.assertEqual(common.attrib['scaleW'], '514')
        self.assertEqual(common.attrib['scaleH'], '110')

    def test_standard_page_filename(self):
        root = self._parse('TaipanStandardFont.xml')
        page = root.find('pages/page')
        self.assertEqual(page.attrib['file'], 'TaipanStandardFont.png')

    def test_thick_page_filename(self):
        root = self._parse('TaipanThickFont.xml')
        page = root.find('pages/page')
        self.assertEqual(page.attrib['file'], 'TaipanThickFont.png')


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Run tests to confirm they fail (module not yet created)**

```bash
cd /mnt/d/dev/taipan/customfonts
python3 test_generate_font_xml.py
```

Expected: `ModuleNotFoundError: No module named 'generate_font_xml'`

---

### Task 2: Implement the generator script

**Files:**
- Create: `customfonts/generate_font_xml.py`

- [ ] **Step 3: Create the script**

```python
# customfonts/generate_font_xml.py
"""Generate BMFont XML index files for TaipanStandardFont and TaipanThickFont."""
import struct
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

FONTS = [
    {
        'name': 'TaipanStandardFont',
        'png':  'TaipanStandardFont.png',
        'xml':  'TaipanStandardFont.xml',
        'chars_per_row': 16,
    },
    {
        'name': 'TaipanThickFont',
        'png':  'TaipanThickFont.png',
        'xml':  'TaipanThickFont.xml',
        'chars_per_row': 32,
    },
]

CELL_W      = 14   # content width in px
CELL_H      = 16   # content height in px
CELL_PITCH  = 16   # cell_w + 2px separator
ROW_PITCH   = 18   # cell_h + 2px separator
ORIGIN      = 2    # first cell starts at x=2, y=2 (after 2px border)
XADVANCE    = 16   # cursor advance = full cell pitch
LINE_HEIGHT = 18   # line advance = full row pitch
BASE        = 16   # baseline = bottom of cell


def read_png_size(path):
    """Return (width, height) from a PNG file's IHDR chunk."""
    with open(path, 'rb') as f:
        f.read(8)   # PNG signature
        f.read(4)   # IHDR chunk length
        f.read(4)   # 'IHDR'
        w = struct.unpack('>I', f.read(4))[0]
        h = struct.unpack('>I', f.read(4))[0]
    return w, h


def char_cell(char_code, chars_per_row):
    """Return (x, y) pixel coordinates of the top-left corner of a character's cell."""
    char_idx = char_code - 32
    col = char_idx % chars_per_row
    row = char_idx // chars_per_row
    x = ORIGIN + col * CELL_PITCH
    y = ORIGIN + row * ROW_PITCH
    return x, y


def generate_xml(font):
    png_path = os.path.join(SCRIPT_DIR, font['png'])
    xml_path = os.path.join(SCRIPT_DIR, font['xml'])
    scale_w, scale_h = read_png_size(png_path)
    chars_per_row = font['chars_per_row']
    name = font['name']

    lines = [
        '<?xml version="1.0"?>',
        '<font>',
        f'  <info face="{name}" size="{CELL_H}" bold="0" italic="0" charset=""'
        f' unicode="1" stretchH="100" smooth="0" aa="0" padding="0,0,0,0"'
        f' spacing="0,0" outline="0"/>',
        f'  <common lineHeight="{LINE_HEIGHT}" base="{BASE}"'
        f' scaleW="{scale_w}" scaleH="{scale_h}" pages="1"'
        f' packed="0" alphaChnl="4" redChnl="0" greenChnl="0" blueChnl="0"/>',
        '  <pages>',
        f'    <page id="0" file="{font["png"]}" />',
        '  </pages>',
        '  <chars count="95">',
    ]

    for c in range(32, 127):
        x, y = char_cell(c, chars_per_row)
        lines.append(
            f'    <char id="{c}" x="{x}" y="{y}"'
            f' width="{CELL_W}" height="{CELL_H}"'
            f' xoffset="0" yoffset="0" xadvance="{XADVANCE}"'
            f' page="0" chnl="15" />'
        )

    lines += [
        '  </chars>',
        '</font>',
    ]

    with open(xml_path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    print(f'Written: {xml_path}')


def main():
    for font in FONTS:
        generate_xml(font)


if __name__ == '__main__':
    main()
```

- [ ] **Step 4: Run all tests**

```bash
cd /mnt/d/dev/taipan/customfonts
python3 test_generate_font_xml.py -v
```

Expected output (all passing):
```
test_all_chars_fixed_dimensions ... ok
test_exclamation_standard ... ok
test_second_row_start_standard ... ok
test_space_is_first_cell_standard ... ok
test_space_thick_font ... ok
test_standard_common_metrics ... ok
test_standard_page_filename ... ok
test_standard_space_char ... ok
test_standard_xml_char_count ... ok
test_thick_common_metrics ... ok
test_thick_font_dimensions ... ok
test_thick_page_filename ... ok
test_thick_xml_char_count ... ok
test_tilde_last_char_standard ... ok
test_tilde_last_char_thick ... ok

----------------------------------------------------------------------
Ran 15 tests in 0.XXXs

OK
```

- [ ] **Step 5: Verify the output files look correct**

```bash
head -12 /mnt/d/dev/taipan/customfonts/TaipanStandardFont.xml
head -12 /mnt/d/dev/taipan/customfonts/TaipanThickFont.xml
```

Expected: well-formed XML with correct `<info>`, `<common>`, `<pages>`, and first few `<char>` entries starting with `id="32" x="2" y="2"`.

- [ ] **Step 6: Commit**

```bash
cd /mnt/d/dev/taipan
git add customfonts/generate_font_xml.py customfonts/test_generate_font_xml.py \
        customfonts/TaipanStandardFont.xml customfonts/TaipanThickFont.xml
git commit -m "feat: generate BMFont XML index files for Taipan custom fonts"
```
