class_name BattleUI
extends Control
## 战斗 UI 控制器 —— Meowa 切片换皮版（六分层）
##
## 增量改造说明：
##   - 指令/目标选择状态机、键盘闭环（Z/X/WASD·方向键）与 TurnStateMachine 对接逻辑
##     完全沿用旧版（_input / _handle_menu_input / _handle_target_input / select_command /
##     select_target / 技能 action 构造）。
##   - 仅把占位 Label 换成 12 张切片：中央 9-patch 框（③）、命令栏底板四格（④）、
##     我方/敌方头像框 + HP/MP TextureProgressBar（②⑤）、顶部行动顺序 pip 条（①）、
##     金色准星 / 红色锁定标记叠加层（⑥）。
##   - 切片加载失败一律回退纯色块 / 默认 StyleBox，不崩溃。

# ── 节点引用（六分层）──
@onready var _turn_order_bar: HBoxContainer = $TurnOrderBar          # ① 顶部行动顺序条
@onready var _enemy_container: HBoxContainer = $EnemyContainer        # ② 上方敌方区域
@onready var _central_box: NinePatchRect = $CentralBox               # ③ 中央 Undertale 框
@onready var _message_label: Label = $CentralBox/MessageLabel        # ③ 框内单条战况文字
@onready var _command_bar: NinePatchRect = $CommandBar               # ④ 命令栏底板
@onready var _command_cells: HBoxContainer = $CommandBar/CommandCells # ④ 四格固定命令
@onready var _party_container: VBoxContainer = $PartyPanel/PartyContainer # ⑤ 左下我方状态列
@onready var _reticle_layer: Control = $ReticleLayer                 # ⑥ 准星 / 锁敌层
@onready var _turn_label: Label = $TurnLabel

# ── 既有常量（沿用，勿改键位/指令字符串）──
const COMMAND_ATTACK: String = "attack"
const COMMAND_SKILL: String = "skill"
const COMMAND_FLEE: String = "flee"
const TARGET_GROUP_ENEMY: String = "enemy"
const TARGET_GROUP_PARTY: String = "party"
const SKILL_TYPE_ATTACK: int = 0
const CONFIRM_KEY: Key = KEY_Z
const CANCEL_KEY: Key = KEY_X
const MENU_MODE_COMMAND: String = "command"
const MENU_MODE_SKILL: String = "skill"

# ── 攻击力度转盘（纯代码自绘，攻击流中实例化叠加在中央框上）──
const ATTACK_WHEEL_SCENE: PackedScene = preload("res://scenes/battle/AttackPowerWheel.tscn")

# 视觉常量（切片路径 / 配色 / 像素缩放）已抽到 BattleWidgets，本控制器仅引用所需配色。

# 固定四格命令（行动 / 技能 / 物品 / 逃跑）。"物品" 逻辑未实现 → UI 占位置灰。
const CMD_LABELS: Array[String] = ["行动", "技能", "物品", "逃跑"]
const CMD_ITEM_INDEX: int = 2

var battle_controller: Node = null
var _turn_state_machine: Node = null
var _party_units: Array = []
var _enemy_units: Array = []
var _current_actor = null
var _is_selecting_target: bool = false
var _valid_targets: Array = []
var _on_target_picked: Callable = Callable()
var _menu_buttons: Array = []   # 当前菜单的可高亮项节点（命令格或中央框选项）
var _menu_actions: Array = []   # 与 _menu_buttons 对齐的 Callable
var _menu_disabled: Array = []  # 与 _menu_buttons 对齐的置灰标记
var _menu_labels: Array = []    # 与 _menu_buttons 对齐的原始文本
var _selected_menu_index: int = 0
var _selected_target_index: int = 0
var _menu_mode: String = MENU_MODE_COMMAND
# 头像中心屏幕坐标缓存（供 ⑥ 准星/锁定标记定位）
var _enemy_anchor_by_unit: Dictionary = {}
var _party_anchor_by_unit: Dictionary = {}
var _menu_visible: bool = false
var _wheel_active: bool = false   # 攻击转盘期间：BattleUI 自身 _input 让位给转盘
var _central_option_box: VBoxContainer = null   # ③ 中央框二级选项临时容器

