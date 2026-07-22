extends Node
## 战斗 / 背包 确定性逻辑单元测试（headless，无资产依赖）
## 覆盖：DamageCalculator 公式、EnemyAI 选靶、BattleUnit 钳制、GameData 背包/装备边界。
## 以场景方式运行（自动加载单例须先就绪，故不用 --script SceneTree）：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       res://test/battle_logic_test.tscn
## 退出码 = 失败数（0 = 全通过）。

var _fails: int = 0

const TIMING_RULES := preload("res://scripts/battle/DefenseTimingRules.gd")
const TIMING_CHECK := preload("res://scripts/battle/DefenseTimingCheck.gd")

class FleeBattleController:
	extends Node
	signal timing_submitted(hit_results: Array)
	signal intent_preview_released

	var party: Array = []
	var enemies: Array = []
	var intents: Dictionary = {}
	var freeze_count: int = 0
	var wait_for_timing: bool = false
	var wait_for_intent_preview: bool = false
	var last_frozen_order: Array = []
	var timing_summaries: Array[Dictionary] = []
	var inventory_state := InventoryState.new()

	func get_party_units() -> Array:
		return party

	func get_enemy_units() -> Array:
		return enemies

	func get_all_units() -> Array:
		var units: Array = party.duplicate()
		units.append_array(enemies)
		return units

	func get_inventory_slots() -> Array[InventoryState.Slot]:
		return inventory_state.get_slots()

	func consume_item(item_id: String) -> bool:
		return inventory_state.remove_item(item_id, 1)

	func freeze_enemy_intents(turn_order: Array) -> void:
		freeze_count += 1
		last_frozen_order = turn_order.duplicate()
		if wait_for_intent_preview:
			await intent_preview_released

	func get_enemy_intent(enemy: BattleUnit) -> Dictionary:
		return intents.get(enemy, {}).duplicate(true)

	func run_timing_check(
			_attacker: BattleUnit,
			_target: BattleUnit,
			_base_damage: int,
			_intent: Dictionary = {}) -> Array:
		if wait_for_timing:
			return await timing_submitted
		return [{
			"hit_index": 0,
			"hit_count": 1,
			"contact": true,
			"outcome": DefenseTimingRules.Outcome.FAILURE,
		}]

	func finish_timing_check(_target: BattleUnit, timing_result: Dictionary) -> void:
		timing_summaries.append(timing_result.duplicate(true))

func _ready() -> void:
	_test_damage_calculator()
	_test_enemy_ai_targeting()
	_test_enemy_attack_patterns()
	_test_right_side_attack_origins_and_barrage()
	await _test_round_start_intents()
	_test_enemy_intent_execution()
	_test_battle_unit_clamp()
	_test_stance_lifecycle()
	_test_defense_timing_rules()
	_test_attack_duration_scale()
	_test_impact_camera_feedback()
	_test_battle_hud_frames()
	await _test_turn_arc_bar()
	await _test_reticle_animations()
	await _test_defense_action_field()
	await _test_enemy_damage_waits_for_timing()
	_test_flee_turn_flow()
	_test_inventory()
	_test_equipment_battle_copy()
	_test_battle_session_transactions()
	_test_inventory_pagination()
	_test_inventory_detail_layout()
	print("[test] 结果：%s" % ("全部通过 ✅" if _fails == 0 else "%d 项失败 ❌" % _fails))
	get_tree().quit(_fails)

func _check(label: String, ok: bool) -> void:
	if ok:
		print("[test] ✅ %s" % label)
	else:
		push_error("[test] ❌ %s" % label)
		_fails += 1

func _make_unit(atk: int, def: int, spd: int, hp: int = 100) -> BattleUnit:
	var u := BattleUnit.new()
	u.atk = atk
	u.def = def
	u.spd = spd
	u.hp = hp
	u.max_hp = hp
	return u

func _make_skill(power: int, dmg_type: SkillData.DamageType) -> SkillData:
	var s := SkillData.new()
	s.power = power
	s.damage_type = dmg_type
	s.skill_type = SkillData.SkillType.ATTACK
	return s

func _clear_gamedata_inventory(gd: Node) -> void:
	for slot: InventoryState.Slot in gd.get_inventory_slots():
		gd.remove_item(slot.item.id, slot.count)
	for slot: String in InventoryState.EQUIPMENT_SLOTS:
		gd.unequip_item(slot)

func _test_damage_calculator() -> void:
	var calc := DamageCalculator.new()
	var atk := _make_unit(20, 0, 10)
	var tgt := _make_unit(0, 5, 10)

	# 物理：atk - def，倍率默认 1.0
	_check("calc_physical 20atk-5def = 15", calc.calc_physical(atk, tgt) == 15)

	# 力度倍率 1.5×：round((20-5)*1.5)=round(22.5)=23（half away from zero）
	atk.power_multiplier = 1.5
	_check("calc_physical ×1.5 = 23", calc.calc_physical(atk, tgt) == 23)
	atk.power_multiplier = 1.0

	# 下限保护：净值<=0 仍至少 1 点
	var weak := _make_unit(1, 0, 10)
	var tank := _make_unit(0, 99, 10)
	_check("calc_physical 下限保 1", calc.calc_physical(weak, tank) == 1)

	# 技能物理：atk + power - def
	var skill := _make_skill(10, SkillData.DamageType.PHYSICAL)
	_check("calc_skill 物理 20+10-5 = 25", calc.calc_skill(atk, tgt, skill) == 25)

	# 技能魔法：atk + power - def/2
	var mskill := _make_skill(10, SkillData.DamageType.MAGIC)
	_check("calc_skill 魔法 20+10-5/2 = 28", calc.calc_skill(atk, tgt, mskill) == 28)

func _test_enemy_ai_targeting() -> void:
	var enemy := _make_unit(10, 0, 5)
	enemy.ai_type = EnemyStats.AIType.HUNTER
	var hi := _make_unit(0, 0, 5, 30)
	hi.display_name = "高血"
	var lo := _make_unit(0, 0, 5, 10)
	lo.display_name = "低血"

	# 猎手攻击 HP 最低者
	var res := EnemyAI.decide_action(enemy, [hi, lo])
	_check("hunter 指令 = attack", res.command == BattleCommands.ATTACK)
	_check("hunter 选 HP 最低目标", res.target == lo)

	# 全员阵亡时 target = null，不崩
	hi.hp = 0
	lo.hp = 0
	var res2 := EnemyAI.decide_action(enemy, [hi, lo])
	_check("全灭时 target = null", res2.target == null)

func _test_enemy_attack_patterns() -> void:
	seed(20260718)
	var target := _make_unit(0, 0, 5)
	var enemy := _make_unit(10, 0, 5)
	var hunter_patterns: Dictionary = {}
	var hunter_barrage_subtypes: Dictionary = {}
	var burner_patterns: Dictionary = {}
	var mutant_patterns: Dictionary = {}
	var params_valid: bool = true
	for _sample in range(80):
		enemy.ai_type = EnemyStats.AIType.HUNTER
		var hunter_intent: Dictionary = EnemyAI.decide_intent(enemy, [target])
		hunter_patterns[hunter_intent.attack_pattern] = true
		if hunter_intent.attack_pattern == EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE:
			hunter_barrage_subtypes[hunter_intent.pattern_params.subtype] = true
		params_valid = params_valid and _attack_pattern_params_valid(hunter_intent)
		enemy.ai_type = EnemyStats.AIType.BURNER
		var burner_intent: Dictionary = EnemyAI.decide_intent(enemy, [target])
		burner_patterns[burner_intent.attack_pattern] = true
		params_valid = params_valid and _attack_pattern_params_valid(burner_intent)
		enemy.ai_type = EnemyStats.AIType.MUTANT
		var mutant_intent: Dictionary = EnemyAI.decide_intent(enemy, [target])
		mutant_patterns[mutant_intent.attack_pattern] = true
		params_valid = params_valid and _attack_pattern_params_valid(mutant_intent)
	_check("猎手随机覆盖三套固定攻击流程", hunter_patterns.size() == 3
		and hunter_patterns.has(EnemyAI.PATTERN_HUNTER_LOCK_THRUST)
		and hunter_patterns.has(EnemyAI.PATTERN_HUNTER_CROSS_THRUST)
		and hunter_patterns.has(EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE))
	_check("慢速弹幕随机覆盖直线与伪蒙特卡洛子类型",
		hunter_barrage_subtypes.size() == 2
		and hunter_barrage_subtypes.has(EnemyAI.BARRAGE_STRAIGHT)
		and hunter_barrage_subtypes.has(EnemyAI.BARRAGE_MONTE_CARLO))
	_check("燃烬者随机覆盖两套固定区域攻击流程", burner_patterns.size() == 2
		and burner_patterns.has(EnemyAI.PATTERN_BURNER_ERUPTION)
		and burner_patterns.has(EnemyAI.PATTERN_BURNER_SCORCH_FIELD))
	_check("变异体随机覆盖两套固定攻击流程", mutant_patterns.size() == 2
		and mutant_patterns.has(EnemyAI.PATTERN_MUTANT_SWEEP)
		and mutant_patterns.has(EnemyAI.PATTERN_MUTANT_CLEAVE))
	_check("攻击流程随机参数始终在设计范围内", params_valid)

