# import_tiled_map.gd  —  Godot 4.x headless 转换器
# ============================================================
# 作用：把 Meowa/Tiled 导出的 map.tiled.json + 贴图，转成：
#   (a) 一个 TileSet 资源（.tres，3 个地面 atlas 源）
#   (b) 一个「纯地图」场景（.tscn）：灰底 + Ground 瓦片层
#       + Trees 树精灵 + Bounds 边界碰撞（贴着空地边缘的一圈 void 格）
#
# 该地图的瓦片索引在导出时已烘焙成最终 gid，逐格直接渲染即可，
# 无需运行期 dual-grid 逻辑。树是「对象」（任意像素坐标），按 Sprite2D 摆放，
# 不进 TileSet。
#
# 运行（同 import_sprites 风格，headless）：
#   /Applications/Godot.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/import_tiled_map.gd
#
# 注：本转换器面向 forest-clearing 这一张导出（资产绑定在下方常量里显式列出，
#     便于审阅）；数据量大的部分（384 格瓦片、23 个对象）全部由 JSON 驱动。
# ============================================================
extends SceneTree

const MAP_DIR := "res://assets/maps/forest-clearing"
const MAP_JSON := MAP_DIR + "/map.tiled.json"
const TILESET_OUT := MAP_DIR + "/forest_clearing_tileset.tres"
const SCENE_OUT := "res://scenes/ForestClearingMap.tscn"
const TREE_PNG := MAP_DIR + "/tree_vine_umbrella.png"

# firstgid -> 地面 tileset 贴图（对象 tileset(gid 49)单独处理，不进 TileSet）
const GROUND_PNGS := {
	1: MAP_DIR + "/tileset_25404.png",
	17: MAP_DIR + "/tileset_25386.png",
	33: MAP_DIR + "/tileset_25413.png",
}

const BG_COLOR := Color("909090")  # 复现 preview 的灰底（可后调）

# 树脚碰撞（树是装饰 Sprite，给底部加一小块实体挡住玩家）
const FOOT_DY := 22.0   # 树脚＝精灵中心下方多少像素（碰撞点 / body 原点）
const FOOT_W := 26.0
const FOOT_H := 12.0

var _meta_by_firstgid: Dictionary = {}   # firstgid -> {tilecount, columns, source_id}


func _initialize() -> void:
	var data = _read_json(MAP_JSON)
	if data == null:
		push_error("[import_tiled_map] 读取/解析 map.tiled.json 失败")
		quit(1)
		return

	var tileset := _build_tileset(data)
	if ResourceSaver.save(tileset, TILESET_OUT) != OK:
		push_error("[import_tiled_map] 保存 TileSet 失败: %s" % TILESET_OUT)
		quit(1)
		return
	print("[import_tiled_map] TileSet 已写出 → %s" % TILESET_OUT)

	var root := _build_scene(data)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("[import_tiled_map] PackedScene.pack 失败")
		quit(1)
		return
	if ResourceSaver.save(packed, SCENE_OUT) != OK:
		push_error("[import_tiled_map] 保存场景失败: %s" % SCENE_OUT)
		quit(1)
		return
	print("[import_tiled_map] 地图场景已写出 → %s" % SCENE_OUT)
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


# --- 构造 TileSet：3 个地面 atlas 源 -------------------------------
func _build_tileset(data: Dictionary) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(int(data["tilewidth"]), int(data["tileheight"]))

	var source_id := 0
	for ts in data["tilesets"]:
		var fg := int(ts["firstgid"])
		if not GROUND_PNGS.has(fg):
			continue  # 对象 tileset（树）跳过
		var columns := int(ts["columns"])
		var tilecount := int(ts["tilecount"])
		var rows := int(ceil(float(tilecount) / float(columns)))

		var src := TileSetAtlasSource.new()
		src.texture = load(GROUND_PNGS[fg])
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


# --- 构造「纯地图」场景 -------------------------------------------
func _build_scene(data: Dictionary) -> Node2D:
	var width := int(data["width"])
	var height := int(data["height"])
	var tw := int(data["tilewidth"])
	var th := int(data["tileheight"])

	var root := Node2D.new()
	root.name = "ForestClearingMap"

	# 灰底：放大覆盖地图 + 四周留白，保证静态相机视野内都是灰
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.position = Vector2(-tw * 8, -th * 8)
	bg.size = Vector2(width * tw + tw * 16, height * th + th * 16)
	root.add_child(bg)

	# Ground 瓦片层
	var tile_data: Array = _find_layer(data, "tilelayer")["data"]
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = load(TILESET_OUT)  # 已写盘，按 ext_resource 引用
	var painted := 0
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

	# Trees 树对象（Tiled tile-object：(x,y) 为底边左下角，宽高 64）
	# 每棵树 = StaticBody2D（原点落在树脚）+ 子 Sprite（上移还原画面）+ 子 Foot 碰撞
	var trees := Node2D.new()
	trees.name = "Trees"
	var tree_tex := load(TREE_PNG)
	var foot_shape := RectangleShape2D.new()
	foot_shape.size = Vector2(FOOT_W, FOOT_H)
	var obj_layer = _find_layer(data, "objectgroup")
	var tree_count := 0
	if obj_layer != null:
		for obj in obj_layer["objects"]:
			var center := Vector2(
				float(obj["x"]) + float(obj["width"]) * 0.5,
				float(obj["y"]) - float(obj["height"]) * 0.5)
			var body := StaticBody2D.new()  # 默认 collision_layer=1，与 Bounds 一致
			body.name = "Tree_%d" % int(obj["id"])
			body.position = center + Vector2(0, FOOT_DY)
			var spr := Sprite2D.new()
			spr.name = "Sprite"
			spr.texture = tree_tex
			spr.position = Vector2(0, -FOOT_DY)  # 上移，画面与原来一致
			body.add_child(spr)
			var foot := CollisionShape2D.new()
			foot.name = "Foot"
			foot.shape = foot_shape  # 23 棵共享同一矩形资源
			body.add_child(foot)
			trees.add_child(body)
			tree_count += 1
	root.add_child(trees)

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
	print("[import_tiled_map] 瓦片 %d 格 / 树 %d 棵 / 边界 %d 格" % [painted, tree_count, bound_cells])
	return root


func _find_layer(data: Dictionary, layer_type: String):
	for L in data["layers"]:
		if str(L.get("type", "")) == layer_type:
			return L
	return null


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
