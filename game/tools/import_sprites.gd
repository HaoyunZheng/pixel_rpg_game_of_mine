# import_sprites.gd  —  Godot 4.x headless 导入器
# ============================================================
# 作用:扫描 res://assets/sprites/<角色>/frames.json + sheet.png,
#       用 AtlasTexture 从大图开窗切片(零额外贴图开销),
#       构造 SpriteFrames 并存成 .tres,可直接挂给 AnimatedSprite2D。
#
# 运行(由 pipeline.py 第④段自动调用,也可手动跑):
#   /Applications/Godot.app/Contents/MacOS/Godot \
#       --headless --path <你的项目> --script res://tools/import_sprites.gd
#
# frames.json 结构示例:
#   {
#     "character": "knight",
#     "cell_width": 32, "cell_height": 32, "fps": 8,
#     "animations": { "idle": {"row":0,"frames":4},
#                     "walk": {"row":1,"frames":6},
#                     "attack": {"row":2,"frames":5} }
#   }
# ============================================================
extends SceneTree

const SPRITES_DIR := "res://assets/sprites"


func _initialize() -> void:
	var count := _import_all()
	print("[import_sprites] 完成,共生成 %d 个 SpriteFrames 资源。" % count)
	quit()


func _import_all() -> int:
	var made := 0
	var root := DirAccess.open(SPRITES_DIR)
	if root == null:
		push_warning("找不到目录: %s" % SPRITES_DIR)
		return 0

	root.list_dir_begin()
	var name := root.get_next()
	while name != "":
		if root.current_is_dir() and not name.begins_with("."):
			var char_dir := "%s/%s" % [SPRITES_DIR, name]
			if _import_character(char_dir):
				made += 1
		name = root.get_next()
	root.list_dir_end()
	return made


func _import_character(char_dir: String) -> bool:
	var json_path := char_dir + "/frames.json"
	var sheet_path := char_dir + "/sheet.png"

	if not FileAccess.file_exists(json_path) or not FileAccess.file_exists(sheet_path):
		return false

	# --- 读 frames.json ---
	var txt := FileAccess.get_file_as_string(json_path)
	var meta = JSON.parse_string(txt)
	if typeof(meta) != TYPE_DICTIONARY:
		push_warning("frames.json 解析失败: %s" % json_path)
		return false

	var cw : int = int(meta.get("cell_width", 32))
	var ch : int = int(meta.get("cell_height", 32))
	var fps : float = float(meta.get("fps", 8))
	var animations : Dictionary = meta.get("animations", {})

	# --- 加载精灵表为纹理 ---
	var img := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
	if img == null:
		# 退回 res:// 加载方式
		var t := load(sheet_path)
		if t == null:
			push_warning("无法加载 sheet.png: %s" % sheet_path)
			return false
		img = (t as Texture2D).get_image()
	var sheet_tex := ImageTexture.create_from_image(img)

	# --- 构造 SpriteFrames ---
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")

	for anim_name in animations.keys():
		var info : Dictionary = animations[anim_name]
		var row : int = int(info.get("row", 0))
		var frames : int = int(info.get("frames", 1))

		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, fps)
		sf.set_animation_loop(anim_name, anim_name != "attack")  # 攻击默认不循环

		for col in range(frames):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet_tex
			atlas.region = Rect2(col * cw, row * ch, cw, ch)
			atlas.filter_clip = true
			sf.add_frame(anim_name, atlas)

	# --- 存盘 ---
	var char_name := char_dir.get_file()
	var out_path := "%s/%s_frames.tres" % [char_dir, char_name]
	var err := ResourceSaver.save(sf, out_path)
	if err != OK:
		push_warning("保存失败(%d): %s" % [err, out_path])
		return false
	print("[import_sprites] %s → %s  (%d 个动画)" % [char_name, out_path, animations.size()])
	return true
