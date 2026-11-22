"""Extract frames from one move clip at 12 fps and remove the background.

usage: python3 cut_move.py <char_dir> <move>
Reads <char_dir>/dl/<move>.mp4, writes <char_dir>/work/<move>/cut/*.png (cached).
"""
import os, sys, glob, subprocess
from PIL import Image
from rembg import remove, new_session

root, move = sys.argv[1], sys.argv[2]
raw = f"{root}/work/{move}/raw"
cut = f"{root}/work/{move}/cut"
os.makedirs(raw, exist_ok=True)
os.makedirs(cut, exist_ok=True)
if not glob.glob(f"{raw}/*.png"):
    subprocess.run(["ffmpeg", "-v", "error", "-i", f"{root}/dl/{move}.mp4", "-vf", "fps=12",
                    f"{raw}/f_%03d.png"], check=True)
files = sorted(glob.glob(f"{raw}/*.png"))
if move in ("idle", "walk"):
    files = files[:-1]      # last frame repeats the first in a loop
session = new_session("isnet-general-use")
for f in files:
    o = f"{cut}/{os.path.basename(f)}"
    if not os.path.exists(o):
        remove(Image.open(f).convert("RGB"), session=session).save(o)
print(move, len(files), "frames", flush=True)