func _attack_pattern_params_valid(intent: Dictionary) -> bool:
	var params: Dictionary = intent.pattern_params
	match intent.attack_pattern:
		EnemyAI.PATTERN_HUNTER_LOCK_THRUST:
			return params.hit_count in [2, 3] \
				and params.telegraph >= 0.45 and params.telegraph <= 0.75 \
				and params.active >= 0.16 and params.active <= 0.24 \
				and params.gap >= 0.12 and params.gap <= 0.22 \
				and params.width >= 42.0 and params.width <= 56.0 \
				and params.aim_offset.length() <= 48.01
		EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
			return params.hit_count == 2 \
				and params.angle_degrees >= 20.0 and params.angle_degrees <= 35.0 \
				and params.stagger >= 0.16 and params.stagger <= 0.30 \
				and params.telegraph >= 0.65 and params.telegraph <= 0.95 \
				and params.active >= 0.25 and params.active <= 0.40 \
				and params.width >= 38.0 and params.width <= 52.0
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE:
			return params.hit_count == 3 \
				and params.subtype in [EnemyAI.BARRAGE_STRAIGHT, EnemyAI.BARRAGE_MONTE_CARLO] \
				and params.seed is int and params.bullet_count == 36 \
				and params.bullet_speed == 240.0 and params.bullet_radius == 8.0 \
				and params.spawn_interval == 0.10 and params.wander_interval == 0.22 \
				and params.wander_vertical_speed == 110.0 \
				and params.telegraph == 0.45 and params.active == 5.2 and params.gap == 0.25
		EnemyAI.PATTERN_BURNER_ERUPTION:
			return params.hit_count in [2, 3] \
				and params.telegraph >= 0.50 and params.telegraph <= 0.72 \
				and params.active >= 0.28 and params.active <= 0.40 \
				and params.gap >= 0.15 and params.gap <= 0.25 \
				and params.radius >= 88.0 and params.radius <= 122.0 \
				and params.aim_offset.length() <= 80.01 \
				and params.rotation_degrees >= 95.0 and params.rotation_degrees <= 135.0
		EnemyAI.PATTERN_BURNER_SCORCH_FIELD:
			return params.hit_count == 2 and params.start_side in [-1, 1] \
				and params.telegraph >= 0.70 and params.telegraph <= 0.95 \
				and params.active >= 0.40 and params.active <= 0.58 \
				and params.gap >= 0.18 and params.gap <= 0.28 \
				and params.radius >= 180.0 and params.radius <= 240.0 \
				and params.center_offset >= 90.0 and params.center_offset <= 140.0 \
				and params.vertical_offset >= -48.0 and params.vertical_offset <= 48.0
		EnemyAI.PATTERN_MUTANT_SWEEP:
			return params.hit_count == 2 and params.clockwise is bool \
				and params.telegraph >= 0.80 and params.telegraph <= 1.15 \
				and params.active >= 0.50 and params.active <= 0.75 \
				and params.gap >= 0.18 and params.gap <= 0.35 \
				and params.arc_degrees >= 100.0 and params.arc_degrees <= 140.0 \
				and params.width >= 72.0 and params.width <= 96.0
		EnemyAI.PATTERN_MUTANT_CLEAVE:
			return params.hit_count == 3 \
				and params.offset_x >= -120.0 and params.offset_x <= 120.0 \
				and params.telegraph >= 1.0 and params.telegraph <= 1.4 \
				and params.active >= 0.25 and params.active <= 0.40 \
				and params.aftershock_delay >= 0.18 and params.aftershock_delay <= 0.35 \
				and params.width >= 84.0 and params.width <= 116.0 \
				and params.aftershock_spacing >= 100.0 and params.aftershock_spacing <= 160.0
		_:
			return false

func _test_right_side_attack_origins_and_barrage() -> void:
	var arena := Rect2(48.0, 176.0, 864.0, 236.0)
	var player := arena.get_center() + Vector2(0.0, arena.size.y * 0.24)
	var origin := Vector2(arena.end.x - TIMING_CHECK.ENEMY_ORIGIN_INSET, arena.get_center().y)
	var patterns: Array = [
		[EnemyAI.PATTERN_HUNTER_LOCK_THRUST, {"hit_count": 2}],
		[EnemyAI.PATTERN_HUNTER_CROSS_THRUST, {"hit_count": 2}],
		[EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE, {"subtype": EnemyAI.BARRAGE_STRAIGHT}],
		[EnemyAI.PATTERN_BURNER_ERUPTION, {"hit_count": 2}],
		[EnemyAI.PATTERN_BURNER_SCORCH_FIELD, {"hit_count": 2}],
		[EnemyAI.PATTERN_MUTANT_SWEEP, {"hit_count": 2}],
		[EnemyAI.PATTERN_MUTANT_CLEAVE, {"hit_count": 3}],
		[EnemyAI.PATTERN_FALLBACK_THRUST, {}],
	]
	var all_from_right: bool = true
	for entry: Array in patterns:
		var stages: Array[Dictionary] = DefenseAttackPatterns.build(
			entry[0], entry[1], arena, player, origin)
		for stage: Dictionary in stages:
			all_from_right = all_from_right and Vector2(stage.origin) == origin
	_check("全部敌方攻击阶段共享右侧判定点", all_from_right)

	var straight := TIMING_CHECK.new()
	add_child(straight)
	straight.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE, {
			"subtype": EnemyAI.BARRAGE_STRAIGHT, "seed": 71,
			"bullet_count": 36, "hit_count": 3,
		})
	var child_count: int = straight.get_child_count()
	straight._advance_phase()
	_check("慢速弹幕可从预警态无错切入活跃态",
		straight._phase == straight.Phase.ACTIVE)
	straight._phase_elapsed = 0.21
	straight._update_barrage(0.01)
	var straight_leftward: bool = true
	for index in range(straight._bullets_spawned):
		straight_leftward = straight_leftward and straight._bullet_velocities[index].x < 0.0
	_check("直线慢速弹幕按 36 发上限复用紧凑数组且全部向左",
		straight._bullet_positions.size() == 36 and straight._bullets_spawned == 3
		and straight_leftward and straight.get_child_count() == child_count)
	straight._finish_barrage_results()
	_check("弹幕无接触时仍固定回传三个伤害槽",
		straight._hit_results.size() == 3
		and straight._hit_results.all(func(result): return not result.contact))
	straight.free()

	var random_a := TIMING_CHECK.new()
	var random_b := TIMING_CHECK.new()
	add_child(random_a)
	add_child(random_b)
	var random_params := {
		"subtype": EnemyAI.BARRAGE_MONTE_CARLO, "seed": 20260718,
		"bullet_count": 36, "hit_count": 3,
	}
	random_a.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE, random_params)
	random_b.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE, random_params)
	for timing in [random_a, random_b]:
		timing._phase = timing.Phase.ACTIVE
		timing._phase_elapsed = 0.41
		timing._update_barrage(0.23)
	_check("相同种子的伪蒙特卡洛弹幕可复现且保持左移",
		random_a._bullet_positions == random_b._bullet_positions
		and random_a._bullet_velocities == random_b._bullet_velocities
		and random_a._bullet_velocities[0].x < 0.0
		and not is_equal_approx(
			TIMING_CHECK.barrage_vertical_speed(20260718, 0, 0, 110.0),
			TIMING_CHECK.barrage_vertical_speed(20260718, 0, 1, 110.0)))
	_check("慢速弹幕使用扫掠圆判定避免大 delta 穿透",
		TIMING_CHECK.swept_circle_hits(
			Vector2(100.0, 0.0), Vector2(-100.0, 0.0), Vector2.ZERO, 18.0))
	random_a._barrage_results_recorded = 0
	random_a._hit_results.clear()
	for _contact in range(4):
		random_a._resolve_barrage_contact()
	_check("大量视觉弹幕最多结算三个伤害槽", random_a._hit_results.size() == 3)

	var dodge := TIMING_CHECK.new()
	add_child(dodge)
	dodge.start(BattleUnit.Stance.DODGE, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE, random_params)
	dodge._total_elapsed = 1.0
	dodge._reaction_started_at = 1.0
	for _contact in range(4):
		dodge._resolve_barrage_contact()
	dodge._impact_particles.emitting = false
	dodge._total_elapsed = 2.0
	dodge._reaction_started_at = -1.0
	dodge._resolve_barrage_contact()
	_check("多次成功闪避后碰撞仍触发受击判定与粒子",
		dodge._hit_results.any(func(result):
			return result.outcome == DefenseTimingRules.Outcome.FAILURE)
		and dodge._impact_particles.emitting)
	dodge.free()
	random_a.free()
	random_b.free()

