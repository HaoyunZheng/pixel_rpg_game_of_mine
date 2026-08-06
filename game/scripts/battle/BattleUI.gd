class_name BattleUI
extends Control
## 战斗 UI 控制器 —— Meowa 切片换皮版（六分层）
##
## 增量改造说明：
##   - 指令/目标选择状态机、键盘闭环（Z/X/WASD·方向键）与 TurnStateMachine 对接逻辑
##     完全沿用旧版（_input / _handle_menu_input / _handle_target_input / select_command /
##     select_target / 技能 action 构造）。
##   - 仅把占位 Label 换成 12 张切片：中央 9-patch 框（③）、命令栏底板四格（④）、
##     我方/敌方头像框 + HP/MP TextureProgressBar（②⑤）、顶部弧线头像行动条（①）、
##     金色准星 / 红色锁定标记叠加层（⑥）。
##   - 切片加载失败一律回退纯色块 / 默认 StyleBox，不崩溃。

# ── 节点引用（六分层）──
@onready var _turn_order_bar: Control = $TurnOrderBar               # ① 顶部弧线行动顺序条
@onready var _enemy_container: HBoxContainer = $EnemyContainer        # ② 上方敌方区域
@onready var _central_box: NinePatchRect = $CentralBox               # ③ 中央 Undertale 框
@onready var _message_label: Label = $CentralBox/MessageLabel        # ③ 框内单条战况文字
@onready var _stage_box: NinePatchRect = $StageBox                   # ③b 右侧独立演出框
@onready var _command_bar: Control = $CommandBar                     # ④ 命令栏（四格各自带框，不再用整条底板）
@onready var _command_cells: HBoxContainer = $CommandBar/CommandCells # ④ 四格固定命令
@onready var _party_panel: NinePatchRect = $PartyPanel
@onready var _party_container: VBoxContainer = $PartyPanel/PartyContainer # ⑤ 左下我方状态列
@onready var _reticle_layer: Control = $ReticleLayer                 # ⑥ 准星 / 锁敌层
@onready var _impact_camera_noise: PhantomCameraNoiseEmitter2D = $ImpactCameraNoise

# ── 既有常量（沿用，勿改键位/指令字符串）──
const TARGET_GROUP_ENEMY: String = "enemy"
const TARGET_GROUP_PARTY: String = "party"
const CONFIRM_KEY: Key = KEY_Z
const CANCEL_KEY: Key = KEY_X
const MENU_MODE_COMMAND: String = "command"
const MENU_MODE_ACTION: String = "action"
const MENU_MODE_SKILL: String = "skill"
const MENU_MODE_ITEM: String = "item"
const TIMING_TWEEN_SECONDS: float = 0.3
const DESIGN_SIZE: Vector2 = Vector2(480.0, 270.0)
const TARGET_RETICLE_SIZE_1080P: int = 96
const TARGET_RETICLE_HEAD_RATIO: float = 0.22
const TARGET_RETICLE_ENTER_SCALE: float = 0.72
const TARGET_RETICLE_PRESS_SCALE: float = 0.82
const TARGET_RETICLE_PULSE_SCALE: float = 1.85
const TARGET_RETICLE_ENTER_SECONDS: float = 0.28
const TARGET_RETICLE_MOVE_SECONDS: float = 0.2
const TARGET_RETICLE_PRESS_SECONDS: float = 0.06
const TARGET_RETICLE_PULSE_SECONDS: float = 0.18
const TARGET_RETICLE_CANCEL_SECONDS: float = 0.08
const INTENT_PRESS_SECONDS: float = 0.08
const INTENT_PULSE_SECONDS: float = 0.25
const INTENT_STAGGER_SECONDS: float = 0.1
const HIT_FLASH_IN_SECONDS: float = 0.02
const HIT_FLASH_OUT_SECONDS: float = 0.08

# ── 攻击力度转盘（纯代码自绘，攻击流中实例化叠加在中央框上）──
const ATTACK_WHEEL_SCENE: PackedScene = preload("res://scenes/battle/AttackPowerWheel.tscn")
const DEFENSE_TIMING_SCENE: PackedScene = preload("res://scenes/battle/DefenseTimingCheck.tscn")

# 视觉常量（切片路径 / 配色 / 像素缩放）已抽到 BattleWidgets，本控制器仅引用所需配色。

# 固定四格命令（行动 / 技能 / 物品 / 逃跑）。"物品" 无可用物品时置灰。
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
var _timing_active: bool = false
var _central_option_box: VBoxContainer = null   # ③ 中央框二级选项临时容器
var _enemy_intents: Dictionary = {}
var _timing_normal_rect: Rect2 = Rect2()
var _timing_overlay: Control = null
var _timing_result_label: Label = null
var _timing_tween: Tween = null
var _intent_refresh_pending: bool = false
var _stage_party_actor = null
var _target_reticle: Control = null
var _target_reticle_tween: Tween = null
var _target_confirming: bool = false
var _intent_preview_active: bool = false
var _intent_preview_tween: Tween = null
var _intent_marker_by_unit: Dictionary = {}
var _hud_scale: float = 1.0
var _party_avatar_size: int = 120
var _enemy_sprite_size: int = 224

