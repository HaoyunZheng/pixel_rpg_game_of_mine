extends Node
## Log — 全局分级日志（autoload）
## 统一 [模块] 前缀输出，支持按等级静音。发布构建把 min_level 调到 WARN 即可压掉调试噪声。
## 用法：Log.info("Battle", "进入战斗") / Log.warn("GameData", "配置缺失")

enum Level { DEBUG, INFO, WARN, ERROR }

## 低于此等级的日志被丢弃。
var min_level: Level = Level.DEBUG

func debug(tag: String, message: String) -> void:
	_emit(Level.DEBUG, tag, message)

func info(tag: String, message: String) -> void:
	_emit(Level.INFO, tag, message)

func warn(tag: String, message: String) -> void:
	_emit(Level.WARN, tag, message)

func error(tag: String, message: String) -> void:
	_emit(Level.ERROR, tag, message)

func _emit(level: Level, tag: String, message: String) -> void:
	if level < min_level:
		return
	var line := "[%s] %s" % [tag, message]
	match level:
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
		_:
			print(line)
