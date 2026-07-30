class_name CampfireUI
extends CanvasLayer
## 篝火整备菜单：暂停世界，复用战斗/背包主题并保持 Z/X/WASD 键盘闭环。

signal closed

const CONFIRM_SFX: AudioStreamWAV = preload(
	"res://assets/derived/audio/sfx/interface/shift_choice.wav")
const MOVE_SFX: AudioStreamWAV = preload(
	"res://assets/derived/audio/sfx/interface/moving_ui.wav")
const DESCRIPTIONS: Array[String] = [
	"恢复全队 HP / MP，并清除异常状态。",
	"消耗余烬提升等级。",
	"分配技能点，强化现有技能。",
	"前往已经点燃的篝火。",
	"离开篝火，返回荒林。",
]
const CAMPFIRE_DESTINATIONS: Dictionary = {
	&"forest_clearing": {
		"display_name": "林间空地",
		"scene_path": "res://scenes/ForestClearing.tscn",
		"scene_name": "ForestClearing",
		"spawn_id": "forest_clearing",
	},
	&"forest_ruins": {
		"display_name": "路边废墟",
		"scene_path": "res://scenes/ForestMain.tscn",
		"scene_name": "ForestMain",
		"spawn_id": "forest_ruins",
	},
}

@onready var _panel: PanelContainer = $Overlay/Center/Panel
@onready var _title: Label = $Overlay/Center/Panel/Content/Title
@onready var _subtitle: Label = $Overlay/Center/Panel/Content/Subtitle
@onready var _status: Label = $Overlay/Center/Panel/Content/Status
@onready var _sfx: AudioStreamPlayer = $UISFX
@onready var _buttons: Array[Button] = [
	$Overlay/Center/Panel/Content/RestButton,
	$Overlay/Center/Panel/Content/UpgradeButton,
	$Overlay/Center/Panel/Content/SkillButton,
	$Overlay/Center/Panel/Content/TravelButton,
	$Overlay/Center/Panel/Content/LeaveButton,
]

var _is_open: bool = false
var _pause_claim_active: bool = false
var _tree_was_paused: bool = false
var _current_campfire_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 20
	visible = false
	_panel.add_theme_stylebox_override("panel", InventoryWidgets.make_dialog_style())
	for index in range(_buttons.size()):
		var button := _buttons[index]
		_apply_button_style(button)
		button.focus_entered.connect(_on_button_focused.bind(index))
		button.mouse_entered.connect(button.grab_focus)
		var previous := _buttons[posmod(index - 1, _buttons.size())]
		var next := _buttons[posmod(index + 1, _buttons.size())]
		button.focus_neighbor_top = previous.get_path()
		button.focus_neighbor_bottom = next.get_path()
	$Overlay/Center/Panel/Content/RestButton.pressed.connect(_on_rest_pressed)
	$Overlay/Center/Panel/Content/UpgradeButton.pressed.connect(_on_upgrade_pressed)
	$Overlay/Center/Panel/Content/SkillButton.pressed.connect(_on_skill_pressed)
	$Overlay/Center/Panel/Content/TravelButton.pressed.connect(_on_travel_pressed)
	$Overlay/Center/Panel/Content/LeaveButton.pressed.connect(close)


func _exit_tree() -> void:
	_release_pause_claim()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_open or not event.pressed or event.echo:
		return
	if event is InputEventKey and event.keycode == KEY_X:
		get_viewport().set_input_as_handled()
		close()


func open(campfire_id: StringName, campfire_name: String) -> void:
	if _is_open:
		return
	_is_open = true
	_current_campfire_id = campfire_id
	_tree_was_paused = get_tree().paused
	_pause_claim_active = true
	_title.text = "篝火 · %s" % campfire_name
	_status.text = DESCRIPTIONS[0]
	_refresh_header()
	visible = true
	get_tree().paused = true
	_buttons[0].grab_focus()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_release_pause_claim()
	closed.emit()


func is_open() -> bool:
	return _is_open


func _release_pause_claim() -> void:
	if not _pause_claim_active:
		return
	_pause_claim_active = false
	var tree := get_tree()
	if tree != null:
		tree.paused = _tree_was_paused


func _apply_button_style(button: Button) -> void:
	var normal := BattleWidgets.make_cmd_cell_style()
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", normal)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = BattleWidgets.COL_GOLD
	focus.set_border_width_all(3)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", BattleWidgets.COL_BONE)
	button.add_theme_color_override("font_hover_color", BattleWidgets.COL_GOLD)
	button.add_theme_color_override("font_focus_color", BattleWidgets.COL_GOLD)
	button.add_theme_color_override("font_pressed_color", BattleWidgets.COL_GOLD.lightened(0.15))


