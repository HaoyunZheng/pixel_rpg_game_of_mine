extends Node
## CC0 战斗特效导入检查：只验证源文件与 SpriteFrames 切帧契约。

const FRAMES_PATH: String = "res://assets/derived/combat_vfx/combat_attack_frames.tres"
const SOURCE_PATHS: Array[String] = [
	"res://assets/derived/combat_vfx/source/pixel_art_sword_slash_sprites.png",
	"res://assets/derived/combat_vfx/source/black_and_white_ray.png",
	"res://assets/derived/combat_vfx/source/arcane_bolt.png",
	"res://assets/derived/combat_vfx/source/blade_red_34.png",
	"res://assets/derived/combat_vfx/source/blade_red_35.png",
]
const EXPECTED_FRAMES: Dictionary = {
	&"hunter_ray": 8,
	&"hunter_bolt": 6,
	&"mutant_slash": 9,
	&"mutant_claw": 2,
}

func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for source_path: String in SOURCE_PATHS:
		if not FileAccess.file_exists(source_path):
			failures.append("缺少源图：%s" % source_path)
	var frames := load(FRAMES_PATH) as SpriteFrames
	if frames == null:
		failures.append("无法加载 SpriteFrames：%s" % FRAMES_PATH)
	else:
		for animation_name: StringName in EXPECTED_FRAMES:
			if not frames.has_animation(animation_name):
				failures.append("缺少动画：%s" % animation_name)
				continue
			var expected: int = int(EXPECTED_FRAMES[animation_name])
			var actual: int = frames.get_frame_count(animation_name)
			if actual != expected:
				failures.append("%s 帧数错误：%d != %d" % [animation_name, actual, expected])
	if failures.is_empty():
		print("[CombatVFXAssets] 资源检查通过：8/6/9/2 帧")
		await get_tree().process_frame
		get_tree().quit(OK)
		return
	for failure: String in failures:
		push_error("[CombatVFXAssets] %s" % failure)
	await get_tree().process_frame
	get_tree().quit(1)
