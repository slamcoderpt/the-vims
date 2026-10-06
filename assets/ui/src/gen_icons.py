#!/usr/bin/env python3
"""Generate the HUD icon PNGs in assets/ui/icons/ from Noto Color Emoji
(copied next to this script) plus a few procedurally drawn glyphs.

usage: python3 assets/ui/src/gen_icons.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "icons")
SIZE = 64
FONT = ImageFont.truetype(os.path.join(HERE, "NotoColorEmoji.ttf"), 109)

# name: (emoji, tint or None)
GREEN = (92, 205, 74)
PURPLE = (176, 104, 240)
PINK = (240, 104, 122)
EMOJI = {
    # needs
    "need_fun": ("\U0001F60A", GREEN),
    "need_hunger": ("\U0001F354", None),
    "need_hygiene": ("\U0001F4A7", None),
    "need_energy": ("\U0001F6CF", PURPLE),
    "need_social": ("\U0001F464", PINK),
    "need_bladder": ("\U0001F6BD", None),
    "bone": ("\U0001F9B4", None),
    # tasks / actions
    "laptop": ("\U0001F4BB", None),
    "palette": ("\U0001F3A8", None),
    "book": ("\U0001F4D8", None),
    "book_open": ("\U0001F4D6", None),
    "chart": ("\U0001F4CA", None),
    "bill": ("\U0001F9FE", None),
    "paw": ("\U0001F43E", (214, 120, 52)),
    "apple": ("\U0001F34E", None),
    "chat": ("\U0001F4AC", None),
    "target": ("\U0001F3AF", None),
    "camera": ("\U0001F4F7", None),
    "trophy": ("\U0001F3C6", None),
    "home": ("\U0001F3E0", None),
    "bath": ("\U0001F6C1", None),
    "brush": ("\U0001FAA5", None),
    "bed": ("\U0001F6CF", None),
    "toys": ("\U0001F9F8", None),
    "burger": ("\U0001F354", None),
    "people": ("\U0001F465", None),
    "heart": ("❤️", None),
    "plate": ("\U0001F37D", None),
    "broom": ("\U0001F9F9", None),
    "cart": ("\U0001F6D2", None),
    "register": ("\U0001F4B3", None),
    "music": ("\U0001F3B5", None),
    "bulb": ("\U0001F4A1", None),
    "sun": ("☀️", None),
    "moon": ("\U0001F319", None),
    "leaf": ("\U0001F341", None),
    "snow": ("❄️", None),
    "blossom": ("\U0001F338", None),
    "money": ("\U0001F4B5", None),
    "sofa": ("\U0001F6CB", None),
    "plant": ("\U0001FAB4", None),
    "hammer": ("\U0001F528", None),
    "cook": ("\U0001F373", None),
    "gift": ("\U0001F381", None),
    "zzz": ("\U0001F4A4", None),
    "smile": ("\U0001F60A", None),
    "scale": ("⚖️", None),
    "star": ("⭐", None),
    "pencil": ("✏️", None),
    "fire": ("\U0001F525", None),
    "work": ("\U0001F4BC", None),
    "gamepad": ("\U0001F3AE", None),
    "guitar": ("\U0001F3B8", None),
    "piano": ("\U0001F3B9", None),
    "phone": ("\U0001F4F1", None),
    "coffee": ("☕", None),
    "tv": ("\U0001F4FA", None),
    "shower": ("\U0001F6BF", None),
    "toilet": ("\U0001F6BD", None),
    "pizza": ("\U0001F355", None),
    "email": ("\U0001F4E7", None),
    "ball": ("⚽", None),
    "wave": ("\U0001F44B", None),
    "laugh": ("\U0001F604", None),
    "teddy": ("\U0001F9F8", None),
    "carrot": ("\U0001F955", None),
    "bread": ("\U0001F35E", None),
    "milk": ("\U0001F95B", None),
    "banana": ("\U0001F34C", None),
    "cereal": ("\U0001F963", None),
    "lantern": ("\U0001F3EE", None),
    "pumpkin": ("\U0001F383", None),
    "drink": ("\U0001F964", None),
    "cake": ("\U0001F370", None),
    "dance": ("\U0001F483", None),
    "tooth": ("\U0001F9B7", None),
    "eat": ("\U0001F374", None),
    "sleep": ("\U0001F634", None),
}


def tint(im, rgb):
    px = im.load()
    mx = 0.01
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 128:
                mx = max(mx, (0.3 * r + 0.59 * g + 0.11 * b) / 255.0)
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255.0 / mx
            f = 0.5 + 0.6 * lum
            px[x, y] = (min(255, int(rgb[0] * f)), min(255, int(rgb[1] * f)), min(255, int(rgb[2] * f)), a)
    return im


def fit(im):
    bb = im.getbbox()
    im = im.crop(bb)
    s = max(im.width, im.height)
    sq = Image.new("RGBA", (s, s))
    sq.paste(im, ((s - im.width) // 2, (s - im.height) // 2))
    return sq.resize((SIZE, SIZE), Image.LANCZOS)


def emoji(ch):
    im = Image.new("RGBA", (180, 180))
    ImageDraw.Draw(im).text((10, 10), ch, font=FONT, embedded_color=True)
    if im.getbbox() is None:
        raise SystemExit("missing glyph %r" % ch)
    return im


def big():
    return Image.new("RGBA", (256, 256)), 256


def save(name, im):
    im.save(os.path.join(OUT, name + ".png"))


def house_white():
    im, s = big()
    d = ImageDraw.Draw(im)
    w = (255, 255, 255, 255)
    d.polygon([(128, 22), (240, 120), (212, 120), (128, 46), (44, 120), (16, 120)], fill=w)
    d.rounded_rectangle((52, 108, 204, 236), radius=14, fill=w)
    d.polygon([(52, 112), (128, 46), (204, 112)], fill=w)
    d.rectangle((168, 34, 196, 90), fill=w)
    d.rounded_rectangle((104, 150, 152, 236), radius=10, fill=(0, 0, 0, 0))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def arrow_up(rgb):
    im, s = big()
    d = ImageDraw.Draw(im)
    c = rgb + (255,)
    d.polygon([(128, 18), (232, 130), (168, 130), (168, 238), (88, 238), (88, 130), (24, 130)], fill=c)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def moon_blue():
    im, s = big()
    d = ImageDraw.Draw(im)
    d.ellipse((24, 24, 232, 232), fill=(92, 104, 238, 255))
    d.ellipse((92, 4, 270, 190), fill=(0, 0, 0, 0))
    # soft inner highlight
    hi = Image.new("RGBA", (256, 256))
    hd = ImageDraw.Draw(hi)
    hd.ellipse((40, 60, 120, 200), fill=(140, 160, 255, 90))
    im = Image.alpha_composite(im, Image.composite(hi, Image.new("RGBA", (256, 256)), im.split()[3]))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def dots():
    im, s = big()
    d = ImageDraw.Draw(im)
    for x in (56, 128, 200):
        d.ellipse((x - 22, 106, x + 22, 150), fill=(60, 64, 84, 255))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def armchair():
    im, s = big()
    d = ImageDraw.Draw(im)
    base, mid, dark, hi = (242, 168, 72, 255), (226, 140, 50, 255), (190, 104, 34, 255), (255, 206, 128, 255)
    d.rounded_rectangle((44, 40, 212, 150), radius=30, fill=mid)          # back
    d.rounded_rectangle((58, 50, 198, 132), radius=22, fill=base)
    d.rounded_rectangle((60, 54, 196, 76), radius=12, fill=hi)
    d.rounded_rectangle((52, 128, 204, 196), radius=18, fill=base)        # seat
    d.rounded_rectangle((52, 128, 204, 146), radius=10, fill=hi)
    for x0 in (14, 186):                                                   # arms
        d.rounded_rectangle((x0, 100, x0 + 56, 210), radius=22, fill=mid)
        d.rounded_rectangle((x0 + 4, 102, x0 + 52, 124), radius=12, fill=hi)
    d.rounded_rectangle((40, 196, 216, 214), radius=8, fill=dark)
    for x0 in (44, 196):
        d.rectangle((x0, 210, x0 + 16, 236), fill=(120, 76, 40, 255))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def sprout_pot():
    im, s = big()
    d = ImageDraw.Draw(im)
    g1, g2, g3 = (92, 186, 72, 255), (64, 150, 54, 255), (140, 214, 104, 255)
    d.rectangle((122, 70, 134, 160), fill=g2)                              # stem
    d.ellipse((40, 50, 132, 110), fill=g1)                                 # left leaf
    d.ellipse((52, 58, 112, 84), fill=g3)
    d.ellipse((124, 30, 220, 92), fill=g1)                                 # right leaf
    d.ellipse((140, 38, 200, 62), fill=g3)
    d.ellipse((96, 6, 160, 62), fill=g2)                                   # top leaf
    d.polygon([(66, 148), (190, 148), (172, 238), (84, 238)], fill=(206, 104, 60, 255))
    d.rounded_rectangle((54, 134, 202, 164), radius=8, fill=(226, 124, 76, 255))
    d.rectangle((60, 136, 196, 144), fill=(240, 152, 104, 255))
    d.polygon([(70, 166), (186, 166), (182, 182), (74, 182)], fill=(176, 84, 48, 255))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def need_fun():
    """Flat green smiley like the ref need column (not a glossy emoji)."""
    im, s = big()
    d = ImageDraw.Draw(im)
    d.ellipse((16, 16, 240, 240), fill=(104, 214, 80, 255))
    d.ellipse((36, 30, 200, 150), fill=(134, 228, 108, 255))
    d.ellipse((36, 40, 236, 236), fill=(104, 214, 80, 255))
    ink = (34, 92, 40, 255)
    d.rounded_rectangle((82, 82, 108, 124), radius=13, fill=ink)
    d.rounded_rectangle((148, 82, 174, 124), radius=13, fill=ink)
    d.arc((66, 104, 190, 196), start=20, end=160, fill=ink, width=18)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def need_social():
    """Pink pair of heads (social), soft flat style."""
    im, s = big()
    d = ImageDraw.Draw(im)
    back, front, hi = (238, 120, 136, 255), (250, 150, 160, 255), (255, 196, 202, 255)
    d.ellipse((128, 40, 220, 132), fill=back)
    d.rounded_rectangle((112, 128, 246, 230), radius=50, fill=back)
    d.ellipse((30, 60, 138, 168), fill=front)
    d.ellipse((50, 74, 96, 110), fill=hi)
    d.rounded_rectangle((8, 160, 162, 246), radius=56, fill=front)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (ch, t) in EMOJI.items():
        im = fit(emoji(ch))
        if t:
            im = tint(im, t)
        save(name, im)
    save("need_fun", need_fun())
    save("need_social", need_social())
    save("house_white", house_white())
    save("arrow_up", arrow_up((70, 196, 60)))
    save("moon_blue", moon_blue())
    save("dots", dots())
    save("armchair", armchair())
    save("sprout", sprout_pot())
    print("icons:", len(os.listdir(OUT)))


if __name__ == "__main__":
    main()
