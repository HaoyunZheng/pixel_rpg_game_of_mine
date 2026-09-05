extends Node2D
## 工程入口场景。启动后自动进入初始场景（林间空地）。

const START_SCENE: String = "res://scenes/ForestClearing.tscn"

func _ready() -> void:
	Log.info("Main", "游戏启动成功 ✅")
	# 延迟一帧，确保 AutoLoad 完全就绪后再切换
	call_deferred("_enter_start_scene")

func _enter_start_scene() -> void:
	var checkpoint: Dictionary = await GameData.load_checkpoint()
	if checkpoint.is_empty():
		Log.info("Main", "未发现有效篝火存档，进入林间空地")
		SceneManager.change_scene(
			START_SCENE, {"scene_name": "ForestClearing", "from": "boot"})
		return
	SceneManager.change_scene(checkpoint.scene_path, {
		"scene_name": checkpoint.scene_name,
		"from": "checkpoint",
		"spawn_id": checkpoint.spawn_id,
	})
