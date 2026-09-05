extends SceneTree

const MAP_SCENE := "res://scenes/ForestMainMap.tscn"
const TILESET_PATH := "res://assets/derived/maps/forest-main/forest_main_tileset.tres"

var _failed := false


func _initialize() -> void:
	var packed := load(MAP_SCENE) as PackedScene
	_check(packed != null, "ForestMainMap 场景可加载")
	if packed == null:
		_finish()
		return

	var map := packed.instantiate()
	root.add_child(map)
	var layer_count := 0
	var used_cells := 0
	var shared_tileset: TileSet
	for child in map.get_children():
		if child is TileMapLayer:
			layer_count += 1
			used_cells += child.get_used_cells().size()
			if shared_tileset == null:
				shared_tileset = child.tile_set
			else:
				_check(child.tile_set == shared_tileset, "%s 复用共享 TileSet" % child.name)
	_check(layer_count == 6, "地表恰有 6 个 TileMapLayer")
	_check(used_cells == 3276, "6 层地表共使用 3276 个单元")
	_check(shared_tileset != null and shared_tileset.resource_path == TILESET_PATH, "地表引用外部 TileSet 资源")
	if shared_tileset != null:
		var atlas := shared_tileset.get_source(0) as TileSetAtlasSource
		_check(atlas != null and atlas.get_tiles_count() == 189, "atlas 恰好包含 189 个地块")
		_check(atlas != null and atlas.use_texture_padding, "atlas 启用纹理边缘填充")
		_check(shared_tileset.get_physics_layers_count() == 0, "地表 TileSet 不添加物理多边形")
		_check(shared_tileset.get_terrain_sets_count() == 0, "定稿地图不生成 terrain 元数据")

	var trees := 0
	var rocks := 0
	var signs := 0
	var objects := map.get_node_or_null("Objects")
	_check(objects != null, "静态对象容器存在")
	if objects != null:
		_check(objects.y_sort_enabled, "静态对象启用 Y 排序")
		for object in objects.get_children():
			var kind := String(object.get_meta("forest_object_kind", ""))
			if kind.begins_with("tree"):
				trees += 1
			elif kind.begins_with("rock"):
				rocks += 1
			elif kind == "sign":
				signs += 1
	_check(trees == 1135, "保留 1135 棵树")
	_check(rocks == 52, "保留 52 块岩石")
	_check(signs == 2, "保留 2 块路牌")
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[verify_forest_main_map] PASS: %s" % message)
	else:
		_failed = true
		push_error("[verify_forest_main_map] FAIL: %s" % message)


func _finish() -> void:
	if _failed:
		quit(1)
	else:
		print("[verify_forest_main_map] 地图结构验证通过")
		quit()
