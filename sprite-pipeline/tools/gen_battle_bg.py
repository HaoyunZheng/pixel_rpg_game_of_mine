#!/usr/bin/env python3
"""战斗背景程序化生成：阴郁魔幻森林空地（480×270 像素画 → ×4 最近邻 = 1920×1080）。

画面要求（来自开发者提示词）：四周是树林，经灌木过渡到屏幕中间，
中间为一片裸露的地面；整体画风阴郁、魔法幻想世界、轻微适度的黑暗风格。

实现：固定种子的值噪声 + 椭圆距离场分三区（裸地 / 灌木 / 树林），
边缘树干剪影、微光孢子、薄雾与暗角收尾，posterize 保持像素画色阶。
（Meowa API 已被开发者禁用、Codex imagegen 本环境不可用，按既定政策走纯程序化。）

产物：game/assets/ui/battle/bg_battle_forest.png（1920×1080）
用法：python3 tools/gen_battle_bg.py
"""

import random
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 480, 270
SCALE = 4
SEED = 20260611
OUT = Path(__file__).resolve().parent.parent.parent / "game" / "assets" / "ui" / "battle" / "bg_battle_forest.png"

CX, CY, RX, RY = 240.0, 172.0, 132.0, 56.0   # 中央空地椭圆

DIRT = [(54, 44, 40), (62, 50, 42), (47, 38, 36), (40, 32, 32)]
PEBBLE = (72, 61, 52)
BUSH = [(30, 42, 30), (38, 52, 36), (24, 34, 26), (20, 28, 23)]
BUSH_HI = (52, 68, 44)
FOREST = [(14, 20, 17), (18, 26, 21), (11, 15, 14), (16, 23, 19)]
TRUNK = [(33, 26, 27), (26, 20, 22)]
SPORE = [(96, 170, 156), (140, 100, 170)]
MIST = (180, 176, 168)


def make_value_noise(rng: random.Random, gw: int, gh: int) -> callable:
    """粗网格随机值 + 双线性插值 → 有机团块噪声，免 numpy。"""
    grid = [[rng.random() for _ in range(gw + 2)] for _ in range(gh + 2)]

    def sample(x: float, y: float) -> float:
        gx, gy = x / W * gw, y / H * gh
        ix, iy = int(gx), int(gy)
        fx, fy = gx - ix, gy - iy
        a = grid[iy][ix] * (1 - fx) + grid[iy][ix + 1] * fx
        b = grid[iy + 1][ix] * (1 - fx) + grid[iy + 1][ix + 1] * fx
        return a * (1 - fy) + b * fy

    return sample


def main() -> None:
    rng = random.Random(SEED)
    noise_zone = make_value_noise(rng, 24, 14)    # 区域边界扰动
    noise_tex = make_value_noise(rng, 96, 54)     # 细纹理
    im = Image.new("RGB", (W, H))
    px = im.load()

    # ── 三区铺底：树林 → 灌木 → 裸地（椭圆距离场 + 噪声扰动边界）──
    for y in range(H):
        for x in range(W):
            d = ((x - CX) / RX) ** 2 + ((y - CY) / RY) ** 2
            d += (noise_zone(x, y) - 0.5) * 0.9          # 让边界犬牙交错
            t = noise_tex(x, y)
            if d <= 1.0:                                  # 裸露地面
                col = DIRT[int(t * 3.99)]
                if rng.random() < 0.012:
                    col = PEBBLE
            elif d <= 2.1:                                # 灌木过渡带
                col = BUSH[int(t * 3.99)]
                if rng.random() < 0.02 and d < 1.6:
                    col = BUSH_HI
            else:                                         # 外围树林
                col = FOREST[int(t * 3.99)]
            px[x, y] = col

    d = ImageDraw.Draw(im, "RGBA")

    # ── 边缘树干剪影（左右两翼 + 顶部一排，向心渐稀）──
    def trunk(x: int, top: int, bottom: int, w: int) -> None:
        c = TRUNK[rng.random() > 0.5]
        d.rectangle([x, top, x + w, bottom], fill=c)
        d.line([x, top, x, bottom], fill=(12, 9, 11))                 # 暗侧
        d.line([x + w, top, x + w, bottom], fill=(44, 36, 35))        # 亮侧
        d.ellipse([x - w * 2, top - 14, x + w * 3, top + 8], fill=(13, 18, 15))  # 树冠团

    for _ in range(16):                                   # 左翼
        x = int(rng.random() ** 2 * 70)
        trunk(x, rng.randint(8, 60), rng.randint(200, 260), rng.randint(4, 8))
    for _ in range(16):                                   # 右翼
        x = W - 1 - int(rng.random() ** 2 * 70)
        trunk(x - 6, rng.randint(8, 60), rng.randint(200, 260), rng.randint(4, 8))
    for _ in range(12):                                   # 顶排远树
        x = rng.randint(40, W - 40)
        trunk(x, rng.randint(0, 14), rng.randint(40, 80), rng.randint(3, 5))
    # 顶部树冠压暗一条
    d.rectangle([0, 0, W, 26], fill=(10, 14, 12, 150))

    # ── 轻度黑暗风点缀：微光孢子（青/紫荧光，带 1px 晕）──
    for _ in range(14):
        sx, sy = rng.randint(30, W - 30), rng.randint(40, H - 30)
        dd = ((sx - CX) / RX) ** 2 + ((sy - CY) / RY) ** 2
        if dd < 0.9:                                      # 不落在空地正中
            continue
        c = SPORE[rng.random() > 0.45]
        d.point([(sx, sy)], fill=c + (230,))
        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            d.point([(sx + ox, sy + oy)], fill=c + (70,))

    # ── 空地边缘薄雾（横向半透明浅条）──
    for _ in range(10):
        mx = rng.randint(60, W - 140)
        my = int(CY + rng.uniform(-1.2, 1.0) * RY)
        mw = rng.randint(30, 90)
        d.rectangle([mx, my, mx + mw, my + 1], fill=MIST + (16,))

    # ── 暗角（四角向心压暗，营造阴郁）──
    px = im.load()
    for y in range(H):
        for x in range(W):
            nx, ny = (x - W / 2) / (W / 2), (y - H / 2) / (H / 2)
            v = nx * nx * 0.55 + ny * ny * 0.75
            if v > 0.35:
                f = 1.0 - min(0.42, (v - 0.35) * 0.6)
                r, g, b = px[x, y]
                px[x, y] = (int(r * f), int(g * f), int(b * f))

    # ── 像素画色阶收束 + ×4 最近邻放大 ──
    im = im.point(lambda v: (v // 6) * 6)
    im = im.resize((W * SCALE, H * SCALE), Image.NEAREST)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT)
    print(f"[gen_battle_bg] 写出 {OUT} {im.size}")


if __name__ == "__main__":
    main()
