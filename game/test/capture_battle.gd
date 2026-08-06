extends SceneTree
## 战斗界面视觉回归：常态 UI 与五种敌方攻击的预警、前沿、接触证物。
## BATTLE_CAPTURE_STATE=normal|lock|expanded|barrage|combat_vfx|player_hit|attack_wheel|hud_confirm_menu|hud_confirm_target
## combat_vfx 额外读取 BATTLE_CAPTURE_ATTACK/MOMENT/DEBUG。

const SCENE := "res://scenes/Battle.tscn"
const OUT_DIR := "res://screenshots/battle-regression"
const TIMING_SCENE := "res://scenes/battle/DefenseTimingCheck.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.6).timeout
	root.mode = Window.MODE_WINDOWED
	await create_timer(0.25).timeout
	var width := maxi(1, int(OS.get_environment("BATTLE_CAPTURE_WIDTH")))
	var height := maxi(1, int(OS.get_environment("BATTLE_CAPTURE_HEIGHT")))
	if width == 1:
		width = 1920
	if height == 1:
		height = 1080
	root.size = Vector2i(width, height)

	var battle := (load(SCENE) as PackedScene).instantiate()
	root.add_child(battle)
	await create_timer(0.4).timeout
	var ui = battle.get_node("UI/BattleUI")
	var state := OS.get_environment("BATTLE_CAPTURE_STATE")
	if state.is_empty():
		state = "lock"
	var output_name: String = state
	match state:
		"normal":
			ui.show_enemy_intents({})
			await process_frame
			await process_frame
		"expanded":
			await _show_expanded_timing(battle, ui)
		"barrage":
			await _show_expanded_timing(battle, ui, true)
		"combat_vfx":
			output_name = await _show_combat_vfx(battle, ui)
		"player_hit":
			_show_player_hit(battle, ui)
		"attack_wheel":
			_show_attack_wheel(ui)
		"hud_confirm_menu":
			ui.show_actor_turn(battle.get("_party_units")[0])
			ui.call("_activate_selected_menu_item")
			await create_timer(0.05).timeout
		"hud_confirm_target":
			ui.call("_start_target_select", "enemy", func(_target): pass)
			await create_timer(0.05).timeout

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var shot_count: int = 3 if state in ["barrage", "player_hit"] else 1
	for shot in range(shot_count):
		await RenderingServer.frame_post_draw
		var suffix: String = "_%02d" % shot if shot_count > 1 else ""
		var output := "%s/%s_%dx%d%s.png" % [OUT_DIR, output_name, width, height, suffix]
		var err := root.get_texture().get_image().save_png(output)
		print("[capture_battle] %s err=%d" % [output, err])
		if err != OK:
			quit(err)
			return
		if shot + 1 < shot_count:
			if state == "player_hit":
				await process_frame
			else:
				await create_timer(0.2).timeout
	quit(OK)

func _show_player_hit(battle: Node, ui: Control) -> void:
	# ponytail: --script 不解析项目全局类名，夹具保持无类型引用。
	var target = battle.get("_enemy_units")[0]
	ui.play_player_hit(target, 12.0)

func _show_attack_wheel(ui: Control) -> void:
	var wheel: Control = load("res://scenes/battle/AttackPowerWheel.tscn").instantiate()
	ui.add_child(wheel)
	wheel.start_over_central_box(ui.get_node("CentralBox"), ui.get_node("CommandBar"))

func _show_expanded_timing(battle: Node, ui: Control, barrage: bool = false) -> void:
	var timing: Node = await _create_timing(battle, ui)
	if barrage:
		# ponytail: 捕获夹具直接跳过预警，避免为一张回归图等真实时间。
		timing.start(1, ui.get("_central_box").get_global_rect(), "hunter_slow_barrage", {
			"subtype": "straight", "seed": 20260722,
		})
		timing.call("_advance_phase")
		timing.set("_phase_elapsed", 1.0)
		timing.call("_update_barrage", 0.0)
		await create_timer(0.35).timeout
	else:
		timing.start(1, ui.get("_central_box").get_global_rect())
	await process_frame

func _create_timing(battle: Node, ui: Control) -> Node:
	var attacker = battle.get("_enemy_units")[0]
	var target = battle.get("_party_units")[0]
	# ponytail: --script 不解析项目全局类名；测试夹具只需锁定现有 DEFEND 枚举值。
	target.set("pending_stance", 1)
	ui.set("_timing_active", true)
	ui.call("_set_menu_visible", false)
	ui.set("_timing_normal_rect", Rect2(ui.get("_central_box").position, ui.get("_central_box").size))
	await ui.call("_set_timing_layout", true)
	ui.call("_build_timing_overlay", attacker, target)
	var timing := (load(TIMING_SCENE) as PackedScene).instantiate()
	ui.add_child(timing)
	ui.get("_timing_result_label").text = "%s 攻击 %s｜Z 防御" % [attacker.display_name, target.display_name]
	return timing

