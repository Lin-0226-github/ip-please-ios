"""生成 App 图标：像素风证件 + 红色 IP 印章，64x64 逻辑网格放大到 1024。"""
import os
from PIL import Image, ImageDraw

BASE = 64
SCALE = 8
SIZE = BASE * SCALE

BG      = (0x16, 0x13, 0x13)
BG2     = (0x1e, 0x1a, 0x1a)
CARD    = (0xE4, 0xDF, 0xD4)
CARD_SH = (0xB9, 0xB2, 0xA4)
INK     = (0x3A, 0x33, 0x2E)
INK2    = (0x7A, 0x70, 0x66)
RED     = (0xB5, 0x3A, 0x2E)
PHOTO   = (0x6B, 0x5B, 0x4C)
PHOTO2  = (0x8A, 0x77, 0x64)

img = Image.new("RGB", (SIZE, SIZE), BG)
d = ImageDraw.Draw(img)


def rect(x, y, w, h, color):
    d.rectangle([x * SCALE, y * SCALE, (x + w) * SCALE - 1, (y + h) * SCALE - 1], fill=color)


# 背景：四周压暗，做出检查亭的景深感
rect(0, 0, BASE, BASE, BG)
rect(2, 2, BASE - 4, BASE - 4, BG2)
rect(4, 4, BASE - 8, BASE - 8, (0x1a, 0x16, 0x16))

# 证件投影
rect(9, 15, 47, 35, (0x0d, 0x0b, 0x0b))
# 证件本体
rect(7, 13, 47, 35, CARD)
# 证件顶部色带
rect(7, 13, 47, 5, (0xC9, 0xC2, 0xB4))
# 证件底部描边
rect(7, 45, 47, 3, CARD_SH)

# 头像框
rect(11, 21, 17, 19, INK)
rect(12, 22, 15, 17, PHOTO)
# 头像：剪影
rect(16, 25, 7, 6, PHOTO2)          # 头
rect(14, 32, 11, 7, PHOTO2)         # 肩
rect(17, 33, 5, 4, PHOTO)

# 文字行
rect(31, 22, 19, 2, INK)
rect(31, 27, 16, 2, INK2)
rect(31, 32, 19, 2, INK2)
rect(31, 37, 12, 2, INK2)

# 红色圆形印章
cx, cy, r = 46, 44, 12
for y in range(BASE):
    for x in range(BASE):
        dx, dy = x - cx, y - cy
        dist = (dx * dx + dy * dy) ** 0.5
        if r - 2.4 <= dist <= r - 0.5:
            rect(x, y, 1, 1, RED)

# 印章里的 IP 两个字母：手写 3x5 像素字形，2 倍块放大，保证边缘干净
GLYPHS = {
    "I": ["111", "010", "010", "010", "111"],
    "P": ["110", "101", "110", "100", "100"],
}
px_scale = 2
text = "IP"
letters_w = 3 * px_scale * len(text) + 2 * (len(text) - 1)
letters_h = 5 * px_scale
ox = cx - letters_w // 2
oy = cy - letters_h // 2
for idx, ch in enumerate(text):
    glyph = GLYPHS[ch]
    gx = ox + idx * (3 * px_scale + 2)
    for gy, row in enumerate(glyph):
        for gxx, bit in enumerate(row):
            if bit == "1":
                rect(gx + gxx * px_scale, oy + gy * px_scale, px_scale, px_scale, RED)

out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "res", "icons")
os.makedirs(out_dir, exist_ok=True)
master = img
master.save(os.path.join(out_dir, "Icon-1024.png"))

sizes = {
    "Icon-20@2x.png": 40, "Icon-20@3x.png": 60,
    "Icon-29@2x.png": 58, "Icon-29@3x.png": 87,
    "Icon-40@2x.png": 80, "Icon-40@3x.png": 120,
    "Icon-60@2x.png": 120, "Icon-60@3x.png": 180,
    "Icon-76@1x.png": 76, "Icon-76@2x.png": 152,
    "Icon-83.5@2x.png": 167,
}
for name, px in sizes.items():
    master.resize((px, px), Image.LANCZOS).save(os.path.join(out_dir, name))

print("icons written:", len(sizes) + 1)