# ───────────────────────────────────────────── 生命周期 / 对外接口

func setup(party: Array, enemies: Array, controller: Node = null, turn_state_machine: Node = null) -> void:
	battle_controller = controller
	_turn_state_machine = turn_state_machine
	_party_units = party
	_enemy_units = enemies
	_build_command_cells()
	_refresh_display()
	_clear_menu_highlight()
	_set_menu_visible(false)
	_message_label.text = "战斗开始！"

func refresh() -> void:
	_refresh_display()

func show_actor_turn(actor) -> void:
	_current_actor = actor
	_turn_label.text = "✦ 轮到 %s" % actor.display_name
	_is_selecting_target = false
	_clear_reticles()
	_rebuild_turn_order_bar(actor)
	if actor.is_player and not actor.is_dead():
		_build_command_menu()
		_message_label.text = "✦ %s 行动了——请选择指令。" % actor.display_name
	else:
		_clear_menu_highlight()
		_set_menu_visible(false)
		_message_label.text = "%s 正在行动..." % actor.display_name

func show_battle_result(victory: bool) -> void:
	_clear_menu_highlight()
	_set_menu_visible(false)
	_clear_reticles()
	_message_label.text = "战斗结束 — %s" % ("胜利！" if victory else "失败...")
	_turn_label.text = ""

# ───────────────────────────────────────────── ① 顶部行动顺序条（pip）

func _rebuild_turn_order_bar(active_actor) -> void:
	for child in _turn_order_bar.get_children():
		child.queue_free()
	var order: Array = []
	if battle_controller != null and battle_controller.has_method("get_all_units"):
		order = battle_controller.get_all_units()
	else:
		order = _party_units.duplicate()
		order.append_array(_enemy_units)
	for unit in order:
		if unit.is_dead():
			continue
		var is_active: bool = unit == active_actor
		_turn_order_bar.add_child(BattleWidgets.make_pip(is_active))

# ───────────────────────────────────────────── ②⑤ 敌我状态卡（头像框 + HP/MP 条）

func _refresh_display() -> void:
	# ② 敌方
	_enemy_anchor_by_unit.clear()
	for child in _enemy_container.get_children():
		child.queue_free()
	for enemy in _enemy_units:
		_enemy_container.add_child(BattleWidgets.make_unit_card(enemy, false))
	# ⑤ 我方
	_party_anchor_by_unit.clear()
	for child in _party_container.get_children():
		child.queue_free()
	for member in _party_units:
		_party_container.add_child(BattleWidgets.make_unit_card(member, true))

# ───────────────────────────────────────────── ④ 命令栏四格（固定）

func _build_command_cells() -> void:
	for child in _command_cells.get_children():
		child.queue_free()
	for i in range(CMD_LABELS.size()):
		var cell := Label.new()
		cell.text = CMD_LABELS[i]
		cell.add_theme_font_size_override("font_size", 30)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == CMD_ITEM_INDEX:
			cell.modulate = BattleWidgets.COL_DIM  # 物品：逻辑未实现，置灰
		_command_cells.add_child(cell)

## 命令模式：把四格命令接入既有 _menu_buttons 高亮/激活机制。
func _build_command_menu() -> void:
	_menu_mode = MENU_MODE_COMMAND
	_clear_menu_highlight()
	_set_menu_visible(true)
	# _menu_buttons 直接复用四个命令格 Label，行动绑定到旧的指令分发。
	var cells: Array = _command_cells.get_children()
	var actions: Array = [
		func(): _on_cmd_pressed("攻击"),   # 行动 → 攻击（Demo：行动一级即进攻击目标选择）
		func(): _on_cmd_pressed("技能"),
		func(): pass,                        # 物品：占位
		func(): _on_cmd_pressed("逃跑"),
	]
	for i in range(cells.size()):
		_menu_buttons.append(cells[i])
		_menu_actions.append(actions[i])
		_menu_disabled.append(i == CMD_ITEM_INDEX)
		_menu_labels.append(CMD_LABELS[i])
	_select_menu_index(0)