func _show_combat_vfx(battle: Node, ui: Control) -> String:
	var attack: String = OS.get_environment("BATTLE_CAPTURE_ATTACK")
	if attack.is_empty():
		attack = "hunter_lock"
	var moment: String = OS.get_environment("BATTLE_CAPTURE_MOMENT")
	if moment not in ["telegraph", "mid", "impact"]:
		moment = "mid"
	var debug: bool = OS.get_environment("BATTLE_CAPTURE_DEBUG") == "1"
	var config: Dictionary = _combat_config(attack)
	var timing: Node = await _create_timing(battle, ui)
	timing.call("start", 0, ui.get("_central_box").get_global_rect(), config.pattern, config.params)
	timing.set_physics_process(false)
	timing.set("debug_attack_front", debug)
	if moment == "telegraph":
		timing.set("_phase_elapsed", float(timing.call("_phase_duration")) * 0.76)
	else:
		var progress: float = 0.45 if moment == "mid" else (0.50 if attack == "mutant_sweep" else 0.72)
		timing.set("_phase", 1)
		if attack == "hunter_barrage":
			_advance_capture_barrage(timing, progress)
		else:
			timing.set("_phase_elapsed", float(timing.call("_phase_duration")) * progress)
			timing.set("_active_progress", maxf(0.0, progress - 0.02))
			timing.set("_stage_contact_resolved", true)
			timing.call("_update_active_hazard")
		if moment == "impact":
			_place_capture_player(timing, attack)
	timing.queue_redraw()
	ui.get("_timing_result_label").text = "%s｜%s｜%s" % [
		attack, moment, "判定遮罩" if debug else "正式画面"]
	await process_frame
	await process_frame
	return "%s_%s_%s" % [attack, moment, "mask" if debug else "formal"]

func _advance_capture_barrage(timing: Node, progress: float) -> void:
	var target_time: float = float(timing.call("_phase_duration")) * progress
	var elapsed: float = 0.0
	while elapsed < target_time:
		var step: float = minf(0.05, target_time - elapsed)
		elapsed += step
		timing.set("_phase_elapsed", elapsed)
		timing.call("_update_barrage", step)

func _place_capture_player(timing: Node, attack: String) -> void:
	var contact: Vector2
	if attack in ["hunter_lock", "hunter_cross"]:
		contact = Vector2(timing.get("_stage_start")).lerp(
			Vector2(timing.get("_stage_end")), float(timing.get("_active_progress")))
	elif attack == "hunter_barrage":
		var positions: PackedVector2Array = timing.get("_bullet_positions")
		var active: PackedByteArray = timing.get("_bullet_active")
		var arena_center: Vector2 = Rect2(timing.get("_arena_rect")).get_center()
		var closest_distance: float = INF
		for index in range(active.size()):
			if active[index] == 0:
				continue
			var distance: float = positions[index].distance_squared_to(arena_center)
			if distance < closest_distance:
				closest_distance = distance
				contact = positions[index]
	else:
		var fronts: PackedVector2Array = timing.get("_front_world_current")
		var segment_index: int = 1 if attack == "mutant_sweep" else 0
		contact = (fronts[segment_index * 2] + fronts[segment_index * 2 + 1]) * 0.5
	timing.set("_player_position", contact)
	var player_area := timing.get("_player_area") as Area2D
	player_area.position = contact

func _combat_config(attack: String) -> Dictionary:
	match attack:
		"hunter_cross":
			return {"pattern": "hunter_cross_thrust", "params": {
				"hit_count": 2, "angle_degrees": 29.0, "stagger": 0.22,
				"telegraph": 0.64, "active": 0.24, "width": 35.0,
			}}
		"hunter_barrage":
			return {"pattern": "hunter_slow_barrage", "params": {
				"hit_count": 3, "subtype": "monte_carlo", "seed": 20260803,
				"bullet_count": 24, "bullet_speed": 280.0, "bullet_radius": 7.0,
				"spawn_interval": 0.16, "wander_interval": 0.32,
				"wander_vertical_speed": 85.0, "telegraph": 0.55,
				"active": 4.6, "gap": 0.25,
			}}
		"mutant_sweep":
			return {"pattern": "mutant_sweep", "params": {
				"hit_count": 2, "clockwise": true, "telegraph": 0.95,
				"active": 0.69, "gap": 0.33, "arc_degrees": 120.0, "width": 66.0,
			}}
		"mutant_cleave":
			return {"pattern": "mutant_cleave", "params": {
				"hit_count": 3, "offset_x": 0.0, "telegraph": 1.075,
				"active": 0.35, "aftershock_delay": 0.31, "width": 80.0,
				"aftershock_spacing": 135.0,
			}}
		_:
			return {"pattern": "hunter_lock_thrust", "params": {
				"hit_count": 2, "telegraph": 0.50, "active": 0.17,
				"gap": 0.20, "width": 32.0, "aim_offset": Vector2.ZERO,
			}}
