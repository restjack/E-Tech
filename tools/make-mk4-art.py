"""Generate every Mk4 graphic from Factorissimo's own art.

    python tools/make-mk4-art.py <path to unzipped factorissimo mod> [outdir]

Writes into E-Tech/graphics/factory-mk4/:
    factory-4.png                     ground building facade
    space-factory-4.png               space-platform variant
    tech-factory-architecture-4.png   technology icon
    icon-factory-4.png                item/entity icon
    factory-wall-4.png                interior wall + floor-pattern tile

Lives outside E-Tech/ on purpose: the mod portal rejects zips containing
scripts. Needs Pillow and C:/Windows/Fonts/ariblk.ttf.

WHY THIS EXISTS. The Mk4 reuses the Mk3's exterior footprint, so without its own
art the two tiers are indistinguishable - and a prototype `tint` cannot fix
that, because tint is a multiply (darken only) and it cannot repaint the "03"
painted on the facade. So the tier number is repainted and the building
recoloured here.

THE TWO SKINS DIFFER. The ground building is yellow paint on a blue-grey wall;
the space building is BLUE paint on neutral grey, at exactly half the
resolution. Everything below is parameterised per skin rather than hardcoded.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

MOD = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "E-Tech", "graphics", "factory-mk4")
G = os.path.join(MOD, "graphics")
FONT_PATH = "C:/Windows/Fonts/ariblk.ttf"

os.makedirs(OUT, exist_ok=True)


def out(name):
    return os.path.join(OUT, name)


# --- paint detectors ---------------------------------------------------------
# "Paint" is the tier lettering and the hazard band - the parts that keep their
# own colour when the rest of the building is recoloured.

def yellow_paint(p):
    r, g, b, a = p
    return a > 0 and r > 60 and b < r * 0.68 and abs(r - g) < 45


def blue_paint(p):
    r, g, b, a = p
    return a > 0 and b > 80 and b - r > 30


def luminance(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def load_glyph(height, x_squash=1.0):
    """A "4" from a real typeface.

    Hand-drawn polygons were tried first and looked crude in game: the facade
    font is a heavy rounded grotesque - measured off the "0" at 136x151 with a
    ~42px stroke - and a guessed 34px stroke with a sliver of a counter did not
    read as the same font. Arial Black matches it closely.
    """
    font = ImageFont.truetype(FONT_PATH, 400)
    bb = font.getbbox("4")
    g = Image.new("L", (bb[2] - bb[0] + 40, bb[3] - bb[1] + 40), 0)
    ImageDraw.Draw(g).text((20 - bb[0], 20 - bb[1]), "4", font=font, fill=255)
    g = g.crop(g.getbbox())
    return g.resize((max(1, round(g.width * height / g.height * x_squash)), height),
                    Image.LANCZOS)


# --- shared building pipeline ------------------------------------------------

def repaint_building(src, geom, is_paint, tint, paint_recolour=None):
    """Turn a factory-3 body sprite into a factory-4 one."""
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    px = im.load()

    crate = geom["crate"]
    ex0, ey0, ex1, ey1 = geom["erase"]

    def must_erase(x, y):
        cx0, cy0, cx1, cy1 = crate
        if cx0 <= x < cx1 and cy0 <= y < cy1:
            return True                 # the crate, whatever colour it is
        return is_paint(px[x, y])       # the "3"

    # 1. Clear the bay - crate included. The crates are drawn ON TOP of the
    # digits in the same colour family at every brightness, so they cannot be
    # masked per pixel; and the "4" carries its crossbar lower than the "3"
    # carried its middle, so leaving the crate hides the bar and the digit reads
    # as a wedge. Only the crate footprint and the old glyph are touched -
    # wiping the whole bay as one rectangle left a visibly flat patch.
    for y in range(ey0, ey1):
        clean = [x for x in geom["clean_x"]
                 if px[x, y][3] > 0 and not is_paint(px[x, y])]
        if not clean:
            continue
        for x in range(ex0, ex1):
            if px[x, y][3] == 0 or not must_erase(x, y):
                continue
            sx = min(clean, key=lambda c: abs(c - x))
            r, g, b, _ = px[sx, y]
            px[x, y] = (r, g, b, px[x, y][3])

    # 2. Paint the "4".
    dh, dtop, dleft = geom["digit_h"], geom["digit_top"], geom["digit_left"]
    glyph = load_glyph(dh)

    zx0, zy0, zx1, zy1 = geom["zero"]
    tot, n = [0, 0, 0], 0
    for y in range(zy0, zy1):
        for x in range(zx0, zx1):
            p = px[x, y]
            if is_paint(p) and luminance(*p[:3]) > geom["paint_min_lum"]:
                tot[0] += p[0]; tot[1] += p[1]; tot[2] += p[2]; n += 1
    paint = tuple(c // max(1, n) for c in tot)

    wtot, wn = 0.0, 0
    for y in range(dtop, dtop + dh):
        for x in range(dleft, dleft + glyph.width):
            p = px[x, y]
            if p[3] == 0 or is_paint(p):
                continue
            wtot += luminance(*p[:3]); wn += 1
    wall_lum = wtot / max(1, wn)

    gpx = glyph.load()
    for gy in range(glyph.height):
        for gx in range(glyph.width):
            cov = gpx[gx, gy]
            if not cov:
                continue
            x, y = dleft + gx, dtop + gy
            r, gg, b, a = px[x, y]
            if a == 0:
                continue
            # Blend by the glyph's own antialiasing, and carry the wall's
            # shading into the paint - a flat fill next to the weathered "0"
            # reads as pasted on.
            k = (cov / 255.0) * 0.90
            shade = max(0.78, min(1.12, luminance(r, gg, b) / wall_lum))
            px[x, y] = (int(paint[0] * shade * k + r * (1 - k)),
                        int(paint[1] * shade * k + gg * (1 - k)),
                        int(paint[2] * shade * k + b * (1 - k)), a)

    # 3. Recolour: map every non-paint pixel to its own luminance tinted, which
    # keeps all the corrugation and grime but changes the material colour.
    for y in range(H):
        for x in range(W):
            r, gg, b, a = px[x, y]
            if a == 0:
                continue
            if is_paint((r, gg, b, a)):
                if paint_recolour:
                    lum = luminance(r, gg, b)
                    px[x, y] = (min(255, int(lum * paint_recolour[0])),
                                min(255, int(lum * paint_recolour[1])),
                                min(255, int(lum * paint_recolour[2])), a)
                continue
            lum = luminance(r, gg, b)
            px[x, y] = (min(255, int(lum * tint[0])),
                        min(255, int(lum * tint[1])),
                        min(255, int(lum * tint[2])), a)
    return im


# Ground building: yellow paint kept, warm brown siding turned steel blue.
GROUND = dict(
    crate=(845, 1035, 970, 1133),
    erase=(846, 950, 1006, 1142),
    clean_x=range(986, 1120),
    zero=(700, 955, 845, 1140),
    digit_h=151, digit_top=974, digit_left=855,
    paint_min_lum=110,
)
repaint_building(os.path.join(G, "factory", "factory-3.png"),
                 GROUND, yellow_paint, (0.60, 0.76, 1.02)).save(out("factory-4.png"))
print("wrote factory-4.png")

# Space building: exactly half the resolution, so every box halves. All three
# stock space tiers already share a blue-grey skin, so recolouring the WALL
# would not separate a Mk4 from a Mk3 - the PAINT goes amber instead, which
# reads instantly against the blue.
SPACE = dict(
    crate=(422, 517, 485, 566),
    erase=(423, 475, 503, 571),
    clean_x=range(493, 560),
    zero=(350, 477, 422, 570),
    digit_h=75, digit_top=487, digit_left=427,
    paint_min_lum=60,
)
repaint_building(os.path.join(G, "factory", "space-factory-3.png"),
                 SPACE, blue_paint, (0.92, 0.96, 1.0),
                 paint_recolour=(1.45, 1.05, 0.35)).save(out("space-factory-4.png"))
print("wrote space-factory-4.png")


# --- technology icon ---------------------------------------------------------
# An isometric render with "03" on a TILTED face, straddling the yellow band and
# the grey wall above it. Factorissimo's framing is kept - the architecture
# techs sit in a row and a front elevation would stick out - so the digit is
# repainted in place. Both problems are handled by working along the FACE AXIS
# (the direction the band runs): a horizontal fill smears band colour up over
# wall, and an upright glyph would not sit on the face.
TECH_ZERO = (104, 147, 131, 191)
TECH_THREE = (134, 156, 163, 204)
FACE_SLOPE = 0.39      # dy/dx along the band, measured off the 0/3 baselines
ANGLE = 21             # degrees clockwise, same source
UPRIGHT_H = 47         # un-rotating the "3"'s 30x49 box gives ~14x47 ...
X_SQUASH = 0.41        # ... i.e. the render foreshortens x to ~0.41


def tech_digit(p):
    r, g, b, a = p
    return a > 0 and r > 150 and g > 120 and b < 95


tech = Image.open(os.path.join(G, "technology", "factory-architecture-3.png")).convert("RGBA")
tpx = tech.load()
TW, TH = tech.size

x0, y0, x1, y1 = TECH_THREE
for y in range(y0 - 2, y1 + 3):
    for x in range(x0 - 2, x1 + 3):
        if not (0 <= x < TW and 0 <= y < TH) or not tech_digit(tpx[x, y]):
            continue
        for step in range(1, 60):
            sx, sy = x - step, int(round(y - step * FACE_SLOPE))
            if not (0 <= sx < TW and 0 <= sy < TH):
                break
            sp = tpx[sx, sy]
            if sp[3] > 0 and not tech_digit(sp):
                tpx[x, y] = (sp[0], sp[1], sp[2], tpx[x, y][3])
                break

tot, n = [0, 0, 0], 0
for y in range(TECH_ZERO[1], TECH_ZERO[3] + 1):
    for x in range(TECH_ZERO[0], TECH_ZERO[2] + 1):
        p = tpx[x, y]
        if tech_digit(p):
            tot[0] += p[0]; tot[1] += p[1]; tot[2] += p[2]; n += 1
tech_paint = tuple(c // max(1, n) for c in tot)

tglyph = load_glyph(UPRIGHT_H, X_SQUASH).rotate(-ANGLE, resample=Image.BICUBIC, expand=True)
tg = tglyph.load()
for gy in range(tglyph.height):
    for gx in range(tglyph.width):
        cov = tg[gx, gy]
        if not cov:
            continue
        x, y = TECH_THREE[0] + gx, TECH_THREE[1] + gy
        if not (0 <= x < TW and 0 <= y < TH):
            continue
        r, gg, b, a = tpx[x, y]
        if a == 0:
            continue
        k = (cov / 255.0) * 0.92
        tpx[x, y] = (int(tech_paint[0] * k + r * (1 - k)),
                     int(tech_paint[1] * k + gg * (1 - k)),
                     int(tech_paint[2] * k + b * (1 - k)), a)


def recolour_keep_paint(img, tint):
    p = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g_, b, a = p[x, y]
            if a == 0 or yellow_paint((r, g_, b, a)):
                continue
            lum = luminance(r, g_, b)
            p[x, y] = (min(255, int(lum * tint[0])),
                       min(255, int(lum * tint[1])),
                       min(255, int(lum * tint[2])), a)
    return img


recolour_keep_paint(tech, (0.60, 0.76, 1.02)).save(out("tech-factory-architecture-4.png"))
print("wrote tech-factory-architecture-4.png")

# Item/entity icon: a tight front crop at 64px. No digit is legible at that
# size, so this only needs the recolour.
recolour_keep_paint(
    Image.open(os.path.join(G, "icon", "factory-3.png")).convert("RGBA"),
    (0.60, 0.76, 1.02)).save(out("icon-factory-4.png"))
print("wrote icon-factory-4.png")

# --- interior wall / floor-pattern tiles -------------------------------------
# Without these the INSIDE of a Mk4 is identical to a Mk3. The stock ground
# tiers are orange (1), blue (2) and yellow (3), so the Mk4 goes teal - close
# to its steel-blue exterior but clear of factory-2's blue. The space tiles get
# amber instead, matching the amber paint on the space building, because all
# three stock space tiers are already blue-grey.
def recolour_tile(src, dst, tint):
    if not os.path.exists(src):
        print("skipped", os.path.basename(dst), "- no", os.path.basename(src))
        return
    tile = Image.open(src).convert("RGBA")
    p = tile.load()
    for y in range(tile.height):
        for x in range(tile.width):
            r, g_, b, a = p[x, y]
            if a == 0:
                continue
            lum = luminance(r, g_, b)
            p[x, y] = (min(255, int(lum * tint[0])),
                       min(255, int(lum * tint[1])),
                       min(255, int(lum * tint[2])), a)
    tile.save(dst)
    print("wrote", os.path.basename(dst))


recolour_tile(os.path.join(G, "tile", "factory-wall-3.png"),
              out("factory-wall-4.png"), (0.38, 1.05, 1.12))
recolour_tile(os.path.join(G, "tile", "space-factory-wall-3.png"),
              out("space-factory-wall-4.png"), (1.35, 1.00, 0.42))