func _test_round_start_intents() -> void:
	var controller := FleeBattleController.new()
	var party := _make_unit(10, 5, 8)
	party.is_player = true
	var enemy := _make_unit(10, 5, 9)
	enemy.is_player = false
	controller.party = [party]
	controller.enemies = [enemy]
	controller.wait_for_intent_preview = true
	add_child(controller)
	var macro_sm := BattleStateMachine.new()
	macro_sm.setup(controller)
	add_child(macro_sm)
	macro_sm.start_battle()
	_check("RoundStart 先计算行动顺序再冻结敌方意图",
		controller.freeze_count == 1 and controller.last_frozen_order == [enemy, party])
	_check("红环预告完成前保持 ROUND_START",
		macro_sm.current_state == BattleStateMachine.MacroState.ROUND_START)
	controller.wait_for_intent_preview = false
	controller.intent_preview_released.emit()
	await get_tree().process_frame
	_check("红环预告完成后才进入 TURN_LOOP",
		macro_sm.current_state == BattleStateMachine.MacroState.TURN_LOOP)
	macro_sm.request_next_turn()
	_check("下一 RoundStart 重新冻结一次意图", controller.freeze_count == 2)
	macro_sm.free()
	controller.free()

func _test_enemy_intent_execution() -> void:
	var enemy := _make_unit(20, 0, 10)
	enemy.is_player = false
	enemy.ai_type = EnemyStats.AIType.HUNTER
	var frozen_target := _make_unit(0, 5, 8, 10)
	var other_target := _make_unit(0, 5, 7, 30)
	var intent: Dictionary = EnemyAI.decide_intent(enemy, [other_target, frozen_target])
	_check("敌方意图包含锁定字段", intent.actor == enemy
		and intent.command == BattleCommands.ATTACK
		and intent.target_side == EnemyAI.TARGET_SIDE_PARTY
		and intent.target_mode == EnemyAI.TARGET_MODE_SINGLE
		and intent.targets == [frozen_target])

	# 冻结后即使血量条件变化，意图仍指向 RoundStart 选中的对象。
	frozen_target.hp = 0
	other_target.hp = 1
	_check("冻结意图不随世界状态重选目标", intent.targets[0] == frozen_target)
	var controller := FleeBattleController.new()
	controller.party = [frozen_target, other_target]
	controller.enemies = [enemy]
	controller.intents[enemy] = intent
	add_child(controller)
	var micro_sm := TurnStateMachine.new()
	micro_sm.battle_controller = controller
	micro_sm.damage_calculator = DamageCalculator.new()
	add_child(micro_sm)
	var results: Array = []
	micro_sm.action_executed.connect(func(result: Dictionary): results.append(result))
	micro_sm.start_turn(enemy)
	_check("失效单体目标不重定向", other_target.hp == 1 and results[0].targets.is_empty())

	var living_target := _make_unit(0, 5, 6, 30)
	var dead_target := _make_unit(0, 5, 5, 30)
	dead_target.hp = 0
	controller.party = [living_target, dead_target]
	controller.intents[enemy] = {
		"actor": enemy,
		"command": BattleCommands.ATTACK,
		"skill": null,
		"target_side": EnemyAI.TARGET_SIDE_PARTY,
		"target_mode": EnemyAI.TARGET_MODE_ALL,
		"targets": [living_target, dead_target],
	}
	micro_sm.start_turn(enemy)
	_check("全体行动只结算存活目标", living_target.hp == 15 and dead_target.hp == 0
		and results[1].targets == [living_target])
	micro_sm.free()
	controller.free()

func _test_battle_unit_clamp() -> void:
	var u := _make_unit(0, 0, 5, 50)
	u.take_damage(80)
	_check("take_damage 不低于 0", u.hp == 0)
	u.heal(999)
	_check("heal 不超过 max_hp", u.hp == 50)

func _test_stance_lifecycle() -> void:
	var actor := _make_unit(0, 0, 10)
	actor.is_player = true
	var sm := TurnStateMachine.new()
	add_child(sm)
	sm.start_turn(actor)
	sm.select_command(BattleCommands.DEFEND)
	_check("选择防御后姿态持续", actor.pending_stance == BattleUnit.Stance.DEFEND)
	sm.start_turn(actor)
	_check("下一次行动开始重置防御姿态", actor.pending_stance == BattleUnit.Stance.ATTACK)
	sm.select_command(BattleCommands.DODGE)
	_check("选择闪避后姿态持续", actor.pending_stance == BattleUnit.Stance.DODGE)
	sm.start_turn(actor)
	_check("下一次行动开始重置闪避姿态", actor.pending_stance == BattleUnit.Stance.ATTACK)
	sm.free()

func _test_defense_timing_rules() -> void:
	var defend_perfect: Dictionary = TIMING_RULES.evaluate_outcome(
		BattleUnit.Stance.DEFEND, TIMING_RULES.Outcome.PERFECT, 10, 5, 100)
	var defend_success: Dictionary = TIMING_RULES.evaluate_outcome(
		BattleUnit.Stance.DEFEND, TIMING_RULES.Outcome.SUCCESS, 4, 5, 100)
	var defend_low_mp: Dictionary = TIMING_RULES.evaluate_outcome(
		BattleUnit.Stance.DEFEND, TIMING_RULES.Outcome.SUCCESS, 10, 1, 100)
	var defend_fail: Dictionary = TIMING_RULES.evaluate_outcome(
		BattleUnit.Stance.DEFEND, TIMING_RULES.Outcome.FAILURE, 10, 5, 100)
	_check("完美防御零伤害零 MP", defend_perfect.damage == 0 and defend_perfect.mp_change == 0)
	_check("普通防御向上取整并最多消耗 2 MP", defend_success.damage == 2 and defend_success.mp_change == -2)
	_check("普通防御 MP 不足时只扣现有值", defend_low_mp.damage == 4 and defend_low_mp.mp_change == -1)
	_check("防御失败承受完整伤害", defend_fail.damage == 10 and defend_fail.mp_change == 0)

	var dodge_perfect: Dictionary = TIMING_RULES.evaluate_outcome(
		BattleUnit.Stance.DODGE, TIMING_RULES.Outcome.PERFECT, 10, 9, 10)
	var dodge_success: Dictionary = TIMING_RULES.evaluate_outcome(
		BattleUnit.Stance.DODGE, TIMING_RULES.Outcome.SUCCESS, 10, 0, 10)
	var dodge_fail: Dictionary = TIMING_RULES.evaluate_outcome(
		BattleUnit.Stance.DODGE, TIMING_RULES.Outcome.FAILURE, 10, 0, 10)
	_check("完美闪避零伤害且 MP 回复不越上限", dodge_perfect.damage == 0 and dodge_perfect.mp_change == 1)
	_check("普通闪避零伤害不回复 MP", dodge_success.damage == 0 and dodge_success.mp_change == 0)
	_check("闪避失败承受完整伤害", dodge_fail.damage == 10)

	var repeated_target := _make_unit(0, 0, 5, 20)
	repeated_target.mp = 3
	repeated_target.max_mp = 100
	for _hit in range(2):
		var hit: Dictionary = TIMING_RULES.evaluate_outcome(
			BattleUnit.Stance.DEFEND, TIMING_RULES.Outcome.SUCCESS,
			4, repeated_target.mp, repeated_target.max_mp)
		TIMING_RULES.apply(repeated_target, hit)
	_check("连续受击逐次结算同一姿态", repeated_target.hp == 16 and repeated_target.mp == 0)

