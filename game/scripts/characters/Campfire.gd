class_name Campfire
extends Area2D
## 篝火交互体：靠近显示提示，按 Z 打开暂停式整备菜单。

const CAMPFIRE_UI_SCENE := preload("res://scenes/ui/CampfireUI.tscn")

@export var campfire_id: StringName = &""
@export var display_name: String = "无名篝火"

@onready var _prompt: Label = $Prompt

var _player_in_range: bool = false
var _campfire_ui = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or get_tree().paused or DialogueManager.is_active():
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_prompt.visible = false
		_open_menu()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_in_range = true
	_prompt.visible = not get_tree().paused and not DialogueManager.is_active()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_in_range = false
	_prompt.visible = false


func _open_menu() -> void:
	if _campfire_ui == null:
		_campfire_ui = CAMPFIRE_UI_SCENE.instantiate()
		add_child(_campfire_ui)
		_campfire_ui.closed.connect(_on_menu_closed)
	GameData.discover_campfire(campfire_id)
	var save_error := GameData.save_checkpoint(campfire_id)
	_campfire_ui.open(campfire_id, display_name, save_error == OK)


func _on_menu_closed() -> void:
	GameData.save_checkpoint(campfire_id)
	_prompt.visible = _player_in_range and not DialogueManager.is_active()
