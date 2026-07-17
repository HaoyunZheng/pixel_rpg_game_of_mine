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

	var party: Array = []
	var enemies: Array = []
	var intents: Dictionary = {}
	var freeze_count: int = 0
	var wait_for_timing: bool = false

	func get_party_units() -> Array:
		return party

	func get_enemy_units() -> Array:
		return enemies

	func get_all_units() -> Array:
		var units: Array = party.duplicate()
		units.append_array(enemies)
		return units

	func freeze_enemy_intents() -> void:
		freeze_count += 1

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

func _ready() -> void:
	_test_damage_calculator()
	_test_enemy_ai_targeting()
	_test_enemy_attack_patterns()
	_test_round_start_intents()
	_test_enemy_intent_execution()
	_test_battle_unit_clamp()
	_test_stance_lifecycle()
	_test_defense_timing_rules()
	await _test_defense_action_field()
	await _test_enemy_damage_waits_for_timing()
	_test_flee_turn_flow()
	_test_inventory()
	_test_equipment_battle_copy()
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
	var mutant_patterns: Dictionary = {}
	var params_valid: bool = true
	for _sample in range(80):
		enemy.ai_type = EnemyStats.AIType.HUNTER
		var hunter_intent: Dictionary = EnemyAI.decide_intent(enemy, [target])
		hunter_patterns[hunter_intent.attack_pattern] = true
		params_valid = params_valid and _attack_pattern_params_valid(hunter_intent)
		enemy.ai_type = EnemyStats.AIType.MUTANT
		var mutant_intent: Dictionary = EnemyAI.decide_intent(enemy, [target])
		mutant_patterns[mutant_intent.attack_pattern] = true
		params_valid = params_valid and _attack_pattern_params_valid(mutant_intent)
	_check("猎手随机覆盖两套固定攻击流程", hunter_patterns.size() == 2
		and hunter_patterns.has(EnemyAI.PATTERN_HUNTER_LOCK_THRUST)
		and hunter_patterns.has(EnemyAI.PATTERN_HUNTER_CROSS_THRUST))
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
				and params.width >= 22.0 and params.width <= 30.0 \
				and params.aim_offset.length() <= 48.01
		EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
			return params.hit_count == 2 \
				and params.angle_degrees >= 20.0 and params.angle_degrees <= 35.0 \
				and params.stagger >= 0.16 and params.stagger <= 0.30 \
				and params.telegraph >= 0.65 and params.telegraph <= 0.95 \
				and params.active >= 0.25 and params.active <= 0.40 \
				and params.width >= 18.0 and params.width <= 26.0
		EnemyAI.PATTERN_MUTANT_SWEEP:
			return params.hit_count == 2 and params.clockwise is bool \
				and params.telegraph >= 0.80 and params.telegraph <= 1.15 \
				and params.active >= 0.50 and params.active <= 0.75 \
				and params.gap >= 0.18 and params.gap <= 0.35 \
				and params.arc_degrees >= 100.0 and params.arc_degrees <= 140.0 \
				and params.width >= 56.0 and params.width <= 76.0
		EnemyAI.PATTERN_MUTANT_CLEAVE:
			return params.hit_count == 3 \
				and params.offset_x >= -120.0 and params.offset_x <= 120.0 \
				and params.telegraph >= 1.0 and params.telegraph <= 1.4 \
				and params.active >= 0.25 and params.active <= 0.40 \
				and params.aftershock_delay >= 0.18 and params.aftershock_delay <= 0.35 \
				and params.width >= 64.0 and params.width <= 92.0 \
				and params.aftershock_spacing >= 100.0 and params.aftershock_spacing <= 160.0
		_:
			return false

