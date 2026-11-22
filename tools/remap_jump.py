"""Map frames from a zoomed-out clip back to the character's normal scale.

The wide jump clips were made from a start image in which the fighter was shrunk
to K (70%) around his feet. This scales each cut-out frame back up by 1/K around
the same feet point and places it in the packer's padded space
(1280 x 720+TOP, original space shifted down by TOP), so the jump lines up with
every other move and the head stays visible above the old frame top.

usage: python3 remap_jump.py <src_cut_dir> <dst_cut_dir> <feet_x> <feet_y> <K>
"""
import glob, os, sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
fx, fy, K = float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
TOP = 360
os.makedirs(dst, exist_ok=True)
for p in sorted(glob.glob(f"{src}/*.png")):
    im = Image.open(p).convert("RGBA")
    big = im.resize((round(im.width / K), round(im.height / K)), Image.LANCZOS)
    ox = round(fx - fx / K)
    oy = round(fy - fy / K) + TOP
    canvas = Image.new("RGBA", (1280, 720 + TOP), (0, 0, 0, 0))
    canvas.paste(big, (ox, oy), big)
    canvas.save(f"{dst}/{os.path.basename(p)}")
print("remapped", len(glob.glob(f"{dst}/*.png")), "frames")
