extends SceneTree
## 一次性视觉验证 —— 程序化触发对话后截图，确认 Dialogic 渲染对话框 + 文本。
## 沿用 capture.gd 的「等帧画完再回读 viewport」原则；【不要】加 --headless。
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script res://test/capture_dialogue.gd
## 产出：res://screenshots/dialogue/frame_000.png

const SCENE := "res://scenes/ForestClearing.tscn"
const OUT_DIR := "res://screenshots/dialogue"

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed := load(SCENE) as PackedScene
	root.add_child(packed.instantiate())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# settle：等 _ready / 相机 / 首帧动画落位
	for _i in 12:
		await process_frame

	# 程序化触发对话（绕过走近 + 按键，专验 Dialogic 渲染与回流链路）
	var dm := root.get_node("/root/DialogueManager")
	var ok: bool = dm.start("forest_wanderer")
	print("[capture_dialogue] start() = %s" % ok)

	# 等 Dialogic 布局实例化 + 逐字浮现若干字
	for _i in 60:
		await process_frame

	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png("%s/frame_000.png" % OUT_DIR)
	print("[capture_dialogue] 截图 err=%d  is_active=%s" % [err, dm.is_active()])
	quit()