# ───────────────────────────────────────────── 生命周期 / 对外接口

func _ready() -> void:
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()

func setup(party: Array, enemies: Array, controller: Node = null, turn_state_machine: Node = null) -> void:
	battle_controller = controller
	_turn_state_machine = turn_state_machine
	_party_units = party
	_enemy_units = enemies
	_build_command_cells()
	_apply_layout()
	_clear_menu_highlight()
	_set_menu_visible(false)
	_message_label.text = "战斗开始！"
	_stage_party_actor = _first_living_party()
	_show_stage_actor(_stage_party_actor)

func refresh() -> void:
	_refresh_display()

func show_actor_turn(actor) -> void:
	_current_actor = actor
	_is_selecting_target = false
	_clear_target_reticles()
	_rebuild_turn_order_bar(actor)
	if actor.is_player and not actor.is_dead():
		_stage_party_actor = actor
		_show_stage_actor(actor)
		_build_command_menu()
		_message_label.text = _actor_turn_message(actor)
	else:
		_clear_menu_highlight()
		_set_menu_visible(false)
		_message_label.text = "%s 正在行动..." % actor.display_name

func show_battle_result(victory: bool, ember_reward: int = 0) -> void:
	_clear_menu_highlight()
	_set_menu_visible(false)
	_clear_all_reticles()
	_message_label.text = "战斗结束 — %s" % ("胜利！" if victory else "失败...")
	if victory and ember_reward > 0:
		_message_label.text += "\n获得余烬 ×%d" % ember_reward

func run_timing_check(
		attacker: BattleUnit,
		target: BattleUnit,
		_base_damage: int,
		intent: Dictionary = {}) -> Array:
	_timing_active = true
	_set_menu_visible(false)
	_clear_target_reticles()
	_timing_normal_rect = Rect2(_central_box.position, _central_box.size)
	_show_stage_actor(attacker)
	await _set_timing_layout(true)
	_build_timing_overlay(attacker, target)
	var timing := DEFENSE_TIMING_SCENE.instantiate()
	add_child(timing)
	timing.impact_feedback.connect(_on_timing_impact_feedback)
	var key_hint: String = "WASD 移动｜Z 弹反" if target.pending_stance == BattleUnit.Stance.DEFEND else "WASD 移动｜Shift 冲刺"
	if target.pending_stance == BattleUnit.Stance.ATTACK:
		key_hint = "WASD 移动｜攻击姿态无主动防御"
	_timing_result_label.text = "%s 攻击 %s｜%s" % [attacker.display_name, target.display_name, key_hint]
	timing.start(
		target.pending_stance,
		_central_box.get_global_rect(),
		String(intent.get("attack_pattern", EnemyAI.PATTERN_FALLBACK_THRUST)),
		Dictionary(intent.get("pattern_params", {})))
	var hit_results: Array = await timing.timing_resolved
	return hit_results

func _on_timing_impact_feedback(amplitude: float) -> void:
	_impact_camera_noise.noise.amplitude = amplitude
	_impact_camera_noise.emit()

func play_player_hit(target: BattleUnit, strength: float) -> void:
	var avatar: Control = _find_avatar_for_unit(target)
	if avatar == null or avatar.get_child_count() == 0:
		return
	var flash_overlay: CanvasItem = null
	for child in avatar.get_children():
		if child.has_meta("hit_flash_overlay"):
			flash_overlay = child as CanvasItem
			break
	if flash_overlay == null:
		return
	flash_overlay.modulate.a = 1.0
	_on_timing_impact_feedback(strength)
	var flash_tween := create_tween()
	flash_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flash_tween.tween_interval(HIT_FLASH_IN_SECONDS)
	flash_tween.tween_property(flash_overlay, "modulate:a", 0.001, HIT_FLASH_OUT_SECONDS)
	await flash_tween.finished

func finish_timing_check(target: BattleUnit, timing_result: Dictionary) -> void:
	if is_instance_valid(_timing_result_label):
		_timing_result_label.text = _format_timing_result(target, timing_result)
	_refresh_display()
	await _set_timing_layout(false)
	_clear_timing_overlay()
	if _stage_party_actor == null or _stage_party_actor.is_dead():
		_stage_party_actor = _first_living_party()
	_show_stage_actor(_stage_party_actor)
	_message_label.visible = true
	_timing_active = false