func _on_button_focused(index: int) -> void:
	if not _is_open:
		return
	match index:
		1:
			_status.text = _get_upgrade_description()
		2:
			_status.text = _get_skill_description()
		3:
			_status.text = _get_travel_description()
		_:
			_status.text = DESCRIPTIONS[index]
	_play_sfx(MOVE_SFX, -12.0)


func _on_rest_pressed() -> void:
	if GameData.rest_party():
		_status.text = "火焰抚平伤口。全队 HP / MP 已恢复。"
	else:
		_status.text = "没有同行者能够回应这团火。"
	_play_sfx(CONFIRM_SFX, -8.0)


func _on_upgrade_pressed() -> void:
	var member := GameData.get_party_member(0)
	var cost := GameData.get_level_up_cost(0)
	if member == null:
		_status.text = "火焰中没有可辨认的身影。"
	elif cost <= 0:
		_status.text = "%s已达到当前可提升的极限。" % member.display_name
	elif GameData.upgrade_party_member(0):
		member = GameData.get_party_member(0)
		_status.text = "%s升至 Lv.%d，获得 1 技能点。" % [member.display_name, member.level]
	else:
		_status.text = "余烬不足：本次升级需要 %d。" % cost
	_refresh_header()
	_play_sfx(CONFIRM_SFX, -10.0)


func _on_skill_pressed() -> void:
	var member := GameData.get_party_member(0)
	var skill := _get_primary_skill(member)
	if member == null or skill == null:
		_status.text = "当前没有可强化的技能。"
	elif GameData.get_skill_rank(0, skill.id) >= skill.max_rank:
		_status.text = "%s已达到当前最高等级。" % skill.display_name
	elif GameData.upgrade_skill(0, skill.id):
		_status.text = "%s强化至 Lv.%d，威力提升。" % [
			skill.display_name, GameData.get_skill_rank(0, skill.id)]
	else:
		_status.text = "技能点不足；升级可获得技能点。"
	_play_sfx(CONFIRM_SFX, -10.0)


func _on_travel_pressed() -> void:
	var destination := _get_travel_destination()
	if destination.is_empty():
		_status.text = "尚未点燃其它篝火。"
		_play_sfx(CONFIRM_SFX, -10.0)
		return
	_play_sfx(CONFIRM_SFX, -10.0)
	close()
	SceneManager.change_scene(destination.scene_path, {
		"scene_name": destination.scene_name,
		"from": "campfire",
		"spawn_id": destination.spawn_id,
	})

func _refresh_header() -> void:
	_subtitle.text = "持有余烬 %d · 火星仍未熄灭" % GameData.get_ember_count()

func _get_upgrade_description() -> String:
	var member := GameData.get_party_member(0)
	if member == null:
		return "没有可升级的角色。"
	var cost := GameData.get_level_up_cost(0)
	if cost <= 0:
		return "%s Lv.%d｜已达当前上限" % [member.display_name, member.level]
	return "%s Lv.%d → Lv.%d｜需要余烬 %d" % [
		member.display_name, member.level, member.level + 1, cost]

func _get_skill_description() -> String:
	var member := GameData.get_party_member(0)
	var skill := _get_primary_skill(member)
	if member == null or skill == null:
		return "当前没有可强化的技能。"
	return "技能点 %d｜%s Lv.%d/%d" % [
		member.skill_points,
		skill.display_name,
		GameData.get_skill_rank(0, skill.id),
		skill.max_rank,
	]

func _get_travel_description() -> String:
	var destination := _get_travel_destination()
	if destination.is_empty():
		return "尚未点燃其它篝火。"
	return "前往已点燃的篝火：%s" % destination.display_name

func _get_travel_destination() -> Dictionary:
	# ponytail: Demo 只有两座篝火；出现第三座时再增加目的地选择层。
	for campfire_id: StringName in CAMPFIRE_DESTINATIONS:
		if campfire_id != _current_campfire_id \
				and GameData.is_campfire_discovered(campfire_id):
			return CAMPFIRE_DESTINATIONS[campfire_id]
	return {}

func _get_primary_skill(member: PartyMemberState) -> SkillData:
	if member == null or member.stats_res == null or member.stats_res.skills.is_empty():
		return null
	# ponytail: Demo 主角只有一个成长技能；新增第二个技能时再补选择层。
	return member.stats_res.skills[0] as SkillData


func _play_sfx(stream: AudioStream, volume_db: float) -> void:
	_sfx.stream = stream
	_sfx.volume_db = volume_db
	_sfx.play()
