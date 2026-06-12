class_name BattleWidgets
extends RefCounted
## 战斗 UI 无状态视图工厂 —— 纯静态函数：输入参数 → 返回 Control，不持有任何战斗状态。
## 从 BattleUI 抽离，集中像素缩放 / 配色 / 切片路径与控件构建，降低 BattleUI 体量。
## 这里是 UI 视觉常量的单一数据源；BattleUI 控制器侧需要的配色直接引用 BattleWidgets.COL_*。

# ── 切片资源路径 ──
const ASSET_DIR: String = "res://assets/ui/battle/"
const TEX_PIP: String = ASSET_DIR + "pip_turn.png"
const TEX_PIP_ACTIVE: String = ASSET_DIR + "pip_turn_active.png"
const TEX_RETICLE: String = ASSET_DIR + "reticle_target_gold.png"
const TEX_MARKER_LOCKED: String = ASSET_DIR + "marker_locked_red.png"
const TEX_CHIP: String = ASSET_DIR + "chip_status.png"
const TEX_BAR_HP: String = ASSET_DIR + "bar_hp_9p.png"
const TEX_BAR_MP: String = ASSET_DIR + "bar_mp_9p.png"
const TEX_BAR_TRACK: String = ASSET_DIR + "bar_track_9p.png"
const TEX_AVATAR_FRAME: String = ASSET_DIR + "avatar_frame_9p.png"
const TEX_CMD_CELL: String = ASSET_DIR + "cmd_cell_9p.png"

# ── 配色（Brief §1.1，骨白/血红/法力蓝/金/余烬橙）──
const COL_BONE: Color = Color(0.847, 0.812, 0.753)       # 骨白
const COL_GOLD: Color = Color(0.902, 0.753, 0.290)       # 金色反馈（我锁敌/选中）
const COL_DIM: Color = Color(0.45, 0.43, 0.40)           # 置灰
const COL_ALLY: Color = Color(0.22, 0.52, 0.82)          # 友蓝占位
const COL_ENEMY: Color = Color(0.82, 0.22, 0.22)         # 敌红占位
const COL_HP: Color = Color(0.70, 0.27, 0.27)            # HP 暗红
const COL_MP: Color = Color(0.31, 0.52, 0.66)            # MP 法力蓝
const PIXEL_SCALE: int = 4                                # 480×270 基准 ×4 → 1080p（准星/锁定标记等小件仍按此放大；面板/条/pip 切片已按屏幕尺寸烘焙、1:1 绘制）

# ───────────────────────────────────────────── 切片加载（缺失回退 null）

static func load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res as Texture2D

# ───────────────────────────────────────────── ① 行动顺序 pip

static func make_pip(active: bool) -> Control:
	# pip 切片已按屏幕尺寸烘焙（56/72px），1:1 绘制；非当前 pip 在条内垂直居中。
	var tex: Texture2D = load_tex(TEX_PIP_ACTIVE if active else TEX_PIP)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.stretch_mode = TextureRect.STRETCH_KEEP
		rect.custom_minimum_size = tex.get_size()
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	# 回退：金/暗骨白纯色圆点
	var dot := ColorRect.new()
	var px: int = 72 if active else 56
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = COL_GOLD if active else COL_BONE.darkened(0.4)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot

# ───────────────────────────────────────────── ②⑤ 敌我状态卡（头像框 + HP/MP 条）

## 一个单位卡：[头像框+占位色块] | [姓名 / HP 条 / (我方)MP 条]
static func make_unit_card(unit, is_party: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unit.is_dead():
		row.modulate = Color(0.5, 0.5, 0.5)

	# 头像框（avatar_frame_9p）+ 单位 sprite 正面帧（无外观时回退占位纯色块）
	var avatar := make_avatar(unit, is_party)
	avatar.set_meta("unit_ref", unit)
	row.add_child(avatar)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)

	# HP 条（底轨 + 填充，TextureProgressBar 九宫横拉）
	info.add_child(make_stat_bar(unit.hp, unit.max_hp, TEX_BAR_HP, COL_HP))
	# MP 条仅我方（敌方 max_mp 通常为 0）
	if is_party and unit.max_mp > 0:
		info.add_child(make_stat_bar(unit.mp, unit.max_mp, TEX_BAR_MP, COL_MP))

	row.add_child(info)
	return row

