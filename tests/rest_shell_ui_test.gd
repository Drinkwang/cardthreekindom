extends Node

const UISkin = preload("res://scripts/ui/ui_skin.gd")
const Chrome = preload("res://scripts/ui/paper_chrome.gd")
const Story = preload("res://scripts/story_book.gd")
var checks := 0
var failures := 0
var captures := 0
var output := ""
var native := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 8) -> void:
	for frame in count: await get_tree().process_frame

func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722

func contrast(foreground: Color, background: Color) -> float:
	var first := luminance(foreground)
	var second := luminance(background)
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)

func find_control(root: Node, node_name: String) -> Control:
	if root is Control and str(root.name) == node_name: return root
	var control := root.find_child(node_name, true, false) as Control
	check(control != null, "存在真实页面节点：" + node_name)
	return control

func test_bounds(control: Control, label: String) -> void:
	if control == null: return
	var viewport_bounds := get_viewport().get_visible_rect().grow(1.0)
	check(control.is_visible_in_tree(), label + "确实可见")
	check(control.size.x > 0.0 and control.size.y > 0.0, label + "具有实际布局尺寸")
	check(viewport_bounds.encloses(control.get_global_rect()), label + "完整收在实际视口内")

func test_dark_panel(control: Control, label: String) -> void:
	if control == null: return
	test_bounds(control, label)
	var style := control.get_theme_stylebox("panel") as StyleBoxFlat
	check(style != null, label + "为真实平滑面板")
	if style == null: return
	check(style.bg_color.is_equal_approx(UISkin.LACQUER), label + "使用统一玄漆底色")
	check(style.border_color.is_equal_approx(UISkin.LACQUER_RULE), label + "使用统一暗金边线")

func test_paper(control: Control, label: String, require_text: bool = true) -> void:
	if control == null: return
	test_bounds(control, label)
	var style := control.get_theme_stylebox("panel")
	var fill: Variant = style.get("bg_color")
	check(fill is Color, label + "保留独立内容纸面")
	if not fill is Color: return
	check(luminance(fill) > 0.60, label + "内容为纸白而非玄漆底")
	if not require_text: return
	var readable := 0
	for child in control.find_children("*", "Label", true, false):
		if not child.is_visible_in_tree() or child.text.is_empty(): continue
		var color: Color = child.get_theme_color("font_color")
		if luminance(color) < 0.30 and contrast(color, fill) >= 4.5:
			readable += 1
	check(readable > 0, label + "实际内容至少一处深墨正文达到4.5:1")

func test_header(header: Control, label: String) -> void:
	if header == null: return
	test_dark_panel(header, label)
	var visible_labels := 0
	for child in header.find_children("*", "Label", true, false):
		if not child.is_visible_in_tree() or child.text.is_empty(): continue
		visible_labels += 1
		var color: Color = child.get_theme_color("font_color")
		check(luminance(color) > 0.30 and contrast(color, UISkin.LACQUER) >= 4.5,
			label + "浅字实际对比度至少4.5:1：" + child.text)
	check(visible_labels >= 2, label + "核查真实标题与资源文字")
	if native: await test_rendered_header(header, label)

func test_rendered_header(header: Control, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var area := header.get_global_rect().grow(-5.0)
	var dark := 0
	for row in 8:
		for column in 48:
			var point := area.position + area.size * Vector2((column + 0.5) / 48.0, (row + 0.5) / 8.0)
			var pixel := Vector2i((point * scale).floor())
			if luminance(image.get_pixelv(pixel)) < 0.10: dark += 1
	check(float(dark) / 384.0 >= 0.45, label + "原生GPU输出以玄漆底为主而非旧纸框或黑屏")

func test_chrome(root: Node, label: String) -> void:
	var count := 0
	for control in root.find_children("*", "Control", true, false):
		if control.get_script() != Chrome: continue
		count += 1
		check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE and control.focus_mode == Control.FOCUS_NONE,
			label + "金框装饰不截鼠标和键盘焦点：" + str(control.get_path()))
	check(count > 0, label + "实际存在玄漆或纸面装饰")

