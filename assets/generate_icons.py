#!/usr/bin/env python3
"""레인 워즈 앱 아이콘(512/1024)과 기능 그래픽(1024x500) 생성.
- 한글은 맑은 고딕(Windows)으로 그린다. (Arial에는 한글이 없어 글자가 깨진다)
- 기능 그래픽 오른쪽 그림은 실제 게임 화면(screenshot_6_boss_raid.png)에서 잘라 쓴다.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
# 스크린샷과 피처 그래픽은 스토어 등록용이라 git 밖(build/store_assets)에 둔다
STORE = os.path.join(HERE, "..", "build", "store_assets")
FONT_BOLD = "C:/Windows/Fonts/malgunbd.ttf"
FONT_REG = "C:/Windows/Fonts/malgun.ttf"


def font(path, size):
    return ImageFont.truetype(path, size)  # 없으면 예외 -> 깨진 이미지를 조용히 만들지 않는다


def outlined_text(draw, xy, text, fnt, fill, outline=(15, 20, 40), width=3, anchor="la"):
    x, y = xy
    for dx in range(-width, width + 1):
        for dy in range(-width, width + 1):
            if dx or dy:
                draw.text((x + dx, y + dy), text, font=fnt, fill=outline, anchor=anchor)
    draw.text((x, y), text, font=fnt, fill=fill, anchor=anchor)


def tower_scene(draw, size):
    """타워 3개 (가운데 큰 것 + 좌우). 가장자리 66% 안쪽(안전 영역)에 둔다."""
    c = size // 2
    def tower(cx, base_y, w, h, body, roof):
        x0, x1 = cx - w // 2, cx + w // 2
        draw.rectangle([x0, base_y - h, x1, base_y], fill=body, outline=(255, 255, 255), width=max(2, size // 200))
        draw.polygon([(x0 - w * 0.3, base_y - h), (x1 + w * 0.3, base_y - h), (cx, base_y - h - w * 0.65)], fill=roof)
    tower(c, int(size * 0.66), int(size * 0.20), int(size * 0.34), (180, 120, 220), (255, 220, 100))
    tower(c - int(size * 0.24), int(size * 0.70), int(size * 0.12), int(size * 0.20), (100, 200, 220), (255, 180, 120))
    tower(c + int(size * 0.24), int(size * 0.70), int(size * 0.12), int(size * 0.20), (255, 140, 180), (150, 220, 150))


def make_icon(size):
    # 모서리까지 꽉 찬 정사각형 (구글/런처가 알아서 모양을 깎는다)
    img = Image.new("RGB", (size, size))
    px = img.load()
    cx = cy = size / 2
    maxd = (2 * (size / 2) ** 2) ** 0.5
    for y in range(size):
        for x in range(size):
            d = (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / maxd
            px[x, y] = (int(48 - 30 * d), int(150 - 70 * d), int(185 - 40 * d))
    draw = ImageDraw.Draw(img)
    tower_scene(draw, size)
    f = font(FONT_BOLD, size // 9)
    outlined_text(draw, (size // 2, int(size * 0.80)), "WARS", f, (255, 255, 255), width=max(2, size // 170), anchor="mm")
    return img


def make_feature():
    w, h = 1024, 500
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(20 + 100 * t), int(150 - 70 * t), int(180 + 20 * t)))

    # 오른쪽: 실제 게임 화면의 보스 장면
    shot = Image.open(os.path.join(STORE, "screenshot_6_boss_raid.png")).convert("RGB")
    crop = shot.crop((250, 760, 830, 1380))          # 보스 + 몬스터
    crop = crop.resize((430, 460), Image.LANCZOS)
    mask = Image.new("L", crop.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, crop.width, crop.height], radius=28, fill=255)
    shadow = Image.new("RGBA", (crop.width + 40, crop.height + 40), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([20, 24, crop.width + 20, crop.height + 24], radius=30, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    px0, py0 = 560, 20
    img.paste(shadow, (px0 - 20, py0 - 20), shadow)
    img.paste(crop, (px0, py0), mask)

    # 왼쪽: 제목/부제
    outlined_text(d, (60, 120), "레인 워즈", font(FONT_BOLD, 112), (255, 255, 255), width=4)
    outlined_text(d, (64, 270), "타워로 길을 만들고", font(FONT_BOLD, 40), (255, 225, 110), width=3)
    outlined_text(d, (64, 325), "10단계 보스를 쓰러뜨려라", font(FONT_BOLD, 40), (255, 225, 110), width=3)

    return img


if __name__ == "__main__":
    make_icon(512).save(os.path.join(HERE, "icon_512.png"), "PNG")
    make_icon(1024).save(os.path.join(HERE, "icon_1024.png"), "PNG")
    make_feature().save(os.path.join(STORE, "feature_graphic.png"), "PNG")
    print("OK: icon_512.png, icon_1024.png, feature_graphic.png")
