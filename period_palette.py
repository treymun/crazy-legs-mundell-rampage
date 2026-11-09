"""Convert the composed 320x200 image to an original 256-color VGA grade."""
from pathlib import Path

import numpy as np

from resource_path import get_resource_path

ROOT = Path(__file__).resolve().parent
LOOKUP = Path(get_resource_path("assets/tiles/vga_rgb555.npy"))
RGB5 = (np.arange(256,dtype=np.uint16)*31+127)//255
RED5, GREEN5 = RGB5<<10, RGB5<<5

# Independent color ramps for the county's materials and readable cue colors.
# The working RGB555 table is generated from these values, not sampled from
# a commercial game's assets.
RAMPS = (
    ((0,0,0),(253,252,247),24),          # Neutral metal and paper
    ((13,10,9),(217,202,181),22),       # Warm gray wood and plaster
    ((9,13,26),(192,210,240),22),       # Denim and dusk sky
    ((9,19,17),(162,197,182),18),       # Machinery patina
    ((19,12,5),(209,169,117),20),       # Weathered boards
    ((24,11,7),(250,181,142),26),       # Skin and leather
    ((33,7,11),(246,106,92),18),        # Red signage and damage
    ((31,13,7),(197,96,59),20),         # Clay and rust
    ((12,17,8),(176,184,111),20),       # Field greens
    ((30,24,16),(255,242,204),20),      # Warm lamp and lettering
    ((40,23,5),(255,190,84),18),        # Amber cues
    ((16,10,23),(163,153,197),12),      # Cool cast shadow
    ((15,30,7),(169,221,75),8),         # Green signal lamps
    ((10,35,41),(157,234,235),8),       # Cyan highlights
)


def generate_lookup():
    colors = np.rint(np.concatenate([np.linspace(low,high,steps) for low,high,steps in RAMPS])).astype(np.uint8)
    assert len(np.unique(colors,axis=0))==256
    code = np.arange(32768, dtype=np.uint16)
    rgb = np.column_stack((code >> 10, code >> 5 & 31, code & 31)).astype(np.float32) * 255 / 31
    result = np.empty((32768, 3), dtype=np.uint8)
    for start in range(0, len(rgb), 1024):
        samples = rgb[start:start + 1024]
        error = samples[:, None] - colors[None]
        distance = (error**2 * [.90, 1.10, .82]).sum(axis=2)
        result[start:start + len(samples)] = colors[distance.argmin(axis=1)]
    LOOKUP.parent.mkdir(parents=True, exist_ok=True)
    np.save(LOOKUP, result, allow_pickle=False)


class VGAPalette:
    def __init__(self):
        self.base = np.load(LOOKUP, allow_pickle=False)
        self.tone = None

    def brightness(self, level):
        self.tone = (None if level == 100 else
                     np.rint((np.arange(256)/255)**(100/level)*255).astype(np.uint8))

    def grade(self, scene):
        """Adjust scene lighting before compositing the status bar and text."""
        if self.tone is not None:
            import pygame as pg
            pixels = pg.surfarray.pixels3d(scene)
            pixels[:] = self.tone[pixels]

    def apply(self, surface):
        import pygame as pg

        pixels = pg.surfarray.pixels3d(surface)
        r,g,b = pixels.transpose(2,0,1)
        code = RED5[r] | GREEN5[g] | RGB5[b]
        pixels[:] = self.base[code]
