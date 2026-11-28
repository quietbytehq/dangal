"""Render the arcade world map (no borders) from world-atlas land-50m."""
import json, numpy as np
from PIL import Image, ImageDraw, ImageFilter
W, H = 1280, 720
LON0, LON1 = -85.0, 135.0
PX = W / (LON1 - LON0)
LAT_TOP = 74.0
def xy(lon, lat):
    return ((lon - LON0) * PX, (LAT_TOP - lat) * PX)
d = json.load(open('/tmp/wa/package/land-50m.json'))
sx, sy = d['transform']['scale']; tx, ty = d['transform']['translate']
arcs = []
for a in d['arcs']:
    x = y = 0; pts = []
    for dx, dy in a:
        x += dx; y += dy; pts.append((x * sx + tx, y * sy + ty))
    arcs.append(pts)
def arc(i):
    return arcs[i] if i >= 0 else arcs[~i][::-1]
rings = []
for g in d['objects']['land']['geometries']:
    polys = g['arcs'] if g['type'] == 'MultiPolygon' else [g['arcs']]
    for poly in polys:
        for ring in poly:
            pts = []
            for i in ring:
                pts += arc(i)
            rings.append(pts)
S = 2   # supersample
land = Image.new('L', (W * S, H * S), 0)
dr = ImageDraw.Draw(land)
for pts in rings:
    # unwrap across the antimeridian
    out = []; off = 0; prev = None
    for lon, lat in pts:
        if prev is not None and lon + off - prev > 180: off -= 360
        elif prev is not None and lon + off - prev < -180: off += 360
        prev = lon + off; out.append((lon + off, lat))
    for shift in (0, -360, 360):
        poly = [((xy(lo + shift, la)[0]) * S, xy(lo + shift, la)[1] * S) for lo, la in out]
        if len(poly) > 2:
            dr.polygon(poly, fill=255)
land = land.resize((W, H), Image.LANCZOS)
L = np.asarray(land).astype(np.float32) / 255
# ocean: deep navy with a soft vignette and a faint lat/long grid
yy, xx = np.mgrid[0:H, 0:W]
vig = 1 - 0.55 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) / 2
ocean = np.dstack([8 + 6 * vig, 14 + 14 * vig, 30 + 30 * vig])
img = ocean.copy()
grid = np.zeros((H, W), np.float32)
for lon in range(-80, 140, 15):
    x = int(round(xy(lon, 0)[0])); grid[:, max(x, 0):x + 1] = 1
for lat in range(-45, 75, 15):
    y = int(round(xy(0, lat)[1])); grid[max(y, 0):y + 1, :] = 1
img += grid[..., None] * np.array([10, 30, 45])
# land: dotted halftone fill in teal, bright glowing coastline
dots = ((xx % 6 < 3) & (yy % 6 < 3)).astype(np.float32)
fill = np.array([24, 70, 84]) * (0.75 + 0.25 * dots[..., None])
img = img * (1 - L[..., None]) + fill * L[..., None]
edge = np.asarray(land.filter(ImageFilter.FIND_EDGES)).astype(np.float32) / 255
edge[:2, :] = 0; edge[-2:, :] = 0; edge[:, :2] = 0; edge[:, -2:] = 0
glow = np.asarray(Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255
img += glow[..., None] * np.array([40, 160, 200]) * 1.6 + edge[..., None] * np.array([80, 220, 255])
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save('/home/claude/rustam-fighter/assets/map/world.png')
print('map ok', xy(-9.4, 53.0), xy(69.2, 34.5))