func _on_cmd_pressed(cmd: String) -> void:
	if _turn_state_machine == null:
		return
	match cmd:
		"攻击":
			# 选完目标后：进 TARGET_SELECT 态 → 弹力度转盘 → 等定格写倍率 → 才 select_target。
			# 关键时序（§3.2）：select_target 同步触发伤害计算，转盘必须先跑完写好 power_multiplier。
			_start_target_select(TARGET_GROUP_ENEMY, func(t): _turn_state_machine.select_command(COMMAND_ATTACK); _show_attack_wheel(t))
		"技能":
			_show_skill_menu()
		"逃跑":
			_turn_state_machine.select_command(COMMAND_FLEE)

## 攻击力度转盘：覆盖中央框、弱化命令栏 → 等 Z 定格 → 倍率回填攻击者 → 才放行 select_target。
## 时序：此函数被攻击 lambda 调用，select_command(ATTACK) 已置 TARGET_SELECT 态；
## 转盘 await 完成前不调 select_target，故伤害计算一定读到已写好的 power_multiplier。
func _show_attack_wheel(target) -> void:
	var wheel := ATTACK_WHEEL_SCENE.instantiate()
	add_child(wheel)
	_wheel_active = true
	wheel.start_over_central_box(_central_box, _command_bar)
	var res: Array = await wheel.wheel_resolved   # [multiplier: float, tier_name: String]
	_wheel_active = false
	var multiplier: float = res[0]
	var tier_name: String = res[1]
	if _current_actor != null:
		_current_actor.power_multiplier = multiplier   # 回填攻击者，calc_physical 读用
	_message_label.text = "%s ×%.1f" % [tier_name, multiplier]
	_turn_state_machine.select_target(target)          # 现在才放行 → ACTION_EXECUTE 用上倍率

## 技能二级选项：渲染在中央框内（§B.3：二级选项进中央框，不另开遮挡层）。
func _show_skill_menu() -> void:
	_menu_mode = MENU_MODE_SKILL
	_clear_menu_highlight()
	var stats: Resource = _current_actor.stats_res
	var skills: Array = []
	if stats != null and stats.get("skills") != null:
		skills = stats.skills
	# 中央框改为列出技能选项
	_render_central_options_header("✦ 选择技能（Z确认 / X返回）")
	for skill in skills:
		if skill != null and skill.has_method("get_instance_id"):
			var label := "%s (%d MP)" % [skill.display_name, skill.mp_cost]
			var disabled: bool = _current_actor.mp < skill.mp_cost
			_add_central_option(label, _create_skill_action(skill), disabled)
	_add_central_option("返回", _build_command_menu, false)
	_select_menu_index(0)

func _create_skill_action(skill) -> Callable:
	return func() -> void:
		var target_type := TARGET_GROUP_ENEMY if skill.skill_type == SKILL_TYPE_ATTACK else TARGET_GROUP_PARTY
		_start_target_select(target_type, func(t): _turn_state_machine.select_command(COMMAND_SKILL, skill); _turn_state_machine.select_target(t))

# ───────────────────────────────────────────── ③ 中央框二级选项渲染

func _render_central_options_header(header: String) -> void:
	# 用一个临时 VBox 覆盖在 MessageLabel 上呈现选项列表。
	_clear_central_options()
	_message_label.text = header
	_central_option_box = VBoxContainer.new()
	_central_option_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_central_option_box.anchor_top = 0.35
	_central_option_box.anchor_bottom = 1.0
	_central_option_box.offset_left = -200
	_central_option_box.offset_right = 200
	_central_option_box.offset_bottom = -24
	_central_option_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_central_option_box.add_theme_constant_override("separation", 6)
	_central_option_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_central_box.add_child(_central_option_box)

