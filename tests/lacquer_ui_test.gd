extends Node

const UISkin = preload("res://scripts/ui/ui_skin.gd")
const Chrome = preload("res://scripts/ui/paper_chrome.gd")
const Story = preload("res://scripts/story_book.gd")
var checks := 0
var failures := 0
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

func display_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

func test_lacquer_surface() -> void:
	for pixel_scale in [1, 2]:
		var surface_view := SubViewport.new()
		surface_view.size = Vector2i(384, 128) * pixel_scale
		surface_view.disable_3d = true
		surface_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(surface_view)
		var panel := Panel.new()
		panel.add_theme_stylebox_override("panel", UISkin.lacquer_panel(0.0))
		surface_view.add_child(panel)
		panel.size = Vector2(384, 128)
		panel.scale = Vector2.ONE * pixel_scale
		UISkin.chrome(panel, "lacquer")
		await frames()
		await RenderingServer.frame_post_draw
		var image := surface_view.get_texture().get_image()
		check(image.get_size() == surface_view.size, "%d倍原生漆面使用真实GPU输出尺寸" % pixel_scale)
		var column_peaks: Array[float] = []
		var large_jumps := 0
		var samples := 0
		var total_brightness := 0.0
		for column in 96:
			var pixel_x: int = (64 + column * 2) * pixel_scale
			var previous := display_luminance(image.get_pixel(pixel_x, 48 * pixel_scale))
			var peak := 0.0
			for pixel_y in range(48 * pixel_scale + 1, 78 * pixel_scale):
				var brightness := display_luminance(image.get_pixel(pixel_x, pixel_y))
				var difference := absf(brightness - previous)
				peak = maxf(peak, difference)
				if difference > 1.5 / 255.0: large_jumps += 1
				total_brightness += brightness
				samples += 1
				previous = brightness
			column_peaks.append(peak)
		column_peaks.sort()
		var median_peak := column_peaks[column_peaks.size() / 2]
		var expected_brightness := display_luminance(UISkin.LACQUER)
		check(absf(total_brightness / samples - expected_brightness) <= 0.04, "%d倍原生空白区域确实渲染玄漆面而非黑屏" % pixel_scale)
		check(median_peak <= 1.5 / 255.0, "%d倍漆面相邻行跳变中位峰值%.3f/255不超过1.5/255，不出现重复横纹" % [pixel_scale, median_peak * 255.0])
		print("[Lacquer surface] pixel_scale=%d columns=96 rows=%d median_peak=%.3f/255 worst_peak=%.3f/255 large_jump_ratio=%.5f" % [pixel_scale, 30 * pixel_scale - 1, median_peak * 255.0, column_peaks[-1] * 255.0, float(large_jumps) / samples])
		surface_view.queue_free()
		await frames()

func snapshot(filename: String) -> void:
	if output.is_empty() or not native: return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(filename)) == OK, "保存原生界面：" + filename)