func click(button: Button) -> void:
	check(button != null, "真实页面入口存在")
	if button == null: return
	check(button.is_visible_in_tree() and not button.disabled, "真实页面入口可操作：" + button.text)
	test_bounds(button, "按钮" + button.text)
	if native:
		var point := button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		get_viewport().push_input(motion, true)
		await frames(3)
		check(button.is_hovered(), "实际鼠标穿过装饰到达：" + button.text)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			event.position = point
			event.global_position = point
			get_viewport().push_input(event, true)
	else:
		button.pressed.emit()
	await frames()

func snapshot(filename: String) -> void:
	if output.is_empty() or not native: return
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename))
	check(error == OK, "保存原生页面截图：" + filename)
	if error == OK: captures += 1

func fixture() -> void:
	GameState.new_game()
	GameState.stop_automation(false)
	GameState.narrative_paused = false
	GameState.story_seen.clear()
	for event in Story.events(): GameState.story_seen.append(str(event.id))

func test_rest_state(main, label: String) -> void:
	check(not GameState.in_battle and not GameState.round_active, label + "保持真实休息状态")
	check(not main._input_allowed(), label + "遮挡底层拍牌输入")

func test_shell(root: Control, prefix: String, label: String) -> void:
	test_dark_panel(find_control(root, prefix + "ShellFrame"), label + "外框")
	await test_header(find_control(root, prefix + "ShellHeader"), label + "顶栏")
	test_chrome(root, label)

