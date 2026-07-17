class_name BattleUnit
extends RefCounted
## 战斗中的单位 — 运行时状态包装

enum Stance { ATTACK, DEFEND, DODGE }

var id: String = ""
var display_name: String = ""
var is_player: bool = false
var hp: int = 0
var max_hp: int = 0
var mp: int = 0
var max_mp: int = 0
var atk: int = 0
var def: int = 0
var spd: int = 0

var ai_type: int = EnemyStats.AIType.MUTANT
var status_effects: Array[StatusEffect] = []
var stats_res: Resource = null
## 本次攻击的力度倍率（攻击转盘写入，DamageCalculator.calc_physical 末乘，结算后复位 1.0）。
## 不进 from_party_member / from_enemy_stats 持久拷贝——默认值即正确，非转盘路径恒为 1.0。
var power_multiplier: float = 1.0
## 仅存在于本场战斗：选择后持续到该单位下一次行动开始。
var pending_stance: Stance = Stance.ATTACK

func is_dead() -> bool:
	return hp <= 0

func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	Log.info("BattleUnit", "%s 受到 %d 点伤害，剩余 HP: %d/%d" % [display_name, amount, hp, max_hp])

func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
	Log.info("BattleUnit", "%s 回复 %d 点 HP，当前: %d/%d" % [display_name, amount, hp, max_hp])

func consume_mp(amount: int) -> void:
	mp = maxi(0, mp - amount)

func restore_mp(amount: int) -> void:
	mp = mini(max_mp, mp + amount)
	Log.info("BattleUnit", "%s 回复 %d 点 MP，当前: %d/%d" % [display_name, amount, mp, max_mp])

func has_status(effect_type: StatusEffect.Type) -> bool:
	for effect in status_effects:
		if effect.type == effect_type:
			return true
	return false

static func from_party_member(member: Dictionary, combat_bonuses: Dictionary = {}) -> BattleUnit:
	var unit := BattleUnit.new()
	unit.id = member.id
	unit.display_name = member.display_name
	unit.hp = member.hp
	unit.max_hp = member.max_hp
	unit.mp = member.mp
	unit.max_mp = member.max_mp
	unit.atk = member.atk + int(combat_bonuses.get("atk", 0))
	unit.def = member.def + int(combat_bonuses.get("def", 0))
	unit.spd = member.spd
	unit.is_player = true
	unit.status_effects = member.status_effects.duplicate()
	unit.stats_res = member.stats_res
	return unit

static func from_enemy_stats(stats) -> BattleUnit:
	var unit := BattleUnit.new()
	unit.id = stats.id
	unit.display_name = stats.display_name
	unit.hp = stats.max_hp
	unit.max_hp = stats.max_hp
	unit.mp = 0
	unit.max_mp = 0
	unit.atk = stats.atk
	unit.def = stats.def
	unit.spd = stats.spd
	unit.is_player = false
	unit.ai_type = stats.ai_type
	unit.stats_res = stats
	return unit
