class_name BattleStateMachine
extends Node
## 战斗宏观状态机
## BattleEntry → RoundStart → TurnLoop → BattleEnd

enum MacroState { ENTRY, ROUND_START, TURN_LOOP, BATTLE_END }

signal state_changed(new_state: MacroState)
signal turn_order_calculated(order: Array)
signal battle_ended(victory: bool)

var current_state: MacroState = MacroState.ENTRY
var _battle_controller: Node = null
var _turn_order: Array = []
var _round_count: int = 0

func setup(battle_controller: Node) -> void:
	_battle_controller = battle_controller

func start_battle() -> void:
	_transition_to(MacroState.ENTRY)

func _transition_to(new_state: MacroState) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	match new_state:
		MacroState.ENTRY: _on_entry()
		MacroState.ROUND_START: _on_round_start()
		MacroState.TURN_LOOP: _on_turn_loop()
		MacroState.BATTLE_END: _on_battle_end()

func _on_entry() -> void:
	Log.info("BattleState", "战斗初始化完成")
	_transition_to(MacroState.ROUND_START)

func _on_round_start() -> void:
	_round_count += 1
	Log.info("BattleState", "第 %d 回合开始" % _round_count)
	_resolve_dot_effects()
	_calculate_turn_order()
	turn_order_calculated.emit(_turn_order)
	_transition_to(MacroState.TURN_LOOP)

func _resolve_dot_effects() -> void:
	for unit in _battle_controller.get_all_units():
		for effect in unit.status_effects.duplicate():
			if effect.type == StatusEffect.Type.POISON:
				var dot_damage: int = maxi(1, effect.potency)
				unit.take_damage(dot_damage)
				Log.info("BattleState", "%s 受到 %d 点中毒伤害" % [unit.display_name, dot_damage])
			effect.duration -= 1
			if effect.duration <= 0:
				unit.status_effects.erase(effect)
				Log.info("BattleState", "%s 的 %s 效果消失" % [unit.display_name, effect.get_display_name()])

func _calculate_turn_order() -> void:
	var all_units: Array = _battle_controller.get_all_units()
	all_units.sort_custom(func(a, b):
		if a.spd != b.spd:
			return a.spd > b.spd
		return a.is_player and not b.is_player
	)
	_turn_order = all_units
	var names: Array = _turn_order.map(func(u): return u.display_name)
	Log.info("BattleState", "行动顺序: %s" % " → ".join(names))

func _on_turn_loop() -> void:
	pass

func request_next_turn() -> void:
	_transition_to(MacroState.ROUND_START)

func check_battle_end() -> bool:
	var all_enemies_dead: bool = _battle_controller.get_enemy_units().all(func(u): return u.is_dead())
	var all_party_dead: bool = _battle_controller.get_party_units().all(func(u): return u.is_dead())
	if all_enemies_dead or all_party_dead:
		_transition_to(MacroState.BATTLE_END)
		return true
	return false

func _on_battle_end() -> void:
	var victory: bool = _battle_controller.get_enemy_units().all(func(u): return u.is_dead())
	Log.info("BattleState", "战斗结束 — 胜利: %s" % victory)
	battle_ended.emit(victory)