func test_pages(main, height: int) -> void:
	check(GameState.in_battle and GameState.owned == {"I01": 1} and GameState.carry.is_empty(), "单人开局保持原规则")
	await click(main._btn_retreat)
	test_rest_state(main, "大本营")
	check(main._home.visible and main._home._hub_tiles.size() == 4 and main._home._hub_page.columns == 2,
		"真实返回休息后仍为商店、构筑、技能、基建四格")
	check(main._home.find_child("ReturnToMain", true, false) == null, "营地不恢复旧主界面出口")
	await test_shell(main._home, "Rest", "大本营")
	test_paper(find_control(main._home, "RestShellPaperBody"), "营地内容")
	test_dark_panel(find_control(main._home, "CampOutcome"), "营地战果底栏")
	test_bounds(main._home._hub_page, "营地四格")
	for key in ["shop", "deck", "upgrade", "base"]:
		check(main._home._hub_tiles.has(key), "保留原整备入口：" + key)
		test_bounds(main._home._hub_tiles[key], "营地入口" + key)
	await snapshot("rest-%d-hub.png" % height)
	await click(main._home._hub_tiles.shop)
	test_rest_state(main, "商店")
	check(main._shop.visible and not main._home.visible, "真实商店入口打开独立页面")
	await test_shell(main._shop, "Shop", "商店")
	test_paper(find_control(main._shop, "ShopPaperContent"), "商店内容")
	test_paper(main._shop.content, "商店货架")
	await snapshot("rest-%d-shop.png" % height)
	await click(find_control(main._shop, "ReturnToCamp") as Button)
	check(main._home.visible and not main._shop.visible, "商店返回大本营而非战斗")
	await click(main._home._hub_tiles.deck)
	test_rest_state(main, "构筑")
	var deck = main._home._deck_page
	check(deck.is_visible_in_tree(), "构筑真实入口显示将牌册")
	await test_shell(main._home, "Rest", "构筑")
	test_paper(find_control(main._home, "RestShellPaperBody"), "构筑内容")
	test_paper(find_control(deck, "DeckSelected"), "构筑选中卡详情")
	test_bounds(deck, "构筑页")
	await snapshot("rest-%d-deck.png" % height)
	for tab in ["装备", "带兵", "上阵"]:
		await click(find_control(deck, "DeckTab_" + tab) as Button)
		check(deck._tab == tab and deck.is_visible_in_tree(), "真实鼠标切换构筑子页：" + tab)
		test_bounds(find_control(deck, "DeckBody"), "构筑" + tab + "内容")
		test_paper(find_control(deck, "DeckSelected"), "构筑" + tab + "详情")
	await click(main._home._back_button)
	await click(main._home._hub_tiles.upgrade)
	test_rest_state(main, "技能")
	var upgrade = main._home._upgrade_page
	check(upgrade.is_visible_in_tree() and upgrade.cards.size() == 9, "技能真实入口保留九项手动技能")
	await test_shell(main._home, "Rest", "技能")
	test_paper(find_control(main._home, "RestShellPaperBody"), "技能内容")
	test_paper(upgrade._detail_panel, "技能纸面详情")
	test_bounds(upgrade, "技能页")
	check(upgrade._buy_button.disabled and GameState.skill_points == 0, "零技能点禁用学习且不改变成长规则")
	await snapshot("rest-%d-upgrade.png" % height)
	await click(main._home._back_button)
	await click(main._home._hub_tiles.base)
	test_rest_state(main, "基建")
	check(main._city.visible and not main._home.visible, "基建真实入口显示独立页面")
	await test_shell(main._city, "Base", "基建")
	for panel_name in ["CityManagement", "BuildingLedger", "BuildingWarehouse"]:
		test_paper(find_control(main._city, panel_name), "基建" + panel_name)
	test_dark_panel(find_control(main._city, "BaseOutcome"), "基建战果底栏")
	await snapshot("rest-%d-base.png" % height)
	await click(find_control(main._city, "BaseReturnToCamp") as Button)
	check(main._home.visible and not main._city.visible, "基建返回仍为营地")
	var region_state: Dictionary = GameState.region_state.duplicate(true)
	var cleared_zones: Dictionary = GameState.cleared_zones.duplicate(true)
	var outcome: Dictionary = GameState.last_outcome.duplicate(true)
	GameState.region_state[1] = "cleared"
	GameState.cleared_zones[1] = range(GameState.zone_count(1))
	GameState.last_outcome["region"] = 1
	GameState.last_outcome["result"] = "cleared"
	main._home.refresh()
	await frames()
	check(main._home._primary_action.text == "选择下一座城", "通关夹具显示既有舆图入口，不新增功能")
	await click(main._home._primary_action)
	test_rest_state(main, "舆图")
	check(main._map_layer.visible and not main._home.visible, "真实舆图入口打开地图而非重开战斗")
	await test_shell(main._map_layer, "Map", "舆图")
	test_paper(find_control(main._map_layer, "MapShellPaperBody"), "舆图内容", false)
	await snapshot("rest-%d-map.png" % height)
	await click(find_control(main._map_layer, "MapReturnToCamp") as Button)
	check(main._home.visible and not main._map_layer.visible, "舆图真实返回营地")
	GameState.region_state = region_state
	GameState.cleared_zones = cleared_zones
	GameState.last_outcome = outcome
	main._home.refresh()
	await frames()
	await test_reveal(main, height)
	await test_battle_lock(main)

