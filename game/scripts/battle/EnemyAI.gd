class_name EnemyAI
extends RefCounted
## 敌人 AI — 签名行为（MVP 简化版）

const TARGET_SIDE_PARTY: String = "party"
const TARGET_SIDE_ENEMY: String = "enemy"
const TARGET_MODE_SINGLE: String = "single"
const TARGET_MODE_ALL: String = "all"

## 将 AI 本轮决策固化为轻量 Dictionary。调用者在 RoundStart 保存该字典，
## 敌人实际行动时只读取，不重新选靶。
static func decide_intent(enemy: BattleUnit, party_units: Array) -> Dictionary:
	var action: Dictionary = decide_action(enemy, party_units)
	var target: BattleUnit = action.get("target", null)
	var targets: Array = [target] if target != null else []
	return {
		"actor": enemy,
		"command": action.get("command", BattleCommands.ATTACK),
		"skill": action.get("skill", null),
		"target_side": TARGET_SIDE_PARTY,
		"target_mode": TARGET_MODE_SINGLE,
		"targets": targets,
	}

static func decide_action(enemy: BattleUnit, party_units: Array) -> Dictionary:
	match enemy.ai_type:
		EnemyStats.AIType.HUNTER:
			return _hunter_ai(enemy, party_units)
		EnemyStats.AIType.BURNER:
			return _burner_ai(enemy, party_units)
		EnemyStats.AIType.MUTANT:
			return _mutant_ai(enemy, party_units)
		_:
			return _mutant_ai(enemy, party_units)

## 猎手：攻击 HP 最低的目标（MVP 简化，暂不做诅咒值读取）
static func _hunter_ai(_enemy: BattleUnit, party_units: Array) -> Dictionary:
	var party := party_units.filter(func(u): return not u.is_dead())
	if party.is_empty():
		return {"command": BattleCommands.ATTACK, "skill": null, "target": null}
	party.sort_custom(func(a, b): return a.hp < b.hp)
	return {"command": BattleCommands.ATTACK, "skill": null, "target": party[0]}

## 燃烬者：攻击 HP 最高的目标
static func _burner_ai(_enemy: BattleUnit, party_units: Array) -> Dictionary:
	var party := party_units.filter(func(u): return not u.is_dead())
	if party.is_empty():
		return {"command": BattleCommands.ATTACK, "skill": null, "target": null}
	party.sort_custom(func(a, b): return a.hp > b.hp)
	return {"command": BattleCommands.ATTACK, "skill": null, "target": party[0]}

## 变异兽：狂暴不可预测 —— 随机挑一个存活目标（区别于猎手/燃烬者的确定性选靶）
static func _mutant_ai(_enemy: BattleUnit, party_units: Array) -> Dictionary:
	var party := party_units.filter(func(u): return not u.is_dead())
	if party.is_empty():
		return {"command": BattleCommands.ATTACK, "skill": null, "target": null}
	var target = party[randi() % party.size()]
	return {"command": BattleCommands.ATTACK, "skill": null, "target": target}
