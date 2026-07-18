class_name InteractableNPC
extends Area2D
## 可交互 NPC / 触发体 —— 走近后按交互键（Z）启动一段对话。
## 触发统一走 DialogueManager.start(dialogue_id, context)，不直接碰 Dialogic。
## 占位表现：友方绿（见《通用文档》附录 B.1）；提示标签随玩家进出范围显隐。

## REGISTRY 中登记的对话键。
@export var dialogue_id: String = ""

@onready var _prompt: Node = get_node_or_null("Prompt")

var _player_in_range: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_set_prompt_visible(false)

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_in_range = true
		_set_prompt_visible(not DialogueManager.is_active())

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_in_range = false
		_set_prompt_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or DialogueManager.is_active():
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_set_prompt_visible(false)
		DialogueManager.start(dialogue_id)

func _set_prompt_visible(value: bool) -> void:
	if _prompt is CanvasItem:
		(_prompt as CanvasItem).visible = value
