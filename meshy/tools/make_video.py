"""An MP4 of a kind's motion rows (live_frames.gd ... video): each row at
real speed, then at half speed, 3x the game's pixels, captioned.

    python meshy/tools/make_video.py <frames dir> <kind> <out.mp4> row:caption [row:caption ...]
"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

FFMPEG = ("C:/Users/treym/AppData/Local/Microsoft/WinGet/Packages/"
          "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg.exe")
src, kind, out = sys.argv[1], sys.argv[2], sys.argv[3]
rows = [a.split(":", 1) for a in sys.argv[4:]]
tmp = os.path.join(os.path.dirname(os.path.abspath(out)), "_video_tmp_" + kind)
shutil.rmtree(tmp, ignore_errors=True)
os.makedirs(tmp)
font = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 22)
n = 0
for row, caption in rows:
    files = sorted(f for f in os.listdir(os.path.join(src, row)) if f.endswith(".png"))
    for speed, tag in ((1, "real speed"), (2, "half speed")):
        for f in files:
            im = Image.open(os.path.join(src, row, f)).convert("RGB").resize((960, 600), Image.NEAREST)
            d = ImageDraw.Draw(im)
            text = "%s (new Meshy model): %s, %s" % (kind, caption, tag)
            d.rectangle([0, 0, 960, 30], fill=(0, 0, 0))
            d.text((8, 3), text, font=font, fill=(255, 235, 170))
            for _ in range(speed):
                im.save(os.path.join(tmp, "f_%05d.png" % n))
                n += 1
        # a short hold between parts
        for _ in range(8):
            im.save(os.path.join(tmp, "f_%05d.png" % n))
            n += 1
subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "f_%05d.png"),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", out], check=True)
shutil.rmtree(tmp, ignore_errors=True)
print("video", out, n, "frames", os.path.getsize(out) // 1024, "KB")