func move_mouse(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await frames(3)

func mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func click(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "真实按钮可操作：" + button.text)
	if native:
		var point := button.get_global_rect().get_center()
		await move_mouse(point)
		mouse_button(point, true)
		mouse_button(point, false)
	else:
		button.pressed.emit()
	await frames()

func fixture() -> void:
	GameState.new_game()
	GameState.stop_automation(false)
	GameState.narrative_paused = false
	GameState.story_seen.clear()
	for event in Story.events(): GameState.story_seen.append(str(event.id))

func test_panel(control: Control, label: String) -> void:
	var style := control.get_theme_stylebox("panel") as StyleBoxFlat
	check(style != null, label + "保留真实面板样式")
	if style == null: return
	check(style.bg_color.is_equal_approx(UISkin.LACQUER), label + "使用玄漆深底")
	check(style.border_color.is_equal_approx(UISkin.LACQUER_RULE), label + "边线统一为暗金")

func test_label(label: Label, background: Color, message: String) -> void:
	var color := label.get_theme_color("font_color")
	check(luminance(color) > 0.30 and contrast(color, background) >= 4.5, message + "浅色文字对比度至少4.5:1")

func test_button(button: Button, label: String) -> void:
	var states := {"normal": "font_color", "hover": "font_hover_color", "pressed": "font_pressed_color"}
	for state in states:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		check(style != null, label + "具有独立" + state + "样式")
		if style == null: continue
		check(contrast(button.get_theme_color(states[state]), style.bg_color) >= 4.5, label + state + "正文对比度至少4.5:1")
	var normal_style := button.get_theme_stylebox("normal") as StyleBoxFlat
	var hover_style := button.get_theme_stylebox("hover") as StyleBoxFlat
	var pressed_style := button.get_theme_stylebox("pressed") as StyleBoxFlat
	var disabled_style := button.get_theme_stylebox("disabled") as StyleBoxFlat
	var focus_style := button.get_theme_stylebox("focus") as StyleBoxFlat
	if normal_style != null and hover_style != null and pressed_style != null:
		check(normal_style.bg_color != hover_style.bg_color and normal_style.bg_color != pressed_style.bg_color, label + "悬停和按下与常态有视觉差异")
	check(focus_style != null and not focus_style.draw_center and focus_style.border_width_left >= 2, label + "焦点使用不遮文字的双像素边线")
	if normal_style != null:
		check(contrast(button.get_theme_color("font_focus_color"), normal_style.bg_color) >= 4.5, label + "焦点态正文保持可读")
	check(disabled_style != null and contrast(button.get_theme_color("font_disabled_color"), disabled_style.bg_color) >= 2.5, label + "禁用态弱化后仍可辨识")

func test_chrome(root: Node) -> void:
	var count := 0
	for node in root.find_children("*", "Control", true, false):
		if node.get_script() != Chrome: continue
		count += 1
		check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, "装饰不截鼠标或键盘焦点：" + str(node.get_path()))
	check(count >= 10, "实际场景存在并核查至少十处边框或徽章装饰")

func test_rendered_panels(main) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	for control in [main.find_child("CityHUD", true, false), main._bar, main._camera_toolbar]:
		var area: Rect2 = control.get_global_rect().grow(-6.0)
		var dark := 0
		for row in 8:
			for column in 48:
				var point := area.position + area.size * Vector2((column + 0.5) / 48.0, (row + 0.5) / 8.0)
				var pixel := Vector2i((point * scale).floor())
				if luminance(image.get_pixelv(pixel)) < 0.08: dark += 1
		check(float(dark) / 384.0 >= 0.50, "实际渲染深漆底占主导，不被旧宣纸装饰覆盖：" + str(control.name))

