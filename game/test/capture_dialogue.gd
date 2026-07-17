extends SceneTree
## 一次性视觉验证 —— 程序化推进到首次选择，确认 Dialogic 对话框、文本与选择布局。
## 沿用 capture.gd 的「等帧画完再回读 viewport」原则；【不要】加 --headless。
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script res://test/capture_dialogue.gd
## 可用 DIALOGUE_CAPTURE_WIDTH / DIALOGUE_CAPTURE_HEIGHT 指定窗口尺寸。
## 产出：res://screenshots/dialogue/choice_<宽>x<高>.png

const SCENE := "res://scenes/ForestClearing.tscn"
const OUT_DIR := "res://screenshots/dialogue"

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed := load(SCENE) as PackedScene
	root.add_child(packed.instantiate())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# GameData 启动时会应用全屏偏好，等待后再切回本次验证所需窗口尺寸。
	await create_timer(0.6).timeout
	root.mode = Window.MODE_WINDOWED
	await create_timer(0.25).timeout
	var width := int(OS.get_environment("DIALOGUE_CAPTURE_WIDTH"))
	var height := int(OS.get_environment("DIALOGUE_CAPTURE_HEIGHT"))
	if width <= 0:
		width = 1920
	if height <= 0:
		height = 1080
	root.size = Vector2i(width, height)
	for _i in 12:
		await process_frame

	# 程序化触发对话（绕过走近 + 按键，专验 Dialogic 渲染与回流链路）
	var dm := root.get_node("/root/DialogueManager")
	var dialogic := root.get_node("/root/Dialogic")
	var ok: bool = dm.start("forest_wanderer")
	print("[capture_dialogue] start() = %s" % ok)

	# 跳过前三段逐字显示，停在首次选择；循环上限防止资源异常时挂住验证。
	for _i in 160:
		await process_frame
		dialogic.Inputs.stop_timers()
		if dialogic.current_state == dialogic.States.AWAITING_CHOICE:
			break
		dialogic.Inputs.handle_input()
	await create_timer(0.3).timeout

	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var output := "%s/choice_%dx%d.png" % [OUT_DIR, width, height]
	var err := img.save_png(output)
	print("[capture_dialogue] 截图 %s err=%d is_active=%s choice=%s" % [
		output, err, dm.is_active(), dialogic.current_state == dialogic.States.AWAITING_CHOICE,
	])
	quit()
