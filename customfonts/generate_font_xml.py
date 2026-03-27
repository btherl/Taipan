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
        'range_start': 32,
        'range_end': 127,   # 32 + 96 - 1
        'chars_count': 96,
    },
    {
        'name': 'TaipanThickFont',
        'png':  'TaipanThickFont.png',
        'xml':  'TaipanThickFont.xml',
        'chars_per_row': 32,
        'range_start': 32,
        'range_end': 223,   # 32 + 192 - 1
        'chars_count': 192,
    },
]

CELL_W      = 14   # content width in px
CELL_H      = 16   # content height in px
CELL_PITCH  = 16   # cell_w + 2px separator
ROW_PITCH   = 18   # cell_h + 2px separator
ORIGIN      = 2    # first cell starts at x=2, y=2 (after 2px border)
XADVANCE    = 14   # cursor advance = same as content, no additional spacing
LINE_HEIGHT = 16   # line advance = same as content, no additional spacing
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
        f' unicode="1" stretchH="100" smooth="0" aa="1" padding="0,0,0,0"'
        f' spacing="0,0" outline="0"/>',
        f'  <common lineHeight="{LINE_HEIGHT}" base="{BASE}"'
        f' scaleW="{scale_w}" scaleH="{scale_h}" pages="1"'
        f' packed="0" alphaChnl="4" redChnl="0" greenChnl="0" blueChnl="0"/>',
        '  <pages>',
        f'    <page id="0" file="{font["png"]}" />',
        '  </pages>',
        f'  <chars count="{font["chars_count"]}">',
    ]

    for c in range(font['range_start'], font['range_end']):
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