func test_battle(main, height: int) -> void:
	var header := main.find_child("CityHUD", true, false) as Control
	check(header != null, "真实顶部资源栏存在")
	if header == null: return
	test_panel(header, "顶部栏")
	test_panel(main._bar, "底部栏")
	test_panel(main._camera_toolbar, "镜头工具栏")
	for label in [main._lbl_gold, main._lbl_stamina, main._lbl_bar, main._lbl_progress, main._zoom_label]:
		test_label(label, UISkin.LACQUER, str(label.get_path()))
	main._update_topbar()
	main._update_topbar()
	var plaque := main._lbl_region.get_parent().get_parent() as PanelContainer
	check(plaque != null, "城名保留独立牌匾")
	if plaque != null:
		var style := plaque.get_theme_stylebox("panel") as StyleBoxFlat
		check(style != null and luminance(style.bg_color) < 0.08, "城名牌匾使用深漆底")
		if style != null:
			test_label(main._lbl_region, style.bg_color, "连续状态刷新后的城名")
			test_label(main._lbl_route, style.bg_color, "城池路线")
	check(is_equal_approx(main._bar.size.y, 112.0), "%d高度底栏保持112像素" % height)
	var footer: Rect2 = main._bar.get_global_rect()
	var miniature: Rect2 = main._minimap.get_global_rect()
	check(main._minimap.size.is_equal_approx(Vector2(220, 96)), "小地图保持220×96而非扩大挤占地图")
	check(footer.encloses(miniature) and is_equal_approx(miniature.position.y - footer.position.y, 8.0) and is_equal_approx(footer.end.y - miniature.end.y, 8.0), "小地图上下各8像素且完整收在底栏内")
	check(main._minimap.find_child("MapTitle", true, false) == null, "小地图不增加地图标题")
	check(main._minimap._paper is StyleBoxFlat and main._minimap._paper.bg_color.is_equal_approx(UISkin.LACQUER), "小地图外框同步玄漆深底")
	check(is_equal_approx(main._slot_row.get_global_rect().get_center().y, footer.get_center().y), "默认上阵卡牌在底栏内垂直居中")
	var occupied := 0
	var empty := 0
	for slot in main._slot_row.get_children():
		check(slot.size.y >= 88.0 and footer.encloses(slot.get_global_rect()), "上阵卡面保留88像素且不贴边裁切")
		var style := slot.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null: continue
		if str(slot.card_id).is_empty():
			empty += 1
			check(luminance(style.bg_color) < 0.08, "空同行位为深漆底而非白纸卡")
			for label in slot.find_children("*", "Label", true, false): test_label(label, style.bg_color, "空槽" + label.text)
		else:
			occupied += 1
			check(luminance(style.bg_color) > 0.65, "真实武将卡保留纸白层次")
	check(occupied == 1 and empty == 3, "单人开局保持一张主角卡和三个空同行位")
	test_button(main._btn_retreat, "返回休息")
	for button in main._camera_toolbar.find_children("*", "Button", true, false): test_button(button, "镜头" + button.text)
	check(GameState.in_battle and main._input_allowed(), "换肤后拍牌仍可操作")
	var initial_carry: Array = GameState.carry.duplicate()
	var slot = main._slot_row.get_child(1)
	check(not slot._can_drop_data(Vector2.ZERO, {"paan_kind": "pool", "id": "G00"}), "战斗中卡槽仍拒绝拖入武将")
	main._deploy_at("G00", 0)
	check(GameState.carry == initial_carry, "战斗中换肤不会打开配将入口")
	test_chrome(main)
	if native: await test_rendered_panels(main)
	await snapshot("battle-%d-default.png" % height)
	if native: await test_pointer_states(main, height)

func test_pointer_states(main, height: int) -> void:
	var button: Button = main._btn_retreat
	var point := button.get_global_rect().get_center()
	await move_mouse(point)
	check(button.is_hovered(), "真实鼠标能穿过鎏金装饰到达按钮")
	await snapshot("battle-%d-hover.png" % height)
	mouse_button(point, true)
	await frames(3)
	check(button.is_pressed(), "真实按下能进入按钮按压态")
	await snapshot("battle-%d-pressed.png" % height)
	var outside := Vector2(800, 44)
	await move_mouse(outside)
	mouse_button(outside, false)
	await frames(3)
	check(GameState.in_battle and not main._home.visible, "移出后释放不会误触休息或拍牌")
	button.grab_focus()
	await frames(3)
	check(button.has_focus(), "按钮保留可见键盘焦点")
	await snapshot("battle-%d-focus.png" % height)
	button.release_focus()

