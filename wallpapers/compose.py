"""Phone wallpapers (1080 x 2400) from wallpapers.sh's frames: white lines on black, each pixel 3 x 3, the PROPRUSH
title from the trailer's title card on a framed plate near the bottom. Usage: compose.py <frames dir> <out dir>"""

import sys

from PIL import Image, ImageDraw, ImageFilter, ImageOps

FRAMES, OUT = sys.argv[1], sys.argv[2]
W, H, K = 1080, 2400, 3
CROP = 360
INK, PAPER = (255, 255, 255), (0, 0, 0)
# Shot, frame kept; the stills are held, the chase is in the drift's second corner
SHOTS = [
    ("city-skybridge", 25),
    ("vibetown", 25),
    ("yard-crane", 25),
    ("apex", 25),
    ("flatout", 25),
    ("car-chase", 190),
]


def frame(name, n):
    return Image.open("%s/%s_%04d.png" % (FRAMES, name, n)).convert("L")


def portrait(im, car):
    cx = im.width // 2
    if car:
        # The car's wheels are the only solid black in the frame: what is left after a 5 px erosion
        box = im.point(lambda v: 255 if v < 100 else 0).filter(ImageFilter.MinFilter(5)).getbbox()
        if box:
            cx = (box[0] + box[2]) // 2
    x0 = max(0, min(im.width - CROP, cx - CROP // 2))
    return im.crop((x0, 0, x0 + CROP, im.height))


def ink(m):
    return ImageOps.colorize(m.point(lambda v: 255 if v > 127 else 0), INK, PAPER)


title = ink(frame("title", 60).crop((0, 10, 128, 30)))
title = title.resize((title.width * 6, title.height * 6), Image.NEAREST)
for name, n in SHOTS:
    img = ink(portrait(frame(name, n), name == "car-chase")).resize((W, H), Image.NEAREST)
    x, y = (W - title.width) // 2, H - title.height - 170
    ImageDraw.Draw(img).rectangle(
        [x - 6, y - 6, x + title.width + 6, y + title.height + 6], fill=PAPER, outline=INK, width=6
    )
    img.paste(title, (x, y))
    img.save("%s/proprush-%s.png" % (OUT, name))
