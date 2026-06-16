class_name ExplorableMap
extends Node2D
## 探索类场景基类（林间空地 / 野外区共用）。
## 承载两图重复的背包开关与场景切换互斥标志；子类只管各自地图与触发器逻辑。
## 背包界面懒加载，打开/关闭与暂停由 InventoryUI 自身管理。

const INVENTORY_UI_SCENE: String = "res://scenes/ui/InventoryUI.tscn"

var _is_transitioning: bool = false
var _inventory_ui: InventoryUI = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"open_inventory"):
		_open_inventory()
		get_viewport().set_input_as_handled()

func _open_inventory() -> void:
	if _is_transitioning:
		return
	if _inventory_ui == null:
		_inventory_ui = load(INVENTORY_UI_SCENE).instantiate()
		add_child(_inventory_ui)
	if not _inventory_ui.is_open():
		_inventory_ui.open()