func show_enemy_intents(intents: Dictionary, turn_order: Array = []) -> void:
	_enemy_intents = intents.duplicate(true)
	_intent_preview_active = true
	_is_selecting_target = false
	_clear_target_reticles()
	_clear_menu_highlight()
	_set_menu_visible(false)
	await get_tree().process_frame
	_clear_intent_markers()
	_rebuild_intent_markers(false)
	var ordered_units: Array = turn_order if not turn_order.is_empty() else _enemy_intents.keys()
	for unit in ordered_units:
		if unit != null and not unit.is_dead():
			_turn_order_bar.show_order(ordered_units, unit)
			break
	var telegraphs: Array = []
	for unit in ordered_units:
		if not _enemy_intents.has(unit):
			continue
		var targets: Array = _enemy_intents[unit].get("targets", []).filter(
			func(target): return _intent_marker_by_unit.has(target))
		if not targets.is_empty():
			telegraphs.append(targets)
	if telegraphs.is_empty():
		_show_all_intent_markers()
		_intent_preview_active = false
		return
	_intent_preview_tween = create_tween()
	for index in range(telegraphs.size()):
		if index > 0:
			_intent_preview_tween.tween_interval(INTENT_STAGGER_SECONDS)
		_intent_preview_tween.tween_callback(_pulse_intent_targets.bind(telegraphs[index]))
	_intent_preview_tween.tween_interval(
		INTENT_PRESS_SECONDS * 2.0 + INTENT_PULSE_SECONDS)
	await _intent_preview_tween.finished
	_intent_preview_tween = null
	_show_all_intent_markers()
	_intent_preview_active = false

# ───────────────────────────────────────────── ① 顶部弧线行动顺序条

func _rebuild_turn_order_bar(active_actor) -> void:
	var order: Array = []
	if battle_controller != null and battle_controller.has_method("get_turn_order"):
		order = battle_controller.get_turn_order()
	elif battle_controller != null and battle_controller.has_method("get_all_units"):
		order = battle_controller.get_all_units()
	else:
		order = _party_units.duplicate()
		order.append_array(_enemy_units)
	_turn_order_bar.show_order(order, active_actor)

# ───────────────────────────────────────────── ②⑤ 敌我状态卡（头像框 + HP/MP 条）

func _refresh_display() -> void:
	# ② 敌方
	_enemy_anchor_by_unit.clear()
	for child in _enemy_container.get_children():
		# ponytail: 立即移出容器，queue_free 留到帧末也不会与新卡重叠渲染。
		_enemy_container.remove_child(child)
		child.queue_free()
	for index in _enemy_units.size():
		var enemy = _enemy_units[index]
		var top_margin: int = calculate_enemy_vertical_offset(
			index, _enemy_units.size(), _enemy_container.size.y, _enemy_sprite_size)
		var vertical_travel: int = maxi(0, floori(_enemy_container.size.y) - _enemy_sprite_size)
		var slot := MarginContainer.new()
		slot.custom_minimum_size = Vector2(_enemy_sprite_size, floori(_enemy_container.size.y))
		slot.add_theme_constant_override("margin_top", top_margin)
		slot.add_theme_constant_override("margin_bottom", vertical_travel - top_margin)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := BattleWidgets.make_unit_card(
			enemy, false, false, _enemy_sprite_size, _hud_scale)
		card.set_meta("unit_ref", enemy)
		slot.add_child(card)
		_enemy_container.add_child(slot)
	# ⑤ 我方
	_party_anchor_by_unit.clear()
	for child in _party_container.get_children():
		_party_container.remove_child(child)
		child.queue_free()
	for member in _party_units:
		_party_container.add_child(BattleWidgets.make_unit_card(
			member, true, member == _current_actor, _party_avatar_size, _hud_scale))
	_schedule_intent_marker_refresh()

# ───────────────────────────────────────────── ④ 命令栏四格（固定）

func _build_command_cells() -> void:
	for child in _command_cells.get_children():
		child.queue_free()
	for i in range(CMD_LABELS.size()):
		var disabled: bool = i == CMD_ITEM_INDEX and not _has_battle_usable_items()
		_command_cells.add_child(BattleWidgets.make_command_cell(CMD_LABELS[i], disabled))

## 命令模式：把四格命令接入既有 _menu_buttons 高亮/激活机制。
func _build_command_menu() -> void:
	_menu_mode = MENU_MODE_COMMAND
	_clear_menu_highlight()
	_set_menu_visible(true)
	# _menu_buttons 直接复用四个命令格 Label，行动绑定到旧的指令分发。
	var cells: Array = _command_cells.get_children()
	var actions: Array = [
		_show_action_menu,
		func(): _on_cmd_pressed("技能"),
		func(): _on_cmd_pressed("物品"),
		func(): _on_cmd_pressed("逃跑"),
	]
	for i in range(cells.size()):
		_menu_buttons.append(cells[i])
		_menu_actions.append(actions[i])
		_menu_disabled.append(i == CMD_ITEM_INDEX and not _has_battle_usable_items())
		_menu_labels.append(CMD_LABELS[i])
	_select_menu_index(0)

