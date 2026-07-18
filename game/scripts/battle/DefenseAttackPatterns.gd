class_name DefenseAttackPatterns
extends RefCounted
## 防御动作场的固定攻击流程模板。随机参数由 EnemyAI 冻结后传入，这里只展开阶段。

static func build(
		pattern_id: String,
		params: Dictionary,
		arena_rect: Rect2,
		player_position: Vector2,
		enemy_origin: Vector2) -> Array[Dictionary]:
	var stages: Array[Dictionary] = []
	var telegraph: float = float(params.get("telegraph", 0.75))
	var active: float = float(params.get("active", 0.30))
	var width: float = float(params.get("width", 48.0))
	match pattern_id:
		EnemyAI.PATTERN_HUNTER_LOCK_THRUST:
			for index in range(int(params.get("hit_count", 2))):
				stages.append({"kind": "aimed", "telegraph": telegraph, "active": active,
					"gap": float(params.get("gap", 0.16)), "width": width,
					"offset": Vector2(params.get("aim_offset", Vector2.ZERO)).rotated(index * 0.9)})
		EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
			var angle: float = deg_to_rad(float(params.get("angle_degrees", 26.0)))
			for index in range(2):
				stages.append({"kind": "cross", "telegraph": telegraph, "active": active,
					"gap": float(params.get("stagger", 0.22)), "width": width,
					"angle": angle if index == 0 else -angle})
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE:
			stages.append({
				"kind": "barrage",
				"telegraph": float(params.get("telegraph", 0.45)),
				"active": float(params.get("active", 5.2)),
				"gap": float(params.get("gap", 0.25)),
				"hit_count": int(params.get("hit_count", 3)),
				"subtype": String(params.get("subtype", EnemyAI.BARRAGE_STRAIGHT)),
				"seed": int(params.get("seed", 1)),
				"bullet_count": int(params.get("bullet_count", 36)),
				"bullet_speed": float(params.get("bullet_speed", 240.0)),
				"bullet_radius": float(params.get("bullet_radius", 8.0)),
				"spawn_interval": float(params.get("spawn_interval", 0.10)),
				"wander_interval": float(params.get("wander_interval", 0.22)),
				"wander_vertical_speed": float(params.get("wander_vertical_speed", 110.0)),
			})
		EnemyAI.PATTERN_BURNER_ERUPTION:
			var aim_offset := Vector2(params.get("aim_offset", Vector2.ZERO))
			var rotation_step := deg_to_rad(float(params.get("rotation_degrees", 115.0)))
			var area_radius := minf(float(params.get("radius", 104.0)),
				minf(arena_rect.size.x, arena_rect.size.y) * 0.46)
			for index in range(int(params.get("hit_count", 2))):
				var center := player_position + aim_offset.rotated(rotation_step * index)
				center = Vector2(clampf(center.x, arena_rect.position.x + area_radius, arena_rect.end.x - area_radius),
					clampf(center.y, arena_rect.position.y + area_radius, arena_rect.end.y - area_radius))
				stages.append({"kind": "area", "telegraph": telegraph, "active": active,
					"gap": float(params.get("gap", 0.20)), "radius": area_radius,
					"center": center})
		EnemyAI.PATTERN_BURNER_SCORCH_FIELD:
			var side: int = int(params.get("start_side", 1))
			var center_offset: float = float(params.get("center_offset", 112.0))
			var vertical_offset: float = float(params.get("vertical_offset", 0.0))
			var area_radius := minf(float(params.get("radius", 210.0)),
				minf(arena_rect.size.x, arena_rect.size.y) * 0.46)
			for index in range(2):
				var center := player_position + Vector2(side * center_offset, vertical_offset * (1.0 if index == 0 else -1.0))
				center = Vector2(clampf(center.x, arena_rect.position.x + area_radius, arena_rect.end.x - area_radius),
					clampf(center.y, arena_rect.position.y + area_radius, arena_rect.end.y - area_radius))
				stages.append({"kind": "area", "telegraph": telegraph, "active": active,
					"gap": float(params.get("gap", 0.23)), "radius": area_radius,
					"center": center})
				side *= -1
		EnemyAI.PATTERN_MUTANT_SWEEP:
			var arc: float = deg_to_rad(float(params.get("arc_degrees", 120.0)))
			var clockwise: bool = bool(params.get("clockwise", true))
			for index in range(2):
				var forward: bool = clockwise if index == 0 else not clockwise
				stages.append({"kind": "sweep", "telegraph": telegraph, "active": active,
					"gap": float(params.get("gap", 0.25)), "width": width,
					"angle_from": PI + (arc * 0.5 if forward else -arc * 0.5),
					"angle_to": PI + (-arc * 0.5 if forward else arc * 0.5)})
		EnemyAI.PATTERN_MUTANT_CLEAVE:
			var center_x: float = arena_rect.get_center().x + float(params.get("offset_x", 0.0))
			var spacing: float = float(params.get("aftershock_spacing", 128.0))
			for offset_x in [0.0, -spacing, spacing]:
				stages.append({"kind": "cleave", "telegraph": telegraph if offset_x == 0.0 else float(params.get("aftershock_delay", 0.24)),
					"active": active, "gap": 0.12, "width": width * (1.0 if offset_x == 0.0 else 0.55),
					"x": center_x + offset_x})
		_:
			stages.append({"kind": "cleave", "telegraph": telegraph, "active": active,
				"gap": 0.15, "width": width, "x": arena_rect.get_center().x})
	for stage: Dictionary in stages:
		stage.origin = enemy_origin
	return stages

static func style(pattern_id: String) -> Dictionary:
	match pattern_id:
		EnemyAI.PATTERN_HUNTER_LOCK_THRUST:
			return {"label": "猎手·锁定连刺", "color": Color(0.42, 0.82, 1.0)}
		EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
			return {"label": "猎手·交叉穿刺", "color": Color(0.62, 0.72, 1.0)}
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE:
			return {"label": "猎手·慢速弹幕", "color": Color(0.36, 0.74, 1.0)}
		EnemyAI.PATTERN_BURNER_ERUPTION:
			return {"label": "燃烬者·灼地连爆", "color": Color(1.0, 0.50, 0.12)}
		EnemyAI.PATTERN_BURNER_SCORCH_FIELD:
			return {"label": "燃烬者·焦土围猎", "color": Color(1.0, 0.24, 0.10)}
		EnemyAI.PATTERN_MUTANT_SWEEP:
			return {"label": "变异体·交替横扫", "color": Color(0.92, 0.30, 0.48)}
		EnemyAI.PATTERN_MUTANT_CLEAVE:
			return {"label": "变异体·蓄力重劈", "color": Color(1.0, 0.42, 0.18)}
		_:
			return {"label": "直线突击", "color": Color(1.0, 0.38, 0.22)}
