"""Transcode the WAV soundtrack masters to OGG for Android and web builds.

Windows keeps the higher-quality Opus files; the mobile and Emscripten players
prefer OGG and fall back to the WAV masters when no encoded copy exists.
Requires ffmpeg on PATH (GitHub Actions installs it automatically).
"""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from campaign_score import TRACK_TITLES  # noqa: E402


def ffmpeg():
    found = shutil.which("ffmpeg")
    if found:
        return found
    try:
        import imageio_ffmpeg
    except ImportError:
        raise SystemExit("Install ffmpeg (or imageio-ffmpeg) to transcode the soundtrack.")
    return imageio_ffmpeg.get_ffmpeg_exe()


def main():
    tool = ffmpeg()
    source = ROOT / "assets" / "wav"
    target = ROOT / "assets" / "music"
    made = 0
    for stem in TRACK_TITLES:
        wav = source / f"{stem}.wav"
        ogg = target / f"{stem}.ogg"
        if not wav.is_file():
            raise SystemExit(f"Missing soundtrack master: {wav}")
        if ogg.is_file() and ogg.stat().st_mtime >= wav.stat().st_mtime:
            continue
        subprocess.run([tool, "-y", "-loglevel", "error", "-i", str(wav),
                        "-c:a", "libvorbis", "-q:a", "5", str(ogg)], check=True)
        made += 1
    print(f"OGG soundtrack ready ({made} new file{'s' if made != 1 else ''}).")


if __name__ == "__main__":
    main()
