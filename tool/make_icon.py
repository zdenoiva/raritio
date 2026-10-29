from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import os

SIZE = 1024
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(OUT, "android", "app", "src", "main", "res")

# --- background -----------------------------------------------------------
bg = Image.new("RGBA", (SIZE, SIZE), (10, 10, 14, 255))
px = bg.load()
for y in range(SIZE):
    t = y / (SIZE - 1)
    r = int(12 + 8 * t)
    g = int(14 + 10 * t)
    b = int(24 + 22 * t)
    for x in range(SIZE):
        px[x, y] = (r, g, b, 255)

# soft blue/purple glow
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse((-180, 40, 760, 980), fill=(59, 130, 246, 74))
gd.ellipse((350, -120, 1240, 760), fill=(139, 92, 246, 56))
glow = glow.filter(ImageFilter.GaussianBlur(90))
bg = Image.alpha_composite(bg, glow)


def gradient_card(w, h, top, bottom):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        d.line((0, y, w, y), fill=(r, g, b, 255))
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, w - 1, h - 1), radius=54, fill=255)
    img.putalpha(mask)
    return img


# back card
back = gradient_card(540, 760, (30, 41, 59), (76, 29, 149))
back = back.rotate(9, expand=True, resample=Image.BICUBIC)
bd = ImageDraw.Draw(back)
bd.rounded_rectangle((4, 4, back.width - 5, back.height - 5), radius=56, outline=(255, 255, 255, 40), width=3)

# shadow for front card
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle((300, 190, 800, 900), radius=70, fill=(0, 0, 0, 120))
shadow = shadow.filter(ImageFilter.GaussianBlur(38))
bg = Image.alpha_composite(bg, shadow)

back_pos = ((SIZE - back.width) // 2 + 34, (SIZE - back.height) // 2 + 6)
bg.alpha_composite(back, back_pos)

# front card
front = gradient_card(560, 790, (59, 130, 246), (139, 92, 246))
front = front.rotate(-11, expand=True, resample=Image.BICUBIC)
fd = ImageDraw.Draw(front)
fd.rounded_rectangle((5, 5, front.width - 6, front.height - 6), radius=58, outline=(255, 255, 255, 105), width=4)
front_pos = ((SIZE - front.width) // 2 - 26, (SIZE - front.height) // 2 - 8)
bg.alpha_composite(front, front_pos)

# letter R
font_path = r"C:\Windows\Fonts\arialbd.ttf"
if not os.path.exists(font_path):
    font_path = r"C:\Windows\Fonts\segoeuib.ttf"
font = ImageFont.truetype(font_path, 440)
draw = ImageDraw.Draw(bg)
text = "R"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
tx = (SIZE - tw) // 2 - bbox[0] - 20
ty = (SIZE - th) // 2 - bbox[1] - 30
# soft text shadow
shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sdraw = ImageDraw.Draw(shadow_layer)
sdraw.text((tx + 8, ty + 12), text, font=font, fill=(0, 0, 0, 110))
shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(9))
bg = Image.alpha_composite(bg, shadow_layer)
draw = ImageDraw.Draw(bg)
draw.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))

# rarity spark (four-point star) on the upper-right of the card
cx, cy, r = 748, 286, 58
star = []
for i in range(8):
    angle = -math.pi / 2 + i * math.pi / 4
    radius = r if i % 2 == 0 else r * 0.30
    star.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
draw.polygon(star, fill=(253, 230, 138, 255))
draw.ellipse((cx - 8, cy - 8, cx + 8, cy + 8), fill=(255, 255, 255, 220))

# small secondary spark
cx, cy, r = 698, 212, 26
star = []
for i in range(8):
    angle = -math.pi / 2 + i * math.pi / 4
    radius = r if i % 2 == 0 else r * 0.30
    star.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
draw.polygon(star, fill=(255, 255, 255, 210))

# save master and Android launcher sizes
master = bg.convert("RGB")
master.save(os.path.join(OUT, "tool", "raritio_icon.png"))

sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for folder, size in sizes.items():
    target_dir = os.path.join(RES, folder)
    os.makedirs(target_dir, exist_ok=True)
    master.resize((size, size), Image.LANCZOS).save(os.path.join(target_dir, "ic_launcher.png"))
    print(f"Wrote {folder}/ic_launcher.png ({size}px)")
