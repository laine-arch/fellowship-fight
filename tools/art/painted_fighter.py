"""Builds a fighter's game art from one painted character illustration.

Run from the repo root:  python3 tools/art/painted_fighter.py preacher
Needs: pillow, numpy, opencv-python-headless, rembg (pip install "rembg[cpu]").

Every body part is lifted straight from the painting: a strip of the image along a limb is
straightened onto the rig's bone and trimmed to the part's shape, so the in-game fighter keeps
the illustration's brushwork. Outputs go to game/art/fighters/<id>/ with the same file names and
pivots the rig builder expects (head.webp, portrait.webp, bust.webp, torso.png, upper_arm.png,
forearm.png, fist.png, thigh.png, shin.png; shoe.png is kept). Then rebuild the rigs:
    godot --headless --path game -s res://tools/build_fighters.gd

To add another painted fighter, copy the SPEC entry and fill in coordinates on that image
(open it in any editor that shows pixel positions). Coordinates are in the source image.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2  # parts are rendered at 2x

SPEC = {
    "preacher": {
        "source": "source-art/fighter-preacher-painted.webp",
        "mirror": True,  # the painting faces left; fighters face right
        # areas that must never be used (title lettering, badges, the second large face)
        "exclude": [
            [(0, 0), (480, 0), (480, 195), (375, 200), (340, 240), (330, 280), (0, 280)],
            [(560, 0), (1024, 0), (1024, 760), (935, 760), (845, 635), (760, 585), (700, 555), (650, 530),
             (612, 442), (668, 420), (668, 388), (628, 330), (606, 268), (572, 190)],
            [(0, 1170), (470, 1170), (470, 1536), (0, 1536)],
        ],
        "head": [(345, 250), (380, 212), (425, 203), (500, 205), (548, 222), (586, 280), (626, 352), (662, 393),
                 (662, 418), (612, 418), (582, 410), (560, 432), (542, 470), (505, 503), (440, 500), (380, 488),
                 (358, 470), (352, 425), (350, 372), (358, 318), (348, 282)],
        "neck": (478, 497),          # where the head meets the neck
        "headH": 74,                 # head height in game units
        "portrait": (554, 0, 1024, 470),
        "bust": (60, 190, 990, 1170),
        # limb strips: start point, end point, strip width (all in source pixels)
        "upper_arm": [(690, 655), (885, 800), 130],
        "forearm": [(118, 800), (238, 648), 105],
        "thigh": [(560, 1085), (770, 1330), 240],
        "shin": [(770, 1330), (905, 1515), 200],
        "fist": [(640, 850, 945, 1095), (905, 905), (690, 1000)],  # crop box, wrist, knuckles
        "torso": (345, 560, 690, 1040),
        "skin": (196, 136, 98),
        "pants": (52, 46, 46),
    },
}

# part canvas [w, h, pivotX, pivotY] in game units; must match tools/rig/render_parts.mjs
PARTS = {"torso": (96, 132, 48, 112), "upper_arm": (48, 84, 24, 24), "forearm": (40, 72, 20, 20), "fist": (40, 40, 20, 20),
         "thigh": (48, 100, 24, 24), "shin": (40, 92, 20, 20), "shoe": (56, 36, 18, 18)}
LIMB = {"upper_arm": (38, [14, 16.5, 11.5]), "forearm": (35, [11.5, 13, 8.5]), "thigh": (50, [17.5, 17, 12.5]), "shin": (52, [12.5, 14, 10])}
INK = (24, 16, 20)


def poly_mask(size, polys, fill=255, base=0):
    m = Image.new("L", size, base)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon(p, fill=fill)
    return m


def cutout(img, keep_poly=None, exclude=()):
    from rembg import new_session, remove
    a = remove(img, session=new_session("u2net_human_seg")).getchannel("A")
    if keep_poly:
        a = Image.fromarray(np.minimum(np.array(a), np.array(poly_mask(img.size, [keep_poly]))))
    if exclude:
        a = Image.fromarray(np.minimum(np.array(a), np.array(poly_mask(img.size, exclude, fill=0, base=255))))
    out = img.convert("RGBA")
    out.putalpha(a)
    return out


def pad(im, p):
    o = Image.new("RGBA", (im.width + 2 * p, im.height + 2 * p), (0, 0, 0, 0))
    o.paste(im, (p, p))
    return o


def outline(rgba, px=3, color=INK):
    a = np.array(rgba.getchannel("A"))
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (px * 2 + 1, px * 2 + 1))
    ring = cv2.dilate(a, k)
    base = Image.new("RGBA", rgba.size, color + (0,))
    base.putalpha(Image.fromarray(ring).filter(ImageFilter.GaussianBlur(0.6)))
    base.alpha_composite(rgba)
    return base


def capsule_mask(w, h, segs, ss=4):
    """Antialiased union of tapered capsules, segs in output pixels: (x1,y1,x2,y2,r1,r2)."""
    m = np.zeros((h * ss, w * ss), np.uint8)
    for x1, y1, x2, y2, r1, r2 in segs:
        p1, p2 = np.array([x1, y1]) * ss, np.array([x2, y2]) * ss
        cv2.circle(m, tuple(int(v) for v in p1), int(r1 * ss), 255, -1)
        cv2.circle(m, tuple(int(v) for v in p2), int(r2 * ss), 255, -1)
        d = p2 - p1
        n = np.array([-d[1], d[0]]) / (np.linalg.norm(d) + 1e-6)
        quad = np.array([p1 + n * r1 * ss, p2 + n * r2 * ss, p2 - n * r2 * ss, p1 - n * r1 * ss], np.int32)
        cv2.fillConvexPoly(m, quad, 255)
    return cv2.resize(m, (w, h), interpolation=cv2.INTER_AREA)


def strip(src, A, B, width_src, out_w, out_h, pivot, length, rmax):
    """Straighten the band of `src` from A to B (width width_src) onto a vertical bone of `length`."""
    A, B = np.array(A, float), np.array(B, float)
    u = B - A
    n = np.array([-u[1], u[0]]) / np.linalg.norm(u)
    ys, xs = np.mgrid[0:out_h, 0:out_w].astype(np.float32)
    lx = (xs / S - pivot[0]) / rmax          # -1..1 across the limb
    ly = (ys / S - pivot[1]) / length         # 0..1 along the bone
    mx = (A[0] + u[0] * ly + n[0] * lx * width_src / 2).astype(np.float32)
    my = (A[1] + u[1] * ly + n[1] * lx * width_src / 2).astype(np.float32)
    return cv2.remap(src, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)


def main(fid):
    sp = SPEC[fid]
    out_dir = f"game/art/fighters/{fid}/"
    src_img = Image.open(sp["source"]).convert("RGB")
    src = np.array(src_img)
    mirror = sp["mirror"]

    # --- head (in-game) ---
    head = cutout(src_img, sp["head"], sp["exclude"])
    bb = head.getbbox()
    head = head.crop(bb)
    anc = (sp["neck"][0] - bb[0], sp["neck"][1] - bb[1])
    if mirror:
        head = head.transpose(Image.FLIP_LEFT_RIGHT)
        anc = (head.width - anc[0], anc[1])
    k = 300 / head.height
    head = head.resize((round(head.width * k), 300), Image.LANCZOS)
    anc = (round(anc[0] * k), round(anc[1] * k))
    head = outline(pad(head, 6), 3)
    anc = (anc[0] + 6, anc[1] + 6)
    head.save(out_dir + "head.webp", quality=92)

    # --- portrait (select screen tiles, HUD) ---
    por = src_img.crop(sp["portrait"])
    por = por.resize((320, 320), Image.LANCZOS)
    por.save(out_dir + "portrait.webp", quality=88)

    # --- bust (VS splash, select panel) ---
    full = cutout(src_img, None, sp["exclude"])
    bust = full.crop(sp["bust"])
    bust = bust.crop(bust.getbbox())
    if mirror:
        bust = bust.transpose(Image.FLIP_LEFT_RIGHT)
    bust = bust.resize((bust.width * 52 // 100, bust.height * 52 // 100), Image.LANCZOS)
    outline(pad(bust, 6), 3).save(out_dir + "bust.webp", quality=86)

    meta = {"scale": 1 / S, "headAnchor": list(anc), "headH": sp["headH"], "parts": {}}

    # --- limbs ---
    for name, (length, (r0, r1, r2)) in LIMB.items():
        w, h, px, py = PARTS[name]
        A, B, wsrc = sp[name]
        rmax = max(r0, r1, r2)
        tex = strip(src, A, B, wsrc, w * S, h * S, (px, py), length, rmax)
        m1 = 0.42 if name in ("upper_arm", "thigh") else 0.32
        segs = [(px * S, py * S, px * S, (py + length * m1) * S, r0 * S, r1 * S),
                (px * S, (py + length * m1) * S, px * S, (py + length) * S, r1 * S, r2 * S)]
        mask = capsule_mask(w * S, h * S, segs)
        part = Image.fromarray(tex).convert("RGBA")
        part.putalpha(Image.fromarray(mask))
        outline(part, 3).save(out_dir + name + ".png")
        meta["parts"][name] = {"pivot": [px, py], "size": [w, h]}

    # --- fist: the wrapped fist, turned so the knuckles continue the forearm (pointing down) ---
    x0, y0, x1, y1 = sp["fist"][0]
    wrist = np.array(sp["fist"][1], float) - [x0, y0]
    knuck = np.array(sp["fist"][2], float) - [x0, y0]
    fist = full.crop((x0, y0, x1, y1))
    d = knuck - wrist
    ang = np.degrees(np.arctan2(d[0], d[1]))      # angle of wrist→knuckles from straight down
    rot = fist.rotate(-ang, resample=Image.BICUBIC, expand=True)
    def rpt(p):  # where a crop point lands after rotate(expand=True)
        c0 = np.array(fist.size) / 2
        c1 = np.array(rot.size) / 2
        t = np.radians(ang)
        v = p - c0
        return c1 + np.array([v[0] * np.cos(t) - v[1] * np.sin(t), v[0] * np.sin(t) + v[1] * np.cos(t)])
    mid = (rpt(wrist) + rpt(knuck)) / 2
    w, h, px, py = PARTS["fist"]
    scale = 28 * S / np.linalg.norm(d)            # wrist→knuckles spans ~28 game units… of a 2x canvas
    rot = rot.resize((round(rot.width * scale), round(rot.height * scale)), Image.LANCZOS)
    mid = mid * scale
    out = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    out.alpha_composite(rot, (round(px * S - mid[0]), round(py * S - mid[1] + 2 * S)))
    # keep only the fist itself (the crop box also catches a little background)
    keep = Image.new("L", out.size, 0)
    ImageDraw.Draw(keep).ellipse([(px - 14) * S, (py - 12) * S, (px + 14) * S, (py + 16) * S], fill=255)
    keep = keep.filter(ImageFilter.GaussianBlur(1.2))
    out.putalpha(Image.fromarray(np.minimum(np.array(out.getchannel("A")), np.array(keep))))
    if mirror:
        out = out.transpose(Image.FLIP_LEFT_RIGHT)
    outline(out, 2).save(out_dir + "fist.png")
    meta["parts"]["fist"] = {"pivot": [px, py], "size": [w, h]}

    # --- torso: the shirt, fitted into the rig's torso shape, with the neck and waistband ---
    w, h, px, py = PARTS["torso"]
    T = 74
    shirt = src_img.crop(sp["torso"])
    if mirror:
        shirt = shirt.transpose(Image.FLIP_LEFT_RIGHT)
    tw, th = 78, T + 12
    shirt = shirt.resize((tw * S, th * S), Image.LANCZOS).convert("RGBA")
    canvas = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    o = lambda x, y: ((px + x) * S, (py + y) * S)
    # neck
    nd = ImageDraw.Draw(canvas)
    sk = tuple(sp["skin"])
    nd.rounded_rectangle([o(-9, -T - 16), o(9, -T + 8)], radius=8 * S, fill=sk + (255,), outline=INK + (255,), width=2 * S)
    nd.line([o(-3, -T - 14), o(-3, -T + 4)], fill=tuple(int(v * 0.75) for v in sk) + (255,), width=3 * S)
    body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    body.paste(shirt, (round((px - tw / 2) * S), round((py - T - 6) * S)))
    shape = [o(-24, 6), o(24, 6), o(29, -T * .45), o(36, -T + 16), o(34, -T - 3), o(12, -T - 6), o(-14, -T - 6),
             o(-37, -T - 2), o(-37, -T + 16), o(-29, -T * .45)]
    m = poly_mask(canvas.size, [shape]).filter(ImageFilter.GaussianBlur(0.8))
    body.putalpha(Image.fromarray(np.minimum(np.array(body.getchannel("A")), np.array(m))))
    body = outline(body, 3)
    canvas.alpha_composite(body)
    bd = ImageDraw.Draw(canvas)
    pc = tuple(sp["pants"])
    bd.rectangle([o(-26, -2), o(26, 9)], fill=INK + (255,))
    bd.rectangle([o(-24, 0), o(24, 7)], fill=pc + (255,))
    canvas.save(out_dir + "torso.png")
    meta["parts"]["torso"] = {"pivot": [px, py], "size": [w, h]}
    meta["parts"]["shoe"] = {"pivot": list(PARTS["shoe"][2:]), "size": list(PARTS["shoe"][:2])}

    json.dump(meta, open(out_dir + "parts.json", "w"), indent=1)
    print("built", fid, "head anchor", anc)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "preacher")
