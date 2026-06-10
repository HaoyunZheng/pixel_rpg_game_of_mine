#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
8 向静态 Sprite 切分器 —— 生成层前置工具
==========================================

输入:一张 3×3 九宫格排布的 8 向角色图(中心格为空),例如从素材站下载的
"8-direction character sheet"。九宫格位置 = 角色朝向:

    ┌─────────┬─────────┬─────────┐
    │ up_left │   up    │ up_right│   ← 背面(朝上/远离镜头)
    ├─────────┼─────────┼─────────┤
    │  left   │  (空)   │  right  │   ← 侧面
    ├─────────┼─────────┼─────────┤
    │down_left│  down   │down_right│  ← 正面(朝下/面向镜头)
    └─────────┴─────────┴─────────┘

处理:等分切成 8 格 → 最近邻降采样到目标像素尺寸(像素化)。
输出:直接写入 processed/<角色>/idle_<方向>/frame_000.png,
     跳过流水线②段(后处理)——因为源图已对齐、已透明背景,
     autocrop / 背景去除反而会破坏 8 个方向间的位置一致性。

之后接流水线③④段即可:
    python3 tools/slice_8dir.py source_sheets/hunter_8dir_fine.png hunter --size 64
    python3 pipeline.py pack import

要求:源图边长能被 3 整除(每格为正方形),目标尺寸 ≤ 格子尺寸。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ModuleNotFoundError:
    sys.exit("缺少 Pillow。请运行: pip install pillow")

# 九宫格 (列, 行) → 方向名。动画名 = idle_<方向>,与 hooded_player 的
# idle_down / idle_left 等既有命名约定一致,斜向用 down_left 形式。
GRID_TO_DIRECTION: dict[tuple[int, int], str] = {
    (0, 0): "up_left",   (1, 0): "up",   (2, 0): "up_right",
    (0, 1): "left",                      (2, 1): "right",
    (0, 2): "down_left", (1, 2): "down", (2, 2): "down_right",
}


def slice_sheet(src: Path, character: str, size: int, work_dir: Path) -> None:
    img = Image.open(src).convert("RGBA")
    w, h = img.size
    if w % 3 or h % 3:
        sys.exit(f"源图尺寸 {w}×{h} 不能被 3 整除,不是规整的 3×3 九宫格。")
    cell_w, cell_h = w // 3, h // 3
    if size > min(cell_w, cell_h):
        sys.exit(f"目标尺寸 {size} 大于格子尺寸 {cell_w}×{cell_h},只支持降采样。")

    processed = work_dir / "processed" / character
    for (col, row), direction in GRID_TO_DIRECTION.items():
        cell = img.crop((col * cell_w, row * cell_h,
                         (col + 1) * cell_w, (row + 1) * cell_h))
        cell = cell.resize((size, size), Image.NEAREST)
        out_dir = processed / f"idle_{direction}"
        out_dir.mkdir(parents=True, exist_ok=True)
        cell.save(out_dir / "frame_000.png")
        print(f"[切分] {character}/idle_{direction} ← 格({col},{row}) "
              f"{cell_w}×{cell_h} → {size}×{size}")
    print(f"[切分] 完成,8 个方向已写入 {processed}")


def main() -> None:
    ap = argparse.ArgumentParser(description="把 3×3 八向静态图切成流水线 processed 帧")
    ap.add_argument("source", help="源九宫格 PNG 路径")
    ap.add_argument("character", help="角色名(决定 processed/<角色>/ 与最终资源名)")
    ap.add_argument("--size", type=int, required=True, help="目标像素边长(如 64)")
    args = ap.parse_args()

    work_dir = Path(__file__).resolve().parent.parent
    slice_sheet(Path(args.source), args.character, args.size, work_dir)


if __name__ == "__main__":
    main()
