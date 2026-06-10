extends Node
## GameData — 全局状态单例
## 管理队伍、背包、剧情标志位、诅咒值/羁绊值等持久化数据。

const MEOWA_API_KEY_ENV: String = "MEOWA_API_KEY"
const MEOWA_LOCAL_CONFIG_PATH: String = "res://secrets/meowa.cfg"
const MEOWA_CONFIG_SECTION: String = "meowa"
const MEOWA_API_KEY_FIELD: String = "api_key"

# ── 队伍状态 ──
var party_members: Array[Dictionary] = []
var current_scene_name: String = ""

# ── 剧情标志位（用于分支条件、NPC 阵营翻转等）──
var flags: Dictionary = {}

# ── 诅咒值 / 羁绊值（P4 启用，P0 预留结构）──
# curse_values[character_id] = int
var curse_values: Dictionary = {}
# bond_values[character_id] = int  （主角与该同伴的羁绊值）
var bond_values: Dictionary = {}

# ── 背包（P3 启用：战斗内使用；野外拾取/战斗掉落后续接入）──
# 槽位结构：{ "item": ItemData, "count": int }
var inventory: Array[Dictionary] = []

# Demo 初始物品（id → 数量）。正式获取途径（拾取/掉落）接入后可清空。
const INITIAL_ITEMS: Dictionary = {
	"res://assets/data/items/item_ash_salve.tres": 2,
	"res://assets/data/items/item_glimmer_water.tres": 1,
	"res://assets/data/items/item_shardstone.tres": 1,
}

# ── 周目识别（前向兼容预留）──
var cycle_count: int = 1

# ── 外部服务配置 ──
var meowa_api_key: String = ""

func _ready() -> void:
	Log.info("GameData", "全局状态单例已加载")
	_apply_default_fullscreen()
	_load_meowa_api_key()
	_init_party()
	_init_inventory()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _apply_default_fullscreen() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func set_flag(key: String, value: bool = true) -> void:
	flags[key] = value

func get_flag(key: String, default: bool = false) -> bool:
	return flags.get(key, default)

func has_meowa_api_key() -> bool:
	return not meowa_api_key.is_empty()

func get_meowa_api_key() -> String:
	return meowa_api_key

func set_curse(character_id: String, value: int) -> void:
	curse_values[character_id] = clampi(value, 0, 100)

func get_curse(character_id: String) -> int:
	return curse_values.get(character_id, 0)

func set_bond(character_id: String, value: int) -> void:
	bond_values[character_id] = clampi(value, 0, 10)

func get_bond(character_id: String) -> int:
	return bond_values.get(character_id, 0)

# ── 背包接口 ──

func add_item(item: ItemData, n: int = 1) -> void:
	for slot in inventory:
		if slot.item.id == item.id:
			slot.count += n
			return
	inventory.append({"item": item, "count": n})

## 扣减指定物品。数量不足时不扣并返回 false；扣到 0 移除该槽位。
func remove_item(item_id: String, n: int = 1) -> bool:
	for slot in inventory:
		if slot.item.id == item_id:
			if slot.count < n:
				return false
			slot.count -= n
			if slot.count <= 0:
				inventory.erase(slot)
			return true
	return false

func get_item_count(item_id: String) -> int:
	for slot in inventory:
		if slot.item.id == item_id:
			return slot.count
	return 0

## 背包快照/回滚（§B.2 战斗数据隔离：失败丢弃物品消耗）
func duplicate_inventory() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for slot in inventory:
		snapshot.append({"item": slot.item, "count": slot.count})
	return snapshot

func restore_inventory(snapshot: Array[Dictionary]) -> void:
	inventory = snapshot

## 初始化队伍（P2）
func _init_party() -> void:
	if not party_members.is_empty():
		return
	var player_stats = load("res://assets/data/characters/char_player.tres")
	var companion_stats = load("res://assets/data/characters/char_companion.tres")
	party_members = [
		_create_member_from_stats(player_stats),
		_create_member_from_stats(companion_stats),
	]
	Log.info("GameData", "队伍初始化完成: %d 人" % party_members.size())

## 初始化背包（P3）
func _init_inventory() -> void:
	if not inventory.is_empty():
		return
	for path in INITIAL_ITEMS:
		var item: ItemData = load(path)
		if item != null:
			add_item(item, INITIAL_ITEMS[path])
	Log.info("GameData", "背包初始化完成: %d 种物品" % inventory.size())

func _create_member_from_stats(stats) -> Dictionary:
	return {
		"id": stats.id,
		"display_name": stats.display_name,
		"hp": stats.max_hp,
		"mp": stats.max_mp,
		"max_hp": stats.max_hp,
		"max_mp": stats.max_mp,
		"atk": stats.atk,
		"def": stats.def,
		"spd": stats.spd,
		"stats_res": stats,
		"status_effects": [] as Array[StatusEffect],
	}

func _load_meowa_api_key() -> void:
	meowa_api_key = OS.get_environment(MEOWA_API_KEY_ENV).strip_edges()
	if not meowa_api_key.is_empty():
		Log.info("GameData", "Meowa API Key 已从环境变量加载")
		return

	var config := ConfigFile.new()
	var error := config.load(MEOWA_LOCAL_CONFIG_PATH)
	if error != OK:
		Log.warn("GameData", "未找到 Meowa API Key 配置，AI 接口将不可用")
		return

	var api_key = config.get_value(MEOWA_CONFIG_SECTION, MEOWA_API_KEY_FIELD, "")
	if api_key is String:
		meowa_api_key = api_key.strip_edges()

	if meowa_api_key.is_empty():
		Log.warn("GameData", "Meowa API Key 配置为空，AI 接口将不可用")
	else:
		Log.info("GameData", "Meowa API Key 已从本地配置加载")
