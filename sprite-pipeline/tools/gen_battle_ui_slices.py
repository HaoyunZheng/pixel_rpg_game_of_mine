#!/usr/bin/env python3
"""战斗 UI 切片重绘（粗方形像素边框版）。

背景：首轮 Meowa 切片在 1080p 下按 NinePatch 源像素 margin 绘制，描边过细且
bar_track 整张 alpha≈0、HP/MP 条源高不一致（5px vs 4px），导致裁切/渲染异常。
本脚本改为**按屏幕像素尺寸直接烘焙**切片：8px 骨白硬边 + 平色内部，
NinePatch margin 即屏幕厚度，1:1 绘制无重采样。状态条使用独立静态外框，
保证进度变化时边框不会随填充长度收缩。

产物（写入 game/assets/ui/battle/，该目录为 game/CLAUDE.md §1 经批准的 UI 例外区）：
  panel_central_9p.png   64×64   中央信息框 9-patch（margin 8）
  cmd_cell_9p.png        48×48   单个命令格 9-patch（margin 8，替代四连底板 bar_command_9p）
  panel_party_strip_9p.png 64×64 左下队伍底板 9-patch（margin 8，半透明内部）
  avatar_frame_9p.png    88×88   头像框（8px 方形硬边）
  bar_track_9p.png       160×32  HP/MP 近黑底轨
  bar_hp_9p.png          160×32  HP 平面填充遮罩（由 HUD 按阈值着色）
  bar_mp_9p.png          160×32  MP 平面填充遮罩（由 HUD 固定着色）
  bar_frame_9p.png       160×32  4px 静态骨白外框（TextureProgressBar.texture_over）
  marker_locked_red.png  24×24   透明底红色环形锁定标记
  pip_turn.png           56×56   行动顺序 pip（非当前，放大）
  pip_turn_active.png    72×72   行动顺序 pip（当前行动者，放大）

用法：python3 tools/gen_battle_ui_slices.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT_DIR = Path(__file__).resolve().parent.parent.parent / "game" / "assets" / "ui" / "battle"

# ── 配色（采样自原 Meowa 切片 / BattleWidgets.COL_*）──
BLACK = (10, 8, 14, 255)          # 近黑（带一点紫调，贴合阴郁基调）
BONE = (230, 223, 205, 255)       # 骨白硬边
BONE_DIM = (176, 168, 152, 255)   # 暗骨白（非当前 pip）
INK_CENTRAL = (27, 24, 34, 255)   # 中央框内部（原切片采样）
INK_CMD = (62, 55, 68, 255)       # 命令格内部（原四连底板采样调暗）
INK_PARTY = (24, 21, 32, 215)     # 队伍底板内部（半透明）
INK_AVATAR = (17, 14, 26, 255)    # 头像框内部（原切片采样）
TRACK = (28, 26, 35, 255)         # 条底轨
BAR_FILL_MASK = (255, 255, 255, 255)
EMBER = (252, 158, 47, 255)       # 当前行动者（余烬橙，原 pip_active 采样）
GOLD = (230, 192, 74, 255)
LOCKED_RED = (214, 45, 55, 255)


def frame_tile(size: int, fill: tuple, border: int = 8) -> Image.Image:
    """单层骨白方形硬边 + 平色内部的 9-patch 瓦片。"""
    im = Image.new("RGBA", (size, size), BONE)
    d = ImageDraw.Draw(im)
    d.rectangle([border, border, size - 1 - border, size - 1 - border], fill=fill)
    return im


def bar_tile(kind: str, w: int = 160, h: int = 32, border: int = 4) -> Image.Image:
    """状态条平面层；外框单独作为 texture_over，永远保持完整。"""
    if kind == "track":
        return Image.new("RGBA", (w, h), TRACK)
    if kind in ("hp", "mp"):
        return Image.new("RGBA", (w, h), BAR_FILL_MASK)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], outline=BONE, width=border)
    return im


def locked_ring_tile(size: int = 24, thickness: int = 3) -> Image.Image:
    """无抗锯齿透明底红环；最近邻放大时保持硬像素边缘。"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([1, 1, size - 2, size - 2], outline=LOCKED_RED, width=thickness)
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
        "panel_central_9p.png": frame_tile(64, INK_CENTRAL),
        "cmd_cell_9p.png": frame_tile(48, INK_CMD),
        "panel_party_strip_9p.png": frame_tile(64, INK_PARTY),
        "avatar_frame_9p.png": frame_tile(88, INK_AVATAR),
        "bar_track_9p.png": bar_tile("track"),
        "bar_hp_9p.png": bar_tile("hp"),
        "bar_mp_9p.png": bar_tile("mp"),
        "bar_frame_9p.png": bar_tile("frame"),
        "marker_locked_red.png": locked_ring_tile(),
        "pip_turn.png": pip_tile(56, BONE_DIM, (210, 202, 184, 255)),
        "pip_turn_active.png": pip_tile(72, EMBER, GOLD),
    }
    for name, im in tiles.items():
        path = OUT_DIR / name
        im.save(path)
        print(f"[gen_battle_ui_slices] 写出 {path} {im.size}")


if __name__ == "__main__":
    main()
