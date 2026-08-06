class_name ExplorableMap
extends Node2D
## 探索类场景基类（林间空地 / 野外区共用）。
## 承载两图重复的背包开关与场景切换互斥标志；子类只管各自地图与触发器逻辑。
## 背包界面懒加载，打开/关闭与暂停由 InventoryUI 自身管理。

const INVENTORY_UI_SCENE: String = "res://scenes/ui/InventoryUI.tscn"
const RETURN_DATA_KEY_ENEMY: String = "enemy_key"
const RETURN_DATA_KEY_PLAYER_POSITION: String = "player_position"
const RETURN_DATA_KEY_ENEMY_POSITION: String = "enemy_position"
const ESCAPE_GRACE_SECONDS: float = 3.0

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

## 战斗返回只恢复本次遭遇的瞬时位置；不把地图坐标写入 GameData。
func _restore_battle_return(
		data: Dictionary,
		player: CharacterBody2D,
		enemies_root: Node) -> bool:
	var player_position = data.get(RETURN_DATA_KEY_PLAYER_POSITION)
	if data.get("from", "") != "battle" or not player_position is Vector2:
		return false
	player.global_position = player_position
	if not data.get("fled", false) or enemies_root == null:
		return true
	var enemy_key: String = data.get(RETURN_DATA_KEY_ENEMY, "")
	for enemy in enemies_root.get_children():
		var encounter_key = enemy.get("encounter_key")
		var candidate_key: String = (
			encounter_key if encounter_key is String and not encounter_key.is_empty()
			else enemy.name)
		if candidate_key != enemy_key:
			continue
		var enemy_position = data.get(RETURN_DATA_KEY_ENEMY_POSITION)
		if enemy_position is Vector2:
			enemy.global_position = enemy_position
		if enemy.has_method("apply_escape_grace"):
			enemy.apply_escape_grace(ESCAPE_GRACE_SECONDS)
		break
	return true