func _test_defense_action_field() -> void:
	_check("弹反按下后 0.05s 内为完美", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DEFEND, 0.05) == TIMING_RULES.Outcome.PERFECT)
	_check("弹反 0.25s 内为普通成功", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DEFEND, 0.20) == TIMING_RULES.Outcome.SUCCESS)
	_check("弹反超时后失败", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DEFEND, 0.26) == TIMING_RULES.Outcome.FAILURE)
	_check("弹反窗口边界外立即失败", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DEFEND, 0.2501) == TIMING_RULES.Outcome.FAILURE)
	_check("冲刺前 0.05s 内为完美闪避", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DODGE, 0.04) == TIMING_RULES.Outcome.PERFECT)
	_check("冲刺 0.20s 内为普通闪避", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DODGE, 0.18) == TIMING_RULES.Outcome.SUCCESS)
	_check("输入时间估算最多回溯一个物理帧", is_equal_approx(
		TIMING_CHECK.estimate_input_time(1.0, 50_000, 1.0 / 60.0), 1.0 + 1.0 / 60.0))
	var parry := TIMING_CHECK.new()
	add_child(parry)
	parry.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540))
	var parry_event := InputEventKey.new()
	parry_event.keycode = KEY_Z
	parry_event.pressed = true
	parry._input(parry_event)
	var parry_started_at: float = parry._reaction_started_at
	parry._total_elapsed = parry_started_at
	var parry_position: Vector2 = parry._player_position
	Input.action_press("move_right")
	parry._move_player(0.05)
	Input.action_release("move_right")
	_check("Z 走真实输入路径开启弹反并冻结移动", parry_started_at >= 0.0
		and parry_started_at <= parry._last_physics_delta
		and parry._player_position == parry_position)
	parry.free()

	var dodge := TIMING_CHECK.new()
	add_child(dodge)
	dodge.start(BattleUnit.Stance.DODGE, Rect2(0, 0, 960, 540))
	var dodge_event := InputEventKey.new()
	dodge_event.keycode = KEY_SHIFT
	dodge_event.physical_keycode = KEY_SHIFT
	dodge_event.pressed = true
	Input.action_press("move_right")
	var dodge_position: Vector2 = dodge._player_position
	dodge._input(dodge_event)
	dodge._total_elapsed = dodge._reaction_started_at
	dodge._move_player(0.05)
	Input.action_release("move_right")
	_check("Shift+方向走真实输入路径产生冲刺位移", dodge._reaction_started_at >= 0.0
		and dodge._reaction_started_at <= dodge._last_physics_delta
		and dodge._player_position.x - dodge_position.x > TIMING_CHECK.MOVE_SPEED * 0.05)
	dodge.free()

	var buffered := TIMING_CHECK.new()
	add_child(buffered)
	buffered.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540))
	buffered._hit_stop_remaining = 0.05
	buffered._input(parry_event)
	var buffered_during_stop: bool = buffered._reaction_started_at < 0.0 \
		and buffered._buffered_action == TIMING_CHECK.PARRY_ACTION
	buffered._physics_process(0.06)
	_check("受击停顿期间的 Z 在解锁后立即执行", buffered_during_stop
		and is_equal_approx(buffered._reaction_started_at, 0.0))
	buffered._total_elapsed = 0.20
	buffered._input(parry_event)
	buffered._physics_process(0.05)
	_check("弹反结束前 0.10s 内的再次输入会衔接下一次弹反",
		is_equal_approx(buffered._reaction_started_at, 0.25))
	buffered.free()

	var paused_buffer := TIMING_CHECK.new()
	add_child(paused_buffer)
	paused_buffer.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540))
	paused_buffer.set_physics_process(false)
	paused_buffer._hit_stop_remaining = 0.20
	paused_buffer._input(parry_event)
	await get_tree().create_timer(TIMING_CHECK.INPUT_BUFFER_SECONDS + 0.02).timeout
	paused_buffer._hit_stop_remaining = 0.0
	paused_buffer._try_consume_reaction_buffer()
	_check("污染兽受击停顿不消耗动作场输入缓冲",
		is_equal_approx(paused_buffer._total_elapsed, 0.0)
		and is_equal_approx(paused_buffer._reaction_started_at, 0.0))
	paused_buffer.free()

	var expired := TIMING_CHECK.new()
	add_child(expired)
	expired.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540))
	expired._buffer_reaction(TIMING_CHECK.PARRY_ACTION, Vector2.DOWN)
	expired._buffered_until_elapsed = expired._total_elapsed - 0.01
	expired._try_consume_reaction_buffer()
	_check("过期输入缓冲不会触发动作", expired._reaction_started_at < 0.0
		and expired._buffered_action == &"")
	expired.free()

	var fallback_dodge := TIMING_CHECK.new()
	add_child(fallback_dodge)
	fallback_dodge.start(BattleUnit.Stance.DODGE, Rect2(0, 0, 960, 540))
	fallback_dodge._last_direction = Vector2.RIGHT
	var fallback_position: Vector2 = fallback_dodge._player_position
	fallback_dodge._input(dodge_event)
	fallback_dodge._total_elapsed = fallback_dodge._reaction_started_at
	fallback_dodge._move_player(0.05)
	_check("Shift 无当前方向时沿最近方向冲刺",
		fallback_dodge._player_position.x - fallback_position.x > TIMING_CHECK.MOVE_SPEED * 0.05)
	fallback_dodge.free()

	var area := TIMING_CHECK.new()
	add_child(area)
	area.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_BURNER_ERUPTION, {
			"hit_count": 2, "telegraph": 0.5, "active": 0.3, "gap": 0.2,
			"radius": 104.0, "aim_offset": Vector2.ZERO,
		})
	area.set_physics_process(false)
	await get_tree().physics_frame
	area._physics_process(0.52 * TIMING_CHECK.ACTION_DURATION_SCALE)
	_check("区域攻击使用圆形物理遮罩并覆盖预警区域",
		area._hazard_shape is CircleShape2D and not area._hit_results.is_empty()
		and area._hit_results[0].contact)
	area.queue_free()

	var field := TIMING_CHECK.new()
	add_child(field)
	field.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_BURNER_SCORCH_FIELD, {
			"hit_count": 2, "radius": 210.0, "center_offset": 112.0,
			"vertical_offset": 24.0, "start_side": -1,
		})
	_check("焦土围猎生成对侧双区域固定流程", field._stages.size() == 2
		and float(field._stages[0].center.x) < field._player_position.x
		and float(field._stages[1].center.x) > field._player_position.x)
	field.queue_free()

	var sweep := TIMING_CHECK.new()
	add_child(sweep)
	sweep.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_MUTANT_SWEEP, {
			"hit_count": 2, "telegraph": 0.8, "active": 0.5, "gap": 0.2,
			"arc_degrees": 140.0, "width": 56.0, "clockwise": true,
		})
	sweep.set_physics_process(false)
	await get_tree().physics_frame
	sweep._physics_process(1.3 * TIMING_CHECK.ACTION_DURATION_SCALE)
	_check("横扫在大 delta 下仍命中经过的玩家", not sweep._hit_results.is_empty()
		and sweep._hit_results[0].contact)
	sweep.queue_free()

	var sweep_parry := TIMING_CHECK.new()
	add_child(sweep_parry)
	sweep_parry.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_MUTANT_SWEEP, {
			"hit_count": 2, "telegraph": 0.8, "active": 0.5, "gap": 0.2,
			"arc_degrees": 140.0, "width": 56.0, "clockwise": true,
		})
	sweep_parry.set_physics_process(false)
	sweep_parry._reaction_started_at = 0.0
	sweep_parry._reaction_ends_at = TIMING_CHECK.PARRY_DURATION
	sweep_parry._total_elapsed = 0.12
	sweep_parry._resolve_contact()
	_check("污染兽横扫接触时有效弹反稳定判定成功",
		sweep_parry._hit_results.size() == 1
		and sweep_parry._hit_results[0].contact
		and sweep_parry._hit_results[0].outcome == TIMING_RULES.Outcome.SUCCESS)
	sweep_parry.free()

	var timing := TIMING_CHECK.new()
	add_child(timing)
	var action_results: Array = []
	timing.timing_resolved.connect(func(results: Array): action_results.assign(results))
	timing.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_MUTANT_CLEAVE, {"hit_count": 3})
	_check("重劈流程生成主劈与两段余震", timing._stages.size() == 3)
	await get_tree().physics_frame
	# 攻击姿态不会因首段失败提前结束，用不同 delta 验证流程不依赖 60 tick。
	timing._stance = BattleUnit.Stance.ATTACK
	for delta in [0.11, 0.07, 0.19, 0.13, 0.23, 0.17, 0.29, 0.31, 0.37, 0.41, 0.43, 0.47, 0.53, 0.59]:
		if is_instance_valid(timing) and timing._running:
			timing._physics_process(delta)
	while is_instance_valid(timing) and timing._running:
		timing._physics_process(0.37)
	await get_tree().process_frame
	_check("秒制动作场完整回传三段重劈结果", action_results.size() == 3
		and action_results[0].contact)

func _test_attack_duration_scale() -> void:
	var timing := TIMING_CHECK.new()
	add_child(timing)
	timing.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_FALLBACK_THRUST, {"telegraph": 0.8, "active": 0.4})
	var stage: Dictionary = timing._stages[0]
	var raw_total: float = float(stage.telegraph) + float(stage.active) + float(stage.gap)
	var scaled_total: float = 0.0
	for phase in [timing.Phase.TELEGRAPH, timing.Phase.ACTIVE, timing.Phase.GAP]:
		timing._phase = phase
		scaled_total += timing._phase_duration()
	timing._phase = timing.Phase.ACTIVE
	timing._phase_elapsed = timing._phase_duration() * 0.5
	timing._update_active_hazard()
	_check("攻击总演出延长至 1.5 倍且轨迹同步减速",
		is_equal_approx(scaled_total, raw_total * 1.5)
		and is_equal_approx(timing._active_progress, 0.5))
	timing.free()

func _test_impact_camera_feedback() -> void:
	var battle_scene: Node = load("res://scenes/Battle.tscn").instantiate()
	_check("战斗场接入 Phantom Camera 噪声链",
		ProjectSettings.has_setting("autoload/PhantomCameraManager")
		and battle_scene.get_node_or_null("BattleCamera/PhantomCameraHost") != null
		and battle_scene.get_node_or_null("BattlePCam") != null
		and battle_scene.get_node_or_null("UI/BattleUI/ImpactCameraNoise") != null)
	battle_scene.free()

	var timing := TIMING_CHECK.new()
	add_child(timing)
	var feedback_amplitudes: Array[float] = []
	if timing.has_signal("impact_feedback"):
		timing.connect("impact_feedback", func(amplitude: float): feedback_amplitudes.append(amplitude))
	timing.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540))
	timing._resolve_contact()
	var elapsed_before: float = timing._total_elapsed
	timing._physics_process(0.02)
	var failure_paused: bool = is_equal_approx(timing._total_elapsed, elapsed_before)
	timing.free()

	var parry := TIMING_CHECK.new()
	add_child(parry)
	parry.impact_feedback.connect(func(amplitude: float): feedback_amplitudes.append(amplitude))
	parry.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540))
	parry._reaction_started_at = parry._total_elapsed
	parry._resolve_contact()
	_check("受击与完美弹反触发分级镜头反馈和局部停顿",
		failure_paused and feedback_amplitudes == [12.0, 16.0]
		and is_equal_approx(parry._hit_stop_remaining, TIMING_CHECK.HIT_STOP_PARRY))
	parry.free()

