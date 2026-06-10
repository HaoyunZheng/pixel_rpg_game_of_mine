extends SceneTree
## 视觉自愈循环 —— 截图捕获器（godogen「截图自我修复」移植 · 2D 静帧版）
##
## 这是 godogen 那条「跑 → 截图 → 比对文字描述 → 修」循环里「截图」那一段的本地落地。
## godogen 用 `godot --write-movie ...` 录帧序列；这里改成 2D 像素 RPG 更省的「回读 viewport 存静帧」。
##
## 用法（工作目录 = game/，且【不要】加 --headless，否则回读到空白帧）：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script res://test/capture.gd -- \
##       --scene res://scenes/Main.tscn --task hello --frames 8 --shots 1 --interval 6
##
## 参数（都在 `--` 之后）：
##   --scene    要截的场景（默认 res://scenes/Main.tscn）
##   --task     本次截图的 slug，决定输出子目录
##   --frames   截第一张前先 settle 的帧数（等 _ready/动画/物理就位）
##   --shots    截几张（静态场景 1 张即可；动态场景多张看变化）
##   --interval 多张之间间隔的帧数
##
## 产出：res://screenshots/<task>/frame_000.png ...（已 .gdignore + .gitignore）
##
## 设计原则（沿用 godogen）：
##   - 捕获逻辑只活在 test/ 里，绝不让 scenes/scripts/ 的游戏逻辑依赖截图状态。
##   - 截前必须等到这一帧真的画完（frame_post_draw）再回读，否则拿到的是脏/空帧。

const DEFAULT_SCENE := "res://scenes/Main.tscn"
const OUT_ROOT := "res://screenshots"


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var scene_path: String = args.get("scene", DEFAULT_SCENE)
	var task: String = args.get("task", "default")
	var settle: int = int(args.get("frames", "8"))
	var shots: int = maxi(1, int(args.get("shots", "1")))
	var interval: int = maxi(1, int(args.get("interval", "6")))

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("[capture] 无法加载场景: %s" % scene_path)
		quit(1)
		return

	root.add_child(packed.instantiate())

	var out_dir := "%s/%s" % [OUT_ROOT, task]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	# 先 settle：让 _ready、第一帧动画、物理落位都跑完，再开始截。
	for _i in settle:
		await process_frame
	await _wait_for_scene_transition()

	for s in shots:
		await RenderingServer.frame_post_draw  # 关键：等这一帧画完再回读 viewport
		var img := root.get_texture().get_image()
		var path := "%s/frame_%03d.png" % [out_dir, s]
		var err := img.save_png(path)
		if err != OK:
			push_error("[capture] 保存失败 %s (err=%d)" % [path, err])
		else:
			print("[capture] 写出 %s  (%dx%d)" % [path, img.get_width(), img.get_height()])
		if s < shots - 1:
			for _i in interval:
				await process_frame

	print("[capture] 完成: task=%s shots=%d -> %s" % [task, shots, ProjectSettings.globalize_path(out_dir)])
	quit()


## 解析 `-- --key value --flag` 形式的命令行参数为字典。
func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var val := "true"
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				val = argv[i + 1]
				i += 1
			out[key] = val
		i += 1
	return out


## 若场景通过 SceneManager 进行启动过渡，等过渡完成再截图，避免捕获到纯黑遮罩帧。
func _wait_for_scene_transition() -> void:
	var scene_manager := root.get_node_or_null("SceneManager")
	if scene_manager == null:
		return
	for _i in 120:
		var pending_scene = scene_manager.get("_pending_scene")
		if pending_scene is String and pending_scene.is_empty():
			return
		await process_frame
