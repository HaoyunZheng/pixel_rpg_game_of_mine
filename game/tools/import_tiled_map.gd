# import_tiled_map.gd  —  Godot 4.x headless 转换器
# ============================================================
# 作用：把 Meowa/Tiled 导出的 map.tiled.json + 贴图，转成：
#   (a) 一个 TileSet 资源（.tres，地面 atlas 源）
#   (b) 一个「纯地图」场景（.tscn）：灰底 + Ground 瓦片层
#       + Objects 对象精灵（树/石等，带脚部碰撞）
#       + Bounds 边界碰撞（贴着空地边缘的一圈 void 格）
#
# 地面有两种导出形态（按 MAPS 配置的 dual_grid 区分）：
#   - 烘焙式（forest-clearing）：tiled.json 的 gid 已是最终显示瓦片，逐格直渲。
#   - dual-grid-15（wilderness）：tiled.json 的 gid 只是逻辑占位（Meowa 有损导出），
#     需按「半格偏移显示网格 + 四角 mask 选边缘瓦片」重建画面（映射表见
#     DUAL_GRID_TILE，由 preview.png 逐格反推验证）。
# 树/石是「对象」（任意像素坐标），按 Sprite2D 摆放，不进 TileSet。
#
# 运行（同 import_sprites 风格，headless）：
#   /Applications/Godot.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/import_tiled_map.gd \
#       -- --map <地图名>           # 不传默认 forest-clearing
#
# 注：每张导出的资产绑定在下方 MAPS 配置表里显式列出（便于审阅）；
#     数据量大的部分（瓦片、对象）全部由 JSON 驱动。
# ============================================================
extends SceneTree

# 每个对象 tileset（按 firstgid 区分）：贴图 + 脚部碰撞参数。
# foot_dy = 脚部碰撞点在精灵中心下方多少像素（碰撞点 / body 原点），
# foot_w / foot_h = 脚部碰撞矩形尺寸。
const MAPS := {
	"forest-clearing": {
		"dir": "res://assets/maps/forest-clearing",
		"tileset_out": "res://assets/maps/forest-clearing/forest_clearing_tileset.tres",
		"scene_out": "res://scenes/ForestClearingMap.tscn",
		"root_name": "ForestClearingMap",
		"bg_color": "909090",  # 复现 preview 的灰底（可后调）
		"ground_pngs": {
			1: "res://assets/maps/forest-clearing/tileset_25404.png",
			17: "res://assets/maps/forest-clearing/tileset_25386.png",
			33: "res://assets/maps/forest-clearing/tileset_25413.png",
		},
		"object_pngs": {
			49: {"png": "res://assets/maps/forest-clearing/tree_vine_umbrella.png",
				"foot_dy": 22.0, "foot_w": 26.0, "foot_h": 12.0, "prefix": "Tree"},
		},
	},
	"wilderness": {
		"dir": "res://assets/maps/wilderness",
		"tileset_out": "res://assets/maps/wilderness/wilderness_tileset.tres",
		"scene_out": "res://scenes/WildernessMap.tscn",
		"root_name": "WildernessMap",
		"bg_color": "909090",
		"dual_grid": true,
		"ground_pngs": {
			1: "res://assets/maps/wilderness/tileset_wild_ground.png",
		},
		"object_pngs": {
			17: {"png": "res://assets/maps/wilderness/tree_pine.png",
				"foot_dy": 22.0, "foot_w": 26.0, "foot_h": 12.0, "prefix": "Tree"},
			18: {"png": "res://assets/maps/wilderness/rock_pile.png",
				"foot_dy": 16.0, "foot_w": 44.0, "foot_h": 20.0, "prefix": "RockPile"},
			19: {"png": "res://assets/maps/wilderness/rock_boulder.png",
				"foot_dy": 16.0, "foot_w": 40.0, "foot_h": 18.0, "prefix": "Boulder"},
		},
	},
}

# dual-grid-15：四角占用 mask（TL=8 TR=4 BL=2 BR=1）-> 4×4 图集坐标。
# 由 preview.png 对照逻辑网格逐显示格反推得到，15 个 mask 全部唯一命中。
const DUAL_GRID_TILE := {
	1: Vector2i(1, 3), 2: Vector2i(0, 0), 3: Vector2i(3, 0), 4: Vector2i(0, 2),
	5: Vector2i(1, 0), 6: Vector2i(2, 3), 7: Vector2i(1, 1), 8: Vector2i(3, 3),
	9: Vector2i(0, 1), 10: Vector2i(3, 2), 11: Vector2i(2, 0), 12: Vector2i(1, 2),
	13: Vector2i(2, 2), 14: Vector2i(3, 1), 15: Vector2i(2, 1),
}

var _cfg: Dictionary = {}
var _meta_by_firstgid: Dictionary = {}   # firstgid -> {tilecount, columns, source_id}