func _test_battle_hud_frames() -> void:
	var battle_scene: Node = load("res://scenes/Battle.tscn").instantiate()
	var ui: Control = battle_scene.get_node("UI/BattleUI")
	var central: NinePatchRect = ui.get_node("CentralBox")
	var stage: NinePatchRect = ui.get_node("StageBox")
	var message: Label = central.get_node("MessageLabel")
	var party_panel: NinePatchRect = ui.get_node("PartyPanel")
	_check("StageBox 是中央框右侧的同级框",
		stage.get_parent() == central.get_parent() and stage.texture == central.texture)
	_check("我方状态列保留布局锚点但移除大外框", party_panel.texture == null)
	_check("中央战况文字固定左上并限制三行",
		message.vertical_alignment == VERTICAL_ALIGNMENT_TOP
		and message.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT
		and message.max_lines_visible == 3)
	var normal: Dictionary = BattleUI.calculate_layout(Vector2(1920, 1080), false)
	var expanded: Dictionary = BattleUI.calculate_layout(Vector2(1920, 1080), true)
	_check("常态双框与命令栏符合 480×270 基准",
		normal.central == Rect2(392, 608, 1040, 328)
		and normal.stage == Rect2(1456, 608, 368, 440)
		and normal.command == Rect2(392, 960, 1040, 88)
		and normal.enemy == Rect2(400, 140, 1120, 280))
	_check("演出态中央框覆盖状态列并止于右侧框",
		expanded.central == Rect2(24, 112, 1408, 936)
		and expanded.stage == Rect2(1456, 112, 368, 936)
		and expanded.central.intersects(expanded.party)
		and is_equal_approx(expanded.stage.position.x - expanded.central.end.x, 24.0))
	_check("敌方立绘按容器高度、均分宽度和上限自适应",
		BattleUI.calculate_enemy_sprite_size(normal.enemy.size, 1, 48.0, 1.0) == 224
		and BattleUI.calculate_enemy_sprite_size(normal.enemy.size, 2, 48.0, 1.0) == 224
		and BattleUI.calculate_enemy_sprite_size(normal.enemy.size, 4, 48.0, 1.0) == 224
		and BattleUI.calculate_enemy_sprite_size(normal.enemy.size, 5, 48.0, 1.0) == 185
		and BattleUI.calculate_enemy_sprite_size(Vector2(746.6667, 186.6667), 4, 32.0, 2.0 / 3.0) == 149)
	_check("敌方槽位按 M 形上下错落且单双数对称",
		BattleUI.calculate_enemy_vertical_offset(0, 1, 280.0, 224) == 28
		and BattleUI.calculate_enemy_vertical_offset(0, 2, 280.0, 224) == 28
		and BattleUI.calculate_enemy_vertical_offset(1, 2, 280.0, 224) == 28
		and BattleUI.calculate_enemy_vertical_offset(0, 3, 280.0, 224) == 56
		and BattleUI.calculate_enemy_vertical_offset(1, 3, 280.0, 224) == 0
		and BattleUI.calculate_enemy_vertical_offset(2, 3, 280.0, 224) == 56
		and BattleUI.calculate_enemy_vertical_offset(0, 4, 280.0, 224) == 56
		and BattleUI.calculate_enemy_vertical_offset(1, 4, 280.0, 224) == 0
		and BattleUI.calculate_enemy_vertical_offset(2, 4, 280.0, 224) == 0
		and BattleUI.calculate_enemy_vertical_offset(3, 4, 280.0, 224) == 56
		and BattleUI.calculate_enemy_vertical_offset(0, 5, 280.0, 185) == 95
		and BattleUI.calculate_enemy_vertical_offset(1, 5, 280.0, 185) == 0
		and BattleUI.calculate_enemy_vertical_offset(2, 5, 280.0, 185) == 95
		and BattleUI.calculate_enemy_vertical_offset(3, 5, 280.0, 185) == 0
		and BattleUI.calculate_enemy_vertical_offset(4, 5, 280.0, 185) == 95)
	_check("队伍头像在 1080p 与 720p 下按人数缩放且不越界",
		BattleUI.calculate_party_avatar_size(normal.party.size.y, 1, 1.0) == 120
		and BattleUI.calculate_party_avatar_size(normal.party.size.y, 3, 1.0) == 120
		and BattleUI.calculate_party_avatar_size(normal.party.size.y, 4, 1.0) == 101
		and BattleUI.calculate_party_avatar_size(293.3333, 4, 2.0 / 3.0) == 67)
	battle_scene.free()

	var party := _make_unit(10, 5, 8)
	party.is_player = true
	party.mp = 20
	party.max_mp = 40
	var inactive_card: Control = BattleWidgets.make_unit_card(party, true, false, 120, 1.0)
	var active_card: Control = BattleWidgets.make_unit_card(party, true, true, 120, 1.0)
	var inactive_avatar: Control = inactive_card.get_child(0)
	var active_avatar: Control = active_card.get_child(0)
	var inactive_visual: Control = inactive_avatar.get_child(1)
	var outline: Panel = active_avatar.get_child(active_avatar.get_child_count() - 1)
	var outline_style := outline.get_theme_stylebox("panel") as StyleBoxFlat
	_check("角色卡只保留圆形头像与 HP/MP 状态条",
		inactive_card.get_child_count() == 2
		and inactive_card.get_child(1).get_child_count() == 2
		and inactive_visual.get_child(0).material is ShaderMaterial)
	_check("当前行动角色保持行高并使用圆形金色粗框",
		active_avatar.custom_minimum_size == inactive_avatar.custom_minimum_size
		and outline_style.get_border_width(SIDE_LEFT) == 6
		and outline_style.border_color == BattleWidgets.COL_GOLD)
	inactive_card.free()
	active_card.free()
	var hp_bar := BattleWidgets.make_stat_bar(60, 100, BattleWidgets.TEX_BAR_HP, BattleWidgets.COL_HP) as TextureProgressBar
	var hp_mid := BattleWidgets.make_stat_bar(40, 100, BattleWidgets.TEX_BAR_HP, BattleWidgets.COL_HP) as TextureProgressBar
	var hp_low := BattleWidgets.make_stat_bar(25, 100, BattleWidgets.TEX_BAR_HP, BattleWidgets.COL_HP) as TextureProgressBar
	_check("状态条使用静态外框、平面阈值色与当前最大值",
		hp_bar is TextureProgressBar
		and hp_bar.texture_over != null
		and hp_bar.get_node("ValueLabel").text == "HP 60/100"
		and hp_bar.tint_progress == BattleWidgets.COL_HP
		and hp_mid.tint_progress == BattleWidgets.COL_HP_MID
		and hp_low.tint_progress == BattleWidgets.COL_HP_LOW)
	hp_bar.free()
	hp_mid.free()
	hp_low.free()
	var player_stats := load("res://assets/data/characters/char_player.tres") as CharacterStats
	_check("角色数据提供可选战斗头像且不影响原外观",
		(player_stats.battle_portrait == null or player_stats.battle_portrait is Texture2D)
		and player_stats.sprite_frames != null)

	var enemy := _make_unit(10, 5, 8)
	enemy.is_player = false
	var enemy_card: Control = BattleWidgets.make_unit_card(enemy, false, false, 192, 1.0)
	_check("常态敌方区域只显示指定尺寸的纯立绘",
		enemy_card.get_child_count() == 1
		and enemy_card.get_child(0).custom_minimum_size == Vector2(192, 192))
	enemy_card.free()

	var overlay_parts: Dictionary = BattleWidgets.make_timing_overlay()
	var overlay: Control = overlay_parts.overlay
	_check("timing overlay 只保留判定文字，不再内嵌敌人卡",
		overlay.get_node_or_null("EnemyPerformanceFrame") == null
		and overlay_parts.result_label is Label)
	overlay.free()