func _show_action_menu() -> void:
	_menu_mode = MENU_MODE_ACTION
	_clear_menu_highlight()
	_render_central_options_header("✦ 选择姿态（Z确认 / X返回）")
	_add_central_option("攻击", func(): _on_cmd_pressed("攻击"), false)
	var stance_row := HBoxContainer.new()
	stance_row.set_meta("action_stance_row", true)
	stance_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stance_row.add_theme_constant_override("separation", maxi(16, roundi(24.0 * _hud_scale)))
	stance_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_central_option_box.add_child(stance_row)
	_add_central_option(
		"防御", func(): _turn_state_machine.select_command(BattleCommands.DEFEND), false, stance_row)
	_add_central_option(
		"闪避", func(): _turn_state_machine.select_command(BattleCommands.DODGE), false, stance_row)
	_select_menu_index(0)

func _on_cmd_pressed(cmd: String) -> void:
	if _turn_state_machine == null:
		return
	match cmd:
		"攻击":
			# 选完目标后：进 TARGET_SELECT 态 → 弹力度转盘 → 等定格写倍率 → 才 select_target。
			# 关键时序（§3.2）：select_target 同步触发伤害计算，转盘必须先跑完写好 power_multiplier。
			_start_target_select(TARGET_GROUP_ENEMY, func(t): _turn_state_machine.select_command(BattleCommands.ATTACK); _show_attack_wheel(t))
		"技能":
			_show_skill_menu()
		"物品":
			_show_item_menu()
		"逃跑":
			_turn_state_machine.select_command(BattleCommands.FLEE)

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
		var target_type := TARGET_GROUP_ENEMY if skill.skill_type == SkillData.SkillType.ATTACK else TARGET_GROUP_PARTY
		_start_target_select(target_type, func(t): _turn_state_machine.select_command(BattleCommands.SKILL, skill); _turn_state_machine.select_target(t))

## 物品二级选项：同技能，渲染在中央框内。缓解物按 §4.5 战斗内置灰。
func _show_item_menu() -> void:
	_menu_mode = MENU_MODE_ITEM
	_clear_menu_highlight()
	_render_central_options_header("✦ 选择物品（Z确认 / X返回）")
	for slot in battle_controller.get_inventory_slots():
		var item: ItemData = slot.item
		if item.category != ItemData.ItemCategory.CONSUMABLE:
			continue
		var label := "%s ×%d" % [item.display_name, slot.count]
		var disabled: bool = slot.count <= 0 or item.item_type == ItemData.ItemType.PALLIATIVE
		_add_central_option(label, _create_item_action(item), disabled)
	_add_central_option("返回", _build_command_menu, false)
	_select_menu_index(0)

func _create_item_action(item: ItemData) -> Callable:
	return func() -> void:
		var target_type := TARGET_GROUP_ENEMY if item.effect_type == ItemData.EffectType.DAMAGE else TARGET_GROUP_PARTY
		_start_target_select(target_type, func(t): _turn_state_machine.select_command(BattleCommands.ITEM, item); _turn_state_machine.select_target(t))

func _has_battle_usable_items() -> bool:
	for slot in battle_controller.get_inventory_slots():
		if slot.count > 0 and slot.item.item_type != ItemData.ItemType.PALLIATIVE and slot.item.category == ItemData.ItemCategory.CONSUMABLE:
			return true
	return false

# ───────────────────────────────────────────── ③ 中央框二级选项渲染

func _render_central_options_header(header: String) -> void:
	# 用一个临时 VBox 覆盖在 MessageLabel 上呈现选项列表。
	_clear_central_options()
	_message_label.text = header
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_central_option_box = BattleWidgets.make_central_option_box(_hud_scale)
	_central_box.add_child(_central_option_box)

func _add_central_option(
		label: String,
		action: Callable,
		disabled: bool,
		parent: Container = null) -> void:
	var item := BattleWidgets.make_menu_option(_hud_scale)
	var target_parent: Container = parent if parent != null else _central_option_box
	if target_parent != null:
		target_parent.add_child(item)
	_menu_buttons.append(item)
	_menu_actions.append(action)
	_menu_disabled.append(disabled)
	_menu_labels.append(label)

func _clear_central_options() -> void:
	if _central_option_box != null and is_instance_valid(_central_option_box):
		_central_option_box.queue_free()
	_central_option_box = null
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

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
	_emit_confirm_particles(_menu_buttons[_selected_menu_index].get_global_rect().get_center())
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
	if _valid_targets.size() == 1:
		var target = _valid_targets[0]
		var picked_callback := _on_target_picked
		_target_confirming = true
		_is_selecting_target = false
		_message_label.text = ""
		await get_tree().process_frame
		_valid_targets.clear()
		_target_confirming = false
		if picked_callback.is_valid():
			picked_callback.call(target)
		return
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
	_message_label.text = "▶ %s" % target.display_name

func _pick_selected_target() -> void:
	if _valid_targets.is_empty() or _target_confirming:
		return
	var target = _valid_targets[_selected_target_index]
	_target_confirming = true
	_is_selecting_target = false
	await _play_target_confirm_pulse()
	_valid_targets.clear()
	_clear_target_reticles()
	_message_label.text = ""
	_target_confirming = false
	if _on_target_picked.is_valid():
		_on_target_picked.call(target)

