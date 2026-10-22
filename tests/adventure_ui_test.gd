extends Node
## 验证技能点消费、精简界面、武将成长与巡城事件的实际页面。
var checks := 0
var failures := 0
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 8) -> void:
	for i in count: await get_tree().process_frame

func snapshot(filename: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(filename)) == OK, "保存界面 " + filename)

func test_minimap_pixels(minimap, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var count: int = minimap.card_positions.size()
	check(count > 0, label + "像素核查有实际存活牌点")
	if count == 0: return
	var indices: Array[int] = []
	for index in mini(5, count): indices.append(index)
	var samples := mini(12, count)
	for sample in samples:
		var index := floori(float(count - 1) * sample / maxi(1, samples - 1))
		if not indices.has(index): indices.append(index)
	check(indices.size() >= samples, "%s像素核查覆盖首区及全图至少%d个牌点" % [label, samples])
	for index in indices:
		var point: Vector2 = minimap.global_position + minimap.world_to_minimap(minimap.card_positions[index])
		var pixel := Vector2i((point * scale).floor())
		var color := image.get_pixelv(pixel)
		check(color.r > color.g + 0.12 and color.r > color.b + 0.12, "%s牌点%d实际渲染中心保持红色可见，不被题签覆盖" % [label, index])
		print("[Minimap pixel] " + JSON.stringify({"layout": label, "index": index, "x": pixel.x, "y": pixel.y, "color": color.to_html()}))

func click(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		var point := button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		get_viewport().push_input(motion, true)
		await frames(3)
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			event.position = point
			event.global_position = point
			get_viewport().push_input(event, true)
	await frames()

func test_minimap_dock(main) -> void:
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		await frames()
		var mini = main._minimap
		var footer: Rect2 = main._bar.get_global_rect()
		check(footer.encloses(mini.get_global_rect()), "%d高度小地图完整收在底栏内部" % height)
		check(not main._table.get_global_rect().intersects(mini.get_global_rect()), "%d高度小地图不盖住地图牌" % height)
		check(mini.global_position.x > main.size.x * 0.5, "%d高度小地图位于右下侧" % height)
		check(mini.find_child("ToggleMap", true, false) == null, "%d高度小地图没有收起按钮" % height)
		var map_size: Vector2 = mini.size
		check(map_size.is_equal_approx(Vector2(220, 96)), "%d高度小地图保持220×96紧凑尺寸" % height)
		check(footer.size.y <= 112.0, "%d高度整个底栏收至112像素内" % height)
		var table: Rect2 = main._table.get_global_rect()
		check(is_equal_approx(table.end.y, footer.position.y) and table.size.y >= height - table.position.y - 140.0 + 28.0 - 0.01 and table.size.y >= height - table.position.y - 164.0 + 52.0 - 0.01, "%d高度地图连续填满本次28像素与累计52像素释放空间" % height)
		check(is_equal_approx(mini.get_global_rect().position.y - footer.position.y, 8.0) and is_equal_approx(footer.end.y - mini.get_global_rect().end.y, 8.0), "%d高度小地图上下各留8像素，不贴底栏上边线" % height)
		check(is_equal_approx(main._slot_row.get_global_rect().get_center().y, footer.get_center().y), "%d高度默认上阵卡牌在底栏内垂直居中" % height)
		check(mini.find_child("MapTitle", true, false) == null, "%d高度小地图不保留标题行" % height)
		check(mini.map_area.size.y > 0.0 and mini.map_area.size.y <= 76.0 and Rect2(Vector2(10, 10), mini.size - Vector2(20, 20)).grow(0.01).encloses(mini.map_area), "%d高度地图体使用四边10像素留白和76像素可用高度" % height)
		var slots := main.find_child("DeploySlotsScroll", true, false) as ScrollContainer
		check(is_equal_approx(slots.custom_minimum_size.y, 96.0) and slots.size.y >= 96.0 and footer.encloses(slots.get_global_rect()), "%d高度卡槽滚动容器保持96像素且完整在底栏内" % height)
		for slot in main._slot_row.get_children():
			check(slot.custom_minimum_size.y >= 88.0 and slot.size.y >= 88.0 and footer.encloses(slot.get_global_rect()), "%d高度上阵卡面不低于88像素且没有被压出底栏" % height)
		print("[Footer compact] height=%d footer=%s table=%s minimap=%s bottom_gap=%s" % [height, footer.size.y, table.size.y, mini.size, footer.end.y - mini.get_global_rect().end.y])
		var deployment_flag: Control = main._lbl_bar.get_parent().get_child(0)
		var deployment_caption := deployment_flag.get_child(0) as Label
		check(deployment_caption.get_minimum_size().y <= deployment_flag.size.y - 6.0, "%d高度上阵两行文字不超过旗内高度" % height)
		check(deployment_flag.get_global_rect().encloses(deployment_caption.get_global_rect()), "%d高度上阵文字完整位于旗子内" % height)
		main._navigate_minimap(main._world_size * 0.5)
		var focus: Vector2 = main._screen_to_world(main._table.size * 0.5)
		for down in [true, false]:
			var frame_click := InputEventMouseButton.new()
			frame_click.button_index = MOUSE_BUTTON_LEFT
			frame_click.pressed = down
			frame_click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			frame_click.position = mini.global_position + Vector2(4, 4)
			frame_click.global_position = frame_click.position
			if DisplayServer.get_name() == "headless":
				frame_click.position -= mini.global_position
				mini._gui_input(frame_click)
			else: get_viewport().push_input(frame_click, true)
		await frames(2)
		check(mini.size.is_equal_approx(map_size) and main._screen_to_world(main._table.size * 0.5).distance_to(focus) < 0.1, "点击地图外框保持尺寸和镜头焦点")
		for down in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_M
			key.pressed = down
			if DisplayServer.get_name() == "headless": main._input(key)
			else: get_viewport().push_input(key, true)
			await frames(2)
		check(mini.size.is_equal_approx(map_size) and main._screen_to_world(main._table.size * 0.5).distance_to(focus) < 0.1, "M键保持地图尺寸和镜头焦点")
		var gold: float = GameState.gold
		var slaps: int = GameState.round_slaps
		var destination: Vector2 = main._world_size * 0.5 + Vector2(100, 70)
		for down in [true, false]:
			var input := InputEventMouseButton.new()
			input.button_index = MOUSE_BUTTON_LEFT
			input.pressed = down
			input.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			input.position = mini.global_position + mini.world_to_minimap(destination)
			input.global_position = input.position
			if DisplayServer.get_name() == "headless":
				input.position -= mini.global_position
				mini._gui_input(input)
			else: get_viewport().push_input(input, true)
		await frames(2)
		check(main._screen_to_world(main._table.size * 0.5).distance_to(destination) < 0.1, "底栏小地图仍按真实坐标定位")
		check(GameState.gold == gold and GameState.round_slaps == slaps, "操作底栏小地图不穿透拍牌")
		check(main._lbl_progress.get_parent().get_global_rect().encloses(main._lbl_progress.get_global_rect()), "底栏状态文字保留在信息栏内")
		main._reset_camera()
		if DisplayServer.get_name() != "headless": await test_minimap_pixels(mini, "新野五分区%d高度" % height)
		await snapshot("adventure-dock-%d.png" % height)

func test_full_footer(main) -> void:
	GameState.new_game()
	GameState.retreat()
	GameState.up.carry = 3
	GameState.up.equip = 5
	GameState.up.troops = 1
	for card_id in ["G00", "G01", "G02", "G03", "G04", "G05"]:
		GameState.owned[card_id] = 1
		check(GameState.carry_add(card_id), "满队底栏夹具实际上阵" + card_id)
	GameState.owned.E01 = 1
	GameState.owned.S01 = 1
	check(GameState.equip_to("G01", "E01"), "满队夹具实际装配装备")
	check(GameState.troop_put("G01", "S01"), "满队夹具实际配属士兵")
	check(GameState.carry_max() == 6 and GameState.carry.size() == 6, "满队夹具包含六携带位")
	check(GameState.start_battle(1), "满队装备带兵夹具开启实际战斗")
	main._close_home()
	main._window_focused = false
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		await frames()
		var slots := main.find_child("DeploySlotsScroll", true, false) as ScrollContainer
		var row: HBoxContainer = main._slot_row
		var horizontal := slots.get_h_scroll_bar()
		var footer: Rect2 = main._bar.get_global_rect()
		print("[Footer full] " + JSON.stringify({"height": height, "footer": footer.size, "footer_min": main._bar.get_combined_minimum_size(), "scroll": slots.size, "scroll_min": slots.get_combined_minimum_size(), "row": row.size, "row_min": row.get_combined_minimum_size(), "horizontal_visible": horizontal.visible, "horizontal": horizontal.size, "horizontal_min": horizontal.get_combined_minimum_size()}))
		check(GameState.in_battle and row.get_child_count() == 7, "%d高度真实战斗底栏包含主角和六携带位" % height)
		check(footer.size.y <= 112.0, "%d高度满队带装备兵底栏不超过112像素" % height)
		check(horizontal.visible and row.size.x > slots.size.x, "%d高度满队底栏实际出现横向滚动条" % height)
		check(row.get_combined_minimum_size().y + horizontal.get_combined_minimum_size().y <= slots.size.y, "%d高度卡面和横滚条最小高度完整装入滚动容器" % height)
		check(footer.encloses(slots.get_global_rect()) and slots.get_global_rect().encloses(horizontal.get_global_rect()), "%d高度滚动容器和横滚条完整位于底栏内" % height)
		check(row.global_position.y - footer.position.y >= 8.0, "%d高度满队卡牌仍与底栏上边线留出8像素" % height)
		var horizontal_point: Vector2 = main._table.get_global_transform().affine_inverse() * horizontal.get_global_rect().get_center()
		check(main._over_camera_ui(horizontal_point), "%d高度鼠标在横滚条上优先操作卡槽，不触发镜头滚屏" % height)
		var attachments := 0
		for slot in row.get_children():
			check(slot.size.y >= 88.0 and slot.position.y >= 0.0 and slot.position.y + slot.size.y <= slots.size.y - horizontal.size.y, "%d高度满队卡面保留88像素且不被横滚条裁切" % height)
			for portrait in slot.find_children("*", "TextureRect", true, false):
				check(portrait.size.y >= 44.0 and slot.get_global_rect().encloses(portrait.get_global_rect()), "%d高度满队头像保留44像素高且没有超出卡面" % height)
			for label in slot.find_children("*", "Label", true, false):
				check(slot.get_global_rect().encloses(label.get_global_rect()) and label.size.y >= label.get_minimum_size().y, "%d高度满队卡面文字完整位于卡框内：%s" % [height, label.text])
				if label.text.contains("装1") and label.text.contains("兵1"): attachments += 1
		check(attachments == 1, "%d高度实际显示装备和带兵信息行" % height)
		slots.scroll_horizontal = 0
		await frames()
		check(slots.get_global_rect().encloses(row.get_child(0).get_global_rect()), "%d高度横滚起点可完整查看主角卡" % height)
		await snapshot("adventure-footer-full-%d-start.png" % height)
		slots.scroll_horizontal = int(horizontal.max_value)
		await frames()
		check(slots.get_global_rect().encloses(row.get_child(row.get_child_count() - 1).get_global_rect()), "%d高度横滚末端可完整查看最后携带卡" % height)
		await snapshot("adventure-footer-full-%d-end.png" % height)

func test_hidden_events(main) -> void:
	check(not main._event_layer.visible and main._minimap.events.is_empty(), "主地图与小地图均隐藏任务和宝箱")
	var chest: Dictionary = GameState.map_event_entries()[0]
	var center: Vector2 = chest.point
	var world_area: Vector2 = main._world_size - Vector2(500, 500)
	GameState.battle[0].nx = (center.x - 250.0) / world_area.x
	GameState.battle[0].ny = (center.y - 250.0) / world_area.y
	main._sync_card_positions()
	main._navigate_minimap(center)
	var hp: float = GameState.battle[0].hp
	var slaps: int = GameState.round_slaps
	main._slap_area(main._world_to_screen(center))
	check(GameState.battle[0].hp < hp and GameState.round_slaps == slaps + 1, "隐藏宝箱位置的敌牌仍能正常拍击")
	check(GameState.map_events[chest.id].status == "ready", "隐藏宝箱不被误触发")
	main._refresh_map_events()
	main._update_minimap()
	check(not main._event_layer.visible and main._minimap.events.is_empty(), "状态刷新后事件仍隐藏")

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "使用隔离测试档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): output = argument.substr(10)
	GameState.set_process(false)
	GameState.new_game()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._window_focused = false
	await frames()
	check(main.find_child("StoryDiary", true, false) == null, "主场景不创建剧情层")
	check(main.find_child("DeployFieldNotes", true, false) == null, "不保留旧教程控件")
	check(main._event_layer != null and main._event_layer.get_parent() == main._pile_layer, "地图事件与敌牌共用世界坐标层")
	check(not main._btn_upgrade.visible and not main._btn_map.visible and not main._btn_home.visible and not main._btn_drawer.visible and not main._btn_pool.visible, "拍击中不显示技能、地图、营地、商店或替换卡池入口")
	check(main._btn_retreat.visible and main._btn_retreat.text == "返回休息", "拍击中只保留结束本轮的休息入口")
	check(GameState.owned == {"I01": 1} and GameState.carry.is_empty(), "单人开局没有预先上阵的将兵")
	var has_cover := false
	for button in main.find_children("*", "Button", true, false):
		if button.text == "封面": has_cover = true
	check(not has_cover, "游戏场景没有返回旧封面的入口")
	await test_minimap_dock(main)
	await snapshot("adventure-play.png")
	test_hidden_events(main)
	for index in range(GameState.battle.size()):
		if int(GameState.battle[index].stage) != 0: continue
		while float(GameState.battle[index].hp) > 0.0:
			GameState.slap_cooldown_left = 0.0
			var hit := GameState.attack(index)
			check(hit, "实际手拍拍翻首区敌牌：%d" % index)
			if not hit: break
	check(GameState.zone_cleared(1, 0), "首个分区通过实际拍击永久征服")
	check(GameState.building_stock("B06") == 1 and GameState.building_stock("B08") == 1, "首区征服实际发放农田与水井建筑卡")
	main._open_home()
	main._open_shop()
	main._open_city()
	main._home.open_home()
	main._shop.open_shop()
	main._city.open_city()
	await frames()
	check(GameState.in_battle and not main._home.visible and not main._shop.visible and not main._city.visible and main._input_allowed(), "拍牌中所有整备页面拒绝打开且本轮继续")
	await click(main._btn_retreat)
	await frames()
	check(not GameState.in_battle and main._home.visible, "明确返回休息后才进入战后营地")
	check(main._home.find_child("ReturnToMain", true, false) == null, "营地没有返回旧主界面的出口")
	check(main._home._hub_tiles.size() == 4 and main._home._hub_tiles.has("base") and main._home._hub_page.columns == 2, "营地恢复商店构筑技能基建四格")
	check(main._home.find_child("CampJournal", true, false) == null, "营地没有札记")
	check(main._home.find_child("CampProgression", true, false) == null, "营地没有巡城教学条")
	check(main._home.get_global_rect().encloses(main._home._hub_page.get_global_rect()), "四格营地在视口内")
	await snapshot("adventure-camp.png")
	await click(main._home._hub_tiles.base)
	check(main._city.visible and not main._home.visible and not GameState.in_battle, "休息营地的基建入口打开独立基建页")
	check(GameState.city_slots(1) == 1 and main._city._sel == 1, "真实征服首区后基建开放一槽并选中新野")
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		await frames()
		for panel_name in ["BuildingWarehouse", "BaseOutcome"]:
			var panel := main._city.find_child(panel_name, true, false) as Control
			check(main._city.get_global_rect().encloses(panel.get_global_rect()), "%d高度基建的%s完整位于窗口内" % [height, panel_name])
	var farm_button: Button
	for building in main._city._side_box.get_children():
		if building is Button and building.get("building_id") == "B06":
			farm_button = building
			break
	check(farm_button != null and not farm_button.disabled, "仓库中首区赠送的农田可实际点击装配")
	var farm_stock := GameState.building_stock("B06")
	var building_gold := GameState.gold
	if farm_button != null:
		await click(farm_button)
		check(GameState.city_buildings(1).has("B06") and GameState.building_stock("B06") == farm_stock - 1, "真实鼠标装配农田并准确扣除仓库一张")
		check(GameState.gold == building_gold, "装配收藏建筑不产生额外金币")
	await snapshot("adventure-base.png")
	var remove_building := main._city.find_child("RemoveSelectedBuilding", true, false) as Button
	check(remove_building != null, "已装配农田显示真实卸下按钮")
	if remove_building != null:
		await click(remove_building)
		check(not GameState.city_buildings(1).has("B06") and GameState.building_stock("B06") == farm_stock, "真实鼠标卸下农田并恢复仓库数量")
		check(GameState.gold == building_gold, "卸下建筑不产生额外金币")
	await click(main._city.find_child("BaseReturnToCamp", true, false) as Button)
	check(main._home.visible and not main._city.visible and not GameState.in_battle, "基建返回战后营地并保持休息")
	GameState.skill_points = 2
	GameState.gold = 0.0
	main._open_upgrade()
	await frames()
	var skills = main._home._upgrade_page
	check(skills.cards.size() == 9, "技能页只保留九项手动技能")
	for retired in ["auto", "auto_next", "auto_power", "idle"]:
		check(not skills.cards.has(retired), "技能页无退役项 " + retired)
	check(not skills._buy_button.disabled, "零金币有技能点仍可升级")
	check(skills._buy_button.text.contains("技能点"), "购买按钮标明技能点")
	var previous_level := GameState.upgrade_level("power")
	await click(skills._buy_button)
	check(GameState.upgrade_level("power") == previous_level + 1 and GameState.skill_points == 1, "实际按钮消费一技能点并升级")
	check(GameState.gold == 0.0, "技能不扣金币")
	GameState.skill_points = 0
	GameState.gold = 100000.0
	skills.refresh()
	check(skills._buy_button.disabled and skills.cards.power.state.text == "技能点不足", "金币不能替代技能点")
	await snapshot("adventure-skills.png")
	GameState.owned.G00 = 1
	GameState.carry = ["G00"]
	main._home.open_section("deck")
	await frames()
	var deck = main._home._deck_page
	deck._select("G00")
	await frames()
	var growth := deck.find_child("DeckHeroGrowth", true, false) as Label
	check(growth != null and growth.text.contains("Lv.") and growth.text.contains("经验") and growth.text.contains("成长倍率"), "武将详情展示等级经验与实际成长")
	await snapshot("adventure-hero.png")
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		GameState.up.carry = 3
		deck.refresh()
		await frames()
		check(get_viewport().get_visible_rect().encloses(main._home.get_global_rect()), "%d高度休息页随窗口尺寸更新" % height)
		check(get_viewport().get_visible_rect().encloses(main._home.find_child("CampOutcome", true, false).get_global_rect()), "%d高度战果底栏在屏幕内" % height)
		for slot in deck.find_child("DeckSlots", true, false).get_children():
			for label in slot.find_children("*", "Label", true, false):
				check(slot.get_global_rect().encloses(label.get_global_rect()), "%d高度六阵位名称与空阵位文字留在框内" % height)
		await snapshot("adventure-deck-six-%d.png" % height)
	main._close_home()
	GameState.region_state[1] = "cleared"
	check(GameState.start_event_visit(1), "已征服新野可进入巡城")
	await frames()
	check(main._lbl_stamina.text == "巡城" and not main._stamina_bar.visible, "巡城没有战斗倒计时")
	check(GameState.battle.is_empty() and not main._event_layer.visible, "巡城没有敌牌，也不显示隐藏事件")
	main._update_minimap()
	check(main._minimap.events.is_empty(), "巡城小地图不显示任务与宝箱标记")
	await snapshot("adventure-visit.png")
	GameState.region_state[15] = "available"
	for parent in GameData.region(15).get("unlocked_by", []): GameState.region_state[int(parent)] = "cleared"
	check(GameState.start_battle(15), "后期十二分区城池可供布局验收")
	main._close_home()
	main._window_focused = false
	await frames()
	main._update_minimap()
	check(main._minimap.zones.size() == 12, "后期小地图显示十二个真实分区")
	for point in [Vector2.ZERO, main._world_size * 0.5, main._world_size]:
		check(main._minimap.minimap_to_world(main._minimap.world_to_minimap(point)).distance_to(point) < 0.02, "十二区紧凑地图世界坐标往返准确")
	var positions: Array[Vector2] = []
	for index in main._cards.size():
		if float(GameState.battle[index].hp) > 0.0:
			positions.append(main._cards[index].rest_pos + main._cards[index].size * 0.5)
	var points_match: bool = main._minimap.card_positions.size() == positions.size()
	for point in positions:
		points_match = points_match and main._minimap.card_positions.any(func(candidate: Vector2) -> bool: return candidate.distance_to(point) < 0.02)
	check(points_match, "十二区紧凑地图红点仍对应每张实际存活牌")
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		await frames()
		if DisplayServer.get_name() != "headless": await test_minimap_pixels(main._minimap, "后期十二分区%d高度" % height)
		await snapshot("adventure-dock-twelve-%d.png" % height)
	check(main._lbl_gold.size.x >= main._lbl_gold.get_minimum_size().x and not main._lbl_gold.clip_text, "高额金币显示完整数值与单位")
	await snapshot("adventure-dock-twelve.png")
	await test_full_footer(main)
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/Main.tscn", "启动直接进入新版流程，不再加载旧主菜单")
	print("[Adventure UI] checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
