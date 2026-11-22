"""Turn an effect clip rendered on black into an additive sprite sheet.
usage: make_vfx.py <clip> <name> — settings per effect below."""
import sys, os, glob, json, subprocess
import numpy as np
from PIL import Image
clip, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
tmp = f"/home/claude/vfxwork/{name}"
os.makedirs(tmp, exist_ok=True)
if not glob.glob(f"{tmp}/*.png"):
    subprocess.run(["ffmpeg", "-v", "error", "-i", clip, "-vf", "fps=12", f"{tmp}/f_%03d.png"], check=True)
frames = [np.asarray(Image.open(p).convert("RGB"), np.float32) / 255 for p in sorted(glob.glob(f"{tmp}/*.png"))]
H, W = frames[0].shape[:2]
yy, xx = np.mgrid[0:H, 0:W]
u, v = xx / (W - 1), yy / (H - 1)
smooth = lambda e0, e1, x: np.clip((x - e0) / (e1 - e0), 0, 1) ** 2 * (3 - 2 * np.clip((x - e0) / (e1 - e0), 0, 1))
lum = [f.max(axis=2).mean() for f in frames]

if name == "chi_orb":
    # centre the frame on the orb (brightness centroid of a mid frame)
    f = frames[len(frames) // 2].max(axis=2)
    m = f > 0.85
    cx, cy = int(xx[m].mean()), int(yy[m].mean())
    r = min(cx, W - cx, cy, H - cy, 300)
    crop = (cx - r, cy - int(r * 0.55), cx + r, cy + int(r * 0.55))
    lo, mask = 0.08, smooth(1.0, 0.75, np.hypot((u - cx / W) / (r / W), (v - cy / H) / (r * 0.55 / H)))
    sel, size, fps, loop, anchor = frames[:18] + frames[16:0:-1], 260, 18, True, "center"
elif name == "fire_burst":
    start = next(i for i, l in enumerate(lum) if l > 0.25) - 1
    sel = frames[start:]
    end = next((i for i, f in enumerate(sel) if i > 4 and f.max(axis=2).mean() < 0.02), len(sel))
    sel = sel[2:end]
    crop, lo = (0, 0, W, H), 0.10
    mask = smooth(0.5, 0.36, np.hypot(u - 0.5, v - 0.5))
    size, fps, loop, anchor = 256, 24, False, "center"
elif name == "rock_burst":
    # skip the opening full-frame flash
    sel = frames[4:38]
    crop = (0, 0, W, H)
    lo = None
    mask = smooth(0.5, 0.33, np.abs(u - 0.5)) * smooth(0.0, 0.35, v)
    size, fps, loop, anchor = 256, 24, False, "bottom"
elif name == "lightning_beam":
    f = np.mean([fr.max(axis=2) for fr in frames], axis=0)
    cy = int(np.argmax(f.mean(axis=1)))
    hh = 120
    crop = (0, cy - hh, W, cy + hh)
    lo = 0.06
    mask = smooth(1.0, 0.55, np.abs(v - cy / H) / (hh / H)) * smooth(1.0, 0.92, u)
    sel, size, fps, loop, anchor = frames[6:42], 640, 18, True, "center"

cells = []
for f in sel:
    if lo is None:
        # golden haze: subtract a heavily blurred copy, keep the rocks and sparks
        from PIL import ImageFilter
        blur = np.asarray(Image.fromarray((f * 255).astype(np.uint8)).filter(
                ImageFilter.GaussianBlur(28)), np.float32) / 255
        g = np.clip((f - blur * 0.92) * 2.6, 0, 1) ** 1.5
    else:
        g = np.clip((f - lo) / (1 - lo), 0, 1)
    g = g * mask[..., None]
    im = Image.fromarray((g * 255).astype(np.uint8)).crop(crop)
    w = size
    h = round(im.height * size / im.width)
    cells.append(im.resize((w, h), Image.LANCZOS))
cw, ch = cells[0].size
cols = min(len(cells), max(1, 2048 // cw))
rows = -(-len(cells) // cols)
sheet = Image.new("RGB", (cols * cw, rows * ch))
for i, c in enumerate(cells):
    sheet.paste(c, ((i % cols) * cw, (i // cols) * ch))
sheet.save(f"{out}/{name}.png", optimize=True)
json.dump({"frame_width": cw, "frame_height": ch, "columns": cols, "frames": len(cells),
           "fps": fps, "loop": loop, "anchor": anchor}, open(f"{out}/{name}.json", "w"), indent=1)
print(name, len(cells), "frames", cw, ch, "sheet", sheet.size)