func test_full_team(main, height: int) -> void:
	GameState.retreat()
	GameState.up.carry = 3
	GameState.up.equip = 5
	GameState.up.troops = 1
	for card_id in ["G00", "G01", "G02", "G03", "G04", "G05"]:
		GameState.owned[card_id] = 1
		check(GameState.carry_add(card_id), "满队夹具实际携带" + card_id)
	GameState.owned.E01 = 1
	GameState.owned.S01 = 1
	check(GameState.equip_to("G01", "E01") and GameState.troop_put("G01", "S01"), "休息期间夹具实际装配装备士兵")
	check(GameState.start_battle(1), "满队夹具进入真实战斗")
	main._close_home()
	await frames()
	var slots := main.find_child("DeploySlotsScroll", true, false) as ScrollContainer
	check(main._slot_row.get_child_count() == 7 and slots.get_h_scroll_bar().visible, "主角加六名将兵仍使用横向滚动")
	check(is_equal_approx(main._bar.size.y, 112.0) and main._bar.get_global_rect().encloses(slots.get_global_rect()), "满队装备带兵后底栏保持112像素")
	for slot in main._slot_row.get_children():
		check(slot.size.y >= 88.0, "满队卡牌不被换肤压缩")
		for portrait in slot.find_children("*", "TextureRect", true, false): check(portrait.size.y >= 44.0, "满队头像保留44像素")
	check(not GameState.carry_remove("G01") and not GameState.troop_remove("G01", "S01"), "战斗中仍不能卸将卸兵")
	slots.scroll_horizontal = 0
	await frames()
	await snapshot("battle-%d-full-team.png" % height)

func test_rest(main, height: int) -> void:
	await click(main._btn_retreat)
	check(main._home.visible and not GameState.in_battle, "真实按钮结束本轮进入休息而非旧主菜单")
	check(main._home._hub_tiles.size() == 4 and main._home._hub_page.columns == 2, "休息继续保留商店构筑技能基建四格")
	check(main._home.find_child("ReturnToMain", true, false) == null, "休息没有旧主菜单入口")
	check(main._home.get_global_rect().encloses(main._home._hub_page.get_global_rect()), "四格休息内容完整位于实际窗口")
	await snapshot("rest-%d-hub.png" % height)
	await click(main._home._hub_tiles.upgrade)
	var page = main._home._upgrade_page
	GameState.skill_points = 0
	page.select_upgrade("radius")
	page.refresh()
	await frames()
	check(page.is_visible_in_tree() and page._buy_button.disabled, "真实技能页零技能点时购买按钮禁用")
	test_button(page._buy_button, "技能学习")
	var style := page._detail_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		check(contrast(page._detail_title.get_theme_color("font_color"), style.bg_color) >= 4.5, "技能详情标题在实际内容底色上可读")
	await snapshot("rest-%d-upgrade-disabled.png" % height)
	test_chrome(main)

func _ready() -> void:
	check(OS.get_cmdline_user_args().has("--test-profile") and GameState.save_path() != GameState.SAVE_PATH, "玄漆UI测试强制隔离正式存档")
	if not OS.get_cmdline_user_args().has("--test-profile") or GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	native = DisplayServer.get_name() != "headless"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): output = argument.substr(10)
	if not output.is_empty(): check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK, "原生截图输出目录可用")
	GameState.set_process(false)
	if OS.get_cmdline_user_args().has("--surface-only"):
		check(native, "漆面GPU专项要求原生渲染而非无窗口模式")
		if native: await test_lacquer_surface()
		print("[Lacquer UI] checks=%d failures=%d actual_gui=%s surface_only=true" % [checks, failures, str(native)])
		get_tree().quit(1 if failures > 0 else 0)
		return
	for height in [720, 800]:
		print("[Lacquer UI] begin height=%d" % height)
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		fixture()
		var main = load("res://scenes/Main.tscn").instantiate()
		add_child(main)
		main._window_focused = false
		await frames()
		if native: await move_mouse(Vector2(800, 44))
		await test_battle(main, height)
		await test_full_team(main, height)
		await test_rest(main, height)
		main.queue_free()
		await frames()
		print("[Lacquer UI] complete height=%d" % height)
	if native: await test_lacquer_surface()
	print("[Lacquer UI] checks=%d failures=%d actual_gui=%s" % [checks, failures, str(native)])
	get_tree().quit(1 if failures > 0 else 0)
