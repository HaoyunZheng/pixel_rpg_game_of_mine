class_name DefenseTimingRules
extends RefCounted
## 防御 / 闪避占位判定的确定性规则；不处理输入或画面。

enum Outcome { FAILURE, SUCCESS, PERFECT }

static func evaluate_outcome(
		stance: BattleUnit.Stance,
		outcome: Outcome,
		base_damage: int,
		current_mp: int,
		max_mp: int) -> Dictionary:
	var damage: int = maxi(0, base_damage)
	var mp_change: int = 0
	match stance:
		BattleUnit.Stance.DEFEND:
			if outcome == Outcome.PERFECT:
				damage = 0
			elif outcome == Outcome.SUCCESS:
				damage = maxi(1, ceili(base_damage * 0.33)) if base_damage > 0 else 0
				if base_damage > 0:
					mp_change = -mini(current_mp, mini(2, ceili(max_mp * 0.02)))
			else:
				damage = maxi(1, ceili(base_damage * 0.60)) if base_damage > 0 else 0
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
	}

static func apply(target: BattleUnit, result: Dictionary) -> void:
	if result.damage > 0:
		target.take_damage(result.damage)
	var mp_change: int = result.mp_change
	if mp_change < 0:
		target.consume_mp(-mp_change)
	elif mp_change > 0:
		target.restore_mp(mp_change)
