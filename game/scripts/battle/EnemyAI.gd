class_name EnemyAI
extends RefCounted
## 敌人 AI — 签名行为（MVP 简化版）

const TARGET_SIDE_PARTY: String = "party"
const TARGET_SIDE_ENEMY: String = "enemy"
const TARGET_MODE_SINGLE: String = "single"
const TARGET_MODE_ALL: String = "all"

const PATTERN_HUNTER_LOCK_THRUST: String = "hunter_lock_thrust"
const PATTERN_HUNTER_CROSS_THRUST: String = "hunter_cross_thrust"
const PATTERN_HUNTER_SLOW_BARRAGE: String = "hunter_slow_barrage"
const BARRAGE_STRAIGHT: String = "straight"
const BARRAGE_MONTE_CARLO: String = "monte_carlo"
const PATTERN_BURNER_ERUPTION: String = "burner_eruption"
const PATTERN_BURNER_SCORCH_FIELD: String = "burner_scorch_field"
const PATTERN_MUTANT_SWEEP: String = "mutant_sweep"
const PATTERN_MUTANT_CLEAVE: String = "mutant_cleave"
const PATTERN_FALLBACK_THRUST: String = "fallback_thrust"

## 将 AI 本轮决策固化为轻量 Dictionary。调用者在 RoundStart 保存该字典，
## 敌人实际行动时只读取，不重新选靶。
static func decide_intent(enemy: BattleUnit, party_units: Array) -> Dictionary:
	var action: Dictionary = decide_action(enemy, party_units)
	var target: BattleUnit = action.get("target", null)
	var targets: Array = [target] if target != null else []
	var pattern: Dictionary = _roll_attack_pattern(enemy.ai_type)
	return {
		"actor": enemy,
		"command": action.get("command", BattleCommands.ATTACK),
		"skill": action.get("skill", null),
		"target_side": TARGET_SIDE_PARTY,
		"target_mode": TARGET_MODE_SINGLE,
		"targets": targets,
		"attack_pattern": pattern.id,
		"pattern_params": pattern.params,
	}

static func _roll_attack_pattern(ai_type: EnemyStats.AIType) -> Dictionary:
	match ai_type:
		EnemyStats.AIType.HUNTER:
			var hunter_pattern: int = randi() % 3
			if hunter_pattern == 0:
				var offset := Vector2(randf_range(-48.0, 48.0), randf_range(-48.0, 48.0)).limit_length(48.0)
				return {
					"id": PATTERN_HUNTER_LOCK_THRUST,
					"params": {
						"hit_count": randi_range(2, 3),
						"telegraph": randf_range(0.45, 0.75),
						"active": randf_range(0.16, 0.24),
						"gap": randf_range(0.12, 0.22),
						"width": randf_range(42.0, 56.0),
						"aim_offset": offset,
					},
				}
			if hunter_pattern == 1:
				return {
					"id": PATTERN_HUNTER_CROSS_THRUST,
					"params": {
						"hit_count": 2,
						"angle_degrees": randf_range(20.0, 35.0),
						"stagger": randf_range(0.16, 0.30),
						"telegraph": randf_range(0.65, 0.95),
						"active": randf_range(0.25, 0.40),
						"width": randf_range(38.0, 52.0),
					},
				}
			return {
				"id": PATTERN_HUNTER_SLOW_BARRAGE,
				"params": {
					"hit_count": 3,
					"subtype": BARRAGE_STRAIGHT if randi() % 2 == 0 else BARRAGE_MONTE_CARLO,
					"seed": randi() & 0x7fffffff,
					"bullet_count": 36,
					"bullet_speed": 240.0,
					"bullet_radius": 8.0,
					"spawn_interval": 0.10,
					"wander_interval": 0.22,
					"wander_vertical_speed": 110.0,
					"telegraph": 0.45,
					"active": 5.2,
					"gap": 0.25,
				},
			}
		EnemyStats.AIType.BURNER:
			if randi() % 2 == 0:
				var offset := Vector2(randf_range(-72.0, 72.0), randf_range(-56.0, 56.0)).limit_length(80.0)
				return {
					"id": PATTERN_BURNER_ERUPTION,
					"params": {
						"hit_count": randi_range(2, 3),
						"telegraph": randf_range(0.50, 0.72),
						"active": randf_range(0.28, 0.40),
						"gap": randf_range(0.15, 0.25),
						"radius": randf_range(88.0, 122.0),
						"aim_offset": offset,
						"rotation_degrees": randf_range(95.0, 135.0),
					},
				}
			return {
				"id": PATTERN_BURNER_SCORCH_FIELD,
				"params": {
					"hit_count": 2,
					"telegraph": randf_range(0.70, 0.95),
					"active": randf_range(0.40, 0.58),
					"gap": randf_range(0.18, 0.28),
					"radius": randf_range(180.0, 240.0),
					"center_offset": randf_range(90.0, 140.0),
					"vertical_offset": randf_range(-48.0, 48.0),
					"start_side": -1 if randi() % 2 == 0 else 1,
				},
			}
		EnemyStats.AIType.MUTANT:
			if randi() % 2 == 0:
				return {
					"id": PATTERN_MUTANT_SWEEP,
					"params": {
						"hit_count": 2,
						"clockwise": randi() % 2 == 0,
						"telegraph": randf_range(0.80, 1.15),
						"active": randf_range(0.50, 0.75),
						"gap": randf_range(0.18, 0.35),
						"arc_degrees": randf_range(100.0, 140.0),
						"width": randf_range(72.0, 96.0),
					},
				}
			return {
				"id": PATTERN_MUTANT_CLEAVE,
				"params": {
					"hit_count": 3,
					"offset_x": randf_range(-120.0, 120.0),
					"telegraph": randf_range(1.0, 1.4),
					"active": randf_range(0.25, 0.40),
					"aftershock_delay": randf_range(0.18, 0.35),
					"width": randf_range(84.0, 116.0),
					"aftershock_spacing": randf_range(100.0, 160.0),
				},
			}
		_:
			return {
				"id": PATTERN_FALLBACK_THRUST,
				"params": {
					"hit_count": 1,
					"telegraph": 0.75,
					"active": 0.30,
					"width": 48.0,
				},
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
