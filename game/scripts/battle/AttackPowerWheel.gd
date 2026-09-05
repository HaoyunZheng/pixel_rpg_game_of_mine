class_name AttackPowerWheel
extends Control
## 攻击力度转盘 —— 纯代码自绘（_draw + draw_arc / draw_line / draw_circle）
##
## 流程：实例化 → start_over_central_box(central_box) 对齐中央框、弱化命令栏 →
##   _process 驱动指针匀速旋转 → 中心 Label 实时显示当前档名/倍率 →
##   Z 定格当前角度 → 落点档区 → 显示定格结果 → 停留 result_hold 秒 →
##   emit_signal("wheel_resolved", multiplier, tier_name) → 自销毁、恢复命令栏。
##
## 顺时针「充能斜坡」闭环布局（自 0°=3 点钟方向顺时针）：
##   失误(开局段) → 普通 → 良好 → 完美(甜点，最窄) → 失误(悬崖段) → 回到 0°。
##   难度单调爬升：失误→普通→良好→完美；完美之后顺时针直接接失误（过冲即失手）。
##   两段失误（开局段 + 完美后悬崖段）跨 0° 连成一片失误区，不再镜像对称。
##
## 集成契约见 docs/superpowers/plans/ATTACK_WHEEL_SPEC.md §3：BattleUI 在
##   select_command(ATTACK) 后 await 本信号，把 multiplier 写到攻击者的
##   power_multiplier，再 select_target(t)。

signal wheel_resolved(multiplier: float, tier_name: String)

# ── 无障碍辅助档（§2.6）──
enum AssistMode { OFF, EASY, AUTO }

# ── 旋转 / 时序（§4）──
@export var spin_speed: float = 4.0                 # 指针转速（弧度/秒，匀速）
@export var result_hold: float = 0.25               # 定格后停留显示时长（秒）
@export var randomize_start_angle: bool = false     # 起点是否随机（默认确定性）

# ── 四档角度占比（整环合计=1.0，§1.4）──
@export var perfect_arc_ratio: float = 0.055        # 完美档（最窄，约 5~6%）
@export var good_arc_ratio: float = 0.22            # 良好档
@export var normal_arc_ratio: float = 0.40         # 普通档（主体）
@export var miss_arc_ratio: float = 0.325          # 失误档（开局段 + 悬崖段合计，跨 0° 连片）

# ── 四档倍率（§1.4）──
@export var perfect_multiplier: float = 1.5
@export var good_multiplier: float = 1.2
@export var normal_multiplier: float = 1.0
@export var miss_multiplier: float = 0.6

# ── 无障碍 ──
@export var assist_mode: AssistMode = AssistMode.OFF
@export var assist_easy_speed_scale: float = 0.5    # EASY 档转速倍率
@export var assist_easy_good_ratio_bonus: float = 0.10  # EASY 档加宽良好+完美窗

# ── 几何（px @1080p，§4）──
@export var ring_radius: float = 200.0              # 环外径
@export var ring_width: float = 16.0               # 环宽；中心预留角色攻击动画空间
@export var perfect_glow_alpha: float = 0.5        # 完美档内外发光 alpha（提亮，glow 更显现）

# ── 黑色粗像素边框（chunky，像素质感；段间分隔 + 环内外缘）──
@export var border_width: float = 3.0              # 黑边粗细（px，建议 2~4）
@export var col_border: Color = Color(0.04, 0.03, 0.05, 1.0)  # 近黑描边

# ── 配色（落色板，§1.4）──
@export var col_perfect: Color = Color(1.0, 0.85, 0.45)    # 余烬橙偏金高亮（提亮，拉开与良好明度差）
@export var col_good: Color = Color(0.902, 0.753, 0.290)   # 金
@export var col_normal: Color = Color(0.55, 0.60, 0.68)    # 法力蓝/骨白中性
@export var col_miss: Color = Color(0.62, 0.20, 0.20)      # 血红压暗
@export var col_ring_bg: Color = Color(0.18, 0.16, 0.18)   # 暗骨白底环
@export var col_pointer: Color = Color(0.847, 0.812, 0.753) # 骨白指针
@export var col_center_text: Color = Color(0.902, 0.753, 0.290) # 金色描边
@export var mask_color: Color = Color(0.05, 0.04, 0.06, 0.72)   # 灰烬黑遮罩
@export var dim_command_bar_alpha: float = 0.25    # 转盘期间命令栏弱化 alpha

const CONFIRM_KEY: Key = KEY_Z
const CANCEL_KEY: Key = KEY_X
const TIER_NAMES: Array[String] = ["完美", "良好", "普通", "失误"]

