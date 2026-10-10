extends Node
## 验证真实构筑操作、刷新稳定性，以及构筑/基建的战后继续入口。

const CORE := ["G04", "G05", "G30", "G40", "G20", "G24"]
const Traits = preload("res://scripts/build_traits.gd")
var checks := 0
var failures := 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)


func frames(count: int = 4) -> void:
	for i in range(count):
		await get_tree().process_frame


func named(node: Node, title: String) -> Node:
	if str(node.name) == title:
		return node
	for child in node.get_children():
		var found := named(child, title)
		if found != null:
			return found
	return null


func press(node: Node, title: String) -> bool:
	var button := named(node, title) as Button
	if button == null or button.disabled:
		check(false, "可操作按钮存在：" + title)
		return false
	button.pressed.emit()
	return true


func menu_pick(node: Node, title: String, id: String) -> bool:
	var menu := named(node, title) as MenuButton
	if menu == null or menu.disabled:
		check(false, "可操作菜单存在：" + title)
		return false
	var popup := menu.get_popup()
	for i in range(popup.item_count):
		if str(popup.get_item_metadata(i)) == id:
			if popup.is_item_disabled(i):
				check(false, "菜单选项可操作：" + id)
				return false
			popup.id_pressed.emit(popup.get_item_id(i))
			return true
	check(false, "菜单列出真实持有卡：" + id)
	return false


func select_slot(deck: Node, id: String) -> bool:
	var slots := named(deck, "DeckSlots")
	if slots != null:
		for child in slots.get_children():
			if child is Button and str(child.get_meta("card_id", "")) == id:
				(child as Button).pressed.emit()
				return true
	check(false, "上阵条可以选择武将：" + id)
	return false


func contains_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text.contains(text):
		return true
	for child in node.get_children():
		if contains_label(child, text):
			return true
	return false


func inside_viewport(control: Control) -> bool:
	var bounds := control.get_viewport_rect().grow(2)
	var rect := control.get_global_rect()
	return bounds.encloses(rect) and rect.size.x > 1 and rect.size.y > 1


func fixture() -> void:
	GameState.new_game()
	GameState.gold = 500000
	GameState.up["power"] = 4
	GameState.up["carry"] = 3
	GameState.up["equip"] = 2
	GameState.up["troops"] = 2
	GameState.carry.clear()
	GameState.hero_equip.clear()
	GameState.hero_troops.clear()
	GameState.hero_lv.clear()
	for id in CORE:
		GameState.owned[id] = 1
	for i in range(5):
		GameState.carry.append(CORE[i])
	for card in GameData.cards:
		if str(card.get("type", "")) == "士兵":
			GameState.owned[str(card["id"])] = 1
	GameState.owned["E01"] = 1
	GameState.owned["E02"] = 1
	GameState.owned["B01"] = 4
	GameState.owned["B02"] = 1
	for region in GameData.regions:
		var index := int(region["idx"])
		GameState.region_state[index] = "cleared" if index <= 4 else "locked"
	GameState.region_state[5] = "available"
	GameState.battle_region = 5
	GameState.in_battle = false
	GameState.end_reason = "settled"
	GameState.last_outcome = {"region": 5, "result": "settled", "gold": 555, "kills": 3, "damage": 1101}
	GameState._recompute_bonus()


