extends Node
## GameData — 全局状态单例
## 管理队伍、背包、剧情标志位、诅咒值/羁绊值等持久化数据。

signal item_used(item_id: String)
signal item_equipped(item_id: String, slot: String)
signal item_unequipped(item_id: String, slot: String)
signal item_discarded(item_id: String, count: int)

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

# 装备槽位（值 = item_id，空串 = 未装备）
var equipment: Dictionary = {"weapon": "", "armor": "", "accessory": ""}

# Demo 初始物品（id → 数量）。正式获取途径（拾取/掉落）接入后可清空。
const INITIAL_ITEMS: Dictionary = {
	"res://assets/data/items/item_ash_salve.tres": 2,
	"res://assets/data/items/item_glimmer_water.tres": 1,
	"res://assets/data/items/item_shardstone.tres": 1,
	"res://assets/data/items/item_throwing_knives.tres": 1,
	"res://assets/data/items/item_bandage_kit.tres": 1,
	"res://assets/data/items/item_black_sack.tres": 1,
	"res://assets/data/items/item_red_pouch.tres": 1,
}

# ── 已击败的明雷敌人（按 encounter_key 记录，胜利写入；野外场景加载时据此移除实例）──
var defeated_enemies: Dictionary = {}

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

func mark_enemy_defeated(enemy_key: String) -> void:
	defeated_enemies[enemy_key] = true

func is_enemy_defeated(enemy_key: String) -> bool:
	return defeated_enemies.get(enemy_key, false)

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

## 使用消耗品：仅处理 HEAL_HP/HEAL_MP，对队伍首位成员生效。
func use_item(item_id: String) -> bool:
	var item: ItemData = get_item_by_id(item_id)
	if item == null:
		return false
	var member: Dictionary = party_members[0]
	match item.effect_type:
		ItemData.EffectType.HEAL_HP:
			member.hp = clampi(member.hp + item.effect_value, 0, member.max_hp)
		ItemData.EffectType.HEAL_MP:
			member.mp = clampi(member.mp + item.effect_value, 0, member.max_mp)
		_:
			Log.warn("GameData", "use_item: 不支持的 effect_type: %s" % item.effect_type)
			return false
	if not remove_item(item_id, 1):
		return false
	item_used.emit(item_id)
	return true

## 装备物品：按 category 映射槽位，槽位已占用先卸下旧物品。
func equip_item(item_id: String) -> bool:
	var item: ItemData = get_item_by_id(item_id)
	if item == null:
		return false
	var slot: String
	match item.category:
		ItemData.ItemCategory.WEAPON:
			slot = "weapon"
		ItemData.ItemCategory.ARMOR:
			slot = "armor"
		ItemData.ItemCategory.ACCESSORY:
			slot = "accessory"
		_:
			return false
	if not equipment[slot].is_empty():
		unequip_item(slot)
	equipment[slot] = item_id
	item_equipped.emit(item_id, slot)
	return true

## 卸下指定槽位的装备。
func unequip_item(slot: String) -> bool:
	var old_id: String = equipment.get(slot, "")
	if old_id.is_empty():
		return false
	equipment[slot] = ""
	item_unequipped.emit(old_id, slot)
	return true

## 丢弃物品：若该物品已装备，先自动卸下，避免悬空 id。
func discard_item(item_id: String, count: int) -> bool:
	for slot in equipment:
		if equipment[slot] == item_id:
			unequip_item(slot)
	var result := remove_item(item_id, count)
	if result:
		item_discarded.emit(item_id, count)
	return result

## 按 id 查找背包中的物品资源，找不到返回 null。
func get_item_by_id(item_id: String) -> ItemData:
	for slot in inventory:
		if slot.item.id == item_id:
			return slot.item
	return null

## 该物品当前是否已装备。
func is_item_equipped(item_id: String) -> bool:
	for slot in equipment:
		if equipment[slot] == item_id:
			return true
	return false

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
