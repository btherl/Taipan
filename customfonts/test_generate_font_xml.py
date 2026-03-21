# customfonts/test_generate_font_xml.py
import unittest
import xml.etree.ElementTree as ET
import os
import sys

# Import the script under test
sys.path.insert(0, os.path.dirname(__file__))
import generate_font_xml as gfx

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


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