# 档索引常量（与 _tier_table / 配色顺序对齐）
const TIER_PERFECT: int = 0
const TIER_GOOD: int = 1
const TIER_NORMAL: int = 2
const TIER_MISS: int = 3

var _center: Vector2 = Vector2.ZERO          # 环心（中央框屏幕矩形中心）
var _angle: float = -PI * 0.5                # 指针当前角度（弧度，-90°=正顶）
var _locked: bool = false                    # 是否已定格
var _resolved: bool = false                  # 是否已发信号（防重复）
var _effective_spin: float = 4.0             # 实际转速（含 assist 缩放）

# 弧段表：每项 = {start, end, tier, color}，角度单位弧度（标准坐标，0=右、顺时针为正）
var _arc_segments: Array = []
# 档名/倍率/颜色查表（按 TIER_* 索引）
var _tier_multipliers: Array[float] = []
var _tier_colors: Array[Color] = []

# 命令栏弱化/恢复
var _command_bar: CanvasItem = null
var _command_bar_prev_alpha: float = 1.0

# 中心实时档名文字
@onready var _mask: ColorRect = $Mask
@onready var _center_label: Label = $CenterLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉指针（纯键盘，防误触）
	z_index = 100
	_normalize_ratios()
	_build_tier_lookup()
	_build_arc_segments()
	_init_start_angle()
	_apply_assist_speed()
	# 屏蔽自身被父级 _input 抢先：本节点处理输入并 accept_event。
	set_process(true)


## BattleUI 调用：把转盘对齐到中央框屏幕中心，弱化命令栏。
## central_box：③ CentralBox（NinePatchRect），command_bar：④ CommandBar（NinePatchRect）。
func start_over_central_box(central_box: Control, command_bar: CanvasItem = null) -> void:
	if is_instance_valid(central_box):
		_center = central_box.get_global_rect().get_center()
	else:
		_center = get_viewport_rect().get_center()
	_command_bar = command_bar
	if is_instance_valid(_command_bar):
		_command_bar_prev_alpha = _command_bar.modulate.a
		var m: Color = _command_bar.modulate
		m.a = dim_command_bar_alpha
		_command_bar.modulate = m
	_position_center_label()
	# AUTO 档：开局即一键锁定良好档，跳过踩点。
	if assist_mode == AssistMode.AUTO:
		_lock_to_tier(TIER_GOOD)
	queue_redraw()


func _process(delta: float) -> void:
	if _locked:
		return
	# 角度递增 → 标准屏幕坐标下顺时针匀速旋转（Y 轴向下，正角度即顺时针）。
	_angle = wrapf(_angle + _effective_spin * delta, -PI, PI)
	_update_center_label_live()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# 转盘阶段：Z 定格；X 不响应（吃掉但不回退，§2.5）；其余键无作用。
	match event.keycode:
		CONFIRM_KEY:
			if not _locked:
				_lock_current()
			accept_event()
		CANCEL_KEY:
			# 不响应 X：吃掉事件，不回退。
			accept_event()
		_:
			# WASD / 方向键在转盘阶段无作用，但吃掉以防穿透到 BattleUI。
			accept_event()


# ───────────────────────────────────────────── 定格 / 落点档区

func _lock_current() -> void:
	var tier: int = _tier_for_angle(_angle)
	_lock_to_tier_keep_angle(tier)


## AUTO 档专用：直接锁定指定档，并把指针摆到该档中点（视觉一致）。
func _lock_to_tier(tier: int) -> void:
	_angle = _tier_center_angle(tier)
	_lock_to_tier_keep_angle(tier)


func _lock_to_tier_keep_angle(tier: int) -> void:
	if _locked:
		return
	_locked = true
	var mult: float = _tier_multipliers[tier]
	var tier_name: String = TIER_NAMES[tier]
	_update_center_label_locked(tier, mult, tier_name)
	queue_redraw()
	# 停留 result_hold 秒后发信号、自销毁（用 SceneTreeTimer，不手写秒表）。
	await get_tree().create_timer(result_hold).timeout
	_emit_and_close(mult, tier_name)


func _emit_and_close(mult: float, tier_name: String) -> void:
	if _resolved:
		return
	_resolved = true
	_restore_command_bar()
	wheel_resolved.emit(mult, tier_name)
	queue_free()


func _restore_command_bar() -> void:
	if is_instance_valid(_command_bar):
		var m: Color = _command_bar.modulate
		m.a = _command_bar_prev_alpha
		_command_bar.modulate = m


# ───────────────────────────────────────────── 角度 / 档区构建

