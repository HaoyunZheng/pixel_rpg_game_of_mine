extends Node
## SceneManager — 场景切换管理单例
## 提供 change_scene(to_path, data) 接口，带全屏淡入淡出过渡。

const TRANSITION_DURATION: float = 0.3

var _overlay: ColorRect
var _tween: Tween
var _pending_scene: String = ""
var _pending_data: Dictionary = {}

func _ready() -> void:
	Log.info("SceneManager", "场景管理单例已加载")
	# 用 CanvasLayer 保证 overlay 始终在最上层，不受场景切换影响
	var canvas := CanvasLayer.new()
	canvas.name = "TransitionCanvas"
	canvas.layer = 100  # 最高层
	get_tree().root.add_child.call_deferred(canvas)

	_overlay = ColorRect.new()
	_overlay.name = "TransitionOverlay"
	_overlay.color = Color.BLACK
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.modulate.a = 0.0
	_overlay.hide()
	canvas.add_child(_overlay)

## 请求切换场景。data 字典会写入 GameData 供目标场景读取。
func change_scene(to_path: String, data: Dictionary = {}) -> void:
	if _pending_scene != "":
		return  # 已有切换在进行中
	_pending_scene = to_path
	_pending_data = data
	_fade_out()

func _fade_out() -> void:
	_overlay.modulate.a = 0.0
	_overlay.show()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(_overlay, "modulate:a", 1.0, TRANSITION_DURATION)
	_tween.finished.connect(_on_fade_out_complete)

func _on_fade_out_complete() -> void:
	# 执行场景切换
	get_tree().change_scene_to_file(_pending_scene)
	get_tree().tree_changed.connect(_on_tree_changed, CONNECT_ONE_SHOT)

func _on_tree_changed() -> void:
	var current_root = get_tree().current_scene
	if current_root:
		# 写入 GameData
		if _pending_data.has("scene_name"):
			GameData.current_scene_name = _pending_data["scene_name"]
		# 通知当前场景数据已就绪（延迟一帧，确保场景 _ready 已执行）
		call_deferred("_notify_scene_enter", current_root)
	_fade_in()

func _notify_scene_enter(current_root: Node) -> void:
	if current_root and current_root.has_method("on_scene_enter"):
		current_root.on_scene_enter(_pending_data.duplicate())

func _fade_in() -> void:
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(_overlay, "modulate:a", 0.0, TRANSITION_DURATION)
	_tween.finished.connect(_on_fade_in_complete)

func _on_fade_in_complete() -> void:
	_overlay.hide()
	_pending_scene = ""
	_pending_data = {}
	Log.info("SceneManager", "场景切换完成: %s" % GameData.current_scene_name)
