class_name PartyMemberState
extends RefCounted
## 队伍成员的可变运行时状态；CharacterStats 仅作为只读模板。

var id: String = ""
var display_name: String = ""
var hp: int = 0
var mp: int = 0
var max_hp: int = 0
var max_mp: int = 0
var atk: int = 0
var def: int = 0
var spd: int = 0
var level: int = 1
var skill_points: int = 0
var skill_ranks: Dictionary = {}
var stats_res: CharacterStats = null
var status_effects: Array[StatusEffect] = []

static func from_stats(stats: CharacterStats) -> PartyMemberState:
	var member := PartyMemberState.new()
	member.id = stats.id
	member.display_name = stats.display_name
	member.hp = stats.max_hp
	member.mp = stats.max_mp
	member.max_hp = stats.max_hp
	member.max_mp = stats.max_mp
	member.atk = stats.atk
	member.def = stats.def
	member.spd = stats.spd
	for raw_skill in stats.skills:
		var skill := raw_skill as SkillData
		if skill != null:
			member.skill_ranks[skill.id] = 1
	member.stats_res = stats
	return member

func copy() -> PartyMemberState:
	var member := PartyMemberState.new()
	member.id = id
	member.display_name = display_name
	member.hp = hp
	member.mp = mp
	member.max_hp = max_hp
	member.max_mp = max_mp
	member.atk = atk
	member.def = def
	member.spd = spd
	member.level = level
	member.skill_points = skill_points
	member.skill_ranks = skill_ranks.duplicate()
	member.stats_res = stats_res
	for effect: StatusEffect in status_effects:
		member.status_effects.append(effect.duplicate() as StatusEffect)
	return member
