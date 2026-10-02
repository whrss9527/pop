#!/usr/bin/env python3
"""把截图做成 App Store 认的尺寸（2880×1800）：比例是 16:10 的直接缩放，不是的话等比缩小放在中间，
四周用这张图自己放大、模糊、调暗后的样子填满。输出 PNG，文件名和顺序不变。

用法：scripts/fit-screenshots.py <截图文件夹> <输出文件夹>   需要 Pillow（pip install pillow）
"""
import sys
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

WIDTH, HEIGHT = 2880, 1800


def fit(image):
    image = image.convert("RGB")
    if abs(image.width / image.height - WIDTH / HEIGHT) < 0.01:
        return image.resize((WIDTH, HEIGHT), Image.LANCZOS)
    scale = max(WIDTH / image.width, HEIGHT / image.height)
    background = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    left, top = (background.width - WIDTH) // 2, (background.height - HEIGHT) // 2
    background = background.crop((left, top, left + WIDTH, top + HEIGHT)).filter(ImageFilter.GaussianBlur(60))
    background = ImageEnhance.Brightness(background).enhance(0.6)
    scale = min(WIDTH * 0.92 / image.width, HEIGHT * 0.92 / image.height)
    front = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    background.paste(front, ((WIDTH - front.width) // 2, (HEIGHT - front.height) // 2))
    return background


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    target.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in source.iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg"))
    for path in files:
        with Image.open(path) as image:
            before = image.size
            fit(image).save(target / (path.stem + ".png"), optimize=True)
        print(f"{path.name}: {before[0]}×{before[1]} → {WIDTH}×{HEIGHT}")
    if not files:
        print(f"{source} 里没有截图")


if __name__ == "__main__":
    main()