func _test_turn_arc_bar() -> void:
	var turn_arc_bar_script: Script = load("res://scripts/battle/TurnArcBar.gd")
	var bar: Control = turn_arc_bar_script.new()
	bar.size = Vector2(800, 112)
	add_child(bar)
	var order: Array = []
	for index in range(8):
		var unit := _make_unit(10, 5, 20 - index)
		unit.is_player = index % 2 == 0
		unit.display_name = "单位%d" % index
		order.append(unit)
	bar.show_order(order, order[3])
	await get_tree().create_timer(0.3).timeout
	var active_orb: Control = null
	var reused_orb: Control = null
	for child in bar.get_children():
		if child.get_meta("unit_ref", null) == order[3]:
			active_orb = child
		if child.get_meta("unit_ref", null) == order[1]:
			reused_orb = child
	var active_border := active_orb.get_node("Border") as Panel
	var active_style := active_border.get_theme_stylebox("panel") as StyleBoxFlat
	_check("弧线行动条最多显示七个无文字圆形头像球",
		bar.get_child_count() == 7
		and active_orb.find_children("*", "Label", true, false).is_empty())
	_check("中央行动者以最大尺寸、描金和下指示符标记",
		active_orb.scale == Vector2.ONE
		and active_style.border_color == BattleWidgets.COL_GOLD
		and active_orb.get_node("Indicator").visible)
	var previous_x: float = active_orb.position.x
	var reused_id: int = reused_orb.get_instance_id()
	bar.show_order(order, order[4])
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var new_active: Control = null
	var reused_after: Control = null
	var has_left_exit: bool = false
	var has_right_entry: bool = false
	for child in bar.get_children():
		var unit = child.get_meta("unit_ref", null)
		has_left_exit = has_left_exit or unit == order[0]
		has_right_entry = has_right_entry or unit == order[7]
		if unit == order[4]:
			new_active = child
		if unit == order[1]:
			reused_after = child
	_check("回合变更复用头像球并整体向左滚动",
		bar.get_child_count() == 7
		and reused_after != null and reused_after.get_instance_id() == reused_id
		and active_orb.position.x < previous_x)
	_check("滚动后左端退场、右端入场并更新中央行动者",
		not has_left_exit and has_right_entry
		and new_active != null and new_active.get_node("Indicator").visible)
	bar.queue_free()

func _test_reticle_animations() -> void:
	var battle_scene: Node = load("res://scenes/Battle.tscn").instantiate()
	battle_scene.set("_battle_started", true)
	add_child(battle_scene)
	await get_tree().process_frame
	var ui = battle_scene.get_node("UI/BattleUI")
	var party := _make_unit(10, 5, 8)
	party.is_player = true
	party.display_name = "我方"
	var enemy_a := _make_unit(10, 5, 10)
	enemy_a.is_player = false
	enemy_a.display_name = "敌A"
	var enemy_b := _make_unit(10, 5, 6)
	enemy_b.is_player = false
	enemy_b.display_name = "敌B"
	var controller := FleeBattleController.new()
	controller.party = [party]
	controller.enemies = [enemy_a, enemy_b]
	add_child(controller)
	ui.setup([party], [enemy_a, enemy_b], controller, null)
	ui.refresh()
	ui.show_actor_turn(party)
	_check("战斗开场同帧刷新不会叠加旧角色卡",
		ui.get_node("EnemyContainer").get_child_count() == 2
		and ui.get_node("PartyPanel/PartyContainer").get_child_count() == 1
		and ui.get_node("StageBox").get_child_count() == 1)
	await get_tree().process_frame
	await get_tree().process_frame

	var picked: Array = []
	ui._start_target_select(BattleUI.TARGET_GROUP_ENEMY, func(target): picked.append(target))
	var entering_marker: Control = ui.get("_target_reticle")
	var first_avatar: Control = ui._find_avatar_for_unit(enemy_a)
	_check("准星按分辨率缩放且以一圈旋转、缩放和淡入开始入场",
		BattleUI.calculate_target_reticle_size(1.0) == 96
		and BattleUI.calculate_target_reticle_size(2.0 / 3.0) == 64
		and entering_marker.size == Vector2(96, 96)
		and is_equal_approx(entering_marker.rotation, -TAU)
		and is_zero_approx(entering_marker.modulate.a)
		and entering_marker.scale == Vector2.ONE * BattleUI.TARGET_RETICLE_ENTER_SCALE
		and entering_marker.position.is_equal_approx(BattleUI.calculate_target_reticle_position(
			first_avatar.get_global_rect(), entering_marker.size)))
	await get_tree().create_timer(0.29).timeout
	var marker: Control = ui.get("_target_reticle")
	_check("准星入场 0.28 秒后恢复原尺寸与完全不透明",
		marker.scale == Vector2.ONE and is_equal_approx(marker.modulate.a, 1.0))
	var marker_id: int = marker.get_instance_id()
	var first_position: Vector2 = marker.position
	ui._move_target_selection(1)
	var marker_after_switch: Control = ui.get("_target_reticle")
	_check("准星切换复用同一节点且保持唯一金色焦点",
		marker_after_switch.get_instance_id() == marker_id
		and ui.get_node("ReticleLayer").get_children().filter(
			func(child): return child.has_meta("target_marker")).size() == 1)
	await get_tree().create_timer(0.21).timeout
	var avatar_a: Control = ui._find_avatar_for_unit(enemy_a)
	var avatar_b: Control = ui._find_avatar_for_unit(enemy_b)
	_check("准星滑到新目标并切换敌方立绘明暗",
		marker.position != first_position
		and marker.position.is_equal_approx(BattleUI.calculate_target_reticle_position(
			avatar_b.get_global_rect(), marker.size))
		and avatar_a.modulate.r < 0.5 and avatar_b.modulate == Color.WHITE)

	ui._pick_selected_target()
	await get_tree().create_timer(0.22).timeout
	_check("确认脉冲开始即封锁输入且尚未执行回调",
		ui.get("_target_confirming") and not ui.get("_is_selecting_target") and picked.is_empty()
		and ui.get_node("ReticleLayer").get_children().any(
			func(child): return child.has_meta("target_pulse")))
	await get_tree().create_timer(0.36).timeout
	_check("外扩环完整播放前不提交目标回调",
		ui.get("_target_confirming") and picked.is_empty())
	await get_tree().create_timer(0.08).timeout
	await get_tree().process_frame
	_check("准星完整脉冲结束后才执行目标回调", picked == [enemy_b])

	ui._show_action_menu()
	ui._start_target_select(BattleUI.TARGET_GROUP_ENEMY, func(_target): pass)
	await get_tree().create_timer(0.21).timeout
	ui._move_target_selection(1)
	ui._cancel_target_select()
	await get_tree().create_timer(0.13).timeout
	await get_tree().process_frame
	_check("X 淡出准星并恢复所有敌人亮度",
		ui.get("_target_reticle") == null
		and ui._find_avatar_for_unit(enemy_a).modulate == Color.WHITE
		and ui._find_avatar_for_unit(enemy_b).modulate == Color.WHITE)
	_check("X 退出目标选择后恢复行动菜单输入",
		ui.get("_menu_visible") and not ui.get("_menu_buttons").is_empty())

	var intents: Dictionary = {
		enemy_a: {"targets": [party]},
		enemy_b: {"targets": [party]},
	}
	ui.show_enemy_intents(intents, [enemy_a, party, enemy_b])
	await get_tree().process_frame
	await get_tree().create_timer(0.12).timeout
	var intent_layer: Control = ui.get_node("ReticleLayer")
	var base_markers: Array = intent_layer.get_children().filter(
		func(child): return child.has_meta("intent_marker") and not child.has_meta("intent_pulse"))
	var pulse_markers: Array = intent_layer.get_children().filter(
		func(child): return child.has_meta("intent_pulse"))
	var count_labels: Array = base_markers[0].find_children("*", "Label", true, false)
	_check("多敌锁定保留单一基础红环和 ×N 数量",
		base_markers.size() == 1 and count_labels[0].text == "×2")
	var party_avatar: Control = ui._find_avatar_for_unit(party)
	_check("红色准星始终围绕角色圆形头像中心",
		base_markers[0].get_global_rect().get_center().is_equal_approx(
			party_avatar.get_global_rect().get_center()))
	_check("同目标多敌意图使用错峰临时脉冲副本",
		ui.get("_intent_preview_active") and pulse_markers.size() == 2)
	await get_tree().create_timer(0.42).timeout
	await get_tree().process_frame
	_check("红环预告结束后只保留基础环",
		not ui.get("_intent_preview_active")
		and intent_layer.get_children().filter(
			func(child): return child.has_meta("intent_pulse")).is_empty())
	ui.show_actor_turn(enemy_a)
	ui.refresh()
	await get_tree().create_timer(0.05).timeout
	_check("敌人实际行动时不重播锁定脉冲",
		intent_layer.get_children().filter(
			func(child): return child.has_meta("intent_pulse")).is_empty())
	ui._set_menu_visible(true)
	await ui._set_timing_layout(true)
	_check("演出态完全隐藏命令栏与准星层",
		is_zero_approx(ui.get_node("CommandBar").modulate.a)
		and is_zero_approx(intent_layer.modulate.a))
	await ui._set_timing_layout(false)
	_check("演出回落后恢复命令栏与准星层透明度",
		is_equal_approx(ui.get_node("CommandBar").modulate.a, 1.0)
		and is_equal_approx(intent_layer.modulate.a, 1.0))
	battle_scene.queue_free()
	controller.queue_free()
	await get_tree().process_frame