func _cancel_target_select() -> void:
	_is_selecting_target = false
	await _fade_out_target_reticle()
	_valid_targets.clear()
	if _turn_state_machine != null:
		_turn_state_machine.cancel_command()
	_set_menu_visible(true)
	if _menu_mode == MENU_MODE_SKILL:
		_show_skill_menu()
	elif _menu_mode == MENU_MODE_ITEM:
		_show_item_menu()
	elif _menu_mode == MENU_MODE_ACTION:
		_show_action_menu()
	else:
		_build_command_menu()
		_message_label.text = _actor_turn_message(_current_actor)

# ───────────────────────────────────────────── ⑥ 准星 / 锁敌标记层

## 我锁敌：金色准星浮于当前合法敌方目标头像上方。
func _update_target_reticle() -> void:
	if _valid_targets.is_empty():
		return
	var target = _valid_targets[_selected_target_index]
	var anchor: Control = _find_avatar_for_unit(target)
	if anchor == null:
		return
	var marker_size := Vector2.ONE * calculate_target_reticle_size(_hud_scale)
	var target_position := calculate_target_reticle_position(anchor.get_global_rect(), marker_size)
	_set_target_brightness(target)
	if _target_reticle_tween != null and _target_reticle_tween.is_valid():
		_target_reticle_tween.kill()
	if not is_instance_valid(_target_reticle):
		var tex: Texture2D = BattleWidgets.load_tex(BattleWidgets.TEX_RETICLE)
		_target_reticle = BattleWidgets.make_overlay_marker(
			tex, roundi(marker_size.x), BattleWidgets.COL_GOLD)
		_target_reticle.set_meta("target_marker", true)
		_reticle_layer.add_child(_target_reticle)
		_target_reticle.pivot_offset = _target_reticle.size * 0.5
		_target_reticle.position = target_position
		_target_reticle.rotation = -TAU
		_target_reticle.modulate.a = 0.0
		_target_reticle.scale = Vector2.ONE * TARGET_RETICLE_ENTER_SCALE
		_target_reticle_tween = create_tween().set_parallel(true)
		_target_reticle_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_target_reticle_tween.tween_property(
			_target_reticle, "rotation", 0.0, TARGET_RETICLE_ENTER_SECONDS)
		_target_reticle_tween.tween_property(
			_target_reticle, "modulate:a", 1.0, TARGET_RETICLE_ENTER_SECONDS)
		_target_reticle_tween.tween_property(
			_target_reticle, "scale", Vector2.ONE, TARGET_RETICLE_ENTER_SECONDS)
		return
	_target_reticle.custom_minimum_size = marker_size
	_target_reticle.size = marker_size
	_target_reticle.pivot_offset = marker_size * 0.5
	_target_reticle_tween = create_tween().set_parallel(true)
	_target_reticle_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_target_reticle_tween.tween_property(
		_target_reticle, "position", target_position, TARGET_RETICLE_MOVE_SECONDS)
	_target_reticle_tween.tween_property(
		_target_reticle, "rotation",
		_target_reticle.rotation + TAU, TARGET_RETICLE_MOVE_SECONDS)
	_target_reticle_tween.tween_property(
		_target_reticle, "modulate:a", 1.0, TARGET_RETICLE_MOVE_SECONDS)
	_target_reticle_tween.tween_property(
		_target_reticle, "scale", Vector2.ONE, TARGET_RETICLE_MOVE_SECONDS)

func _clear_target_reticles() -> void:
	if not is_instance_valid(_reticle_layer):
		return
	if _target_reticle_tween != null and _target_reticle_tween.is_valid():
		_target_reticle_tween.kill()
	_target_reticle_tween = null
	for child in _reticle_layer.get_children():
		if child.has_meta("target_marker"):
			child.queue_free()
	_target_reticle = null
	_restore_target_brightness()

func _fade_out_target_reticle() -> void:
	if not is_instance_valid(_target_reticle):
		_restore_target_brightness()
		return
	if _target_reticle_tween != null and _target_reticle_tween.is_valid():
		_target_reticle_tween.kill()
	_target_reticle_tween = create_tween()
	_target_reticle_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_target_reticle_tween.tween_property(
		_target_reticle, "modulate:a", 0.0, TARGET_RETICLE_CANCEL_SECONDS)
	await _target_reticle_tween.finished
	_clear_target_reticles()

