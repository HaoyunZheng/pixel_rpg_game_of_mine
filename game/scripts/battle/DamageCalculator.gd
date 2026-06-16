class_name DamageCalculator
extends RefCounted
## 伤害计算器 — 确定性公式

func calc_physical(attacker: BattleUnit, target: BattleUnit) -> int:
	var raw: int = attacker.atk - target.def
	# 力度倍率作用于"攻减防"净值后、下限前：完美 1.5× 放大净伤、失误 0.6× 缩小，
	# 但任何档至少打 1 点（保留 §B.2 下限）。power_multiplier 默认 1.0，敌人/非转盘路径行为不变。
	var scaled: int = int(round(raw * attacker.power_multiplier))
	return maxi(1, scaled)

func calc_magic(attacker: BattleUnit, target: BattleUnit) -> int:
	var raw: int = attacker.atk - target.def / 2
	return maxi(1, raw)

func calc_skill(attacker: BattleUnit, target: BattleUnit, skill: SkillData) -> int:
	var base_atk: int = attacker.atk + skill.power
	match skill.damage_type:
		SkillData.DamageType.PHYSICAL:
			return maxi(1, base_atk - target.def)
		SkillData.DamageType.MAGIC:
			return maxi(1, base_atk - target.def / 2)
		_:
			return maxi(1, base_atk - target.def)