func _test_enemy_damage_waits_for_timing() -> void:
	var enemy := _make_unit(20, 0, 10)
	enemy.is_player = false
	var target := _make_unit(0, 5, 8, 30)
	target.is_player = true
	target.mp = 5
	target.max_mp = 100
	target.pending_stance = BattleUnit.Stance.DEFEND
	var controller := FleeBattleController.new()
	controller.party = [target]
	controller.enemies = [enemy]
	controller.wait_for_timing = true
	controller.intents[enemy] = {
		"actor": enemy,
		"command": BattleCommands.ATTACK,
		"skill": null,
		"target_side": EnemyAI.TARGET_SIDE_PARTY,
		"target_mode": EnemyAI.TARGET_MODE_SINGLE,
		"targets": [target],
		"attack_pattern": EnemyAI.PATTERN_MUTANT_CLEAVE,
		"pattern_params": {"hit_count": 3},
	}
	add_child(controller)
	var sm := TurnStateMachine.new()
	sm.battle_controller = controller
	sm.damage_calculator = DamageCalculator.new()
	add_child(sm)
	sm.start_turn(enemy)
	_check("敌方伤害等待判定完成", target.hp == 30 and target.mp == 5)
	controller.timing_submitted.emit([
		{"hit_index": 0, "hit_count": 3, "contact": true, "outcome": TIMING_RULES.Outcome.SUCCESS},
		{"hit_index": 1, "hit_count": 3, "contact": true, "outcome": TIMING_RULES.Outcome.FAILURE},
		{"hit_index": 2, "hit_count": 3, "contact": true, "outcome": TIMING_RULES.Outcome.PERFECT},
	])
	await get_tree().process_frame
	var summary: Dictionary = controller.timing_summaries[0] \
		if not controller.timing_summaries.is_empty() else {}
	_check("污染兽重劈三段依次应用实际伤害和 MP", target.hp == 23 and target.mp == 3)
	_check("混合成功失败汇总保留三段完整计数",
		summary.get("hit_count", 0) == 3
		and summary.get("success_count", 0) == 2
		and summary.get("failure_count", 0) == 1
		and summary.get("outcome", TIMING_RULES.Outcome.PERFECT) == TIMING_RULES.Outcome.FAILURE
		and summary.get("damage", 0) == 7
		and summary.get("mp_change", 0) == -2)
	var result_ui := BattleUI.new()
	target.display_name = "主角"
	_check("混合多段结果显示部分成功与实际伤害",
		result_ui._format_timing_result(target, summary)
		== "主角 部分成功 2/3｜7 伤害｜MP -2")
	result_ui.free()
	sm.free()
	controller.free()

func _test_flee_turn_flow() -> void:
	var fast_actor := _make_unit(0, 0, 13)
	fast_actor.is_player = true
	fast_actor.display_name = "逃跑者"
	var slow_enemy := _make_unit(0, 0, 10)
	var controller := FleeBattleController.new()
	controller.party = [fast_actor]
	controller.enemies = [slow_enemy]
	add_child(controller)
	var sm := TurnStateMachine.new()
	sm.battle_controller = controller
	add_child(sm)
	var results: Array = []
	var finished_turns: Array = []
	sm.action_executed.connect(func(result: Dictionary): results.append(result))
	sm.turn_finished.connect(func(): finished_turns.append(true))
	sm.start_turn(fast_actor)
	sm.select_command(BattleCommands.FLEE)
	_check("逃跑成功返回 fled 结果", results.size() == 1 and results[0].fled)
	_check("逃跑成功不再发出 turn_finished", finished_turns.is_empty())
	_check("逃跑成功后微观状态机停止", sm.current_state == TurnStateMachine.MicroState.IDLE)

	var slow_actor := _make_unit(0, 0, 10)
	slow_actor.is_player = true
	slow_actor.display_name = "失败者"
	var fast_enemy := _make_unit(0, 0, 10)
	controller.party = [slow_actor]
	controller.enemies = [fast_enemy]
	results.clear()
	finished_turns.clear()
	sm.start_turn(slow_actor)
	sm.select_command(BattleCommands.FLEE)
	_check("逃跑失败返回未逃离结果", results.size() == 1 and not results[0].fled)
	_check("逃跑失败照常消耗回合", finished_turns.size() == 1)
	_check("逃跑失败完成行动结算", sm.current_state == TurnStateMachine.MicroState.ACTION_RESOLVE)
	sm.free()
	controller.free()

func _test_inventory() -> void:
	# 自动加载单例在 --script 运行下不作为全局标识符暴露，按节点取（对齐 verify_*.gd）。
	var gd: Node = get_node("/root/GameData")
	_clear_gamedata_inventory(gd)
	var item := ItemData.new()
	item.id = "test_potion"
	item.category = ItemData.ItemCategory.CONSUMABLE

	gd.add_item(item, 2)
	gd.add_item(item, 3)
	_check("add_item 同 id 堆叠 = 5", gd.get_item_count("test_potion") == 5)
	_check("add_item 零数量返回 false", gd.add_item(item, 0) == false)
	_check("add_item 负数量返回 false", gd.add_item(item, -2) == false)
	_check("非法 add 不改数量", gd.get_item_count("test_potion") == 5)

	_check("remove_item 足量返回 true", gd.remove_item("test_potion", 2) == true)
	_check("remove 后剩余 = 3", gd.get_item_count("test_potion") == 3)
	_check("remove_item 零数量返回 false", gd.remove_item("test_potion", 0) == false)
	_check("remove_item 负数量返回 false", gd.remove_item("test_potion", -2) == false)
	_check("remove_item 超量返回 false", gd.remove_item("test_potion", 99) == false)
	_check("超量 remove 不改数量", gd.get_item_count("test_potion") == 3)

	gd.remove_item("test_potion", 3)
	_check("扣到 0 移除槽位", gd.get_item_count("test_potion") == 0)

	var member: PartyMemberState = gd.get_party_member(0)
	item.effect_type = ItemData.EffectType.HEAL_HP
	item.effect_value = 20
	item.usable = true
	gd.add_item(item, 2)
	gd.set_party_member_vitals(0, member.max_hp, member.max_mp)
	_check("满 HP 时 can_use_item = false", gd.can_use_item(item.id) == false)
	_check("满 HP 时 use_item = false", gd.use_item(item.id) == false)
	_check("满 HP 不消耗物品", gd.get_item_count(item.id) == 2)
	gd.set_party_member_vitals(0, member.max_hp - 10, member.max_mp)
	_check("缺 HP 时 can_use_item = true", gd.can_use_item(item.id) == true)
	_check("缺 HP 时 use_item = true", gd.use_item(item.id) == true)
	_check("使用后恢复并消耗 1 个",
		gd.get_party_member(0).hp == member.max_hp and gd.get_item_count(item.id) == 1)
	item.effect_type = ItemData.EffectType.HEAL_MP
	gd.set_party_member_vitals(0, member.max_hp, member.max_mp)
	_check("满 MP 时 use_item = false", gd.use_item(item.id) == false)
	_check("满 MP 不消耗物品", gd.get_item_count(item.id) == 1)
	gd.set_party_member_vitals(0, member.max_hp, member.max_mp - 10)
	_check("缺 MP 时 use_item = true", gd.use_item(item.id) == true)
	_check("使用后恢复 MP 并消耗",
		gd.get_party_member(0).mp == member.max_mp and gd.get_item_count(item.id) == 0)

	var weapon_a := ItemData.new()
	weapon_a.id = "test_weapon_a"
	weapon_a.category = ItemData.ItemCategory.WEAPON
	weapon_a.attack_bonus = 2
	var weapon_b := ItemData.new()
	weapon_b.id = "test_weapon_b"
	weapon_b.category = ItemData.ItemCategory.WEAPON
	weapon_b.attack_bonus = 5
	var armor := ItemData.new()
	armor.id = "test_armor"
	armor.category = ItemData.ItemCategory.ARMOR
	armor.defense_bonus = 3
	gd.add_item(weapon_a)
	gd.add_item(weapon_b)
	gd.add_item(armor)
	_check("装备第一把武器", gd.equip_item(weapon_a.id) == true)
	_check("重复装备同一物品返回 false", gd.equip_item(weapon_a.id) == false)
	_check("替换武器成功", gd.equip_item(weapon_b.id) == true
		and gd.get_equipped_item_id("weapon") == weapon_b.id)
	_check("替换装备不移除旧物品", gd.get_item_count(weapon_a.id) == 1)
	_check("装备护甲成功", gd.equip_item(armor.id) == true)
	_check("未知槽位无法卸下", gd.unequip_item("unknown") == false)
	_check("空槽位无法卸下", gd.unequip_item("accessory") == false)
	var bonuses: Dictionary = gd.get_equipment_bonuses()
	_check("装备加成按当前三槽汇总", bonuses.atk == 5 and bonuses.def == 3)
	_check("非法丢弃返回 false", gd.discard_item(weapon_b.id, 0) == false)
	_check("失败丢弃不卸下装备", gd.get_equipped_item_id("weapon") == weapon_b.id)
	_check("超量丢弃返回 false", gd.discard_item(weapon_b.id, 2) == false)
	_check("超量丢弃仍不卸装", gd.get_equipped_item_id("weapon") == weapon_b.id)
	_check("成功丢弃已装备物品", gd.discard_item(weapon_b.id, 1) == true)
	_check("成功丢弃先卸装并移除",
		gd.get_equipped_item_id("weapon").is_empty() and gd.get_item_count(weapon_b.id) == 0)

