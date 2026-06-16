class_name TurnStateMachine
extends Node
## 战斗微观状态机（单个回合）
## CommandSelect → TargetSelect → ActionExecute → ActionResolve

enum MicroState { IDLE, COMMAND_SELECT, TARGET_SELECT, ACTION_EXECUTE, ACTION_RESOLVE }

const ENEMY_AI_SCRIPT := preload("res://scripts/battle/EnemyAI.gd")

signal state_changed(new_state: MicroState)
signal command_selected(command: String, skill)
signal target_selected(target)
signal action_executed(result: Dictionary)
signal action_resolved
signal turn_finished

var current_state: MicroState = MicroState.IDLE
var battle_controller: Node = null
var damage_calculator = null
var _current_actor = null
var _pending_command: String = ""
var _pending_skill = null
var _pending_item = null
var _pending_target = null

func start_turn(actor) -> void:
	_current_actor = actor
	_pending_command = ""
	_pending_skill = null
	_pending_item = null
	_pending_target = null
	actor.power_multiplier = 1.0   # 兜底复位力度倍率，防上一回合泄漏

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
	command_selected.emit(command, payload)
	if command == BattleCommands.FLEE:
		_transition_to(MicroState.ACTION_EXECUTE)
	else:
		_transition_to(MicroState.TARGET_SELECT)

func cancel_command() -> void:
	if current_state == MicroState.TARGET_SELECT:
		_pending_target = null
		_transition_to(MicroState.COMMAND_SELECT)

func _on_target_select() -> void:
	Log.info("TurnState", "%s 等待目标选择" % _current_actor.display_name)

func select_target(target) -> void:
	if current_state != MicroState.TARGET_SELECT:
		return
	_pending_target = target
	target_selected.emit(target)
	_transition_to(MicroState.ACTION_EXECUTE)

func _on_action_execute() -> void:
	Log.info("TurnState", "%s 执行行动: %s" % [_current_actor.display_name, _pending_command])
	var result := _execute_action()
	action_executed.emit(result)
	_transition_to(MicroState.ACTION_RESOLVE)

func _execute_action() -> Dictionary:
	var result := {
		"actor": _current_actor,
		"command": _pending_command,
		"target": _pending_target,
		"damage": 0,
		"heal": 0,
		"mp_cost": 0,
		"fled": false,
		"item": null,
	}
	match _pending_command:
		BattleCommands.ATTACK:
			if _pending_target and not _pending_target.is_dead() and damage_calculator != null:
				result.damage = damage_calculator.calc_physical(_current_actor, _pending_target)
				_pending_target.take_damage(result.damage)
			_current_actor.power_multiplier = 1.0   # 攻击结算后复位，防泄漏到该单位下次行动
		BattleCommands.SKILL:
			if _pending_skill and _pending_target and not _pending_target.is_dead() and damage_calculator != null:
				result.mp_cost = _pending_skill.mp_cost
				_current_actor.consume_mp(result.mp_cost)
				if _pending_skill.skill_type == SkillData.SkillType.ATTACK:
					result.damage = damage_calculator.calc_skill(_current_actor, _pending_target, _pending_skill)
					_pending_target.take_damage(result.damage)
				elif _pending_skill.skill_type == SkillData.SkillType.HEAL:
					result.heal = _pending_skill.power
					_pending_target.heal(result.heal)
		BattleCommands.FLEE:
			result.fled = _try_flee()
		BattleCommands.ITEM:
			if _pending_item != null and _pending_target and not _pending_target.is_dead():
				if GameData.remove_item(_pending_item.id, 1):
					result.item = _pending_item
					match _pending_item.effect_type:
						ItemData.EffectType.HEAL_HP:
							result.heal = _pending_item.effect_value
							_pending_target.heal(result.heal)
						ItemData.EffectType.HEAL_MP:
							result.heal = _pending_item.effect_value
							_pending_target.restore_mp(result.heal)
						ItemData.EffectType.DAMAGE:
							result.damage = _pending_item.effect_value
							_pending_target.take_damage(result.damage)
	return result

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
	var ai_result := ENEMY_AI_SCRIPT.decide_action(_current_actor, party)
	_pending_command = ai_result.command
	_pending_skill = ai_result.skill
	_pending_target = ai_result.target
	_transition_to(MicroState.ACTION_EXECUTE)

func _resolve_stun(actor) -> void:
	for effect in actor.status_effects:
		if effect.type == StatusEffect.Type.STUN:
			actor.status_effects.erase(effect)
			break
