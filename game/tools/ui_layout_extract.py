#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背包账簿底图 → 版式锚点数据层（layout.json）+ clean-plate 底版 + debug 叠加图。

设计意图（业内"切片元数据"管线：Aseprite Slices / TexturePacker / 本仓库 sprite-pipeline）：
  版式坐标是【资产级数据】，由本工具一次性从背景图离线生成；游戏代码只读 layout.json，
  GDScript 里不写死任何摆放像素。美术换版(bg v2/v3) → 重跑本工具，代码零改。

产出（默认与背景图同目录，可用 --out-dir 改写）：
  layout.json                          —— 井格/顶层标签/小类框/页内分区（背景图原生像素）
  bg_inventory_field_ledger_clean.png  —— 铲掉画死标签与首排井格、上移后三排的物品页 clean plate
  bg_inventory_field_ledger_blank.png  —— 隐去井格、供其它顶层空白页使用的 clean plate
  layout_debug.png                     —— 检测叠加图，离线一次性肉眼/agent 核对用

检测策略（只用经验证稳健的方法，不做逐像素阈值微调）：
  - 井格：梯度投影 + 等距点阵拟合（描边规则强峰，比亮度分段稳）
  - 标签锚点：直接取井列中心（画稿 banner 本与井列对齐，等距既忠实又工整）
  - 页矩形：暖米黄掩码列/行剖面（低阈值 + 区段并集端点，避开页内框线切断）
  - 页内分区：页矩形的【声明式比例】（portrait/header/body/footer），换图按比例自适应

用法（工作目录 = game/）：
  python3 tools/ui_layout_extract.py                         # 用默认背景图全量重生成
  python3 tools/ui_layout_extract.py <bg.png>               # 指定背景图
  python3 tools/ui_layout_extract.py <bg.png> --no-debug    # 跳过 debug 叠加图
  python3 tools/ui_layout_extract.py <bg.png> --out-dir <d> # 改写输出目录

所有"调参面"集中在下方 CONFIG 区；算法函数不应内联魔法数。
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ════════════════════════════════ CONFIG（唯一调参面）════════════════════════════════

DEFAULT_BG = "assets/ui/inventory/bg_inventory_field_ledger_v1.png"
CLEAN_NAME = "bg_inventory_field_ledger_clean.png"   # 运行时实际背景（铲掉画死标签）
BLANK_NAME = "bg_inventory_field_ledger_blank.png"   # 非物品页背景（不保留井格）
LAYOUT_NAME = "layout.json"
DEBUG_NAME = "layout_debug.png"

# ── 粗 ROI（只约束"在哪一带找"，精确边界由算法得出）──
GRID_ROI = (210, 200, 960, 770)
EXPECT_COLS, EXPECT_ROWS = 5, 4
WELL_W_RANGE, WELL_P_RANGE = (105, 130), (130, 150)         # 点阵拟合：格宽 / 周期搜索域
ITEM_GRID_Y_SHIFT = -44
GRID_PATCH_MARGIN_X = 20
GRID_PATCH_MARGIN_Y = 14
BLANK_CONTENT_TOP = 210
SUBCATEGORY_Y = 236
SUBCATEGORY_W = 96
SUBCATEGORY_H = 48
PAGE_TAN = dict(r_min=138, g_min=100, rb_gap=38, gb_gap=20)  # 实测页主色 ~154,120,84

# 标签：clean-plate 铲除区 + 锚点样式（锚点 = 井列中心）
TAB_STRIP_Y = (46, 219)
TAB_STRIP_X = (235, 940)
TAB_CLEAN_SRC_X = (384, 434)
TAB_STYLE = dict(top=55, width=112, selected_scale=1.08, selected_lift=8)

# 详情页内分区（相对页矩形的比例：x,y,w,h ∈ [0,1]）—— 声明式，换图按比例自适应。
# 6 个分区分别对应羊皮纸页实际画稿的 6 个画死结构（梯度+目视核对），对应像素见行尾注释：
#   portrait 物品展示框 / name 物品名(横线之上) / tag 物品标签(名牌框) /
#   stats 状态介绍(两横线之间) / desc 物品说明(描述框) / footer 状态栏(底部操作框)。
# 页矩形 = [1087,117,464,696]。换美术后若画框位置变了，重测画框、按 (px-1087)/464、(py-117)/696 重算即可。
PAGE_ZONES_FRAC = {
	"portrait": (0.05819, 0.04310, 0.35345, 0.23707),   # 物品展示框 左上大框 sprite  px[1114,147,164,165]
	"name":     (0.48491, 0.05029, 0.41379, 0.06897),   # 物品名 横线之上 左对齐       px[1312,152,192,48]
	"tag":      (0.48276, 0.18822, 0.19828, 0.04885),   # 物品标签 名牌框 分类章       px[1311,248,92,34]
	"stats":    (0.08405, 0.33477, 0.81034, 0.12356),   # 状态介绍 两横线之间 数值      px[1126,350,376,86]
	"desc":     (0.09267, 0.52155, 0.81034, 0.21552),   # 物品说明 描述框 Lore 文本     px[1130,480,376,150]
	"footer":   (0.08836, 0.83190, 0.80819, 0.16954),   # 状态栏 底部圆角框 操作/装备   px[1128,696,375,118]
}