## 归一化四档占比，确保和=1.0（§4 校验/兜底）。
func _normalize_ratios() -> void:
	var ratios := PackedFloat32Array([
		perfect_arc_ratio, good_arc_ratio, normal_arc_ratio, miss_arc_ratio,
	])
	# EASY 档：加宽良好+完美窗（从普通档借），更易命中良好以上。
	if assist_mode == AssistMode.EASY:
		var bonus: float = clampf(assist_easy_good_ratio_bonus, 0.0, ratios[2])
		ratios[0] += bonus * 0.4
		ratios[1] += bonus * 0.6
		ratios[2] -= bonus
	var total: float = ratios[0] + ratios[1] + ratios[2] + ratios[3]
	if total <= 0.0:
		ratios = PackedFloat32Array([0.08, 0.22, 0.40, 0.30])
		total = 1.0
	perfect_arc_ratio = ratios[0] / total
	good_arc_ratio = ratios[1] / total
	normal_arc_ratio = ratios[2] / total
	miss_arc_ratio = ratios[3] / total


func _build_tier_lookup() -> void:
	_tier_multipliers = [
		perfect_multiplier, good_multiplier, normal_multiplier, miss_multiplier,
	]
	_tier_colors = [col_perfect, col_good, col_normal, col_miss]


## 构建顺时针「充能斜坡」弧段表。自 0°（3 点钟方向）顺时针单调爬升：
##   失误(开局段) → 普通 → 良好 → 完美(甜点) → 失误(悬崖段) → 回到 0°。
## 失误总占比拆成两段（开局段 + 悬崖段），跨 0° 连成一片失误区。
## 标准坐标 0=右、角度增大=顺时针；用半开区间 [start, end) 防边界双判。
func _build_arc_segments() -> void:
	_arc_segments.clear()
	var two_pi: float = TAU
	var w_perfect: float = perfect_arc_ratio * two_pi
	var w_good: float = good_arc_ratio * two_pi
	var w_normal: float = normal_arc_ratio * two_pi
	# 失误总宽对半拆：开局段（0° 起）+ 悬崖段（完美后）。0° 落在合片失误区正中。
	var w_miss_half: float = miss_arc_ratio * 0.5 * two_pi
	# 从 0°（3 点钟）开始顺时针（角度递增）铺段。
	var cursor: float = 0.0
	_push_segment(cursor, w_miss_half, TIER_MISS); cursor += w_miss_half   # 失误·开局段
	_push_segment(cursor, w_normal, TIER_NORMAL); cursor += w_normal       # 普通
	_push_segment(cursor, w_good, TIER_GOOD); cursor += w_good             # 良好
	_push_segment(cursor, w_perfect, TIER_PERFECT); cursor += w_perfect    # 完美（甜点·最窄）
	_push_segment(cursor, w_miss_half, TIER_MISS); cursor += w_miss_half   # 失误·悬崖段


func _push_segment(start: float, width: float, tier: int) -> void:
	_arc_segments.append({
		"start": start,
		"end": start + width,
		"tier": tier,
		"color": _tier_colors[tier],
	})


## 由角度求所在档：以环起点（0°，失误开局段左界）为基准，规范化到 [0, TAU) 后顺序查表。
func _tier_for_angle(angle: float) -> int:
	var base: float = _arc_segments[0]["start"]   # 失误开局段左界 = 0°（环起点）
	var rel: float = fposmod(angle - base, TAU)   # [0, TAU)
	var acc: float = 0.0
	for seg in _arc_segments:
		var w: float = seg["end"] - seg["start"]
		if rel < acc + w:        # 半开区间 [acc, acc+w)
			return seg["tier"]
		acc += w
	# 浮点兜底：落到最后一段。
	return _arc_segments[_arc_segments.size() - 1]["tier"]


## 某档（取第一段同 tier）的中点角度，用于 AUTO 摆针。
func _tier_center_angle(tier: int) -> float:
	for seg in _arc_segments:
		if seg["tier"] == tier:
			return (seg["start"] + seg["end"]) * 0.5
	return -PI * 0.5


func _init_start_angle() -> void:
	if randomize_start_angle:
		_angle = randf_range(-PI, PI)
	else:
		# 确定性起点：普通档（右侧）中点，离完美档有一段距离，需玩家踩点。
		_angle = _tier_center_angle(TIER_NORMAL)


func _apply_assist_speed() -> void:
	_effective_spin = spin_speed
	if assist_mode == AssistMode.EASY:
		_effective_spin = spin_speed * assist_easy_speed_scale


# ───────────────────────────────────────────── 自绘（_draw）