func _add_central_option(label: String, action: Callable, disabled: bool) -> void:
	var item := Label.new()
	item.add_theme_font_size_override("font_size", 24)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _central_option_box != null:
		_central_option_box.add_child(item)
	_menu_buttons.append(item)
	_menu_actions.append(action)
	_menu_disabled.append(disabled)
	_menu_labels.append(label)

func _clear_central_options() -> void:
	if _central_option_box != null and is_instance_valid(_central_option_box):
		_central_option_box.queue_free()
	_central_option_box = null

# ───────────────────────────────────────────── 菜单高亮 / 激活（沿用旧机制）

func _set_menu_visible(visible: bool) -> void:
	_menu_visible = visible
	_command_bar.visible = visible

func _clear_menu_highlight() -> void:
	_menu_buttons.clear()
	_menu_actions.clear()
	_menu_disabled.clear()
	_menu_labels.clear()
	_clear_central_options()

func _select_menu_index(index: int) -> void:
	var enabled_index := _find_enabled_menu_index(index, 1)
	if enabled_index == -1:
		return
	_selected_menu_index = enabled_index
	_update_menu_selection()

func _move_menu_selection(step: int) -> void:
	var enabled_index := _find_enabled_menu_index(_selected_menu_index + step, step)
	if enabled_index == -1:
		return
	_selected_menu_index = enabled_index
	_update_menu_selection()

func _find_enabled_menu_index(start: int, step: int) -> int:
	if _menu_buttons.is_empty():
		return -1
	var index := posmod(start, _menu_buttons.size())
	for _i in range(_menu_buttons.size()):
		if not _menu_disabled[index]:
			return index
		index = posmod(index + step, _menu_buttons.size())
	return -1

## 选项高亮：金色描边 + 金色「> 」指针（§B.3：金色指针/描边；置灰项保留位置）。
func _update_menu_selection() -> void:
	for i in range(_menu_buttons.size()):
		var node: Control = _menu_buttons[i]
		if not (node is Label):
			continue
		var lbl: Label = node
		var is_sel: bool = i == _selected_menu_index
		if _menu_disabled[i]:
			lbl.modulate = BattleWidgets.COL_DIM
		else:
			lbl.modulate = BattleWidgets.COL_GOLD if is_sel else BattleWidgets.COL_BONE
		# 金色描边仅当前项
		lbl.add_theme_constant_override("outline_size", 6 if is_sel else 0)
		lbl.add_theme_color_override("font_outline_color", BattleWidgets.COL_GOLD if is_sel else Color(0, 0, 0, 0))
		# 命令格用「>」指针；中央框选项同样加指针
		var base: String = _menu_labels[i]
		lbl.text = ("▸ %s" % base) if is_sel else base

func _activate_selected_menu_item() -> void:
	if _selected_menu_index < 0 or _selected_menu_index >= _menu_actions.size():
		return
	if _menu_disabled[_selected_menu_index]:
		return
	_menu_actions[_selected_menu_index].call()

# ───────────────────────────────────────────── 目标选择（沿用旧逻辑 + ⑥ 准星）

func _start_target_select(target_type: String, callback: Callable) -> void:
	_is_selecting_target = true
	_on_target_picked = callback
	_selected_target_index = 0
	_valid_targets.clear()
	if target_type == TARGET_GROUP_ENEMY:
		_valid_targets = _enemy_units.filter(func(u): return not u.is_dead())
	else:
		_valid_targets = _party_units.filter(func(u): return not u.is_dead())
	_clear_central_options()
	_set_menu_visible(false)
	_update_target_message()
	_update_target_reticle()

func _move_target_selection(step: int) -> void:
	if _valid_targets.is_empty():
		return
	_selected_target_index = posmod(_selected_target_index + step, _valid_targets.size())
	_update_target_message()
	_update_target_reticle()

