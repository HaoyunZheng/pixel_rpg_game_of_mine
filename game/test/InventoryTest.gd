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
##   INVENTORY_TEST_ITEM_COUNT：为目标分类生成指定数量的占位物品；空值保留正式初始背包
##   INVENTORY_TEST_PAGE：截图前切到指定页（从 0 开始）
##   INVENTORY_TEST_LONG_TEXT：1 = 使用长名称、长说明和双属性

const INVENTORY_UI_SCENE: String = "res://scenes/ui/InventoryUI.tscn"

func _ready() -> void:
	var category_index: int = clampi(int(OS.get_environment("INVENTORY_TEST_CATEGORY")), 0, 4)
	var item_count: int = int(OS.get_environment("INVENTORY_TEST_ITEM_COUNT"))
	if item_count > 0:
		_make_test_items(category_index, item_count)

	var inv: InventoryUI = load(INVENTORY_UI_SCENE).instantiate()
	add_child(inv)
	inv.open()
	await get_tree().process_frame

	if not OS.get_environment("INVENTORY_TEST_CATEGORY").is_empty():
		inv._category_index = category_index
		inv._update_tab_styles()
		inv._refresh_grid()
		inv._refresh_detail()
	var page_str := OS.get_environment("INVENTORY_TEST_PAGE")
	if not page_str.is_empty():
		inv._set_page_index(maxi(0, int(page_str)))
		inv._refresh_grid()
		inv._refresh_detail()

	match OS.get_environment("INVENTORY_TEST_STATE"):
		"menu":
			await get_tree().process_frame
			inv._enter_action_menu()
		"confirm":
			await get_tree().process_frame
			var slot: Dictionary = inv._focused_slot()
			inv._open_discard_dialog(slot.item, slot.count)


func _make_test_items(category_index: int, item_count: int) -> void:
	GameData.inventory.clear()
	var category: ItemData.ItemCategory = InventoryWidgets.CATEGORY_ORDER[category_index]
	for i in range(item_count):
		var item := ItemData.new()
		item.id = "visual_test_item_%02d" % i
		item.display_name = "测试物品 %02d" % (i + 1)
		item.description = "分页与焦点位置测试占位物。"
		item.category = category
		if OS.get_environment("INVENTORY_TEST_LONG_TEXT") == "1":
			item.display_name = "风蚀遗迹中无法辨认真名的古老守望者长剑 %02d" % (i + 1)
			item.description = "这是一段用于验证说明文字边界的长文本。它应当在羊皮纸说明框内自动换行，并在空间不足时逐级缩小字号；到达最小字号后仍然过长的内容必须以省略号截断，绝不能覆盖属性栏、分隔线或下方操作区域。重复加入这一段文字是为了稳定触发最终截断：所有不可见内容都应被裁切在说明框内部，不能从右边或底部泄漏到其它区域。"
			item.attack_bonus = 12
			item.defense_bonus = 8
		GameData.add_item(item)