func _ready() -> void:
	# Headless 默认窗口尺寸不同于桌面，显式使用项目的标准布局尺寸。
	get_tree().root.size = Vector2i(1280, 800)
	await frames()
	if GameState.save_path() == GameState.SAVE_PATH:
		push_error("ArtV5Test 必须使用独立测试存档；正式存档未改动")
		get_tree().quit(1)
		return
	check(true, "新美术回归使用独立测试档")
	fixture()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	var home = main._home
	home.open_section("deck")
	await frames()
	var deck = home._deck_page
	var original_result: Dictionary = GameState.last_outcome.duplicate(true)
	check(home.visible and deck.visible, "构筑进入实际大本营子页")
	check(get_viewport().get_visible_rect().size == Vector2(1280, 800), "在1280×800标准窗口验证布局")
	for id in CORE:
		check(named(deck, "DeckHero_" + id) != null, "仓库展示核心将牌 " + id)
		press(deck, "DeckHero_" + id)
		await frames()
		check(deck._selected == id, "点击卡格实际选中 " + id)
		check(contains_label(named(deck, "DeckSelected"), str(Traits.describe(id)["description"])), "武将说明与实际构筑能力一致 " + id)
	press(deck, "DeckAdd")
	await frames()
	check(GameState.in_carry("G24") and GameState.carry.size() == 6, "空阵位通过真实按钮上阵第六将")
	var slots := named(deck, "DeckSlots")
	check(slots.get_child_count() == 6, "最大六阵位完整展示")
	for slot in slots.get_children():
		check(inside_viewport(slot as Control), "阵位在标准窗口内 " + str(slot.name))
	check(inside_viewport(named(deck, "DeckSelected") as Control), "武将大卡详情不超出窗口")
	check(inside_viewport(named(deck, "DeckWarehouseScroll") as Control), "仓库滚动区不超出窗口")
	check(contains_label(named(deck, "DeckTeamSummary"), "混搭连锁"), "六将队伍显示实际混搭摘要")
	select_slot(deck, "G04")
	GameState.owned["G04"] = 4
	deck.refresh()
	await frames()
	var gold: float = GameState.gold
	press(deck, "DeckCultivate")
	await frames()
	check(GameState.hero_quality("G04") == 1 and GameState.owned["G04"] == 2, "同名按钮消耗自由3张原版，得到精制并保护上阵卡")
	check(is_equal_approx(GameState.gold, gold), "武将合成不扣金币也不设独立等级")
	press(deck, "DeckRemove")
	await frames()
	check(not GameState.in_carry("G04") and GameState.owned.get("G04", 0) == 2, "卸下返仓，持有卡不减少")
	press(deck, "DeckAdd")
	await frames()
	check(GameState.in_carry("G04"), "卸下后可以重新上阵")
	# 金币刷新需保留可交互节点与滚动位置。
	var warehouse := named(deck, "DeckWarehouse")
	var warehouse_id: int = warehouse.get_instance_id()
	var scroll := named(deck, "DeckWarehouseScroll") as ScrollContainer
	scroll.scroll_vertical = 45
	await frames()
	var scroll_before := scroll.scroll_vertical
	gold = GameState.gold
	GameState.gold = 0
	GameState.changed.emit()
	deck.refresh_values()
	await frames()
	check(named(deck, "DeckWarehouse").get_instance_id() == warehouse_id, "金币tick不重建仓库节点")
	check(scroll.scroll_vertical == scroll_before, "金币tick保持仓库滚动位置")
	check((named(deck, "DeckCultivate") as Button).disabled, "同名自由库存不足时禁用合成")
	GameState.gold = gold
	GameState.changed.emit()
	await frames()
	check((named(deck, "DeckCultivate") as Button).disabled, "金币变化不影响合成材料条件")
	var filter := named(deck, "DeckFilter") as OptionButton
	filter.select(1)
	filter.item_selected.emit(1)
	await frames()
	check(named(deck, "DeckWarehouse").get_child_count() == 2, "雷印筛选只展示对应两将")
	check(deck._selected == "G04", "筛选保留所选武将")
	var search := named(deck, "DeckSearch") as LineEdit
	var search_id := search.get_instance_id()
	search.text = "朱灵"
	search.text_changed.emit("朱灵")
	await frames()
	check(named(deck, "DeckWarehouse").get_child_count() == 1 and named(deck, "DeckHero_G04") != null, "搜索按名字找到真实将牌")
	check(named(deck, "DeckSearch").get_instance_id() == search_id and deck._selected == "G04", "搜索不重建输入框或丢失选择")
	search.text = ""
	search.text_changed.emit("")
	filter.select(0)
	filter.item_selected.emit(0)
	await frames()
	# 每将装备巢、换装与装备转移。
	press(deck, "DeckTab_装备")
	await frames()
	menu_pick(deck, "DeckEquipMenu_兵器", "E01")
	await frames()
	check(GameState.hero_equipped_in_slot("G04", "兵器") == "E01", "装备菜单挂到所选武将")
	menu_pick(deck, "DeckEquipMenu_兵器", "E02")
	await frames()
	check(GameState.hero_equipped_in_slot("G04", "兵器") == "E02" and GameState.equip_owner("E01") == "", "同部位换装返还原装备")
	press(deck, "DeckUnequip_E02")
	await frames()
	check(GameState.equip_owner("E02") == "", "装备卸下按钮实际返仓")
	menu_pick(deck, "DeckEquipMenu_兵器", "E01")
	await frames()
	select_slot(deck, "G05")
	await frames()
	menu_pick(deck, "DeckEquipMenu_兵器", "E01")
	await frames()
	check(GameState.equip_owner("E01") == "G05" and GameState.hero_equipped_in_slot("G04", "兵器") == "", "装备转移不复制、不保留旧主人")
	# 每将兵位实际派兵和撤兵。
	press(deck, "DeckTab_带兵")
	await frames()
	menu_pick(deck, "DeckTroopMenu", "S01")
	await frames()
	check(GameState.hero_troops_of("G05").has("S01") and GameState.troop_owner("S01") == "G05", "派兵挂在所选武将麾下")
	press(deck, "DeckTroopRemove_S01")
	await frames()
	check(GameState.troop_owner("S01") == "", "撤兵实际返仓")
	check(GameState.last_outcome == original_result, "构筑培养换装派兵保留原失败战果")
	check(home._primary_action.text.contains("重新挑战") and home._secondary_action.text.contains("换地图"), "构筑子页保留失败两种继续入口")
	check(inside_viewport(home._primary_action) and inside_viewport(home._secondary_action), "构筑底栏按钮完整位于窗口内")
	# 基建底栏通过真实主场景信号接到地图与重试。
	home.return_to_hub()
	home._hub_tiles["base"].pressed.emit()
	await frames()
	check(main._city.visible and not home.visible, "基建入口打开经营页")
	var city = main._city
	city._on_pick(2)
	await frames()
	check(inside_viewport(named(city, "CityBook") as Control), "城册完整位于标准窗口内")
	check(inside_viewport(named(city, "CityManagement") as Control), "城池经营区完整位于标准窗口内")
	check(inside_viewport(named(city, "BuildingLedger") as Control), "建筑仓库完整位于标准窗口内")
	check(GameState.city_buildings(2).is_empty(), "基建操作使用真实空城")
	var copies := int(GameState.owned.get("B01", 0))
	press(city, "PlaceBuildingB01")
	await frames()
	check(GameState.city_buildings(2) == ["B01"] and int(GameState.owned.get("B01", 0)) == copies - 1, "建造按钮消耗一张卡并实际占用城池槽位")
	check(city._sel == 2 and city._slot == 0, "建造后保留城池并选中实际建筑")
	check(GameState.gold_per_hour() > 0 and contains_label(city._income, "全城产出"), "建造增加真实每小时产出并刷新总览")
	check(contains_label(named(city, "BuildingComboPeriod"), "10秒") and contains_label(named(city, "BuildingComboFormula"), "1 金币"), "原版来源收益预览显示真实十秒周期和金额")
	check(not (named(city, "PlaceBuildingB02") as Button).disabled, "六槽城市可继续装配不同建筑")
	var city_warehouse_id: int = city._side_box.get_child(0).get_instance_id()
	var detail_id: int = named(city, "CitySlots").get_instance_id()
	var outcome_id: int = named(city, "BaseOutcomePrimary").get_instance_id()
	var city_scroll_before: int = city._side_scroll.scroll_horizontal
	gold = GameState.gold
	GameState.gold = 0
	GameState.changed.emit()
	await frames()
	check(city._side_box.get_child(0).get_instance_id() == city_warehouse_id and named(city, "CitySlots").get_instance_id() == detail_id, "金币tick不重建仓库或装配槽")
	check(named(city, "BaseOutcomePrimary").get_instance_id() == outcome_id, "金币tick不重建战后按钮")
	check(city._side_scroll.scroll_horizontal == city_scroll_before and city._sel == 2 and city._slot == 0, "金币tick保留滚动与选中槽")
	check(named(city, "UpgradeSelectedBuilding") == null, "建筑没有金币练级入口")
	press(city, "BuildingSynthesisTab")
	await frames()
	press(city, "FuseBuildingB01Q0")
	await frames()
	check(GameState.building_stock("B01", 0) == copies - 4 and GameState.building_stock("B01", 1) == 1, "同名合成消耗三张仓库原版并产出一张精制")
	check(GameState.city_buildings(2) == ["B01"] and GameState.building_quality(2, 0) == 0, "合成保护已装配卡")
	check(GameState.gold == 0 and city._warehouse_tab == "合成", "零金币也能合成并保留分页")
	press(city, "RemoveSelectedBuilding")
	await frames()
	check(GameState.city_buildings(2).is_empty() and GameState.building_stock("B01", 0) == copies - 3, "卸下原版返还原版")
	press(city, "BuildingWarehouseTab")
	await frames()
	press(city, "PlaceBuildingB01Q1")
	await frames()
	check(GameState.building_quality(2, 0) == 1 and is_equal_approx(GameState.gold_per_hour(), 486.0), "精制保留原星级并提高实际收益35%")
	check(contains_label(named(city, "BuildingComboFormula"), "1.35 金币") and contains_label(named(city, "BuildingComboIncomeRibbon"), "8.1"), "精制卡的周期公式与每分钟收益同步真实结算")
	press(city, "RemoveSelectedBuilding")
	await frames()
	check(GameState.building_stock("B01", 1) == 1, "卸下精制卡保留品相")
	GameState.gold = gold
	GameState.changed.emit()
	check(GameState.last_outcome == original_result, "装配卸下同名合成保留原失败战果")
	check((named(main._city, "BaseOutcomePrimary") as Button).text.contains("重新挑战"), "基建失败保留重新挑战")
	check((named(main._city, "BaseOutcomeSecondary") as Button).text.contains("换地图"), "基建失败保留换地图")
	press(main._city, "BaseOutcomeSecondary")
	await frames()
	check(main._map_layer.visible and main._sel_idx == 5, "基建换地图实际打开地图并定位失败关")
	main._return_from_map()
	await frames()
	home._hub_tiles["base"].pressed.emit()
	await frames()
	var generation: int = GameState.battle_gen
	press(main._city, "BaseOutcomePrimary")
	await frames()
	check(GameState.in_battle and GameState.battle_region == 5 and GameState.battle_gen == generation + 1, "基建重试实际重铺原关")
	check(not main._city.visible and not home.visible and not main._map_layer.visible, "基建重试收起所有整备页")
	GameState.attack(0, false)
	if GameState.in_battle:
		GameState.settle_run()
	await frames()
	home.open_section("deck")
	await frames()
	check(home.visible and home._primary_action.text.contains("重新挑战"), "真实失败后构筑仍可整备重试")
	generation = GameState.battle_gen
	home._primary_action.pressed.emit()
	await frames()
	check(GameState.in_battle and GameState.battle_region == 5 and GameState.battle_gen == generation + 1, "构筑底栏重试实际进入原关")
	# 真实攻击产生胜利，再验证两页的地图接线。
	GameState.up["power"] = 80
	GameState.stamina = 100
	var safety := 0
	while GameState.in_battle and safety < 100:
		safety += 1
		var target := -1
		for i in range(GameState.battle.size()):
			if float(GameState.battle[i]["hp"]) > 0:
				target = i
				break
		if target < 0 or not GameState.attack(target, true):
			break
	await frames()
	check(GameState.end_reason == "cleared" and home.visible, "实际拍翻整桌触发通关整备")
	var won: Dictionary = GameState.last_outcome.duplicate(true)
	home.open_section("deck")
	await frames()
	check(home._primary_action.text.contains("进入大地图"), "构筑通关保留地图入口")
	check(GameState.last_outcome == won and deck.visible, "通关后仍可查看真实构筑")
	home._primary_action.pressed.emit()
	await frames()
	check(main._map_layer.visible and not home.visible, "构筑通关按钮实际进入地图")
	main._return_from_map()
	await frames()
	home._hub_tiles["base"].pressed.emit()
	await frames()
	check((named(main._city, "BaseOutcomePrimary") as Button).text.contains("进入大地图"), "基建通关保留地图入口")
	check(named(main._city, "BaseOutcomeSecondary") == null, "基建通关不再显示失败重试次按钮")
	check(inside_viewport(named(main._city, "BaseOutcomePrimary") as Control), "基建通关按钮完整位于窗口内")
	press(main._city, "BaseOutcomePrimary")
	await frames()
	check(main._map_layer.visible and not main._city.visible, "基建通关按钮实际进入地图")
	main.queue_free()
	await frames()
	print("[Art v5 UI] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
