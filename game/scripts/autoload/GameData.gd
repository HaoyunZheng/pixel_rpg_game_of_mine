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

# ── 背包（P4 启用，P0 预留结构）──
var inventory: Array[Dictionary] = []

# ── 周目识别（前向兼容预留）──
var cycle_count: int = 1

# ── 外部服务配置 ──
var meowa_api_key: String = ""

func _ready() -> void:
	Log.info("GameData", "全局状态单例已加载")
	_apply_default_fullscreen()
	_load_meowa_api_key()
	_init_party()

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
