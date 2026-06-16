extends Node2D
## 背包界面回归测试场景 —— 供 capture.gd 截图验收（不进正式游戏流程）。
##
## 用法：
##   截预览态：  --scene res://test/InventoryTest.tscn --task inventory-ui
##   截菜单态：  INVENTORY_TEST_STATE=menu 加同样命令（--task inventory-ui-menu）
##
## 通过环境变量控制截图前进入的 UI 状态：
##   INVENTORY_TEST_STATE：（空）= 预览态；menu = 操作选择态（ActionMenu 展开）
##   INVENTORY_TEST_CATEGORY：分类索引 0~4（武器/防具/饰品/消耗品/重要物品），默认 0

const INVENTORY_UI_SCENE: String = "res://scenes/ui/InventoryUI.tscn"

func _ready() -> void:
	var inv: InventoryUI = load(INVENTORY_UI_SCENE).instantiate()
	add_child(inv)
	inv.open()
	await get_tree().process_frame

	var cat_str := OS.get_environment("INVENTORY_TEST_CATEGORY")
	if not cat_str.is_empty():
		inv._category_index = clampi(int(cat_str), 0, 4)
		inv._update_tab_styles()
		inv._refresh_grid()
		inv._refresh_detail()

	if OS.get_environment("INVENTORY_TEST_STATE") == "menu":
		await get_tree().process_frame
		inv._enter_action_menu()