func _test_round_start_intents() -> void:
	var controller := FleeBattleController.new()
	add_child(controller)
	var macro_sm := BattleStateMachine.new()
	macro_sm.setup(controller)
	add_child(macro_sm)
	macro_sm.start_battle()
	_check("RoundStart 每轮只冻结一次敌方意图", controller.freeze_count == 1)
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
	_check("冲刺前 0.05s 内为完美闪避", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DODGE, 0.04) == TIMING_RULES.Outcome.PERFECT)
	_check("冲刺 0.20s 内为普通闪避", TIMING_CHECK.classify_contact(
		BattleUnit.Stance.DODGE, 0.18) == TIMING_RULES.Outcome.SUCCESS)
	var parry := TIMING_CHECK.new()
	add_child(parry)
	parry.start(BattleUnit.Stance.DEFEND, Rect2(0, 0, 960, 540))
	var parry_event := InputEventKey.new()
	parry_event.keycode = KEY_Z
	parry_event.pressed = true
	parry._unhandled_input(parry_event)
	var parry_position: Vector2 = parry._player_position
	Input.action_press("move_right")
	parry._move_player(0.05)
	Input.action_release("move_right")
	_check("Z 走真实输入路径开启弹反并冻结移动", parry._reaction_started_at == 0.0
		and parry._player_position == parry_position)
	parry.queue_free()

	var dodge := TIMING_CHECK.new()
	add_child(dodge)
	dodge.start(BattleUnit.Stance.DODGE, Rect2(0, 0, 960, 540))
	var dodge_event := InputEventKey.new()
	dodge_event.keycode = KEY_SHIFT
	dodge_event.physical_keycode = KEY_SHIFT
	dodge_event.pressed = true
	Input.action_press("move_right")
	var dodge_position: Vector2 = dodge._player_position
	dodge._unhandled_input(dodge_event)
	dodge._move_player(0.05)
	Input.action_release("move_right")
	_check("Shift+方向走真实输入路径产生冲刺位移", dodge._reaction_started_at == 0.0
		and dodge._player_position.x - dodge_position.x > TIMING_CHECK.MOVE_SPEED * 0.05)
	dodge.queue_free()

	var sweep := TIMING_CHECK.new()
	add_child(sweep)
	sweep.start(BattleUnit.Stance.ATTACK, Rect2(0, 0, 960, 540),
		EnemyAI.PATTERN_MUTANT_SWEEP, {
			"hit_count": 2, "telegraph": 0.8, "active": 0.5, "gap": 0.2,
			"arc_degrees": 140.0, "width": 56.0, "clockwise": true,
		})
	sweep.set_physics_process(false)
	await get_tree().physics_frame
	sweep._physics_process(1.3)
	_check("横扫在大 delta 下仍命中经过的玩家", not sweep._hit_results.is_empty()
		and sweep._hit_results[0].contact)
	sweep.queue_free()

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
		"attack_pattern": EnemyAI.PATTERN_HUNTER_CROSS_THRUST,
		"pattern_params": {"hit_count": 2},
	}
	add_child(controller)
	var sm := TurnStateMachine.new()
	sm.battle_controller = controller
	sm.damage_calculator = DamageCalculator.new()
	add_child(sm)
	sm.start_turn(enemy)
	_check("敌方伤害等待判定完成", target.hp == 30 and target.mp == 5)
	controller.timing_submitted.emit([
		{"hit_index": 0, "hit_count": 2, "contact": true, "outcome": TIMING_RULES.Outcome.SUCCESS},
		{"hit_index": 1, "hit_count": 2, "contact": true, "outcome": TIMING_RULES.Outcome.SUCCESS},
	])
	await get_tree().process_frame
	_check("多段判定完成后逐段应用伤害和 MP", target.hp == 24 and target.mp == 1)
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
	gd.inventory.clear()
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

	var member: Dictionary = gd.party_members[0]
	item.effect_type = ItemData.EffectType.HEAL_HP
	item.effect_value = 20
	item.usable = true
	gd.add_item(item, 2)
	member.hp = member.max_hp
	_check("满 HP 时 can_use_item = false", gd.can_use_item(item.id) == false)
	_check("满 HP 时 use_item = false", gd.use_item(item.id) == false)
	_check("满 HP 不消耗物品", gd.get_item_count(item.id) == 2)
	member.hp = member.max_hp - 10
	_check("缺 HP 时 can_use_item = true", gd.can_use_item(item.id) == true)
	_check("缺 HP 时 use_item = true", gd.use_item(item.id) == true)
	_check("使用后恢复并消耗 1 个", member.hp == member.max_hp and gd.get_item_count(item.id) == 1)
	item.effect_type = ItemData.EffectType.HEAL_MP
	member.mp = member.max_mp
	_check("满 MP 时 use_item = false", gd.use_item(item.id) == false)
	_check("满 MP 不消耗物品", gd.get_item_count(item.id) == 1)
	member.mp = member.max_mp - 10
	_check("缺 MP 时 use_item = true", gd.use_item(item.id) == true)
	_check("使用后恢复 MP 并消耗", member.mp == member.max_mp and gd.get_item_count(item.id) == 0)

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
	gd.equipment = {"weapon": "", "armor": "", "accessory": ""}
	_check("装备第一把武器", gd.equip_item(weapon_a.id) == true)
	_check("重复装备同一物品返回 false", gd.equip_item(weapon_a.id) == false)
	_check("替换武器成功", gd.equip_item(weapon_b.id) == true and gd.equipment.weapon == weapon_b.id)
	_check("替换装备不移除旧物品", gd.get_item_count(weapon_a.id) == 1)
	_check("装备护甲成功", gd.equip_item(armor.id) == true)
	_check("未知槽位无法卸下", gd.unequip_item("unknown") == false)
	_check("空槽位无法卸下", gd.unequip_item("accessory") == false)
	var bonuses: Dictionary = gd.get_equipment_bonuses()
	_check("装备加成按当前三槽汇总", bonuses.atk == 5 and bonuses.def == 3)
	_check("非法丢弃返回 false", gd.discard_item(weapon_b.id, 0) == false)
	_check("失败丢弃不卸下装备", gd.equipment.weapon == weapon_b.id)
	_check("超量丢弃返回 false", gd.discard_item(weapon_b.id, 2) == false)
	_check("超量丢弃仍不卸装", gd.equipment.weapon == weapon_b.id)
	_check("成功丢弃已装备物品", gd.discard_item(weapon_b.id, 1) == true)
	_check("成功丢弃先卸装并移除", gd.equipment.weapon.is_empty() and gd.get_item_count(weapon_b.id) == 0)

func _test_equipment_battle_copy() -> void:
	var gd: Node = get_node("/root/GameData")
	gd.inventory.clear()
	gd.equipment = {"weapon": "", "armor": "", "accessory": ""}
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

	var player: Dictionary = gd.party_members[0]
	var companion: Dictionary = gd.party_members[1]
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

func _test_inventory_pagination() -> void:
	var gd: Node = get_node("/root/GameData")
	gd.inventory.clear()
	gd.equipment = {"weapon": "", "armor": "", "accessory": ""}
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
	gd.inventory.clear()
	gd.equipment = {"weapon": "", "armor": "", "accessory": ""}
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
