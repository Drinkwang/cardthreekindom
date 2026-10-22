extends Node
## 使用真实分区牌位验证聚拢、命中、呈现、小地图和部分城基建入口。
const Story = preload("res://scripts/story_book.gd")
var checks := 0
var failures := 0
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	for i in range(8): await get_tree().process_frame

func snapshot(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name)) == OK, "保存原生截图" + name)

func _ready() -> void:
	if GameState.save_path() == GameState.SAVE_PATH:
		push_error("必须使用隔离测试档")
		get_tree().quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): output = argument.substr(10)
	GameState.set_process(false)
	GameState.new_game()
	GameState.retreat()
	GameState.owned.G00 = 1
	GameState.owned.E02 = 1
	GameState.up.equip = 1
	GameState.carry = ["G00"]
	GameState.up.crit = 0
	GameState.story_seen.clear()
	for event in Story.events(): GameState.story_seen.append(str(event.id))
	check(GameState.equip_to("G00", "E02"), "营地装长矛")
	check(GameState.start_battle(1), "开始真实新野布局")
	GameState.narrative_paused = false
	for enemy in GameState.battle:
		enemy.hp = 1000.0
		enemy.hp_max = 1000.0
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	main._window_focused = false
	var first := 0
	var neighbor := 1
	var point := GameState.get_enemy_world_center(first)
	var before := GameState.get_enemy_world_center(neighbor)
	check(point.distance_to(before) < 260.0, "真实初始阵型邻牌在聚拢范围内")
	check(main._viewport_world_rect().has_point(point), "默认0%镜头对准首个未征服区")
	check(main._area_targets(before, 40).has(neighbor), "位移前真实命中使用后端牌位")
	main._navigate_minimap(point)
	var cash := GameState.gold
	main._slap_area(main._world_to_screen(point))
	await get_tree().create_timer(0.3).timeout
	var after := GameState.get_enemy_world_center(neighbor)
	check(GameState.round_slaps == 1, "真实界面落掌只计一次")
	check(is_equal_approx(before.distance_to(after), 26.0), "真实邻牌按18加8聚拢26")
	check(after.distance_to(point) < before.distance_to(point), "聚拢方向指向掌心")
	check(GameState.gold > cash, "手拍仍发即时金币")
	var rendered: Vector2 = main._cards[neighbor].node.position + Vector2(main._cards[neighbor].size) * 0.5
	check(rendered.distance_to(after) < 0.1, "0.18秒动画后可见位置到达权威牌位")
	check(main._area_targets(after, 1).has(neighbor), "动画后命中同步新位置")
	var mapped := false
	for map_point in main._minimap.card_positions:
		if map_point.distance_to(after) < 0.1: mapped = true
	check(mapped and main._minimap.zones.size() == 5, "小地图同步位移与全部分区")
	await snapshot("gather.png")
	GameState.up.power = 90
	GameState.slap_cooldown_left = 0.0
	GameState.begin_slap_batch()
	for i in range(GameState.battle.size()):
		if int(GameState.battle[i].stage) == 0: GameState.attack(i)
	GameState.end_slap_batch()
	await frames()
	check(GameState.in_battle and GameState.zone_cleared(1, 0), "真实界面清一区后留在拍击中")
	check(bool(main._minimap.zones[0].cleared), "清区立即标记小地图征服状态")
	await snapshot("zone-cleared.png")
	main._btn_retreat.pressed.emit()
	await frames()
	check(main._home.visible and not GameState.in_battle, "结束一局才进入营地")
	main._home._hub_tiles.base.pressed.emit()
	await frames()
	check(main._city.visible, "新野仅一区也能打开基建")
	check(main._city._city_picker.item_count == 1, "选城器包含部分征服新野")
	check(GameState.place_building(1, "B06", 0, 0), "部分城可以放农田")
	main._city.refresh()
	await frames()
	await snapshot("base.png")
	main._close_city()
	main._open_home()
	main._home.open_section("deck")
	var deck = main._home._deck_page
	deck._selected = "G00"
	deck._tab = "装备"
	deck.refresh()
	await frames()
	var summary_visible := false
	for label in deck.find_children("*", "Label", true, false):
		if label.text.contains("本将聚拢距离 26"): summary_visible = label.is_visible_in_tree()
	check(summary_visible, "实际装备页显示18加8的本将聚拢距离26")
	var matching_visible := false
	for label in deck.find_children("*", "Label", true, false):
		if label.text.contains("契合：聚拢距离 +8"): matching_visible = label.is_visible_in_tree()
	check(matching_visible, "实际已装槽显示契合参数而非旧全队拍力")
	await snapshot("equipment.png")
	main.queue_free()
	await frames()
	print("[Manual combat UI] checks=%d failures=%d actual_gui=%s" % [checks, failures, str(DisplayServer.get_name() != "headless")])
	get_tree().quit(1 if failures else 0)
