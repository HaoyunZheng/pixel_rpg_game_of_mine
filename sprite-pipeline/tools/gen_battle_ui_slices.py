#!/usr/bin/env python3
"""战斗 UI 切片重绘（8-bit 粗黑边版）。

背景：首轮 Meowa 切片在 1080p 下按 NinePatch 源像素 margin 绘制，描边过细且
bar_track 整张 alpha≈0、HP/MP 条源高不一致（5px vs 4px），导致裁切/渲染异常。
本脚本改为**按屏幕像素尺寸直接烘焙**切片：粗黑外框 + 2px 骨白内衬 + 平色内部，
NinePatch margin 即屏幕厚度，1:1 绘制无重采样。配色采样自原 Meowa 切片，保持原画风。

产物（写入 game/assets/ui/battle/，该目录为 game/CLAUDE.md §1 经批准的 UI 例外区）：
  panel_central_9p.png   64×64   中央信息框 9-patch（margin 14）
  cmd_cell_9p.png        48×48   单个命令格 9-patch（margin 12，替代四连底板 bar_command_9p）
  panel_party_strip_9p.png 64×64 左下队伍底板 9-patch（margin 12，半透明内部）
  avatar_frame_9p.png    88×88   头像框（1:1 使用，内域 64×64 恰好放正面帧）
  bar_track_9p.png       160×24  HP/MP 底轨（1:1，修复 alpha=0）
  bar_hp_9p.png          160×24  HP 填充（与底轨同尺寸，黑边随进度收缩）
  bar_mp_9p.png          160×24  MP 填充（同上，带刻度段）
  pip_turn.png           56×56   行动顺序 pip（非当前，放大）
  pip_turn_active.png    72×72   行动顺序 pip（当前行动者，放大）

用法：python3 tools/gen_battle_ui_slices.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT_DIR = Path(__file__).resolve().parent.parent.parent / "game" / "assets" / "ui" / "battle"

# ── 配色（采样自原 Meowa 切片 / BattleWidgets.COL_*）──
BLACK = (10, 8, 14, 255)          # 近黑（带一点紫调，贴合阴郁基调）
BONE = (230, 223, 205, 255)       # 骨白内衬
BONE_DIM = (176, 168, 152, 255)   # 暗骨白（队伍底板内衬 / 非当前 pip）
INK_CENTRAL = (27, 24, 34, 255)   # 中央框内部（原切片采样）
INK_CMD = (62, 55, 68, 255)       # 命令格内部（原四连底板采样调暗）
INK_PARTY = (24, 21, 32, 215)     # 队伍底板内部（半透明）
INK_AVATAR = (17, 14, 26, 255)    # 头像框内部（原切片采样）
TRACK = (40, 38, 48, 255)         # 条底轨
HP_BASE, HP_HI, HP_LO = (117, 69, 68, 255), (172, 143, 125, 255), (84, 46, 48, 255)
MP_BASE, MP_HI, MP_TICK = (49, 87, 142, 255), (96, 135, 187, 255), (38, 66, 110, 255)
EMBER = (252, 158, 47, 255)       # 当前行动者（余烬橙，原 pip_active 采样）
GOLD = (230, 192, 74, 255)


def frame_tile(size: int, border: int, fill: tuple, trim: tuple = BONE, rivets: bool = True) -> Image.Image:
    """粗黑外框 + 2px 内衬 + 2px 暗缝 + 平色内部的 9-patch 瓦片。"""
    im = Image.new("RGBA", (size, size), BLACK)
    d = ImageDraw.Draw(im)
    b = border
    d.rectangle([b, b, size - 1 - b, size - 1 - b], fill=trim)                  # 内衬
    d.rectangle([b + 2, b + 2, size - 3 - b, size - 3 - b], fill=BLACK)        # 暗缝
    d.rectangle([b + 4, b + 4, size - 5 - b, size - 5 - b], fill=fill)         # 内部
    if rivets:
        for cx in (3, size - 5):
            for cy in (3, size - 5):
                d.rectangle([cx, cy, cx + 1, cy + 1], fill=BONE_DIM)           # 角铆钉
    return im


def bar_tile(kind: str, w: int = 160, h: int = 24, border: int = 4) -> Image.Image:
    """HP/MP/底轨条（1:1 屏幕尺寸，黑边烘焙；nine_patch_stretch 下边框随进度收缩）。"""
    im = Image.new("RGBA", (w, h), BLACK)
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = border, border, w - 1 - border, h - 1 - border
    if kind == "track":
        d.rectangle([x0, y0, x1, y1], fill=TRACK)
        # 底轨内顶部一条更暗的内阴影
        d.rectangle([x0, y0, x1, y0 + 1], fill=(28, 26, 35, 255))
        return im
    base, hi, lo = (HP_BASE, HP_HI, HP_LO) if kind == "hp" else (MP_BASE, MP_HI, MP_TICK)
    d.rectangle([x0, y0, x1, y1], fill=base)
    d.rectangle([x0, y0, x1, y0 + 3], fill=hi)      # 顶部高光带
    d.rectangle([x0, y1 - 2, x1, y1], fill=lo)      # 底部暗带
    if kind == "mp":
        for tx in range(x0 + 12, x1 - 2, 16):       # 法力刻度段
            d.rectangle([tx, y0, tx + 1, y1], fill=MP_TICK)
    return im


def pip_tile(size: int, fill: tuple, core: tuple, border: int = 4) -> Image.Image:
    """菱形行动顺序 pip：黑描边 + 主色 + 亮芯。"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = size // 2

    def diamond(r: int, col: tuple) -> None:
        d.polygon([(c, c - r), (c + r, c), (c, c + r), (c - r, c)], fill=col)

    r_outer = c - 1
    diamond(r_outer, BLACK)
    diamond(r_outer - border - 1, fill)
    diamond(max(3, r_outer - border - 9), core)
    d.rectangle([c - 1, c - 1, c, c], fill=BONE)    # 中心点
    return im


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tiles = {
        "panel_central_9p.png": frame_tile(64, 10, INK_CENTRAL),
        "cmd_cell_9p.png": frame_tile(48, 8, INK_CMD),
        "panel_party_strip_9p.png": frame_tile(64, 8, INK_PARTY, trim=BONE_DIM),
        "avatar_frame_9p.png": frame_tile(88, 8, INK_AVATAR, rivets=False),
        "bar_track_9p.png": bar_tile("track"),
        "bar_hp_9p.png": bar_tile("hp"),
        "bar_mp_9p.png": bar_tile("mp"),
        "pip_turn.png": pip_tile(56, BONE_DIM, (210, 202, 184, 255)),
        "pip_turn_active.png": pip_tile(72, EMBER, GOLD),
    }
    for name, im in tiles.items():
        path = OUT_DIR / name
        im.save(path)
        print(f"[gen_battle_ui_slices] 写出 {path} {im.size}")


if __name__ == "__main__":
    main()