func _play_target_confirm_pulse() -> void:
	if not is_instance_valid(_target_reticle):
		return
	if _target_reticle_tween != null and _target_reticle_tween.is_valid():
		_target_reticle_tween.kill()
	_target_reticle_tween = create_tween()
	_target_reticle_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_target_reticle_tween.tween_property(
		_target_reticle, "scale",
		Vector2.ONE * TARGET_RETICLE_PRESS_SCALE, TARGET_RETICLE_PRESS_SECONDS)
	_target_reticle_tween.tween_property(
		_target_reticle, "scale", Vector2.ONE, TARGET_RETICLE_PRESS_SECONDS)
	await _target_reticle_tween.finished
	_target_reticle_tween = null
	var pulse := _target_reticle.duplicate() as Control
	pulse.remove_meta("target_marker")
	pulse.set_meta("target_pulse", true)
	_reticle_layer.add_child(pulse)
	pulse.position = _target_reticle.position
	pulse.pivot_offset = pulse.size * 0.5
	pulse.scale = Vector2.ONE
	pulse.modulate.a = 1.0
	var pulse_tween := create_tween()
	pulse_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(
		pulse, "scale", Vector2.ONE * TARGET_RETICLE_PULSE_SCALE, TARGET_RETICLE_PULSE_SECONDS)
	pulse_tween.parallel().tween_property(
		pulse, "modulate:a", 0.0, TARGET_RETICLE_PULSE_SECONDS)
	pulse_tween.tween_callback(pulse.queue_free)

func _set_target_brightness(selected) -> void:
	for unit in _valid_targets:
		var avatar: Control = _find_avatar_for_unit(unit)
		if avatar != null:
			avatar.modulate = Color.WHITE if unit == selected else Color(0.42, 0.42, 0.42, 1.0)

func _restore_target_brightness() -> void:
	for unit in _party_units + _enemy_units:
		var avatar: Control = _find_avatar_for_unit(unit)
		if avatar != null:
			avatar.modulate = Color.WHITE

func _emit_confirm_particles(screen_position: Vector2) -> void:
	var particles := GPUParticles2D.new()
	particles.set_meta("confirm_particles", true)
	particles.amount = 16
	particles.lifetime = 0.28
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.visibility_rect = Rect2(-240.0, -240.0, 480.0, 480.0)
	particles.texture = DefenseTimingVFX.make_particle_texture()
	particles.z_index = 130
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 180.0
	material.initial_velocity_min = 90.0
	material.initial_velocity_max = 180.0
	material.gravity = Vector3.ZERO
	material.scale_min = 0.35
	material.scale_max = 0.8
	var fade := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		BattleWidgets.COL_GOLD,
		Color(BattleWidgets.COL_GOLD, 0.0),
	])
	fade.gradient = gradient
	material.color_ramp = fade
	particles.process_material = material
	_reticle_layer.add_child(particles)
	particles.global_position = screen_position
	particles.finished.connect(particles.queue_free)
	particles.restart()
	particles.emitting = true

func _clear_intent_markers() -> void:
	if not is_instance_valid(_reticle_layer):
		return
	if _intent_preview_tween != null and _intent_preview_tween.is_valid():
		_intent_preview_tween.kill()
	_intent_preview_tween = null
	for child in _reticle_layer.get_children():
		if child.has_meta("intent_marker"):
			child.queue_free()
	_intent_marker_by_unit.clear()

func _clear_all_reticles() -> void:
	if not is_instance_valid(_reticle_layer):
		return
	if _target_reticle_tween != null and _target_reticle_tween.is_valid():
		_target_reticle_tween.kill()
	if _intent_preview_tween != null and _intent_preview_tween.is_valid():
		_intent_preview_tween.kill()
	for child in _reticle_layer.get_children():
		child.queue_free()
	_target_reticle = null
	_target_reticle_tween = null
	_intent_preview_tween = null
	_intent_marker_by_unit.clear()
	_restore_target_brightness()

func _schedule_intent_marker_refresh() -> void:
	if _intent_refresh_pending:
		return
	_intent_refresh_pending = true
	call_deferred("_update_intent_markers_after_layout")

func _update_intent_markers_after_layout() -> void:
	await get_tree().process_frame
	_intent_refresh_pending = false
	if _intent_preview_active:
		return
	_clear_intent_markers()
	_rebuild_intent_markers(true)

func _rebuild_intent_markers(show_now: bool) -> void:
	for member in _party_units:
		var lock_count: int = _intent_count_for(member)
		if lock_count <= 0 or member.is_dead():
			continue
		var avatar: Control = _find_avatar_for_unit(member)
		if avatar == null:
			continue
		var marker: Control = BattleWidgets.make_intent_marker(avatar, lock_count)
		marker.modulate.a = 1.0 if show_now else 0.0
		_reticle_layer.add_child(marker)
		_intent_marker_by_unit[member] = marker

func _pulse_intent_targets(targets: Array) -> void:
	for target in targets:
		var marker: Control = _intent_marker_by_unit.get(target)
		if marker == null:
			continue
		marker.modulate.a = 1.0
		var pulse := marker.duplicate() as Control
		pulse.set_meta("intent_pulse", true)
		_reticle_layer.add_child(pulse)
		pulse.position = marker.position
		pulse.pivot_offset = pulse.size * 0.5
		pulse.scale = Vector2.ONE
		pulse.modulate.a = 1.0
		var pulse_tween := create_tween()
		pulse_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		pulse_tween.tween_property(pulse, "scale", Vector2.ONE * 0.85, INTENT_PRESS_SECONDS)
		pulse_tween.tween_property(pulse, "scale", Vector2.ONE, INTENT_PRESS_SECONDS)
		pulse_tween.tween_property(pulse, "scale", Vector2.ONE * 1.5, INTENT_PULSE_SECONDS)
		pulse_tween.parallel().tween_property(pulse, "modulate:a", 0.0, INTENT_PULSE_SECONDS)
		pulse_tween.tween_callback(pulse.queue_free)