func _initialize() -> void:
	var map_name := "forest-clearing"
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--map" and i + 1 < user_args.size():
			map_name = user_args[i + 1]
	if not MAPS.has(map_name):
		push_error("[import_tiled_map] 未知地图: %s（可选: %s）" % [map_name, MAPS.keys()])
		quit(1)
		return
	_cfg = MAPS[map_name]
	print("[import_tiled_map] 转换地图: %s" % map_name)

	var data = _read_json(str(_cfg["dir"]) + "/map.tiled.json")
	if data == null:
		push_error("[import_tiled_map] 读取/解析 map.tiled.json 失败")
		quit(1)
		return

	var tileset := _build_tileset(data)
	var tileset_out := str(_cfg["tileset_out"])
	if ResourceSaver.save(tileset, tileset_out) != OK:
		push_error("[import_tiled_map] 保存 TileSet 失败: %s" % tileset_out)
		quit(1)
		return
	print("[import_tiled_map] TileSet 已写出 → %s" % tileset_out)

	var root := _build_scene(data)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("[import_tiled_map] PackedScene.pack 失败")
		quit(1)
		return
	var scene_out := str(_cfg["scene_out"])
	if ResourceSaver.save(packed, scene_out) != OK:
		push_error("[import_tiled_map] 保存场景失败: %s" % scene_out)
		quit(1)
		return
	print("[import_tiled_map] 地图场景已写出 → %s" % scene_out)
	quit()


