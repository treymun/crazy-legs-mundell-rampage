# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller build for the Windows one-file release.

Run with ``pyinstaller --noconfirm CrazyLegsMundellRampage.spec`` (or the
``build_windows.bat`` helper). The soundtrack's duplicate WAV masters are
skipped; playback uses the Opus files and the duration manifests.
"""
import os
import sys
from pathlib import Path

ROOT = Path(SPECPATH).resolve()
sys.path.insert(0, str(ROOT))

from campaign_score import TRACK_TITLES  # noqa: E402
from game_version import VERSION  # noqa: E402

APP = "CrazyLegsMundellRampage"
release, _, qualifier = VERSION.partition("-")
file_parts = (*map(int, release.split(".")),
              int(qualifier.rpartition(".")[2]) if qualifier else 0)
BUILD = ROOT / ".build"
BUILD.mkdir(exist_ok=True)
VERSION_FILE = BUILD / "version.txt"
VERSION_FILE.write_text(
    f"""VSVersionInfo(
  ffi=FixedFileInfo(filevers={file_parts}, prodvers={file_parts}, mask=0x3f,
                    flags=0x0, OS=0x40004, fileType=0x1, subtype=0x0, date=(0, 0)),
  kids=[StringFileInfo([StringTable('040904B0', [
      StringStruct('FileDescription', 'Crazy Legs Mundell Rampage'),
      StringStruct('ProductName', 'Crazy Legs Mundell Rampage'),
      StringStruct('FileVersion', '{VERSION}'),
      StringStruct('ProductVersion', '{VERSION}'),
      StringStruct('OriginalFilename', '{APP}.exe')])]),
        VarFileInfo([VarStruct('Translation', [1033, 1200])])]
)
""",
    encoding="utf-8")


def assets():
    root = ROOT / "assets"
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if (path.parent.name in ("music", "wav") and path.suffix == ".wav"
                and path.stem in TRACK_TITLES):
            continue
        yield str(path), str(path.parent.relative_to(ROOT))


datas = [("THIRD_PARTY_NOTICES.md", "."),
         ("third_party", "third_party"),
         *assets()]

a = Analysis(
    ["main.py"],
    pathex=[str(ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=["PIL.Image"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["IPython", "matplotlib", "scipy", "pandas"],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name=APP,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(ROOT / "assets" / "art" / "hickston.ico"),
    version=str(VERSION_FILE),
)