func _show_all_intent_markers() -> void:
	for marker: Control in _intent_marker_by_unit.values():
		marker.modulate.a = 1.0

func _intent_count_for(unit) -> int:
	var count: int = 0
	for enemy in _enemy_intents:
		if enemy == null or enemy.is_dead():
			continue
		var intent: Dictionary = _enemy_intents[enemy]
		for target in intent.get("targets", []):
			if target == unit:
				count += 1
	return count

func _actor_turn_message(actor) -> String:
	var count: int = _intent_count_for(actor)
	var lock_text: String = "｜敌方锁定 ×%d" % count if count > 0 else ""
	return "✦ %s 行动了——请选择指令%s。" % [actor.display_name, lock_text]

static func calculate_layout(viewport_size: Vector2, expanded: bool) -> Dictionary:
	var ui_scale: float = minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	var stage_left: float = viewport_size.x - 116.0 * ui_scale
	var central_left: float = (6.0 if expanded else 98.0) * ui_scale
	var top: float = (28.0 if expanded else 152.0) * ui_scale
	var bottom: float = (262.0 if expanded else 234.0) * ui_scale
	return {
		"scale": ui_scale,
		"enemy": Rect2(viewport_size.x * 0.5 - 140.0 * ui_scale, 35.0 * ui_scale,
			280.0 * ui_scale, 70.0 * ui_scale),
		"central": Rect2(central_left, top, stage_left - 6.0 * ui_scale - central_left, bottom - top),
		"stage": Rect2(stage_left, top, 92.0 * ui_scale, (262.0 * ui_scale) - top),
		"command": Rect2(98.0 * ui_scale, 240.0 * ui_scale,
			stage_left - 104.0 * ui_scale, 22.0 * ui_scale),
		"party": Rect2(6.0 * ui_scale, 152.0 * ui_scale, 86.0 * ui_scale, 110.0 * ui_scale),
	}

static func calculate_enemy_sprite_size(
		container_size: Vector2,
		enemy_count: int,
		separation: float,
		hud_scale: float) -> int:
	var count: int = maxi(1, enemy_count)
	var available_width: float = (container_size.x - separation * (count - 1)) / count
	return maxi(1, floori(minf(224.0 * hud_scale, minf(container_size.y * 0.88, available_width))))

static func calculate_enemy_vertical_offset(
		index: int,
		enemy_count: int,
		container_height: float,
		sprite_size: int) -> int:
	var travel: int = maxi(0, floori(container_height) - sprite_size)
	if enemy_count <= 2:
		return travel / 2
	var depth: int = mini(index, enemy_count - 1 - index)
	return travel if depth % 2 == 0 else 0

static func calculate_party_avatar_size(
		panel_height: float,
		party_count: int,
		hud_scale: float) -> int:
	var count: int = maxi(1, party_count)
	var separation: float = 12.0 * hud_scale
	var available_height: float = (panel_height - separation * (count - 1)) / count
	return maxi(1, floori(minf(120.0 * hud_scale, available_height)))

static func calculate_target_reticle_size(hud_scale: float) -> int:
	return maxi(1, roundi(TARGET_RETICLE_SIZE_1080P * hud_scale))

static func calculate_target_reticle_position(anchor_rect: Rect2, marker_size: Vector2) -> Vector2:
	var head_center := anchor_rect.position + Vector2(
		anchor_rect.size.x * 0.5, anchor_rect.size.y * TARGET_RETICLE_HEAD_RATIO)
	return head_center - marker_size * 0.5

func _apply_layout() -> void:
	var normal: Dictionary = calculate_layout(get_viewport_rect().size, false)
	var current: Dictionary = calculate_layout(get_viewport_rect().size, _timing_active)
	_central_box.position = current.central.position
	_central_box.size = current.central.size
	_stage_box.position = current.stage.position
	_stage_box.size = current.stage.size
	_command_bar.position = normal.command.position
	_command_bar.size = normal.command.size
	_enemy_container.position = normal.enemy.position
	_enemy_container.size = normal.enemy.size
	_party_panel.position = normal.party.position
	_party_panel.size = normal.party.size
	_hud_scale = normal.scale / BattleWidgets.PIXEL_SCALE
	var enemy_separation: int = roundi(12.0 * normal.scale)
	_enemy_container.add_theme_constant_override("separation", enemy_separation)
	_party_container.add_theme_constant_override("separation", roundi(3.0 * normal.scale))
	_enemy_sprite_size = calculate_enemy_sprite_size(
		_enemy_container.size, _enemy_units.size(), enemy_separation, _hud_scale)
	_party_avatar_size = calculate_party_avatar_size(
		_party_panel.size.y, _party_units.size(), _hud_scale)
	_timing_normal_rect = normal.central
	if not _party_units.is_empty() or not _enemy_units.is_empty():
		_refresh_display()

