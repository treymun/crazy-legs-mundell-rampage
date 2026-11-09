"""Hand-cut seven-row lettering for the game's native 320×200 UI."""
from functools import lru_cache

import pygame as pg


# Rows are bit masks, from the top of each glyph to the baseline.
LETTERS = {
    "A": "0e11111f111111", "B": "1e11111e11111e", "C": "0e11101010110e",
    "D": "1e11111111111e", "E": "1f10101e10101f", "F": "1f10101e101010",
    "G": "0e11101711110f", "H": "1111111f111111", "I": "07020202020207",
    "J": "0702020212120c", "K": "11121418141211", "L": "1010101010101f",
    "M": "111b1515111111", "N": "11191915131311", "O": "0e11111111110e",
    "P": "1e11111e101010", "Q": "0e11111115120d", "R": "1e11111e141211",
    "S": "0f10100e01011e", "T": "1f040404040404", "U": "1111111111110e",
    "V": "11111111110a04", "W": "11111115151b11", "X": "11110a040a1111",
    "Y": "11110a04040404", "Z": "1f01020408101f",
    "0": "0e11111111110e", "1": "02060202020207", "2": "0e11010204081f",
    "3": "1e01010601011e", "4": "02060a121f0202", "5": "1f10101e01011e",
    "6": "0610101e11110e", "7": "1f010204080808", "8": "0e11110e11110e",
    "9": "0e11110f01010e",
    ".": "00000000000303", ",": "00000000000302", ":": "00030300030300",
    ";": "00030300030302", "'": "03030200000000", '"': "15150000000000",
    "-": "0000001f000000", "+": "0004041f040400", "/": "01010204081010",
    "!": "02020202020002", "?": "0e110102040004", "&": "0c12140a15120d",
    "%": "191a0204080b13", "(": "01020404040201", ")": "04020101010204",
    "[": "07040404040407", "]": "07010101010107", "<": "01020408040201",
    ">": "08040201020408", "=": "00001f001f0000", "_": "0000000000001f",
}

MINI = {
    "A": "25755", "B": "65656", "C": "34443", "D": "65556", "E": "74647",
    "F": "74644", "G": "34553", "H": "55755", "I": "72227", "J": "11152",
    "K": "55655", "L": "44447", "M": "77555", "N": "57555", "O": "25552",
    "P": "65644", "Q": "25573", "R": "65655", "S": "34616", "T": "72222",
    "U": "55557", "V": "55552", "W": "55577", "X": "55255", "Y": "55222",
    "Z": "71247",
    "0": "75557", "1": "26227", "2": "71247", "3": "71617", "4": "55711",
    "5": "74617", "6": "74657", "7": "71222", "8": "75757", "9": "75717",
    "-": "00700", "/": "11244", ":": "02020", ".": "00002",
    "'": "22000", "?": "61202",
}

STYLES = {"mini": (1, 5), "body": (1, 7), "menu": (1, 9), "heading": (2, 14)}


@lru_cache(maxsize=128)
def glyph(char, mini):
    if char == " ":
        return (0,) * (5 if mini else 7), 2 if mini else 3
    if mini:
        rows = tuple(int(digit) for digit in MINI.get(char, MINI["?"]))
        return rows, 3
    code = LETTERS.get(char, LETTERS["?"])
    rows = tuple(int(code[i:i+2], 16) for i in range(0, 14, 2))
    return rows, max(rows).bit_length()


def text_width(text, style="body"):
    sx, _ = STYLES[style]
    return max(0, sum(glyph(c, style=="mini")[1]+1 for c in text.upper())-1)*sx


def wrap(text, width, style="body"):
    lines, line = [], ""
    for word in text.split():
        candidate = f"{line} {word}" if line else word
        if line and text_width(candidate, style) > width:
            lines.append(line)
            line = word
        else:
            line = candidate
    return lines + ([line] if line else [])


@lru_cache(maxsize=512)
def label(text, style, color):
    sx, height = STYLES[style]
    surface = pg.Surface((max(1,text_width(text, style)),height),pg.SRCALPHA)
    x = 0
    for c in text.upper():
        rows, w = glyph(c,style=="mini")
        for y, row in enumerate(rows):
            top=y*height//len(rows)
            bottom=(y+1)*height//len(rows)
            for col in range(w):
                if row & (1 << (w-col-1)):
                    pg.draw.rect(surface,color,(x+col*sx,top,sx,bottom-top))
        x += (w+1)*sx
    return surface
