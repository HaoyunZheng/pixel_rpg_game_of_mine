extends Node
## 对话系统包装层（AutoLoad）——见《对话系统文档》§5 / 附录 B.4。
##
## 职责边界：项目内一切对话触发都收敛到这里，外部系统只持有 dialogue_id，
## 不直接调用 Dialogic API、也不直接持有 timeline 资源路径。
##   · 触发入口：start(dialogue_id, context) → 映射到 Dialogic timeline 并播放。
##   · 生命周期：收敛开始/结束信号，由场景层恢复玩家控制。
## Dialogic 管理剧情阶段、选择和 NPC 叙事状态；GameData 保持玩法状态权威。

## 对话开始（已映射到 timeline、Dialogic 即将播放）。
signal dialogue_started(dialogue_id: String)
## 对话结束且结果已回流（场景层据此恢复输入）。
signal dialogue_finished(dialogue_id: String)

## dialogue_id → timeline 资源路径。外部只认 dialogue_id，路径变更只改这里。
const REGISTRY: Dictionary = {
	"forest_wanderer": "res://dialogue/timelines/forest_wanderer.dtl",
	"forest_main_wood_sign": "res://dialogue/timelines/forest_main_wood_sign.dtl",
	"forest_main_stone_sign": "res://dialogue/timelines/forest_main_stone_sign.dtl",
}
const TYPEWRITER_SFX: AudioStreamWAV = preload("res://assets/derived/audio/sfx/interface/speaking.wav")

var _active_id: String = ""
## 是否有对话正在进行（场景层据此互斥：屏蔽移动 / 二次触发）。
func is_active() -> bool:
	return _active_id != ""

## 启动一段对话。
## dialogue_id：REGISTRY 中登记的键。
## context 保留作调用兼容；剧情变量由 Timeline 的 Set/Condition 事件管理。
## 返回是否成功启动（重复触发 / 未登记 / 资源缺失时返回 false）。
@warning_ignore("unused_parameter")
func start(dialogue_id: String, context: Dictionary = {}) -> bool:
	if is_active():
		Log.warn("DialogueManager", "已有对话进行中，忽略新触发: %s" % dialogue_id)
		return false

	var timeline_path: String = REGISTRY.get(dialogue_id, "")
	if timeline_path.is_empty():
		Log.warn("DialogueManager", "未登记的 dialogue_id: %s" % dialogue_id)
		return false
	if not ResourceLoader.exists(timeline_path):
		push_error("[DialogueManager] start: timeline 资源缺失: %s" % timeline_path)
		return false

	_active_id = dialogue_id

	if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.connect(_on_timeline_ended)

	var layout: Node = Dialogic.start(timeline_path)
	if layout != null:
		if layout.is_node_ready():
			_configure_typewriter_sound()
		else:
			layout.ready.connect(_configure_typewriter_sound, CONNECT_ONE_SHOT)
	dialogue_started.emit(dialogue_id)
	Log.info("DialogueManager", "对话开始: %s" % dialogue_id)
	return true

func _on_timeline_ended() -> void:
	var ended_id: String = _active_id
	_active_id = ""

	if Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_timeline_ended)

	dialogue_finished.emit(ended_id)
	Log.info("DialogueManager", "对话结束: %s" % ended_id)

func _configure_typewriter_sound() -> void:
	var sounds: Array[AudioStream] = [TYPEWRITER_SFX]
	for node in get_tree().get_nodes_in_group(&"dialogic_type_sounds"):
		if node is DialogicNode_TypeSounds:
			var type_sound := node as DialogicNode_TypeSounds
			type_sound.sounds = sounds
			type_sound.mode = DialogicNode_TypeSounds.Modes.INTERRUPT
			type_sound.play_every_character = 1
			type_sound.volume_db = -10.0
			type_sound.bus = &"UI"