func _update_target_message() -> void:
	if _valid_targets.is_empty():
		_message_label.text = "没有可选目标，X返回"
		return
	var target = _valid_targets[_selected_target_index]
	_message_label.text = "选择目标（方向键 / Z确认 / X返回）：%s  %d/%d" % [
		target.display_name,
		_selected_target_index + 1,
		_valid_targets.size(),
	]

func _pick_selected_target() -> void:
	if _valid_targets.is_empty():
		return
	var target = _valid_targets[_selected_target_index]
	_is_selecting_target = false
	_valid_targets.clear()
	_clear_reticles()
	_message_label.text = ""
	if _on_target_picked.is_valid():
		_on_target_picked.call(target)

func _cancel_target_select() -> void:
	_is_selecting_target = false
	_valid_targets.clear()
	_clear_reticles()
	if _menu_mode == MENU_MODE_SKILL:
		_show_skill_menu()
	else:
		_build_command_menu()
		_message_label.text = "✦ %s 行动了——请选择指令。" % _current_actor.display_name

# ───────────────────────────────────────────── ⑥ 准星 / 锁敌标记层

## 我锁敌：金色准星浮于当前合法敌方目标头像上方。
func _update_target_reticle() -> void:
	_clear_reticles()
	if _valid_targets.is_empty():
		return
	var target = _valid_targets[_selected_target_index]
	var anchor: Control = _find_avatar_for_unit(target)
	if anchor == null:
		return
	var tex: Texture2D = BattleWidgets.load_tex(BattleWidgets.TEX_RETICLE)
	var marker := BattleWidgets.make_overlay_marker(tex, 16, BattleWidgets.COL_GOLD)
	_reticle_layer.add_child(marker)
	# 浮于头像上方居中
	var center := _avatar_screen_center(anchor)
	marker.position = center - marker.custom_minimum_size * 0.5 - Vector2(0, anchor.size.y * 0.6)

func _clear_reticles() -> void:
	if not is_instance_valid(_reticle_layer):
		return
	for child in _reticle_layer.get_children():
		child.queue_free()

func _find_avatar_for_unit(unit) -> Control:
	var pools: Array = [_enemy_container, _party_container]
	for pool in pools:
		for card in pool.get_children():
			for sub in card.get_children():
				if sub is Control and sub.has_meta("unit_ref") and sub.get_meta("unit_ref") == unit:
					return sub
	return null

func _avatar_screen_center(avatar: Control) -> Vector2:
	return avatar.get_global_rect().get_center()

# ───────────────────────────────────────────── 输入（键盘闭环，沿用旧规则）

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _wheel_active:
		return   # 转盘阶段：输入交给转盘自身处理（仅 Z 定格，X 不响应）
	if _is_selecting_target:
		_handle_target_input(event.keycode)
	elif _menu_visible and not _menu_buttons.is_empty():
		_handle_menu_input(event.keycode)

func _handle_menu_input(keycode: Key) -> void:
	# 命令栏四格为横向 → 左右切换；中央框技能选项为纵向 → 上下切换。两套方向键都接受。
	match keycode:
		KEY_UP, KEY_W, KEY_LEFT, KEY_A:
			_move_menu_selection(-1)
			accept_event()
		KEY_DOWN, KEY_S, KEY_RIGHT, KEY_D:
			_move_menu_selection(1)
			accept_event()
		CONFIRM_KEY:
			_activate_selected_menu_item()
			accept_event()
		CANCEL_KEY:
			if _menu_mode == MENU_MODE_SKILL:
				_build_command_menu()
				_message_label.text = "✦ %s 行动了——请选择指令。" % _current_actor.display_name
				accept_event()

func _handle_target_input(keycode: Key) -> void:
	match keycode:
		KEY_LEFT, KEY_UP, KEY_A, KEY_W:
			_move_target_selection(-1)
			accept_event()
		KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S:
			_move_target_selection(1)
			accept_event()
		CONFIRM_KEY:
			_pick_selected_target()
			accept_event()
		CANCEL_KEY:
			_cancel_target_select()
			accept_event()
