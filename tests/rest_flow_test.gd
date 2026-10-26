extends Node
## 战中页面隔离、拍翻收益、休息期整备和默认0%镜头的真实页面回归。
## Godot --headless --path . tests/RestFlowTest.tscn -- --test-profile
const Story = preload("res://scripts/story_book.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 6) -> void:
	for i in count:
		await get_tree().process_frame

func fixture() -> void:
	GameState.set_process(false)
	GameState.new_game()
	GameState.narrative_paused = false
	GameState.up.crit = 0
	GameState.story_seen.clear()
	for event in Story.events():
		GameState.story_seen.append(str(event.id))

func new_main():
	fixture()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	return main

func press(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "真实按钮可操作：" + button.text)
	button.pressed.emit()
	await frames()

func owned_count() -> int:
	var count := 0
	for id in GameState.owned:
		count += int(GameState.owned[id])
	return count

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "休息流程测试隔离玩家正式存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	await _test_rest_and_purchases()
	await _test_expiry()
	await _test_direct_rest_pages()
	await _test_rest_waiting()
	await _test_default_camera()
	await _test_first_radius_gain()
	_test_pack_prices()
	print("[Rest flow] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_rest_and_purchases() -> void:
	var main = await new_main()
	check(GameState.owned == {"I01": 1} and GameState.carry.is_empty(), "开局只有主角，没有免费将兵")
	check(GameState.gold == 0.0 and GameState.player_xp == 0 and GameState.skill_points == 0, "开局没有金币或成长收益")
	GameState.gold = 10000.0
	GameState.skill_points = 2
	var cash := GameState.gold
	var levels: Dictionary = GameState.up.duplicate(true)
	var stock: Dictionary = GameState.owned.duplicate(true)
	var packs: Dictionary = GameState.pack_bought.duplicate(true)
	var duration := GameState.round_duration
	for button in [main._btn_upgrade, main._btn_map, main._btn_home, main._btn_drawer, main._btn_pool]:
		check(not button.visible, "拍牌时隐藏休息入口：" + button.text)
	check(main._btn_retreat.visible and main._btn_retreat.text == "返回休息", "拍牌HUD保留明确的结束本轮按钮")
	check(not GameState.buy_upgrade("radius"), "拍牌期间数据层拒绝购买升级")
	check(GameState.buy_pack(0).is_empty(), "拍牌期间数据层拒绝开卡包")
	check(GameState.gold == cash and GameState.up == levels and GameState.owned == stock, "被拒购买不扣钱、不升级、不加收藏")
	check(GameState.pack_bought == packs and GameState.total_packs == 0, "被拒开包不增加购买和保底计数")
	check(GameState.skill_points == 2, "战中被拒学习不消耗技能点")
	check(GameState.round_duration == duration and GameState.round_seconds_left == duration, "被拒购买不改变当前轮计时")
	GameState.battle[0].hp = GameState.click_damage() * 0.5
	check(GameState.attack(0) and GameState.run_kills == 1 and GameState.run_gold > 0.0, "真实休息前手拍拍翻一张牌才产生收入")
	GameState.advance_round(3.0)
	var earned := GameState.run_gold
	cash = GameState.gold
	await press(main._btn_retreat)
	check(main._home.visible and not GameState.in_battle and not GameState.round_active, "返回休息按钮先结束当前轮再进入营地")
	check(main._home.find_child("ReturnToMain", true, false) == null, "营地没有返回空桌面的旧出口")
	var has_cover := false
	for button in main.find_children("*", "Button", true, false):
		if button.text == "封面": has_cover = true
	check(not has_cover, "游戏中不保留返回封面的旧入口")
	check(is_zero_approx(GameState.round_seconds_left), "主动休息结束倒计时")
	check(is_equal_approx(GameState.gold, cash) and is_equal_approx(float(GameState.last_outcome.gold), earned), "主动休息保留即时收益且不重复发钱")
	check(is_equal_approx(float(GameState.last_outcome.seconds), 3.0) and int(GameState.last_outcome.slaps) == 1, "休息结算保留真实轮时长和拍数")
	var outcome: Dictionary = GameState.last_outcome.duplicate(true)
	GameState.advance_round(10.0)
	main._open_home()
	check(GameState.gold == cash and GameState.last_outcome == outcome and GameState.runs == 1, "重复打开休息或推进时间不重结算、不续轮")
	await press(main._home._hub_tiles.upgrade)
	var page = main._home._upgrade_page
	page.select_upgrade("radius")
	await frames()
	var radius := GameState.slap_radius()
	var cost := GameState.upgrade_cost("radius")
	var points := GameState.skill_points
	await press(page._buy_button)
	check(GameState.upgrade_level("radius") == 1 and GameState.slap_radius() > radius, "休息页真实按钮可购买范围升级")
	check(GameState.skill_points == points - cost and GameState.gold == cash, "休息学习只扣技能点，不扣金币")
	page.select_upgrade("stamina")
	await frames()
	await press(page._buy_button)
	var next_duration := GameState.round_duration_value()
	check(next_duration > duration and not GameState.round_active, "时长升级只准备下一轮，不重开旧轮")
	check(GameState.skill_points == 0 and GameState.gold == cash, "两项技能准确花完两点且金币不变")
	main._home.return_to_hub()
	await frames()
	await press(main._home._hub_tiles.shop)
	check(main._shop.visible and not GameState.in_battle, "休息营地商店入口仍在休息期")
	var buy_button: Button
	for node in main._shop_boxes["卡包"].get_children():
		if node is Button:
			buy_button = node
			break
	check(buy_button != null, "商店生成真实基础包购买按钮")
	if buy_button != null:
		var count := owned_count()
		cash = GameState.gold
		var price := GameState.pack_price(0)
		await press(buy_button)
		check(GameState.total_packs == 1 and owned_count() == count + 5, "休息购买卡包实际发放五张收藏")
		check(is_equal_approx(GameState.gold, cash - price), "休息购买卡包精确扣款")
		check(main._reveal.visible and main._reveal._slots.size() == 5, "真实购买接上逐张翻牌覆盖层")
		main._reveal._close()
		await get_tree().create_timer(0.3).timeout
	await press(main._shop.find_child("ReturnToCamp", true, false) as Button)
	await press(main._home._primary_action)
	check(GameState.in_battle and GameState.round_active and not main._home.visible, "继续未清分区按钮明确结束休息并重开拍牌")
	check(not main._shop.visible and not main._city.visible and not main._map_layer.visible and not main._reveal.visible and not main._drawer_open and not main._pool_open, "重新拍牌时商店、基建、地图、开包和卡池全部关闭")
	check(is_equal_approx(GameState.round_duration, next_duration) and is_equal_approx(GameState.round_seconds_left, next_duration), "新轮使用休息购买后的完整时长")
	check(GameState.upgrade_level("radius") == 1 and GameState.round_slaps == 0 and GameState.run_gold == 0.0, "新轮保留范围升级并清零轮统计")
	main.queue_free()
	await frames()

func _test_expiry() -> void:
	var main = await new_main()
	GameState.battle[0].hp = GameState.click_damage() * 0.5
	check(GameState.attack(0) and GameState.run_gold > 0.0, "到期回营测试先手拍拍翻一张牌")
	var cash := GameState.gold
	var earned := GameState.run_gold
	var duration := GameState.round_duration
	GameState.advance_round(duration)
	await frames()
	check(main._home.visible and not GameState.in_battle and not GameState.round_active, "倒计时到期真实打开休息营地")
	check(str(GameState.last_outcome.reason) == "time_up" and is_equal_approx(float(GameState.last_outcome.seconds), duration), "到期结算记录完整时长与到期原因")
	check(GameState.gold == cash and is_equal_approx(float(GameState.last_outcome.gold), earned), "到期回营也不重复发即时收益")
	main.queue_free()
	await frames()

func _test_direct_rest_pages() -> void:
	var main = await new_main()
	GameState.advance_round(2.0)
	var cash := GameState.gold
	var generation := GameState.battle_gen
	var remaining := GameState.round_seconds_left
	var outcome: Dictionary = GameState.last_outcome.duplicate(true)
	for entry in [[main, "_open_home"], [main, "_open_upgrade"], [main, "_open_shop"], [main, "_open_map"], [main, "_open_city"], [main._home, "open_home"], [main._shop, "open_shop"], [main._city, "open_city"]]:
		var opener := str(entry[1])
		entry[0].call(opener)
		await frames()
		check(GameState.in_battle and GameState.round_active and GameState.battle_gen == generation, opener + "在拍牌时被拒绝，不提前结束本轮")
		check(not main._home.visible and not main._shop.visible and not main._city.visible and not main._map_layer.visible and main._input_allowed(), opener + "不会弹出页面或暂停拍牌")
		check(GameState.gold == cash and GameState.last_outcome == outcome and GameState.runs == 0 and GameState.round_seconds_left == remaining, opener + "不改收益、轮次或倒计时")
	for section in ["upgrade", "deck", "shop", "base"]:
		main._home.open_section(section)
		await frames()
		check(GameState.in_battle and not main._home.visible and not main._shop.visible and not main._city.visible and main._input_allowed(), "战中不能绕过营地打开整备子页：" + section)
	await press(main._btn_retreat)
	check(not GameState.in_battle and main._home.visible and GameState.runs == 1, "只有明确点击返回休息才结束当前轮")
	for opener in ["_open_home", "_open_upgrade", "_open_shop", "_open_map", "_open_city"]:
		main.call(opener)
		await frames()
		check(not GameState.in_battle and GameState.runs == 1 and GameState.gold == cash, opener + "在休息期打开且不重复结算")
		match opener:
			"_open_home": check(main._home.visible, "休息期打开真实营地")
			"_open_upgrade": check(main._home.visible and main._home._upgrade_page.is_visible_in_tree(), "休息期打开真实技能页")
			"_open_shop": check(main._shop.visible, "休息期打开真实商店")
			"_open_map": check(main._map_layer.visible, "休息期打开真实地图")
			"_open_city": check(main._city.visible, "休息期打开真实基建")
	main.queue_free()
	await frames()

func _test_rest_waiting() -> void:
	var main = await new_main()
	GameState.battle[0].hp = 1000.0
	GameState.battle[0].hp_max = 1000.0
	check(GameState.attack(0) and float(GameState.battle[0].hp) > 0.0, "未拍翻的厚牌只记录受伤")
	check(GameState.gold == 0.0 and GameState.run_gold == 0.0 and GameState.player_xp == 0, "未拍翻时金币和经验均为零")
	await press(main._btn_retreat)
	check(main._home.visible and float(GameState.last_outcome.gold) == 0.0 and int(GameState.last_outcome.kills) == 0, "未拍翻就返回休息不补发收益")
	var generation := GameState.battle_gen
	var runs := GameState.runs
	GameState.advance_round(120.0)
	check(not GameState.in_battle and GameState.battle_gen == generation and GameState.runs == runs, "休息期间等待不会重开轮次")
	check(GameState.gold == 0.0 and GameState.player_xp == 0 and GameState.skill_points == 0, "休息期间等待不产生金币或成长")
	main.queue_free()
	await frames()

func _test_first_radius_gain() -> void:
	var main = await new_main()
	var pair: Array[int] = []
	for index in range(GameState.battle.size()):
		if float(GameState.battle[index].hp) > 0.0: pair.append(index)
		if pair.size() == 2: break
	check(pair.size() == 2, "范围夹具取到两张真实存活敌牌")
	if pair.size() < 2:
		main.queue_free()
		await frames()
		return
	var bounds := GameState.zone_rect(GameState.battle_region, int(GameState.battle[pair[0]].stage))
	var point := bounds.position + Vector2(bounds.size.x * 0.5, 120.0)
	for phase in range(2):
		var area := GameState.battle_world_size() - Vector2(500, 500)
		for position in range(pair.size()):
			var index := pair[position]
			var card: Dictionary = main._cards[index]
			var half_width := float(card.size.x) * 0.5
			var center := point + Vector2((-1.0 if position == 0 else 1.0) * (half_width + 43.0), 0.0)
			GameState.battle[index].nx = (center.x - 250.0) / area.x
			GameState.battle[index].ny = (center.y - 250.0) / area.y
			GameState.battle[index].rot = 0.0
			card.rot = 0.0
			card.node.rotation = 0.0
		main._sync_card_positions()
		if phase == 0:
			check(is_equal_approx(GameState.slap_radius(), 40.0) and main._area_targets(point, GameState.slap_radius()).is_empty(), "初始40范围无法碰到边距43的两张敌牌")
			await press(main._btn_retreat)
			main._open_upgrade()
			GameState.skill_points = 1
			check(GameState.buy_upgrade("radius") and is_equal_approx(GameState.slap_radius(), 46.0), "首次范围升级实际达到46")
			main._home._primary_action.pressed.emit()
			await frames()
		else:
			var targets: Array = main._area_targets(point, GameState.slap_radius())
			check(targets.size() == 2 and targets.has(pair[0]) and targets.has(pair[1]), "首级46范围在同一位置同时覆盖两张实际敌牌")
			main._navigate_minimap(point)
			var first_hp := float(GameState.battle[pair[0]].hp)
			var second_hp := float(GameState.battle[pair[1]].hp)
			main._slap_area(main._world_to_screen(point))
			check(GameState.round_slaps == 1 and float(GameState.battle[pair[0]].hp) < first_hp and float(GameState.battle[pair[1]].hp) < second_hp, "首次扩圈在下一轮同一掌真正伤到两张牌")
	main.queue_free()
	await frames()

func _test_default_camera() -> void:
	var main = await new_main()
	var anchor: Vector2 = main._table.size * 0.5
	var initial_pan: Vector2 = main._camera_pan
	var initial_world: Vector2 = main._screen_to_world(anchor)
	check(is_equal_approx(main._camera_zoom, 6.0) and main._zoom_label.text == "0%", "原+50%实际倍率6现在作为开局默认0%")
	var expected_scale := minf(main._table.size.x / main._world_size.x, main._table.size.y / main._world_size.y) * 6.0
	check(is_equal_approx(main._camera_scale, expected_scale) and main._viewport_world_rect().size.distance_to(main._table.size / expected_scale) < 0.02, "默认0%使用实际倍率6的摄像机比例和世界视野")
	for pair in [[7.5, "+25%"], [3.0, "-50%"], [6.0, "0%"], [4.0, "-33%"]]:
		main._set_camera_zoom(float(pair[0]), anchor)
		check(is_equal_approx(main._camera_zoom, float(pair[0])) and main._zoom_label.text == str(pair[1]), "镜头相对默认比例显示" + str(pair[1]))
	main._set_camera_zoom(100.0, anchor)
	check(is_equal_approx(main._camera_zoom, 8.0) and main._zoom_label.text == "+33%", "实际放大上限仍为8，相对新默认显示+33%")
	main._set_camera_zoom(0.01, anchor)
	check(is_equal_approx(main._camera_zoom, 0.65), "保留原有全城缩小下限")
	var reset: Button
	for node in main._camera_toolbar.find_children("*", "Button", true, false):
		if node is Button and node.text == "回目标区": reset = node
	check(reset != null, "镜头工具栏有回目标区按钮")
	if reset != null:
		await press(reset)
		check(is_equal_approx(main._camera_zoom, 6.0) and main._zoom_label.text == "0%", "真实回目标区按钮恢复实际倍率6并显示0%")
		check(main._camera_pan.is_equal_approx(initial_pan) and main._screen_to_world(anchor).distance_to(initial_world) < 0.02, "真实回目标区按钮恢复与初次进入完全相同的城区位置")
	main.queue_free()
	await frames()

func _test_pack_prices() -> void:
	fixture()
	GameState.retreat()
	GameState.gold = 10000.0
	check(GameState.pack_price(0) == 40, "基础卡包固定40金币")
	var cash := GameState.gold
	var tenth: Array = []
	for i in range(10):
		check(GameState.pack_price(0) == 40, "第%d包购买前基础价格保持40" % (i + 1))
		tenth = GameState.buy_pack(0)
		check(tenth.size() == 5, "第%d包实际发五张牌" % (i + 1))
	check(GameState.total_packs == 10 and GameState.pack_price(0) == 40 and is_equal_approx(GameState.gold, cash - 400.0), "十次基础开包不涨价且累计精确扣400")
	var high := 0
	for id in tenth:
		high = maxi(high, int(GameData.card(str(id)).get("star", 0)))
	check(high >= 3, "第十包仍包含至少三星保底")
	for i in range(GameData.packs.size()):
		var before := GameState.pack_price(i)
		GameState.pack_bought[str(GameData.packs[i].name)] = 100
		check(GameState.pack_price(i) == before, "所有卡包不因历史购买次数涨价：" + str(GameData.packs[i].name))
	GameState.bonus.pack_price_pct = 25.0
	check(GameState.pack_price(0) == 30, "固定包价仍保留真实25%折扣")
