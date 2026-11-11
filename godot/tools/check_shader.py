"""Fail when the display shader samples more textures than a WebGL page allows.

    python godot/tools/check_shader.py

WebGL 2 and many phone GPUs give a fragment shader 16 texture units, and
Godot's canvas renderer keeps several of them for itself (TEXTURE, normal and
specular maps, lights, the screen and SDF textures). Measured in Chrome: with
13 the page drew nothing ("two textures of different types use the same
sampler location"). Past the limit the browser and Android builds lose their
picture while a desktop with more units looks fine, so keep to LIMIT,
counting TEXTURE.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

LIMIT = 10
SHADER = Path(__file__).resolve().parent.parent / "src" / "palette.gdshader"


def main() -> int:
    code = SHADER.read_text(encoding="utf-8")
    samplers = re.findall(r"^\s*uniform\s+(?:sampler2D|sampler2DArray|sampler3D|usampler2D|isampler2D)\s+(\w+)", code, re.M)
    used = len(samplers) + 1  # TEXTURE
    print(f"palette.gdshader samples {used} textures (limit {LIMIT}): TEXTURE, " + ", ".join(samplers))
    if used > LIMIT:
        print("FAIL: too many textures for WebGL and many phones")
        return 1
    print("SHADER OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
