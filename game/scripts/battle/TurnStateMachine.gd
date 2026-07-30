class_name TurnStateMachine
extends Node
## 战斗微观状态机（单个回合）
## CommandSelect → TargetSelect → ActionExecute → ActionResolve

enum MicroState { IDLE, COMMAND_SELECT, TARGET_SELECT, ACTION_EXECUTE, ACTION_RESOLVE }

const ENEMY_AI_SCRIPT := preload("res://scripts/battle/EnemyAI.gd")
const TIMING_RULES := preload("res://scripts/battle/DefenseTimingRules.gd")

signal state_changed(new_state: MicroState)
signal command_selected(command: String, skill)
signal target_selected(target)
signal action_executed(result: Dictionary)
signal action_resolved
signal turn_finished

var current_state: MicroState = MicroState.IDLE
var battle_controller: Node = null
var damage_calculator: DamageCalculator = null
var _current_actor: BattleUnit = null
var _pending_command: String = ""
var _pending_skill: SkillData = null
var _pending_item: ItemData = null
var _pending_target: BattleUnit = null
var _pending_targets: Array = []
var _pending_target_mode: String = EnemyAI.TARGET_MODE_SINGLE
var _pending_enemy_intent: Dictionary = {}

func start_turn(actor: BattleUnit) -> void:
	_current_actor = actor
	_pending_command = ""
	_pending_skill = null
	_pending_item = null
	_pending_target = null
	_pending_targets.clear()
	_pending_target_mode = EnemyAI.TARGET_MODE_SINGLE
	_pending_enemy_intent.clear()
	actor.power_multiplier = 1.0   # 兜底复位力度倍率，防上一回合泄漏
	actor.pending_stance = BattleUnit.Stance.ATTACK

	if actor.has_status(StatusEffect.Type.STUN):
		Log.info("TurnState", "%s 被眩晕，跳过回合" % actor.display_name)
		_resolve_stun(actor)
		turn_finished.emit()
		return

	if actor.is_player:
		_transition_to(MicroState.COMMAND_SELECT)
	else:
		_run_enemy_ai()

func _transition_to(new_state: MicroState) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	match new_state:
		MicroState.COMMAND_SELECT: _on_command_select()
		MicroState.TARGET_SELECT: _on_target_select()
		MicroState.ACTION_EXECUTE: _on_action_execute()
		MicroState.ACTION_RESOLVE: _on_action_resolve()

func _on_command_select() -> void:
	Log.info("TurnState", "%s 等待指令选择" % _current_actor.display_name)

## payload：技能指令传 SkillData，物品指令传 ItemData，其余为 null。
func select_command(command: String, payload = null) -> void:
	if current_state != MicroState.COMMAND_SELECT:
		return
	_pending_command = command
	_pending_skill = payload if command == BattleCommands.SKILL else null
	_pending_item = payload if command == BattleCommands.ITEM else null
	match command:
		BattleCommands.DEFEND:
			_current_actor.pending_stance = BattleUnit.Stance.DEFEND
		BattleCommands.DODGE:
			_current_actor.pending_stance = BattleUnit.Stance.DODGE
		BattleCommands.ATTACK:
			_current_actor.pending_stance = BattleUnit.Stance.ATTACK
	command_selected.emit(command, payload)
	if command in [BattleCommands.FLEE, BattleCommands.DEFEND, BattleCommands.DODGE]:
		_transition_to(MicroState.ACTION_EXECUTE)
	else:
		_transition_to(MicroState.TARGET_SELECT)

func cancel_command() -> void:
	if current_state == MicroState.TARGET_SELECT:
		_pending_target = null
		_transition_to(MicroState.COMMAND_SELECT)

func _on_target_select() -> void:
	Log.info("TurnState", "%s 等待目标选择" % _current_actor.display_name)

