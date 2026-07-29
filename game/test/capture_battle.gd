extends SceneTree
## 战斗界面视觉回归：捕获常态、敌人锁定、中央框扩张和慢速弹幕。
## 环境变量：BATTLE_CAPTURE_STATE=normal|lock|expanded|barrage，BATTLE_CAPTURE_WIDTH/HEIGHT。

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
	match state:
		"normal":
			ui.show_enemy_intents({})
			await process_frame
			await process_frame
		"expanded":
			await _show_expanded_timing(battle, ui)
		"barrage":
			await _show_expanded_timing(battle, ui, true)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var shot_count: int = 3 if state == "barrage" else 1
	for shot in range(shot_count):
		await RenderingServer.frame_post_draw
		var suffix: String = "_%02d" % shot if shot_count > 1 else ""
		var output := "%s/%s_%dx%d%s.png" % [OUT_DIR, state, width, height, suffix]
		var err := root.get_texture().get_image().save_png(output)
		print("[capture_battle] %s err=%d" % [output, err])
		if err != OK:
			quit(err)
			return
		if shot + 1 < shot_count:
			await create_timer(0.2).timeout
	quit(OK)

func _show_expanded_timing(battle: Node, ui: Control, barrage: bool = false) -> void:
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