func _test_equipment_battle_copy() -> void:
	var gd: Node = get_node("/root/GameData")
	_clear_gamedata_inventory(gd)
	var weapon := ItemData.new()
	weapon.id = "battle_copy_weapon"
	weapon.category = ItemData.ItemCategory.WEAPON
	weapon.attack_bonus = 5
	var armor := ItemData.new()
	armor.id = "battle_copy_armor"
	armor.category = ItemData.ItemCategory.ARMOR
	armor.defense_bonus = 3
	gd.add_item(weapon)
	gd.add_item(armor)
	gd.equip_item(weapon.id)
	gd.equip_item(armor.id)

	var player: PartyMemberState = gd.get_party_member(0)
	var companion: PartyMemberState = gd.get_party_member(1)
	var base_player_atk: int = player.atk
	var base_player_def: int = player.def
	var bonuses: Dictionary = gd.get_equipment_bonuses()
	var first_battle := BattleUnit.from_party_member(player, bonuses)
	var second_battle := BattleUnit.from_party_member(player, bonuses)
	var companion_battle := BattleUnit.from_party_member(companion)
	_check("主角战斗副本叠加当前装备", first_battle.atk == base_player_atk + 5
		and first_battle.def == base_player_def + 3)
	_check("重复进入战斗不重复叠加", second_battle.atk == first_battle.atk
		and second_battle.def == first_battle.def)
	_check("装备加成不污染 GameData 基础值", player.atk == base_player_atk
		and player.def == base_player_def)
	_check("队友战斗副本不应用主角装备", companion_battle.atk == companion.atk
		and companion_battle.def == companion.def)

func _test_battle_session_transactions() -> void:
	var gd: Node = get_node("/root/GameData")
	_clear_gamedata_inventory(gd)
	var potion := ItemData.new()
	potion.id = "session_potion"
	potion.category = ItemData.ItemCategory.CONSUMABLE
	gd.add_item(potion, 2)
	var member := gd.get_party_member(0) as PartyMemberState
	gd.set_party_member_vitals(0, member.max_hp - 5, member.max_mp - 3)
	var poison := StatusEffect.new()
	poison.type = StatusEffect.Type.POISON
	poison.duration = 3
	gd.set_party_member_status_effects(0, [poison] as Array[StatusEffect])
	gd.set_enemy_defeated("Enemy1", false)
	gd.set_enemy_defeated("Enemy2", false)

	var victory: BattleSession = gd.create_battle_session(["Enemy1", "Enemy2"] as Array[String])
	victory.party_units[0].hp -= 4
	victory.party_units[0].status_effects[0].duration = 1
	victory.inventory.remove_item(potion.id)
	_check("战斗会话修改不提前污染全局",
		gd.get_party_member(0).hp == member.max_hp - 5
		and gd.get_party_member(0).status_effects[0].duration == 3
		and gd.get_item_count(potion.id) == 2)
	_check("胜利结算只执行一次",
		gd.settle_battle(victory, BattleSession.Outcome.VICTORY)
		and not gd.settle_battle(victory, BattleSession.Outcome.VICTORY))
	_check("胜利提交队伍、背包与全部敌人 key",
		gd.get_party_member(0).hp == member.max_hp - 9
		and gd.get_party_member(0).status_effects[0].duration == 1
		and gd.get_item_count(potion.id) == 1
		and gd.is_enemy_defeated("Enemy1") and gd.is_enemy_defeated("Enemy2"))
	victory.party_units[0].status_effects[0].duration = 0
	_check("结算后全局与会话不共享状态资源",
		gd.get_party_member(0).status_effects[0].duration == 1)

	gd.set_enemy_defeated("Enemy1", false)
	var fled: BattleSession = gd.create_battle_session(["Enemy1"] as Array[String])
	fled.inventory.remove_item(potion.id)
	_check("逃跑提交消耗但不标记敌人",
		gd.settle_battle(fled, BattleSession.Outcome.FLED)
		and gd.get_item_count(potion.id) == 0
		and not gd.is_enemy_defeated("Enemy1"))

	gd.add_item(potion, 2)
	var defeated: BattleSession = gd.create_battle_session(["Enemy1"] as Array[String])
	defeated.party_units[0].hp = 1
	defeated.inventory.remove_item(potion.id)
	_check("失败丢弃会话背包并重置队伍",
		gd.settle_battle(defeated, BattleSession.Outcome.DEFEAT)
		and gd.get_item_count(potion.id) == 2
		and gd.get_party_member(0).hp == gd.get_party_member(0).max_hp
		and gd.get_party_member(0).status_effects.is_empty())

func _test_inventory_pagination() -> void:
	var gd: Node = get_node("/root/GameData")
	_clear_gamedata_inventory(gd)
	for i in range(21):
		var weapon := ItemData.new()
		weapon.id = "page_weapon_%02d" % i
		weapon.category = ItemData.ItemCategory.WEAPON
		gd.add_item(weapon)
	var armor := ItemData.new()
	armor.id = "page_armor"
	armor.category = ItemData.ItemCategory.ARMOR
	gd.add_item(armor)

	var inv: InventoryUI = load("res://scenes/ui/InventoryUI.tscn").instantiate()
	add_child(inv)
	inv._refresh_grid()
	_check("第 1 页只显示 20 种物品", inv._current_items.size() == 20)
	_check("多页分类显示页码", inv._grid_hint_layer.get_node_or_null("PageIndicator") != null)

	inv._set_focus_index(4)
	inv._move_focus(1, 0)
	_check("右边缘进入下一页", inv._get_page_index() == 1 and inv._current_items.size() == 1)
	_check("下一页焦点落在同行首格", inv._get_focus_index() == 0)
	inv._move_focus(1, 0)
	_check("末页右边缘不循环", inv._get_page_index() == 1 and inv._get_focus_index() == 0)
	inv._move_focus(-1, 0)
	_check("左边缘返回上一页同行末格", inv._get_page_index() == 0 and inv._get_focus_index() == 4)

	inv._move_focus(1, 0)
	inv._handle_preview_input(KEY_E)
	_check("E 切换到下一分类", inv._category_index == 1)
	inv._handle_preview_input(KEY_Q)
	_check("Q 切换到上一分类", inv._category_index == 0)
	_check("切换分类后恢复分类页码", inv._get_page_index() == 1)
	_check("切换分类后恢复分类焦点", inv._get_focus_index() == 0)

	gd.remove_item("page_weapon_20")
	inv._refresh_grid()
	_check("删除末页最后一项后页码钳制", inv._get_page_index() == 0 and inv._current_items.size() == 20)
	inv.queue_free()

func _test_inventory_detail_layout() -> void:
	var gd: Node = get_node("/root/GameData")
	_clear_gamedata_inventory(gd)
	var item := ItemData.new()
	item.id = "layout_accessory"
	item.display_name = "风蚀遗迹中无法辨认真名的古老守望者护符"
	item.description = "这是一段用于验证说明文字边界的长文本。它必须在说明框内自动换行，到达最小字号后仍然过长的内容以省略号截断，不能覆盖属性栏、分隔线或下方操作区域。".repeat(3)
	item.category = ItemData.ItemCategory.ACCESSORY
	item.usable = true
	item.discardable = true
	item.attack_bonus = 12
	item.defense_bonus = 8
	gd.add_item(item)

	var inv: InventoryUI = load("res://scenes/ui/InventoryUI.tscn").instantiate()
	add_child(inv)
	inv._category_index = 2
	inv._refresh_grid()
	inv._refresh_detail()
	var name_label: Label = inv._detail_layer.get_node("ItemName")
	var desc_label: Label = inv._detail_layer.get_node("Description")
	_check("详情长名称在 18~26 号字内自适应", name_label.get_theme_font_size("font_size") in range(18, 27))
	_check("详情长说明在 13~17 号字内自适应", desc_label.get_theme_font_size("font_size") in range(13, 18))
	_check("详情文字启用裁切和省略号", name_label.clip_text and desc_label.clip_text
		and desc_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS)
	var desc_zone: Rect2 = inv._zone("desc")
	var desc_font_size: int = desc_label.get_theme_font_size("font_size")
	var visible_text_height: float = desc_label.max_lines_visible * (
		desc_label.get_theme_font("font").get_height(desc_font_size)
		+ desc_label.get_theme_constant("line_spacing"))
	_check("说明文字可见行严格限制在 desc 分区", desc_label.position == desc_zone.position
		and desc_label.size.x == desc_zone.size.x and visible_text_height <= desc_zone.size.y)

	inv._enter_action_menu()
	var footer: Rect2 = inv._zone("footer")
	_check("操作菜单使用无背景 2 列网格", inv._action_menu_box is GridContainer
		and inv._action_menu_box.columns == 2 and inv._action_menu_box.get_child_count() == 3)
	_check("操作菜单严格嵌入 footer 分区", inv._action_menu_box.position == footer.position
		and inv._action_menu_box.size == footer.size)
	inv.queue_free()