static func make_avatar(unit, is_party: bool) -> Control:
	# 头像框切片 88×88 已按屏幕尺寸烘焙（8px 黑框 + 2px 骨白 + 2px 暗缝），1:1 绘制；
	# 内域恰为 64×64，正面帧无重采样。
	var size_px: int = 88
	var border_px: int = 12  # 黑框 8 + 骨白 2 + 暗缝 2
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 头像框 9-patch 先铺底
	var frame_tex: Texture2D = load_tex(TEX_AVATAR_FRAME)
	if frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = frame_tex
		frame.patch_margin_left = border_px
		frame.patch_margin_top = border_px
		frame.patch_margin_right = border_px
		frame.patch_margin_bottom = border_px
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(frame)
	# 单位带 sprite 外观：叠 idle_down 正面帧（框内灰烬底透出 sprite 透明区作为背景）。
	var portrait: Texture2D = get_unit_portrait(unit)
	if portrait != null:
		var rect := TextureRect.new()
		rect.texture = portrait
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.offset_left = border_px
		rect.offset_top = border_px
		rect.offset_right = -border_px
		rect.offset_bottom = -border_px
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
		return holder
	# 无外观回退：内部占位色块（友蓝/敌红），叠在框内、内缩到描边以内，让框边可见。
	var fill := ColorRect.new()
	fill.color = COL_ALLY if is_party else COL_ENEMY
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.offset_left = border_px
	fill.offset_top = border_px
	fill.offset_right = -border_px
	fill.offset_bottom = -border_px
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	return holder

## 取单位头像纹理：stats_res 带 sprite_frames（8 向 idle）时取 idle_down 首帧，否则 null。
static func get_unit_portrait(unit) -> Texture2D:
	if unit.stats_res == null:
		return null
	var frames = unit.stats_res.get("sprite_frames")
	if frames is SpriteFrames and frames.has_animation("idle_down") and frames.get_frame_count("idle_down") > 0:
		return frames.get_frame_texture("idle_down", 0)
	return null

static func make_stat_bar(cur: int, maxv: int, fill_tex_path: String, fallback_col: Color) -> Control:
	# 条切片 160×24 已按屏幕尺寸烘焙（4px 黑框），1:1 绘制零重采样；
	# nine_patch_stretch 令黑框端帽随进度收缩，半血时填充条仍是完整带框胶囊。
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(160, 24)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.min_value = 0
	bar.max_value = maxi(1, maxv)
	bar.value = clampi(cur, 0, maxi(1, maxv))
	bar.step = 0.0
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 4
	bar.stretch_margin_right = 4
	bar.stretch_margin_top = 4
	bar.stretch_margin_bottom = 4
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track: Texture2D = load_tex(TEX_BAR_TRACK)
	var fill: Texture2D = load_tex(fill_tex_path)
	if track != null:
		bar.texture_under = track
	if fill != null:
		bar.texture_progress = fill
	# 任一切片缺失：回退用纯色 StyleBox-like ProgressBar 表达
	if track == null or fill == null:
		return make_stat_bar_fallback(cur, maxv, fallback_col)
	return bar

static func make_stat_bar_fallback(cur: int, maxv: int, col: Color) -> Control:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(40 * PIXEL_SCALE, 14)
	pb.min_value = 0
	pb.max_value = maxi(1, maxv)
	pb.value = clampi(cur, 0, maxi(1, maxv))
	pb.step = 0.0
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.10, 0.13)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb

# ───────────────────────────────────────────── ④ 命令格底框
## 单个命令格的 StyleBox（cmd_cell_9p 切片：8px 黑框 + 2px 骨白 + 2px 暗缝）。
## 每格独立带框，格与格之间由 HBox separation 拉开，文字经 content margin 居中于框内。
static func make_cmd_cell_style() -> StyleBox:
	var tex: Texture2D = load_tex(TEX_CMD_CELL)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 12
		sb.texture_margin_top = 12
		sb.texture_margin_right = 12
		sb.texture_margin_bottom = 12
		sb.content_margin_left = 20
		sb.content_margin_top = 14
		sb.content_margin_right = 20
		sb.content_margin_bottom = 14
		return sb
	# 回退：纯色平框（黑粗边 + 暗紫内部）
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.24, 0.22, 0.27)
	flat.border_color = Color(0.04, 0.03, 0.055)
	flat.set_border_width_all(8)
	flat.set_content_margin_all(16)
	return flat

# ───────────────────────────────────────────── ⑥ 准星 / 锁敌叠加标记

static func make_overlay_marker(tex: Texture2D, base_px: int, fallback_col: Color) -> Control:
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		# 必须真把纹理放大到 ×4 盒子：STRETCH_KEEP 只按原生 16px 画在盒子左上角（又小又偏位）
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = tex.get_size() * PIXEL_SCALE
		rect.size = rect.custom_minimum_size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var dot := ColorRect.new()
	var px: int = base_px * PIXEL_SCALE
	dot.custom_minimum_size = Vector2(px, px)
	dot.size = dot.custom_minimum_size
	dot.color = fallback_col
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot
