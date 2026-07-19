extends SceneTree
## 战斗界面视觉回归：捕获常态、敌人锁定和中央框扩张三种状态。
## 环境变量：BATTLE_CAPTURE_STATE=normal|lock|expanded，BATTLE_CAPTURE_WIDTH/HEIGHT。

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

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await RenderingServer.frame_post_draw
	var output := "%s/%s_%dx%d.png" % [OUT_DIR, state, width, height]
	var err := root.get_texture().get_image().save_png(output)
	print("[capture_battle] %s err=%d" % [output, err])
	quit(err)

func _show_expanded_timing(battle: Node, ui: Control) -> void:
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
	timing.start(1, ui.get("_central_box").get_global_rect())
	await process_frame
