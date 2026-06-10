class_name EnemyAI
extends RefCounted
## 敌人 AI — 签名行为（MVP 简化版）

const AI_TYPE_HUNTER: int = 0
const AI_TYPE_BURNER: int = 1
const AI_TYPE_MUTANT: int = 2
const COMMAND_ATTACK: String = "attack"

static func decide_action(enemy, party_units: Array) -> Dictionary:
	match enemy.ai_type:
		AI_TYPE_HUNTER:
			return _hunter_ai(enemy, party_units)
		AI_TYPE_BURNER:
			return _burner_ai(enemy, party_units)
		AI_TYPE_MUTANT:
			return _mutant_ai(enemy, party_units)
		_:
			return _mutant_ai(enemy, party_units)

## 猎手：攻击 HP 最低的目标（MVP 简化，暂不做诅咒值读取）
static func _hunter_ai(_enemy, party_units: Array) -> Dictionary:
	var party := party_units.filter(func(u): return not u.is_dead())
	if party.is_empty():
		return {"command": COMMAND_ATTACK, "skill": null, "target": null}
	party.sort_custom(func(a, b): return a.hp < b.hp)
	return {"command": COMMAND_ATTACK, "skill": null, "target": party[0]}

## 燃烬者：攻击 HP 最高的目标
static func _burner_ai(_enemy, party_units: Array) -> Dictionary:
	var party := party_units.filter(func(u): return not u.is_dead())
	if party.is_empty():
		return {"command": COMMAND_ATTACK, "skill": null, "target": null}
	party.sort_custom(func(a, b): return a.hp > b.hp)
	return {"command": COMMAND_ATTACK, "skill": null, "target": party[0]}

## 变异兽：狂暴不可预测 —— 随机挑一个存活目标（区别于猎手/燃烬者的确定性选靶）
static func _mutant_ai(_enemy, party_units: Array) -> Dictionary:
	var party := party_units.filter(func(u): return not u.is_dead())
	if party.is_empty():
		return {"command": COMMAND_ATTACK, "skill": null, "target": null}
	var target = party[randi() % party.size()]
	return {"command": COMMAND_ATTACK, "skill": null, "target": target}
