extends Node2D
## 工程入口场景。启动后自动进入初始场景（林间空地）。

const START_SCENE: String = "res://scenes/ForestClearing.tscn"

func _ready() -> void:
	Log.info("Main", "游戏启动成功 ✅  —— 即将进入林间空地。")
	# 延迟一帧，确保 AutoLoad 完全就绪后再切换
	call_deferred("_enter_start_scene")

func _enter_start_scene() -> void:
	SceneManager.change_scene(START_SCENE, {"scene_name": "ForestClearing", "from": "boot"})
