"""Pack the cut-out frames into Godot-ready sprite sheets.

Uses the cached cut-outs in work/<move>/cut. Trims the still frames at the start
and end of each attack by comparing silhouettes (alpha masks), which ignores
video compression noise. All moves share one crop box, so scale and the feet
anchor match across every sheet.
"""
import os, glob, json, sys
import numpy as np
from PIL import Image

# usage: python3 pack_char.py <char_dir> <prefix> <out_dir>
ROOT, PREFIX, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
MOVES = ["idle", "walk", "jab", "roundhouse", "crouch_punch", "crouch_kick", "jump",
         "jump_punch", "jump_kick", "special", "kick_special", "ultra", "block",
         "crouch_block", "hit", "knockdown"]
# effects in these clips (energy, lightning) may reach the frame edge: they don't size the crop box
NO_BOX = {"special", "ultra"}
# guard clips: keep the whole clip, the game holds the guard frame
NO_TRIM = {"block", "crouch_block"}
LOOPING = {"idle", "walk"}
FPS, SCALE, PAD = 12, 0.5, 10
TOP = 360   # headroom added above the 1280x720 source space, for jumps that leave the frame


def load(p):
    """Every frame in one padded space: 1280 x (720 + TOP). Frames already that tall
    (remapped jump frames) are used as they are."""
    im = Image.open(p).convert("RGBA")
    if im.size == (1280, 720 + TOP):
        return im
    c = Image.new("RGBA", (1280, 720 + TOP), (0, 0, 0, 0))
    c.paste(im, (0, TOP))
    return c


def mask(p):
    a = np.asarray(load(p).getchannel("A").resize((320, 270)))
    return a > 60


def trim(files, move):
    if move in LOOPING or move in NO_TRIM:
        return files
    m = [mask(f) for f in files]
    d_start = np.array([np.logical_xor(x, m[0]).mean() for x in m])
    d_end = np.array([np.logical_xor(x, m[-1]).mean() for x in m])
    peak = max(d_start.max(), 1e-6)
    thr = peak * 0.12
    first = int(np.argmax(d_start > thr))
    last = len(m) - 1 - int(np.argmax(d_end[::-1] > thr))
    # keep the moment the move finishes for knockdown (lying still)
    if move == "knockdown":
        last = min(last + 4, len(m) - 1)
    return files[max(first - 1, 0): min(last + 2, len(files))]


def bbox(p):
    return load(p).getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()


data = {}
for mv in MOVES:
    files = sorted(glob.glob(f"{ROOT}/work/{mv}/cut/*.png"))
    if not files:
        print("missing", mv); continue
    if mv in LOOPING and len(files) > 1:
        files = files  # build_all already dropped the duplicate loop frame
    data[mv] = trim(files, mv)
    print(f"{mv:12s} {len(files):3d} -> {len(data[mv]):3d} frames")

boxes = [b for mv, ps in data.items() if mv not in NO_BOX for p in ps if (b := bbox(p))]
box = (max(min(b[0] for b in boxes) - PAD, 0), max(min(b[1] for b in boxes) - PAD, 0),
       min(max(b[2] for b in boxes) + PAD, 1280), min(max(b[3] for b in boxes) + PAD, 720 + TOP))
cw, ch = round((box[2] - box[0]) * SCALE), round((box[3] - box[1]) * SCALE)

ib = bbox(data["idle"][0])
anchor = {"x": round(((ib[0] + ib[2]) / 2 - box[0]) * SCALE),
          "y": round((ib[3] - box[1]) * SCALE)}
body_h = round((ib[3] - ib[1]) * SCALE)

os.makedirs(OUT, exist_ok=True)
os.makedirs(f"{ROOT}/previews", exist_ok=True)
meta = {"frame_width": cw, "frame_height": ch, "fps": FPS, "feet_anchor": anchor,
        "body_height": body_h, "animations": {}}
for mv, ps in data.items():
    cells = [load(p).crop(box).resize((cw, ch), Image.LANCZOS) for p in ps]
    cols = min(len(cells), 8)
    rows = -(-len(cells) // cols)
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        sheet.paste(c, ((i % cols) * cw, (i // cols) * ch))
    sheet.save(f"{OUT}/{PREFIX}_{mv}.png", optimize=True)
    meta["animations"][mv] = {"file": f"{PREFIX}_{mv}.png", "frames": len(cells),
                              "columns": cols, "rows": rows, "loop": mv in LOOPING}
    gif = []
    for c in cells:
        b = Image.new("RGBA", (cw, ch), (30, 20, 40, 255))
        b.alpha_composite(c)
        gif.append(b.convert("P", palette=Image.ADAPTIVE))
    gif[0].save(f"{ROOT}/previews/{mv}.gif", save_all=True, append_images=gif[1:],
                duration=1000 // FPS, loop=0)

json.dump(meta, open(f"{OUT}/{PREFIX}_sprites.json", "w"), indent=2)
print("cell", cw, ch, "anchor", anchor, "body_height", body_h, "box", box)