func _draw() -> void:
	if _center == Vector2.ZERO:
		return
	var point_count: int = 64
	# 1) 底环打底（整圈），避免档间透明缝。
	draw_arc(_center, ring_radius, 0.0, TAU, point_count, col_ring_bg, ring_width, false)
	# 2) 非完美三档彩色弧叠上（完美档最后画，确保最亮且压在最上层）。
	for seg in _arc_segments:
		if seg["tier"] == TIER_PERFECT:
			continue
		draw_arc(_center, ring_radius, seg["start"], seg["end"], point_count, seg["color"], ring_width, false)
	# 3) 完美档：内外双层发光 + 最亮本体（§B.3 完美区最窄、最亮）。
	for seg in _arc_segments:
		if seg["tier"] != TIER_PERFECT:
			continue
		var s: float = seg["start"]
		var e: float = seg["end"]
		# 外发光（略大半径、低 alpha）
		var glow_out: Color = col_perfect
		glow_out.a = perfect_glow_alpha
		draw_arc(_center, ring_radius + ring_width * 0.5 + 6.0, s, e, point_count, glow_out, 8.0, false)
		# 内发光
		var glow_in: Color = col_perfect
		glow_in.a = perfect_glow_alpha
		draw_arc(_center, ring_radius - ring_width * 0.5 - 6.0, s, e, point_count, glow_in, 8.0, false)
		# 本体（满亮，稍加宽以更醒目）
		draw_arc(_center, ring_radius, s, e, point_count, col_perfect, ring_width + 6.0, false)
		break
	# 4) 黑色粗像素边框：环内外缘整圈 + 每两档分界处径向分隔（chunky 像素质感）。
	_draw_chunky_borders(point_count)
	# 5) 指针：圆心 → 当前角度方向，尖端加骨白圆点。
	var tip: Vector2 = _center + Vector2.from_angle(_angle) * (ring_radius + 6.0)
	var pointer_col: Color = col_pointer
	if _locked:
		# 定格后指针取所在档颜色，强调落点。
		pointer_col = _tier_colors[_tier_for_angle(_angle)]
	draw_line(_center, tip, pointer_col, 4.0, true)
	draw_circle(tip, 7.0, col_pointer)
	draw_circle(_center, 6.0, col_pointer.darkened(0.2))


## 黑色粗像素边框：环外缘 + 环内缘整圈黑环，外加每个档区分界处的径向黑分隔线。
## 半径取环边缘并向外/内各让 border_width 半宽，使黑边贴着彩弧外侧（像素感更硬）。
func _draw_chunky_borders(point_count: int) -> void:
	var r_outer: float = ring_radius + ring_width * 0.5
	var r_inner: float = ring_radius - ring_width * 0.5
	# 关闭抗锯齿 → 边缘更硬，贴近像素观感。
	# 1) 外缘整圈黑环。
	draw_arc(_center, r_outer, 0.0, TAU, point_count, col_border, border_width, false)
	# 2) 内缘整圈黑环。
	draw_arc(_center, r_inner, 0.0, TAU, point_count, col_border, border_width, false)
	# 3) 段间径向分隔：每段起点画一条贯穿环宽的黑线（相邻段共用边界，不重复画终点）。
	#    分隔线两端略微外探 border_width 半宽，与内外缘黑环咬合成闭框。
	var half: float = border_width * 0.5
	for seg in _arc_segments:
		var ang: float = seg["start"]
		var dir: Vector2 = Vector2.from_angle(ang)
		var p_in: Vector2 = _center + dir * (r_inner - half)
		var p_out: Vector2 = _center + dir * (r_outer + half)
		draw_line(p_in, p_out, col_border, border_width, false)


# ───────────────────────────────────────────── 中心文字（实时 / 定格）

func _position_center_label() -> void:
	if not is_instance_valid(_center_label):
		return
	# 把 Label 摆到环心，居中。
	var box: Vector2 = Vector2(ring_radius * 1.4, 90.0)
	_center_label.size = box
	_center_label.position = _center - box * 0.5


func _update_center_label_live() -> void:
	if not is_instance_valid(_center_label):
		return
	var tier: int = _tier_for_angle(_angle)
	_center_label.text = "%s ×%.1f" % [TIER_NAMES[tier], _tier_multipliers[tier]]
	_center_label.add_theme_font_size_override("font_size", 30)
	_center_label.add_theme_color_override("font_color", _tier_colors[tier])
	_center_label.add_theme_constant_override("outline_size", 0)


func _update_center_label_locked(tier: int, mult: float, tier_name: String) -> void:
	if not is_instance_valid(_center_label):
		return
	_center_label.text = "%s ×%.1f" % [tier_name, mult]
	# 定格结果态：放大字号 + 该档颜色 + 金色描边（§1.5）。
	_center_label.add_theme_font_size_override("font_size", 46)
	_center_label.add_theme_color_override("font_color", _tier_colors[tier])
	_center_label.add_theme_constant_override("outline_size", 8)
	_center_label.add_theme_color_override("font_outline_color", col_center_text)
