extends Node
## 对话系统包装层（AutoLoad）——见《对话系统文档》§5 / 附录 B.4。
##
## 职责边界：项目内一切对话触发都收敛到这里，外部系统只持有 dialogue_id，
## 不直接调用 Dialogic API、也不直接持有 timeline 资源路径。
##   · 触发入口：start(dialogue_id, context) → 映射到 Dialogic timeline 并播放。
##   · 结果回流：timeline 结束后，按 context 里的钩子写回 GameData（剧情 flag、羁绊等），
##     再 emit dialogue_finished，由场景层恢复玩家控制。
## GameData 始终是剧情 flag / 羁绊 / 诅咒的唯一权威；Dialogic 变量只服务表现层。

## 对话开始（已映射到 timeline、Dialogic 即将播放）。
signal dialogue_started(dialogue_id: String)
## 对话结束且结果已回流（场景层据此恢复输入）。
signal dialogue_finished(dialogue_id: String)

## dialogue_id → timeline 资源路径。外部只认 dialogue_id，路径变更只改这里。
const REGISTRY: Dictionary = {
	"forest_wanderer": "res://dialogue/timelines/forest_wanderer.dtl",
}

var _active_id: String = ""
var _active_context: Dictionary = {}

## 是否有对话正在进行（场景层据此互斥：屏蔽移动 / 二次触发）。
func is_active() -> bool:
	return _active_id != ""

## 启动一段对话。
## dialogue_id：REGISTRY 中登记的键。
## context：运行时上下文与结束钩子，可含：
##   "set_flags": PackedStringArray —— 结束时写入的剧情 flag。
##   "bond_add":  Dictionary[character_id → int] —— 结束时为该同伴推进的羁绊增量。
## 返回是否成功启动（重复触发 / 未登记 / 资源缺失时返回 false）。
func start(dialogue_id: String, context: Dictionary = {}) -> bool:
	if is_active():
		Log.warn("DialogueManager", "已有对话进行中，忽略新触发: %s" % dialogue_id)
		return false

	var timeline_path: String = REGISTRY.get(dialogue_id, "")
	if timeline_path.is_empty():
		push_error("[DialogueManager] start: 未登记的 dialogue_id: %s" % dialogue_id)
		return false
	if not ResourceLoader.exists(timeline_path):
		push_error("[DialogueManager] start: timeline 资源缺失: %s" % timeline_path)
		return false

	_active_id = dialogue_id
	_active_context = context

	if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.connect(_on_timeline_ended)

	Dialogic.start(timeline_path)
	dialogue_started.emit(dialogue_id)
	Log.info("DialogueManager", "对话开始: %s" % dialogue_id)
	return true

func _on_timeline_ended() -> void:
	var ended_id: String = _active_id
	var context: Dictionary = _active_context
	_active_id = ""
	_active_context = {}

	if Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_timeline_ended)

	_apply_end_hooks(context)
	dialogue_finished.emit(ended_id)
	Log.info("DialogueManager", "对话结束并回流: %s" % ended_id)

## 把对话结果写回 GameData（唯一权威）。新增回流类型在此扩展。
func _apply_end_hooks(context: Dictionary) -> void:
	for flag in context.get("set_flags", PackedStringArray()):
		GameData.set_flag(flag)

	var bond_add: Dictionary = context.get("bond_add", {})
	for character_id in bond_add:
		GameData.set_bond(character_id, GameData.get_bond(character_id) + int(bond_add[character_id]))
