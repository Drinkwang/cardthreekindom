extends Node
var failures := 0
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(what)

func frames(count: int = 3) -> void:
	for i in range(count):
		await get_tree().process_frame

func button_meta(node: Node, key: String, value: String) -> Button:
	if node is Button and str(node.get_meta(key, "")) == value:
		return node as Button
	for child in node.get_children():
		var found := button_meta(child, key, value)
		if found != null:
			return found
	return null

func named_button(node: Node, title: String) -> Button:
	if node is Button and str(node.name) == title:
		return node as Button
	for child in node.get_children():
		var found := named_button(child, title)
		if found != null:
			return found
	return null

func menu_item(node: Node, card_id: String) -> Dictionary:
	if node is MenuButton:
		var popup := (node as MenuButton).get_popup()
		for i in range(popup.item_count):
			if str(popup.get_item_metadata(i)) == card_id:
				return {"popup": popup, "id": popup.get_item_id(i)}
	for child in node.get_children():
		var found := menu_item(child, card_id)
		if not found.is_empty():
			return found
	return {}

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "UI验证场景使用独立测试档")
	GameState.new_game()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	var start_region: int = GameState.battle_region
	GameState.gold = 2000
	# 由真实战斗结算触发整备，而不是直接打开营地伪造胜败。
	GameState.attack(0, false)
	GameState.settle_run()
	await frames()
	var home = main._home
	var result: Dictionary = GameState.last_outcome.duplicate(true)
	check(home.visible and not main._map_layer.visible, "失败后回营，地图不会自动弹出")
	check(home._hub_tiles.size() == 4, "主页只有四区入口")
	check(home._hub_tiles.has("base") and not home._hub_tiles.has("map"), "第四区是基建")
	check(home._primary_action.text.contains("重新挑战"), "失败主操作重新挑战")
	check(home._secondary_action.text.contains("换地图"), "失败次操作换地图")
	for key in ["shop", "deck", "upgrade", "base"]:
		check(not home._hub_tiles[key].disabled, "战后保留 " + key + " 入口")
	# 点击真实升级按钮，再从子页返回营地。
	home._hub_tiles["upgrade"].pressed.emit()
	await frames()
	check(home._section == "upgrade", "升级进入独立整备子页")
	var buy := button_meta(home, "upgrade_id", "power")
	check(buy != null and not buy.disabled, "拍力升级按钮可操作")
	var before_power: int = int(GameState.up.get("power", 0))
	if buy != null:
		buy.pressed.emit()
	await frames()
	check(int(GameState.up.get("power", 0)) == before_power + 1, "升级按钮实际增加等级")
	check(home._section == "upgrade", "购买升级不把子页自动关闭")
	var back := named_button(home, "ReturnToCamp")
	check(back != null, "升级子页有返回大本营按钮")
	if back != null:
		back.pressed.emit()
	await frames()
	check(home._section == "hub" and GameState.last_outcome == result, "升级返回后保留原战果")
	# 商店复用现有消费功能，关闭翻牌后仍在商店，再回营。
	home._hub_tiles["shop"].pressed.emit()
	await frames()
	check(main._shop.visible and not home.visible, "商店区打开全屏卡铺")
	check(main._tabs.get_parent() == main._shop.content, "消费页已接入商店")
	var pack_count: int = GameState.total_packs
	var pack_button := main._shop_boxes["卡包"].get_child(1) as Button
	check(pack_button != null and not pack_button.disabled, "商店实际购买按钮可用")
	if pack_button != null:
		pack_button.pressed.emit()
	await frames()
	check(GameState.total_packs == pack_count + 1 and main._reveal.visible, "商店买包真实入库并翻牌")
	main._reveal._reveal_all()
	main._reveal._close()
	await get_tree().create_timer(0.22).timeout
	check(not main._reveal.visible and main._shop.visible, "收起揭牌后仍停留商店")
	var shop_back := named_button(main._shop, "ReturnToCamp")
	if shop_back != null:
		shop_back.pressed.emit()
	await frames()
	check(home.visible and GameState.last_outcome == result, "商店返回保持原关战果")
	check(main._tabs.get_parent() == main._drawer, "卡铺抽屉内容正常归位")
	# 确定的持有卡夹具，操作仍经过新构筑页里的实际菜单。
	GameState.owned["G13"] = 1
	GameState.owned["E01"] = 1
	GameState.up["equip"] = 1
	if GameState.carry.size() >= GameState.carry_max():
		GameState.carry_remove(str(GameState.carry[0]))
	home._hub_tiles["deck"].pressed.emit()
	await frames()
	check(home._section == "deck", "构筑区连接真实将兵装备操作")
	var carry_menu := menu_item(home, "G13")
	check(not carry_menu.is_empty(), "构筑上阵菜单列出持有武将")
	if not carry_menu.is_empty():
		carry_menu["popup"].id_pressed.emit(carry_menu["id"])
	await frames()
	check(GameState.in_carry("G13"), "构筑菜单实际将武将上阵")
	var equipment_tab := button_meta(home, "deck_tab", "装备")
	if equipment_tab != null:
		equipment_tab.pressed.emit()
	await frames()
	var gear_menu := menu_item(home, "E01")
	check(not gear_menu.is_empty(), "装备页列出可装备牌")
	if not gear_menu.is_empty():
		gear_menu["popup"].id_pressed.emit(gear_menu["id"])
	await frames()
	check(GameState.hero_equipped_in_slot("G13", "兵器") == "E01", "装备菜单实际挂在该武将身上")
	home.return_to_hub()
	check(GameState.last_outcome == result, "构筑与装备操作保留原战果")
	home._hub_tiles["base"].pressed.emit()
	await frames()
	check(main._city.visible and main._city._title.text.contains("基建"), "第四区接入实际基建页")
	main._city.closed.emit()
	await frames()
	check(home.visible and GameState.last_outcome == result, "未解锁基建也可返回原营地")
	# 换地图定位失败区域；返回后可以用新升级重开。
	home._secondary_action.pressed.emit()
	await frames()
	check(main._map_layer.visible and main._sel_idx == start_region, "换地图定位刚才的失败区域")
	main._return_from_map()
	await frames()
	var gold_after_prep: float = GameState.gold
	var gen: int = GameState.battle_gen
	home._primary_action.pressed.emit()
	await frames()
	check(GameState.in_battle and GameState.battle_region == start_region, "重试开的是原关")
	check(not home.visible and GameState.stamina == GameState.stamina_max, "重试收营且恢复耐力")
	check(GameState.last_outcome.is_empty() and is_equal_approx(GameState.gold, gold_after_prep), "重试不重复结算金币")
	main._on_home_deploy(start_region)
	check(GameState.battle_gen == gen + 1, "连点不会重复生成新局")
	# 战斗中手动开营，继续按钮只恢复桌面。
	GameState.attack(0, false)
	var hp: float = GameState.battle[0]["hp"]
	var stamina: int = GameState.stamina
	main._open_home()
	await frames()
	check(home._primary_action.text.contains("继续拍卡"), "战斗中回营显示继续")
	home._primary_action.pressed.emit()
	check(GameState.stamina == stamina and GameState.battle[0]["hp"] == hp, "继续拍卡不重铺血量与耐力")
	# 走真实攻击触发首通。
	GameState.up["power"] = 80
	GameState.stamina = 100
	while GameState.in_battle:
		var target := -1
		for i in range(GameState.battle.size()):
			if float(GameState.battle[i]["hp"]) > 0:
				target = i
				break
		if target < 0 or not GameState.attack(target, true):
			break
	await frames()
	check(GameState.end_reason == "cleared" and home.visible, "通关同样留在四区大本营")
	check(not main._map_layer.visible, "通关不会跳过升级直接进地图")
	check(home._primary_action.text.contains("进入大地图"), "通关主操作进入大地图")
	check(home._hub_tiles.size() == 4, "通关后四区都保留")
	var victory_result: Dictionary = GameState.last_outcome.duplicate(true)
	home._hub_tiles["upgrade"].pressed.emit()
	await frames()
	var stamina_button := button_meta(home, "upgrade_id", "stamina")
	var before_stamina: int = GameState.upgrade_level("stamina")
	check(stamina_button != null and not stamina_button.disabled, "通关后实际升级按钮仍可用")
	if stamina_button != null:
		stamina_button.pressed.emit()
	await frames()
	check(GameState.upgrade_level("stamina") == before_stamina + 1, "通关后实际购买升级")
	named_button(home, "ReturnToCamp").pressed.emit()
	await frames()
	check(GameState.last_outcome == victory_result and home._primary_action.text.contains("进入大地图"), "通关后升级返回仍保持胜利与地图操作")
	home._primary_action.pressed.emit()
	await frames()
	check(main._map_layer.visible and GameState.region_status(main._sel_idx) == "available", "进入地图选中相邻可挑战区域")
	# 重载最近战果后主界面从营地恢复。
	GameState.save_game()
	main.queue_free()
	await frames()
	GameState.load_game()
	var restored = load("res://scenes/Main.tscn").instantiate()
	add_child(restored)
	await frames()
	check(restored._home.visible and not GameState.in_battle, "重进游戏从战后营地恢复")
	check(restored._home._primary_action.text.contains("进入大地图"), "恢复通关战果按钮")
	# 新野首通同时开启两个区域，模拟其中一处失败后换另一处。
	var targets: Array[int] = []
	for r in GameData.regions:
		if GameState.region_status(int(r["idx"])) == "available":
			targets.append(int(r["idx"]))
	check(targets.size() >= 2, "存在两个可选区域供换地图验证")
	if targets.size() >= 2:
		restored._on_map_deploy(targets[0])
		GameState.settle_run()
		await frames()
		restored._home._secondary_action.pressed.emit()
		await frames()
		restored._map_view.region_chosen.emit(targets[1])
		await frames()
		check(restored._sel_idx == targets[1], "地图选择另一可挑战区域")
		restored._on_map_deploy(restored._sel_idx)
		await frames()
		check(GameState.in_battle and GameState.battle_region == targets[1] and not restored._home.visible and not restored._map_layer.visible, "换地图后实际进入新区域")
	restored.queue_free()
	print("[Hub v1.4] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
