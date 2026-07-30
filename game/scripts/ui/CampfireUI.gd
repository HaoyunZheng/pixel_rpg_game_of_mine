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

@onready var _panel: PanelContainer = $Overlay/Center/Panel
@onready var _title: Label = $Overlay/Center/Panel/Content/Title
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


func open(campfire_name: String) -> void:
	if _is_open:
		return
	_is_open = true
	_tree_was_paused = get_tree().paused
	_pause_claim_active = true
	_title.text = "篝火 · %s" % campfire_name
	_status.text = DESCRIPTIONS[0]
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
	_status.text = DESCRIPTIONS[index]
	_play_sfx(MOVE_SFX, -12.0)


func _on_rest_pressed() -> void:
	if GameData.rest_party():
		_status.text = "火焰抚平伤口。全队 HP / MP 已恢复。"
	else:
		_status.text = "没有同行者能够回应这团火。"
	_play_sfx(CONFIRM_SFX, -8.0)


func _on_upgrade_pressed() -> void:
	_status.text = "当前没有可用于升级的余烬。"
	_play_sfx(CONFIRM_SFX, -10.0)


func _on_skill_pressed() -> void:
	_status.text = "当前没有可分配的技能点。"
	_play_sfx(CONFIRM_SFX, -10.0)


func _on_travel_pressed() -> void:
	_status.text = "尚未发现其它篝火。"
	_play_sfx(CONFIRM_SFX, -10.0)


func _play_sfx(stream: AudioStream, volume_db: float) -> void:
	_sfx.stream = stream
	_sfx.volume_db = volume_db
	_sfx.play()
