"""Build a self-contained, windowed Windows executable using PyInstaller."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

from campaign_score import TRACK_TITLES
from game_version import VERSION

ROOT = Path(__file__).resolve().parent
APP = f"CrazyLegsMundellRampage-{VERSION}"
release, _, qualifier = VERSION.partition("-")
file_parts = (*map(int,release.split(".")),int(qualifier.rpartition(".")[2]) if qualifier else 0)

VERSION_INFO = f"""VSVersionInfo(
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
"""


def ships(path):
    return path.parent.name!="wav" or path.suffix!=".wav" or path.stem not in TRACK_TITLES


def main():
    if os.name != "nt":
        raise SystemExit(f"Run this build on Windows to produce {APP}.exe.")
    assets = ROOT / "assets"
    if not (assets / "art" / "full_body_player.png").exists():
        raise SystemExit("Use the included assets folder from the project ZIP.")
    if not (assets/"music"/"durations.json").is_file() or any(
            not (assets/"music"/f"{track}.opus").is_file() for track in TRACK_TITLES):
        raise SystemExit("The twelve Opus files and duration manifest must be in assets/music.")
    playback = assets/"music"/"playback_ends.json"
    durations = json.loads((assets/"music"/"durations.json").read_text(encoding="utf-8"))
    if not playback.is_file():
        raise SystemExit("The music playback-end manifest must be in assets/music.")
    ends = json.loads(playback.read_text(encoding="utf-8"))
    if any(track not in ends or not 0.<ends[track]<=durations[track]+.001 for track in TRACK_TITLES):
        raise SystemExit("Invalid music playback ends. Rebuild with soundtrack_production.py --ends-only.")
    work = ROOT / ".build"
    work.mkdir(exist_ok=True)
    staging = work / "output"
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    version = work / "version.txt"
    version.write_text(VERSION_INFO, encoding="utf-8")
    env = os.environ.copy()
    env["PYINSTALLER_CONFIG_DIR"] = str(work / "cache")
    command = [
        sys.executable, "-m", "PyInstaller", "--noconfirm", "--onefile", "--windowed",
        "--noupx", "--name", APP, "--version-file", str(version),
        "--icon", str(assets / "art" / "hickston.ico"),
        "--add-data", f"{ROOT / 'THIRD_PARTY_NOTICES.md'}{os.pathsep}.",
        "--add-data", f"{ROOT / 'third_party'}{os.pathsep}third_party",
        "--hidden-import", "PIL.Image",
        "--exclude-module", "IPython", "--exclude-module", "matplotlib",
        "--exclude-module", "scipy", "--exclude-module", "pandas",
        "--specpath", str(work), "--workpath", str(work / "work"),
        "--distpath", str(staging), str(ROOT / "main.py"),
    ]
    with TemporaryDirectory(prefix="packed-assets-",dir=work) as folder:
        packed = Path(folder)/"assets"
        shutil.copytree(assets,packed,ignore=lambda path,names:
                        [name for name in names if not ships(Path(path)/name)])
        subprocess.run([*command[:-1],"--add-data",f"{packed}{os.pathsep}assets",command[-1]],
                       cwd=ROOT,env=env,check=True)
    target = dist / f"{APP}.exe"
    try:
        (staging / target.name).replace(target)
    except PermissionError as exc:
        raise SystemExit(f"Cannot replace {target.name}. Close any running copy and build again.") from exc
    print("Executable:", target)


if __name__ == "__main__":
    main()

