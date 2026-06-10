extends SceneTree
## 相机验收截图（visual-loop 辅助）—— 把玩家放到几个位置看跟随/缩放/边缘停住。
## 跑法（【不要】加 --headless）：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script res://test/capture_forest_camera.gd

const OUT := "res://screenshots/forest-camera"

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene := (load("res://scenes/ForestClearing.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var player: CharacterBody2D = scene.get_node("Player")
	player.set_physics_process(false)
	var cam: Camera2D = root.get_node("GameCamera")  # 全局持久相机
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var shots := [
		{"name": "spawn", "pos": Vector2(736, 480)},
		{"name": "gate_right_edge", "pos": Vector2(1248, 480)},
		{"name": "left_edge", "pos": Vector2(96, 480)},
		{"name": "top_edge", "pos": Vector2(736, 96)},
	]

	for _i in 10:
		await process_frame

	var idx := 0
	for s in shots:
		player.global_position = s["pos"]
		await physics_frame
		cam.global_position = s["pos"]  # 快照对中（手动相机不靠内置平滑）
		cam.reset_smoothing()
		cam.force_update_scroll()
		for _i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/%02d_%s.png" % [OUT, idx, s["name"]]
		img.save_png(path)
		var c := cam.get_screen_center_position()
		print("[cam] %s  player=(%d,%d)  camera_center=(%.0f,%.0f)" % [
			s["name"], int(s["pos"].x), int(s["pos"].y), c.x, c.y])
		idx += 1

	print("[cam] 完成 -> %s" % ProjectSettings.globalize_path(OUT))
	quit()