func _read_json(res_path: String):
	if not FileAccess.file_exists(res_path):
		push_error("找不到文件: %s" % res_path)
		return null
	var txt := FileAccess.get_file_as_string(res_path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed


# --- 构造 TileSet：地面 atlas 源 -----------------------------------
func _build_tileset(data: Dictionary) -> TileSet:
	var ground_pngs: Dictionary = _cfg["ground_pngs"]
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(int(data["tilewidth"]), int(data["tileheight"]))

	var source_id := 0
	for ts in data["tilesets"]:
		var fg := int(ts["firstgid"])
		if not ground_pngs.has(fg):
			continue  # 对象 tileset（树/石）跳过
		var columns := int(ts["columns"])
		var tilecount := int(ts["tilecount"])
		var rows := int(ceil(float(tilecount) / float(columns)))

		var src := TileSetAtlasSource.new()
		src.texture = load(ground_pngs[fg])
		src.texture_region_size = tileset.tile_size
		for y in rows:
			for x in columns:
				src.create_tile(Vector2i(x, y))
		tileset.add_source(src, source_id)

		_meta_by_firstgid[fg] = {
			"tilecount": tilecount, "columns": columns, "source_id": source_id,
		}
		source_id += 1
	return tileset


# gid -> [source_id, atlas_coords]，找不到返回空数组
func _resolve_gid(gid: int) -> Array:
	for fg in _meta_by_firstgid:
		var fgi := int(fg)
		var m: Dictionary = _meta_by_firstgid[fg]
		if gid >= fgi and gid < fgi + int(m["tilecount"]):
			var local := gid - fgi
			var cols := int(m["columns"])
			return [int(m["source_id"]), Vector2i(local % cols, local / cols)]
	return []


# 对象 gid -> object_pngs 配置（单格对象 tileset，firstgid 即 gid）
func _resolve_object(gid: int) -> Dictionary:
	var object_pngs: Dictionary = _cfg["object_pngs"]
	if object_pngs.has(gid):
		return object_pngs[gid]
	return {}


# --- 构造「纯地图」场景 -------------------------------------------
func _build_scene(data: Dictionary) -> Node2D:
	var width := int(data["width"])
	var height := int(data["height"])
	var tw := int(data["tilewidth"])
	var th := int(data["tileheight"])

	var root := Node2D.new()
	root.name = str(_cfg["root_name"])

	# 灰底：放大覆盖地图 + 四周留白，保证静态相机视野内都是灰
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(str(_cfg["bg_color"]))
	bg.position = Vector2(-tw * 8, -th * 8)
	bg.size = Vector2(width * tw + tw * 16, height * th + th * 16)
	root.add_child(bg)

	# Ground 瓦片层
	var tile_data: Array = _find_layer(data, "tilelayer")["data"]
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = load(str(_cfg["tileset_out"]))  # 已写盘，按 ext_resource 引用
	var painted := 0
	if bool(_cfg.get("dual_grid", false)):
		# dual-grid-15：显示网格比逻辑网格大一圈、错开半格；
		# 每个显示格按其覆盖的 4 个逻辑格的占用情况选边缘瓦片。
		ground.position = Vector2(-tw * 0.5, -th * 0.5)
		for dr in range(height + 1):
			for dc in range(width + 1):
				var mask := 0
				if _logical_filled(tile_data, width, height, dc - 1, dr - 1):
					mask |= 8  # TL
				if _logical_filled(tile_data, width, height, dc, dr - 1):
					mask |= 4  # TR
				if _logical_filled(tile_data, width, height, dc - 1, dr):
					mask |= 2  # BL
				if _logical_filled(tile_data, width, height, dc, dr):
					mask |= 1  # BR
				if mask == 0:
					continue
				ground.set_cell(Vector2i(dc, dr), 0, DUAL_GRID_TILE[mask])
				painted += 1
	else:
		# 烘焙式：gid 即最终显示瓦片
		for i in range(tile_data.size()):
			var gid := int(tile_data[i])
			if gid == 0:
				continue
			var r := _resolve_gid(gid)
			if r.is_empty():
				continue
			ground.set_cell(Vector2i(i % width, i / width), r[0], r[1])
			painted += 1
	root.add_child(ground)

	# Objects 对象（Tiled tile-object：(x,y) 为底边左下角）
	# 每个对象 = StaticBody2D（原点落在脚部）+ 子 Sprite（上移还原画面）+ 子 Foot 碰撞
	var objects := Node2D.new()
	objects.name = "Objects"
	var tex_cache: Dictionary = {}     # png 路径 -> Texture2D
	var shape_cache: Dictionary = {}   # "宽x高" -> RectangleShape2D（同类共享）
	var obj_layer = _find_layer(data, "objectgroup")
	var obj_count := 0
	if obj_layer != null:
		for obj in obj_layer["objects"]:
			var ocfg := _resolve_object(int(obj.get("gid", 0)))
			if ocfg.is_empty():
				continue
			var foot_dy := float(ocfg["foot_dy"])
			var center := Vector2(
				float(obj["x"]) + float(obj["width"]) * 0.5,
				float(obj["y"]) - float(obj["height"]) * 0.5)
			var body := StaticBody2D.new()  # 默认 collision_layer=1，与 Bounds 一致
			body.name = "%s_%d" % [str(ocfg["prefix"]), int(obj["id"])]
			body.position = center + Vector2(0, foot_dy)
			var png := str(ocfg["png"])
			if not tex_cache.has(png):
				tex_cache[png] = load(png)
			var spr := Sprite2D.new()
			spr.name = "Sprite"
			spr.texture = tex_cache[png]
			spr.position = Vector2(0, -foot_dy)  # 上移，画面与原来一致
			body.add_child(spr)
			var shape_key := "%sx%s" % [ocfg["foot_w"], ocfg["foot_h"]]
			if not shape_cache.has(shape_key):
				var s := RectangleShape2D.new()
				s.size = Vector2(float(ocfg["foot_w"]), float(ocfg["foot_h"]))
				shape_cache[shape_key] = s
			var foot := CollisionShape2D.new()
			foot.name = "Foot"
			foot.shape = shape_cache[shape_key]  # 同类对象共享同一矩形资源
			body.add_child(foot)
			objects.add_child(body)
			obj_count += 1
	root.add_child(objects)

	# Bounds 边界碰撞：贴着空地边缘的一圈 void 格（gid==0 且 4 邻接有非空格）
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	var cell_shape := RectangleShape2D.new()
	cell_shape.size = Vector2(tw, th)
	var bound_cells := 0
	for row in height:
		for col in width:
			if int(tile_data[row * width + col]) != 0:
				continue  # 有瓦片=可走，不挡
			if not _has_walkable_neighbor(tile_data, width, height, col, row):
				continue
			var cs := CollisionShape2D.new()
			cs.shape = cell_shape  # 所有格共用一个矩形资源
			cs.position = Vector2(col * tw + tw * 0.5, row * th + th * 0.5)
			bounds.add_child(cs)
			bound_cells += 1
	root.add_child(bounds)

	_set_owner_recursive(root, root)
	print("[import_tiled_map] 瓦片 %d 格 / 对象 %d 个 / 边界 %d 格" % [painted, obj_count, bound_cells])
	return root


func _find_layer(data: Dictionary, layer_type: String):
	for L in data["layers"]:
		if str(L.get("type", "")) == layer_type:
			return L
	return null


# 逻辑格 (c,r) 是否被地形占用（越界视为空）
func _logical_filled(d: Array, w: int, h: int, c: int, r: int) -> bool:
	if c < 0 or c >= w or r < 0 or r >= h:
		return false
	return int(d[r * w + c]) != 0


func _has_walkable_neighbor(d: Array, w: int, h: int, c: int, r: int) -> bool:
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var o: Vector2i = off
		var nc := c + o.x
		var nr := r + o.y
		if nc < 0 or nc >= w or nr < 0 or nr >= h:
			continue
		if int(d[nr * w + nc]) != 0:
			return true
	return false


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child != owner:
			child.owner = owner
		_set_owner_recursive(child, owner)