func _set_timing_layout(expanded: bool) -> void:
	if _timing_tween != null and _timing_tween.is_valid():
		_timing_tween.kill()
	var layout: Dictionary = calculate_layout(get_viewport_rect().size, expanded)
	var target_rect: Rect2 = layout.central
	var stage_rect: Rect2 = layout.stage
	var enemy_alpha: float = 0.15 if expanded else 1.0
	var overlay_alpha: float = 0.0 if expanded else 1.0
	_message_label.visible = false
	_timing_tween = create_tween().set_parallel(true)
	_timing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_timing_tween.tween_property(_central_box, "position", target_rect.position, TIMING_TWEEN_SECONDS)
	_timing_tween.tween_property(_central_box, "size", target_rect.size, TIMING_TWEEN_SECONDS)
	_timing_tween.tween_property(_stage_box, "position", stage_rect.position, TIMING_TWEEN_SECONDS)
	_timing_tween.tween_property(_stage_box, "size", stage_rect.size, TIMING_TWEEN_SECONDS)
	_timing_tween.tween_property(_enemy_container, "modulate:a", enemy_alpha, TIMING_TWEEN_SECONDS)
	_timing_tween.tween_property(_reticle_layer, "modulate:a", overlay_alpha, TIMING_TWEEN_SECONDS)
	_timing_tween.tween_property(_command_bar, "modulate:a", overlay_alpha, TIMING_TWEEN_SECONDS)
	_timing_tween.tween_property(_turn_order_bar, "modulate:a", 1.0, TIMING_TWEEN_SECONDS)
	# 状态列保持原位，由扩张后层级更高的中央框自然覆盖。
	_timing_tween.tween_property(_party_panel, "modulate:a", 1.0, TIMING_TWEEN_SECONDS)
	await _timing_tween.finished

func _build_timing_overlay(attacker: BattleUnit, _target: BattleUnit) -> void:
	_clear_timing_overlay()
	_show_stage_actor(attacker)
	var parts: Dictionary = BattleWidgets.make_timing_overlay()
	_timing_overlay = parts.overlay
	_timing_result_label = parts.result_label
	_central_box.add_child(_timing_overlay)

func _clear_timing_overlay() -> void:
	if is_instance_valid(_timing_overlay):
		_timing_overlay.visible = false
		_timing_overlay.queue_free()
	_timing_overlay = null
	_timing_result_label = null

func _show_stage_actor(unit) -> void:
	for child in _stage_box.get_children():
		_stage_box.remove_child(child)
		child.queue_free()
	if unit != null:
		_stage_box.add_child(BattleWidgets.make_stage_actor(unit, unit.is_player))

func _first_living_party():
	for member in _party_units:
		if not member.is_dead():
			return member
	return null

static func _format_timing_result(target: BattleUnit, result: Dictionary) -> String:
	var outcome_text: String = "失败"
	var hit_count: int = int(result.get("hit_count", 0))
	var success_count: int = int(result.get("success_count", 0))
	var failure_count: int = int(result.get("failure_count", 0))
	if hit_count > 1 and success_count > 0 and failure_count > 0:
		outcome_text = "部分成功 %d/%d" % [success_count, hit_count]
	else:
		match result.get("outcome", DefenseTimingRules.Outcome.FAILURE):
			DefenseTimingRules.Outcome.PERFECT:
				outcome_text = "完美"
			DefenseTimingRules.Outcome.SUCCESS:
				outcome_text = "成功"
	var mp_change: int = result.get("mp_change", 0)
	var mp_text: String = ""
	if mp_change != 0:
		mp_text = "｜MP %+d" % mp_change
	return "%s %s｜%d 伤害%s" % [target.display_name, outcome_text, result.get("damage", 0), mp_text]

func _find_avatar_for_unit(unit) -> Control:
	var pools: Array = [_enemy_container, _party_container]
	for pool in pools:
		var avatar: Control = null
		for node in pool.find_children("*", "Control", true, false):
			if not node.is_queued_for_deletion() \
					and node.has_meta("unit_ref") and node.get_meta("unit_ref") == unit:
				avatar = node
		if avatar != null:
			return avatar
	return null

# ───────────────────────────────────────────── 输入（键盘闭环，沿用旧规则）

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _wheel_active:
		return   # 转盘阶段：输入交给转盘自身处理（仅 Z 定格，X 不响应）
	if _timing_active or _target_confirming or _intent_preview_active:
		return
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
			if _menu_mode in [MENU_MODE_ACTION, MENU_MODE_SKILL, MENU_MODE_ITEM]:
				_build_command_menu()
				_message_label.text = _actor_turn_message(_current_actor)
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
