class_name DefenseTimingRules
extends RefCounted
## 防御 / 闪避占位判定的确定性规则；不处理输入或画面。

enum Outcome { FAILURE, SUCCESS, PERFECT }

const SUCCESS_START_TICK: int = 45
const PERFECT_START_TICK: int = 57
const HIT_TICK: int = 60

static func evaluate(
		stance: BattleUnit.Stance,
		input_tick: int,
		base_damage: int,
		current_mp: int,
		max_mp: int) -> Dictionary:
	var outcome: Outcome = _outcome_for_tick(input_tick)
	var damage: int = maxi(0, base_damage)
	var mp_change: int = 0
	match stance:
		BattleUnit.Stance.DEFEND:
			if outcome == Outcome.PERFECT:
				damage = 0
			elif outcome == Outcome.SUCCESS:
				damage = maxi(1, ceili(base_damage * 0.33))
				mp_change = -mini(current_mp, mini(2, ceili(max_mp * 0.02)))
		BattleUnit.Stance.DODGE:
			if outcome == Outcome.PERFECT:
				damage = 0
				mp_change = mini(2, maxi(0, max_mp - current_mp))
			elif outcome == Outcome.SUCCESS:
				damage = 0
		_:
			outcome = Outcome.FAILURE
	return {
		"outcome": outcome,
		"damage": damage,
		"mp_change": mp_change,
		"input_tick": input_tick,
	}

static func apply(target: BattleUnit, result: Dictionary) -> void:
	if result.damage > 0:
		target.take_damage(result.damage)
	var mp_change: int = result.mp_change
	if mp_change < 0:
		target.consume_mp(-mp_change)
	elif mp_change > 0:
		target.restore_mp(mp_change)

static func _outcome_for_tick(input_tick: int) -> Outcome:
	if input_tick >= PERFECT_START_TICK and input_tick <= HIT_TICK:
		return Outcome.PERFECT
	if input_tick >= SUCCESS_START_TICK and input_tick < PERFECT_START_TICK:
		return Outcome.SUCCESS
	return Outcome.FAILURE