func click_point(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
	await frames(3)

func test_reveal(main, height: int) -> void:
	main._play_reveal("开卡 · 将牌入册", ["S01", "G00", "G01", "S02", "G02"], "五张卡牌 · 收藏保留原纸面")
	var reveal = main._reveal
	reveal.set_process(false)
	await frames()
	check(reveal._next == 0, "开卡初始不提前翻牌")
	var first_card: Control = reveal._slots[0]["wrap"]
	await click_point(first_card.get_global_rect().get_center())
	check(reveal._next == 1 and reveal._flipping, "真实点击卡面穿过新外框，只推进第一张")
	if reveal._flip_tween != null:
		reveal._flip_tween.pause()
		reveal._flip_tween.custom_step(1.0)
	var paper: Control = find_control(reveal, "RevealPaperContent")
	await click_point(paper.get_global_rect().position + Vector2(30, 30))
	check(reveal._next == 2 and reveal._flipping, "真实点击空白纸面不被承托层截走，只推进第二张")
	if reveal._flip_tween != null:
		reveal._flip_tween.pause()
		reveal._flip_tween.custom_step(1.0)
	reveal._reveal_all()
	if reveal._showcasing: reveal._advance()
	await frames()
	check(reveal.visible and not GameState.in_battle, "开卡展示保持休息状态")
	test_dark_panel(find_control(reveal, "RevealShellFrame"), "开卡外框")
	test_paper(find_control(reveal, "RevealPaperContent"), "开卡内容")
	test_bounds(reveal._row, "五张开卡内容")
	test_chrome(reveal, "开卡")
	await snapshot("rest-%d-reveal.png" % height)
	var close_button: Button
	for button in reveal.find_children("*", "Button", true, false):
		if button.text == "收好卡牌": close_button = button
	await click(close_button)
	await get_tree().create_timer(0.3).timeout
	check(not reveal.visible and main._home.visible, "收牌真实返回原休息页")

func test_battle_lock(main) -> void:
	GameState.owned.G00 = 1
	GameState.owned.G01 = 1
	GameState.owned.E01 = 1
	GameState.owned.S01 = 1
	GameState.up.equip = 1
	GameState.up.troops = 1
	check(GameState.carry_add("G00"), "休息期夹具通过真实接口携带武将")
	check(GameState.equip_to("G00", "E01") and GameState.troop_put("G00", "S01"), "休息期夹具通过真实接口装备和带兵")
	main._home.refresh()
	await frames()
	await click(main._home._primary_action)
	check(GameState.in_battle and GameState.round_active and main._input_allowed(), "真实结算主按钮返回可拍牌战斗")
	check(not main._home.visible and not main._shop.visible and not main._city.visible and not main._map_layer.visible,
		"拍牌时全部整备页面关闭")
	var before := [GameState.carry.duplicate(true), GameState.hero_equip.duplicate(true), GameState.hero_troops.duplicate(true), GameState.gold]
	check(not GameState.carry_add("G01") and not GameState.carry_remove("G00"), "战斗中仍不可增加或撤换武将")
	check(not GameState.equip_to("G01", "E01") and not GameState.unequip_from("G00", "E01") and not GameState.troop_remove("G00", "S01"),
		"战斗中仍不可转移装备、卸装备或撤兵")
	for section in ["shop", "deck", "upgrade", "base"]: main._home.open_section(section)
	main._open_map()
	main._shop.open_shop()
	main._city.open_city()
	await frames()
	check(not main._home.visible and not main._shop.visible and not main._city.visible and not main._map_layer.visible and main._input_allowed(),
		"战斗无法通过旧入口绕开整备锁")
	check(before == [GameState.carry, GameState.hero_equip, GameState.hero_troops, GameState.gold],
		"战斗中被拒整备不改变武将、装备、士兵或金币")

func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	check(arguments.has("--test-profile") and GameState.save_path() != GameState.SAVE_PATH, "全页面外框测试隔离正式存档")
	if not arguments.has("--test-profile") or GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	native = DisplayServer.get_name() != "headless"
	check(native, "全页面外框验收要求真实原生窗口与GPU截图")
	for argument in arguments:
		if argument.begins_with("--out-dir="): output = argument.substr(10)
	if not output.is_empty():
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK, "原生截图目录可用")
	GameState.set_process(false)
	for height in [720, 800]:
		print("[Rest shell UI] begin height=%d" % height)
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		fixture()
		var main = load("res://scenes/Main.tscn").instantiate()
		add_child(main)
		main._window_focused = false
		await frames()
		await test_pages(main, height)
		main.queue_free()
		await frames()
		print("[Rest shell UI] complete height=%d" % height)
	if native and not output.is_empty(): check(captures == 14, "720与800高度各保存七个原生页面，总计14张")
	print("[Rest shell UI] checks=%d failures=%d actual_gui=%s screenshots=%d" % [checks, failures, str(native), captures])
	get_tree().quit(1 if failures > 0 else 0)