# debug 叠加图配色（BGR? 否，PIL 用 RGB）
DBG_WELL = (0, 255, 0)
DBG_TAB = (255, 80, 0)
DBG_PAGE = (0, 160, 255)
DBG_ZONE = (255, 0, 255)

# ════════════════════════════════ 检测算法 ════════════════════════════════


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
	cols = fit_lattice(gx, EXPECT_COLS, WELL_W_RANGE, WELL_P_RANGE)
	rows = fit_lattice(gy, EXPECT_ROWS, WELL_W_RANGE, WELL_P_RANGE)
	return [[x0 + cx, y0 + ry, cw, rh] for (ry, rh) in rows for (cx, cw) in cols]


def derive_tabs(wells):
	cols = wells[:EXPECT_COLS]
	centers = [x + w // 2 for x, _, w, _ in cols]
	return dict(centers=centers, **TAB_STYLE)


def derive_subcategories(wells):
	"""沿用井列中心，生成比物品格更轻量的五个小类框。"""
	return [[x + w // 2 - SUBCATEGORY_W // 2, SUBCATEGORY_Y,
			 SUBCATEGORY_W, SUBCATEGORY_H] for x, _, w, _ in wells[:EXPECT_COLS]]


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


def extract_layout(im):
	"""纯检测：从 RGB 图算出 (wells, tabs, page, zones)，不落盘。"""
	arr = np.asarray(im)
	g = arr.mean(axis=2)
	wells = detect_wells(g)
	tabs = derive_tabs(wells)
	page = detect_page(arr)
	zones = page_zones(page)
	return wells, tabs, page, zones


# ════════════════════════════════ 产物生成 ════════════════════════════════


def build_clean_plate(im, wells):
	"""铲除画死标签与首排井格，将后三排井格原尺寸上移。"""
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

	# ponytail: 复用原画后三排，整块平移即可保留井格尺寸、纹理和间距。
	base = build_blank_plate(Image.fromarray(arr), wells)
	remaining = wells[EXPECT_COLS:]
	grid_x0 = max(0, min(w[0] for w in wells) - GRID_PATCH_MARGIN_X)
	grid_x1 = min(arr.shape[1], max(w[0] + w[2] for w in wells) + GRID_PATCH_MARGIN_X)
	source_y0 = min(w[1] for w in remaining) - GRID_PATCH_MARGIN_Y
	source_y1 = max(w[1] + w[3] for w in remaining) + GRID_PATCH_MARGIN_Y
	grid_patch = im.crop((grid_x0, source_y0, grid_x1, source_y1))
	base.paste(grid_patch, (grid_x0, source_y0 + ITEM_GRID_Y_SHIFT))
	return base


def build_blank_plate(clean_img, wells):
	"""复用物品页 clean plate 的空皮革色调，遮去小类与井格区域。"""
	base = clean_img.convert("RGB").copy()
	x0 = max(0, min(w[0] for w in wells) - GRID_PATCH_MARGIN_X)
	x1 = min(base.width, max(w[0] + w[2] for w in wells) + GRID_PATCH_MARGIN_X)
	y0 = BLANK_CONTENT_TOP
	y1 = max(w[1] + w[3] for w in wells) + GRID_PATCH_MARGIN_Y
	sample_x0 = max(w[0] + w[2] for w in wells) + 4
	sample = base.crop((sample_x0, y0, x1, y1))
	# ponytail: 压成 2×2 低频色块，避免边缘和接缝被放大成条纹。
	texture = sample.resize((2, 2), Image.Resampling.LANCZOS).resize(
		(x1 - x0, y1 - y0), Image.Resampling.BICUBIC)
	overlay = base.copy()
	overlay.paste(texture, (x0, y0))
	mask = Image.new("L", base.size, 0)
	ImageDraw.Draw(mask).rectangle((x0 + 8, y0 + 8, x1 - 8, y1 - 8), fill=255)
	mask = mask.filter(ImageFilter.GaussianBlur(8))
	return Image.composite(overlay, base, mask)


def build_debug_overlay(base_img, wells, tabs, subcategories, page, zones):
	"""在给定底图（一般为 clean-plate）上叠画检测框，返回新图（不落盘）。"""
	dbg = base_img.convert("RGB").copy()
	d = ImageDraw.Draw(dbg)
	for (x, y, w, h) in wells:
		d.rectangle([x, y, x + w, y + h], outline=DBG_WELL, width=2)
	for i, cx in enumerate(tabs["centers"]):
		tw = tabs["width"]
		d.rectangle([cx - tw // 2, tabs["top"], cx + tw // 2, tabs["top"] + int(tw * 1.12)],
					outline=DBG_TAB, width=2)
		d.text((cx - 6, tabs["top"] + 4), f"T{i}", fill=(255, 200, 0))
	for i, (x, y, w, h) in enumerate(subcategories):
		d.rectangle([x, y, x + w, y + h], outline=DBG_TAB, width=2)
		d.text((x + 4, y + 4), f"S{i}", fill=(255, 200, 0))
	d.rectangle([page[0], page[1], page[0] + page[2], page[1] + page[3]], outline=DBG_PAGE, width=2)
	for name, (x, y, w, h) in zones.items():
		d.rectangle([x, y, x + w, y + h], outline=DBG_ZONE, width=2)
		d.text((x + 4, y + 4), name, fill=DBG_ZONE)
	return dbg


# ════════════════════════════════ CLI ════════════════════════════════


def run(bg_path, out_dir=None, write_clean=True, write_debug=True, quiet=False):
	"""检测 + 落盘，返回 layout dict。out_dir 默认 = 背景图所在目录。"""
	if not os.path.isfile(bg_path):
		raise SystemExit(f"[ui-layout] 错误：背景图不存在: {bg_path}")
	try:
		im = Image.open(bg_path).convert("RGB")
	except Exception as e:  # noqa: BLE001 — 给出可读错误而非裸栈
		raise SystemExit(f"[ui-layout] 错误：无法读取图片 {bg_path}: {e}")

	out_dir = out_dir or os.path.dirname(bg_path) or "."
	os.makedirs(out_dir, exist_ok=True)

	detected_wells, tabs, page, zones = extract_layout(im)
	subcategories = derive_subcategories(detected_wells)
	wells = [[x, y + ITEM_GRID_Y_SHIFT, w, h]
			 for x, y, w, h in detected_wells[EXPECT_COLS:]]

	clean_img = build_clean_plate(im, detected_wells)
	if write_clean:
		clean_img.save(os.path.join(out_dir, CLEAN_NAME))
		build_blank_plate(clean_img, wells).save(os.path.join(out_dir, BLANK_NAME))

	layout = dict(source=os.path.basename(bg_path), bg=CLEAN_NAME, bg_blank=BLANK_NAME,
				  size=[im.width, im.height], wells=wells, tabs=tabs,
				  subcategories=subcategories, page=page, zones=zones)
	with open(os.path.join(out_dir, LAYOUT_NAME), "w", encoding="utf-8") as f:
		json.dump(layout, f, ensure_ascii=False, indent=1)

	if write_debug:
		build_debug_overlay(clean_img, wells, tabs, subcategories, page, zones).save(
			os.path.join(out_dir, DEBUG_NAME))

	if not quiet:
		outs = [LAYOUT_NAME] + ([CLEAN_NAME, BLANK_NAME] if write_clean else []) + ([DEBUG_NAME] if write_debug else [])
		print(f"[ui-layout] wells={len(wells)} tabs={tabs['centers']} page={page}")
		print(f"[ui-layout] zones={zones}")
		print(f"[ui-layout] 写出 {' / '.join(outs)} → {out_dir}")
	return layout


def parse_args(argv):
	ap = argparse.ArgumentParser(
		description="背包账簿底图 → 版式锚点数据层(layout.json) + clean-plate + debug 叠加图")
	ap.add_argument("bg", nargs="?", default=DEFAULT_BG, help="背景图路径（默认 %(default)s）")
	ap.add_argument("--out-dir", default=None, help="输出目录（默认 = 背景图所在目录）")
	ap.add_argument("--no-clean", action="store_true", help="不重生成 clean-plate")
	ap.add_argument("--no-debug", action="store_true", help="不生成 debug 叠加图")
	ap.add_argument("--quiet", action="store_true", help="静默（不打印摘要）")
	return ap.parse_args(argv)


def main(argv=None):
	a = parse_args(sys.argv[1:] if argv is None else argv)
	run(a.bg, out_dir=a.out_dir, write_clean=not a.no_clean, write_debug=not a.no_debug, quiet=a.quiet)


if __name__ == "__main__":
	main()