func select_target(target: BattleUnit) -> void:
	if current_state != MicroState.TARGET_SELECT:
		return
	_pending_target = target
	_pending_targets = [target]
	_pending_target_mode = EnemyAI.TARGET_MODE_SINGLE
	target_selected.emit(target)
	_transition_to(MicroState.ACTION_EXECUTE)

func _on_action_execute() -> void:
	Log.info("TurnState", "%s 执行行动: %s" % [_current_actor.display_name, _pending_command])
	var result: Dictionary
	if not _current_actor.is_player and _pending_command == BattleCommands.ATTACK:
		result = await _execute_enemy_attack()
	else:
		result = _execute_action()
	action_executed.emit(result)
	if result.fled:
		# 逃跑成功由战斗控制器立即切回野外；不能再进入结算并发出 turn_finished，
		# 否则 Battle 会继续启动下一位单位的行动。
		_transition_to(MicroState.IDLE)
		return
	_transition_to(MicroState.ACTION_RESOLVE)

func _execute_action() -> Dictionary:
	var action_targets: Array = _get_action_targets()
	var result: Dictionary = _new_action_result(action_targets)
	match _pending_command:
		BattleCommands.ATTACK:
			if damage_calculator != null:
				for target in action_targets:
					var damage: int = damage_calculator.calc_physical(_current_actor, target)
					target.take_damage(damage)
					result.damage += damage
			_current_actor.power_multiplier = 1.0   # 攻击结算后复位，防泄漏到该单位下次行动
		BattleCommands.SKILL:
			if _pending_skill and not action_targets.is_empty() and damage_calculator != null:
				result.mp_cost = _pending_skill.mp_cost
				_current_actor.consume_mp(result.mp_cost)
				for target in action_targets:
					if _pending_skill.skill_type == SkillData.SkillType.ATTACK:
						var damage: int = damage_calculator.calc_skill(_current_actor, target, _pending_skill)
						target.take_damage(damage)
						result.damage += damage
					elif _pending_skill.skill_type == SkillData.SkillType.HEAL:
						var healing: int = _current_actor.get_skill_power(_pending_skill)
						target.heal(healing)
						result.heal += healing
		BattleCommands.FLEE:
			result.fled = _try_flee()
		BattleCommands.ITEM:
			if _pending_item != null and not action_targets.is_empty():
				var target: BattleUnit = action_targets[0]
				if battle_controller != null \
						and battle_controller.has_method("consume_item") \
						and battle_controller.consume_item(_pending_item.id):
					result.item = _pending_item
					match _pending_item.effect_type:
						ItemData.EffectType.HEAL_HP:
							result.heal = _pending_item.effect_value
							target.heal(result.heal)
						ItemData.EffectType.HEAL_MP:
							result.heal = _pending_item.effect_value
							target.restore_mp(result.heal)
						ItemData.EffectType.DAMAGE:
							result.damage = _pending_item.effect_value
							target.take_damage(result.damage)
	return result

