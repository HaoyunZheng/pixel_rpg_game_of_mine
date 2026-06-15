#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背包账簿底图 → 版式锚点数据层（layout.json）+ clean-plate 底版

设计意图（业内"切片元数据"管线：Aseprite Slices / TexturePacker / 本仓库 sprite-pipeline）：
  版式坐标是【资产级数据】，由本工具一次性从背景图离线生成；游戏代码只读 layout.json，
  GDScript 里不写死任何摆放像素。美术换版(bg v2/v3) → 重跑本工具，代码零改。

产出（与背景图同目录）：
  layout.json                          —— 井格/标签锚点/页矩形/页内分区（背景图原生像素）
  bg_inventory_field_ledger_clean.png  —— 铲掉画死静态标签的 clean plate（运行时实际背景）
  layout_debug.png                     —— 检测叠加图，离线一次性肉眼/agent 核对用

检测策略（只用经验证稳健的方法，不做逐像素阈值微调）：
  - 井格：梯度投影 + 等距点阵拟合（描边规则强峰，比亮度分段稳）
  - 标签锚点：直接取井列中心（画稿 banner 本与井列对齐，等距既忠实又工整）
  - 页矩形：暖米黄掩码列/行剖面（低阈值 + 区段并集端点，避开页内框线切断）
  - 页内分区：页矩形的【声明式比例】（portrait/header/body/footer），换图按比例自适应

用法（game/ 目录下）：
  python3 tools/ui_layout_extract.py assets/ui/inventory/bg_inventory_field_ledger_v1.png
