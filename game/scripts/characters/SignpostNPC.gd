class_name SignpostNPC
extends InteractableNPC
## 告示牌 NPC：复用通用 NPC 的靠近/按 Z 交互，只承载静态地图信息。


func _ready() -> void:
	add_to_group(&"signpost_npcs")
	super()