func _execute_enemy_attack() -> Dictionary:
	var action_targets: Array = _get_action_targets()
	var result: Dictionary = _new_action_result(action_targets)
	if damage_calculator == null:
		return result
	for target: BattleUnit in action_targets:
		var base_damage: int = damage_calculator.calc_physical(_current_actor, target)
		var hit_results: Array = [{
			"hit_index": 0,
			"hit_count": 1,
			"contact": true,
			"outcome": TIMING_RULES.Outcome.FAILURE,
		}]
		if battle_controller != null and battle_controller.has_method("run_timing_check"):
			hit_results = await battle_controller.run_timing_check(
				_current_actor, target, base_damage, _pending_enemy_intent)
		var planned_hits: int = maxi(1, int(_pending_enemy_intent.get("pattern_params", {}).get("hit_count", 1)))
		var summary: Dictionary = {
			"outcome": TIMING_RULES.Outcome.PERFECT,
			"damage": 0,
			"mp_change": 0,
			"hit_count": 0,
			"success_count": 0,
			"failure_count": 0,
		}
		for hit: Dictionary in hit_results:
			var hit_index: int = int(hit.get("hit_index", 0))
			var hit_damage: int = floori(float(base_damage) / planned_hits)
			if hit_index < base_damage % planned_hits:
				hit_damage += 1
			var timing_result: Dictionary
			if bool(hit.get("contact", false)):
				timing_result = TIMING_RULES.evaluate_outcome(
					target.pending_stance,
					hit.get("outcome", TIMING_RULES.Outcome.FAILURE),
					hit_damage,
					target.mp,
					target.max_mp)
			else:
				timing_result = {
					"outcome": TIMING_RULES.Outcome.SUCCESS,
					"damage": 0,
					"mp_change": 0,
				}
			TIMING_RULES.apply(target, timing_result)
			summary.damage += timing_result.damage
			summary.mp_change += timing_result.mp_change
			summary.hit_count += 1
			if timing_result.outcome == TIMING_RULES.Outcome.FAILURE:
				summary.failure_count += 1
			else:
				summary.success_count += 1
			if timing_result.outcome < summary.outcome:
				summary.outcome = timing_result.outcome
			result.damage += timing_result.damage
			result.timing_results.append(timing_result.merged(hit).merged({"target": target}))
		if battle_controller != null and battle_controller.has_method("finish_timing_check"):
			await battle_controller.finish_timing_check(target, summary)
	return result

func _new_action_result(action_targets: Array) -> Dictionary:
	return {
		"actor": _current_actor,
		"command": _pending_command,
		"target": _pending_target,
		"targets": action_targets,
		"damage": 0,
		"heal": 0,
		"mp_cost": 0,
		"fled": false,
		"item": null,
		"timing_results": [],
	}

func _get_action_targets() -> Array:
	var targets: Array = _pending_targets.duplicate()
	if targets.is_empty() and _pending_target != null:
		targets.append(_pending_target)
	if _pending_target_mode == EnemyAI.TARGET_MODE_ALL:
		return targets.filter(func(target): return target != null and not target.is_dead())
	if targets.is_empty() or targets[0] == null or targets[0].is_dead():
		return []
	return [targets[0]]

func _try_flee() -> bool:
	var controller := battle_controller
	if controller == null:
		return false
	var party_spd := 0
	var enemy_spd := 0
	var party: Array = controller.get_party_units()
	var enemies: Array = controller.get_enemy_units()
	if party.is_empty() or enemies.is_empty():
		return false
	for u in party:
		party_spd += u.spd
	for u in enemies:
		enemy_spd += u.spd
	party_spd /= party.size()
	enemy_spd /= enemies.size()
	return party_spd > enemy_spd * 1.2

func _on_action_resolve() -> void:
	Log.info("TurnState", "行动结算完成")
	action_resolved.emit()
	turn_finished.emit()

func _run_enemy_ai() -> void:
	var party: Array = []
	if battle_controller != null:
		party = battle_controller.get_party_units()
	var intent: Dictionary = {}
	if battle_controller != null and battle_controller.has_method("get_enemy_intent"):
		intent = battle_controller.get_enemy_intent(_current_actor)
	if intent.is_empty():
		intent = ENEMY_AI_SCRIPT.decide_intent(_current_actor, party)
	_pending_enemy_intent = intent.duplicate(true)
	_pending_command = intent.get("command", BattleCommands.ATTACK)
	_pending_skill = intent.get("skill", null)
	_pending_target_mode = intent.get("target_mode", EnemyAI.TARGET_MODE_SINGLE)
	_pending_targets = intent.get("targets", []).duplicate()
	_pending_target = _pending_targets[0] if not _pending_targets.is_empty() else null
	_transition_to(MicroState.ACTION_EXECUTE)

func _resolve_stun(actor: BattleUnit) -> void:
	for effect in actor.status_effects:
		if effect.type == StatusEffect.Type.STUN:
			actor.status_effects.erase(effect)
			break