"""
import sys
import os
import json

import numpy as np
from PIL import Image, ImageDraw

# ── 粗 ROI（只约束"在哪一带找"，精确边界由算法得出）────────────────────────
GRID_ROI = (210, 200, 960, 770)
EXPECT_COLS, EXPECT_ROWS = 5, 4
PAGE_TAN = dict(r_min=138, g_min=100, rb_gap=38, gb_gap=20)  # 实测页主色 ~154,120,84

# 标签：clean-plate 铲除区 + 锚点样式（锚点 = 井列中心）
TAB_STRIP_Y = (46, 219)
TAB_STRIP_X = (235, 940)
TAB_CLEAN_SRC_X = (384, 434)
TAB_STYLE = dict(top=55, width=112, selected_scale=1.08, selected_lift=8)

# 详情页内分区（相对页矩形的比例：x,y,w,h ∈ [0,1]）—— 声明式，换图按比例自适应
PAGE_ZONES_FRAC = {
	"portrait": (0.060, 0.045, 0.275, 0.205),   # 左上 物品大图框
	"header":   (0.380, 0.055, 0.560, 0.190),   # 右上 名称 + 分类章
	"body":     (0.070, 0.300, 0.860, 0.330),   # 中部大框 数值 + 说明
	"footer":   (0.070, 0.730, 0.860, 0.215),   # 底部框 装备状态 / 操作菜单
}


def smooth(p, k=5):
	return np.convolve(p, np.ones(k) / k, mode="same")


def runs_above(profile, thresh, min_w):
	out, s = [], None
	for i, v in enumerate(profile):
		if v > thresh and s is None:
			s = i
		elif v <= thresh and s is not None:
			if i - s >= min_w:
				out.append((s, i))
			s = None
	if s is not None and len(profile) - s >= min_w:
		out.append((s, len(profile)))
	return out


def fit_lattice(profile, n, w_range, p_range):
	"""等距点阵拟合：暴力搜 (起点, 格宽 w, 周期 p) 使 n 格左右描边的梯度响应和最大。"""
	prof = smooth(profile)
	best, best_score = None, -1.0
	for p in range(p_range[0], p_range[1] + 1):
		for w in range(w_range[0], w_range[1] + 1):
			if w >= p:
				continue
			limit = len(prof) - (n - 1) * p - w - 1
			for x0 in range(0, max(limit, 0)):
				s = sum(prof[x0 + i * p] + prof[x0 + i * p + w] for i in range(n))
				if s > best_score:
					best_score, best = s, (x0, w, p)
	assert best is not None, "点阵拟合失败"
	x0, w, p = best
	return [(x0 + i * p, w) for i in range(n)]


def detect_wells(g):
	x0, y0, x1, y1 = GRID_ROI
	roi = g[y0:y1, x0:x1]
	gx = np.abs(np.diff(roi, axis=1)).sum(axis=0)
	gy = np.abs(np.diff(roi, axis=0)).sum(axis=1)
	cols = fit_lattice(gx, EXPECT_COLS, (105, 130), (130, 150))
	rows = fit_lattice(gy, EXPECT_ROWS, (105, 130), (130, 150))
	return [[x0 + cx, y0 + ry, cw, rh] for (ry, rh) in rows for (cx, cw) in cols]


def derive_tabs(wells):
	cols = wells[:EXPECT_COLS]
	centers = [x + w // 2 for x, _, w, _ in cols]
	return dict(centers=centers, **TAB_STYLE)


def detect_page(arr):
	r, gch, b = arr[:, :, 0].astype(int), arr[:, :, 1].astype(int), arr[:, :, 2].astype(int)
	p = PAGE_TAN
	m = (r > p["r_min"]) & (gch > p["g_min"]) & (r - b > p["rb_gap"]) & (gch - b > p["gb_gap"])
	col_runs = runs_above(m.sum(axis=0), m.sum(axis=0).max() * 0.15, 80)
	assert col_runs, "未检测到羊皮纸页（列）"
	cs, ce = col_runs[0][0], col_runs[-1][1]
	band = m[:, cs:ce]
	row_runs = runs_above(band.sum(axis=1), band.sum(axis=1).max() * 0.15, 60)
	assert row_runs, "未检测到羊皮纸页（行）"
	rs, re = row_runs[0][0], row_runs[-1][1]
	return [int(cs), int(rs), int(ce - cs), int(re - rs)]


def page_zones(page):
	px, py, pw, ph = page
	out = {}
	for name, (fx, fy, fw, fh) in PAGE_ZONES_FRAC.items():
		out[name] = [round(px + fx * pw), round(py + fy * ph), round(fw * pw), round(fh * ph)]
	return out


def make_clean_plate(im, wells, out_path):
	"""铲除画死的静态标签 banner：用同条带干净背衬纹理隔块镜像平铺修补。"""
	arr = np.asarray(im).copy()
	y0, y1 = TAB_STRIP_Y
	y1 = min(y1, min(w[1] for w in wells) - 4)
	x0, x1 = TAB_STRIP_X
	sx0, sx1 = TAB_CLEAN_SRC_X
	patch = arr[y0:y1, sx0:sx1].copy()
	pw = patch.shape[1]
	x, flip = x0, False
	while x < x1:
		w = min(pw, x1 - x)
		arr[y0:y1, x:x + w] = (patch[:, ::-1] if flip else patch)[:, :w]
		x += w
		flip = not flip
	Image.fromarray(arr).save(out_path)
	return out_path


def main():
	bg_path = sys.argv[1] if len(sys.argv) > 1 else "assets/ui/inventory/bg_inventory_field_ledger_v1.png"
	im = Image.open(bg_path).convert("RGB")
	arr = np.asarray(im)
	g = arr.mean(axis=2)
	out_dir = os.path.dirname(bg_path)

	wells = detect_wells(g)
	tabs = derive_tabs(wells)
	page = detect_page(arr)
	zones = page_zones(page)

	clean_name = "bg_inventory_field_ledger_clean.png"
	make_clean_plate(im, wells, os.path.join(out_dir, clean_name))

	layout = dict(source=os.path.basename(bg_path), bg=clean_name,
				  size=[im.width, im.height], wells=wells, tabs=tabs, page=page, zones=zones)
	with open(os.path.join(out_dir, "layout.json"), "w", encoding="utf-8") as f:
		json.dump(layout, f, ensure_ascii=False, indent=1)

	dbg = Image.open(os.path.join(out_dir, clean_name)).convert("RGB")
	d = ImageDraw.Draw(dbg)
	for i, (x, y, w, h) in enumerate(wells):
		d.rectangle([x, y, x + w, y + h], outline=(0, 255, 0), width=2)
	for i, cx in enumerate(tabs["centers"]):
		tw = tabs["width"]
		d.rectangle([cx - tw // 2, tabs["top"], cx + tw // 2, tabs["top"] + int(tw * 1.12)],
					outline=(255, 80, 0), width=2)
		d.text((cx - 6, tabs["top"] + 4), f"T{i}", fill=(255, 200, 0))
	d.rectangle([page[0], page[1], page[0] + page[2], page[1] + page[3]], outline=(0, 160, 255), width=2)
	for name, (x, y, w, h) in zones.items():
		d.rectangle([x, y, x + w, y + h], outline=(255, 0, 255), width=2)
		d.text((x + 4, y + 4), name, fill=(255, 0, 255))
	dbg.save(os.path.join(out_dir, "layout_debug.png"))

	print(f"[ui-layout] wells={len(wells)} tabs={tabs['centers']} page={page}")
	print(f"[ui-layout] zones={zones}")
	print(f"[ui-layout] 写出 layout.json / {clean_name} / layout_debug.png")


if __name__ == "__main__":
	main()
