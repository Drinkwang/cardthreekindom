extends Node
## Use the actual GUI path to ensure decorative layers do not intercept controls.
const Story = preload("res://scripts/story_book.gd")
var checks := 0
var failures := 0
var _out := ""
var _gpu := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 6) -> void:
	for i in count:
		await get_tree().process_frame

func move_mouse(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await frames(3)

func click(button: Button) -> void:
	if not _gpu:
		button.pressed.emit()
		await frames()
		return
	var point := button.get_global_rect().get_center()
	await move_mouse(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
	await frames()

func snapshot(filename: String) -> void:
	if not _gpu or _out.is_empty(): return
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	check(picture.save_png(_out.path_join(filename)) == OK, "Save actual UI " + filename)

func _ready() -> void:
	_gpu = DisplayServer.get_name() != "headless"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): _out = argument.substr(10)
	check(GameState.save_path() != GameState.SAVE_PATH, "UI test isolates the player save")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	GameState.set_process(false)
	GameState.new_game()
	GameState.stop_automation(false)
	GameState.narrative_paused = false
	GameState.story_seen.clear()
	for event in Story.events(): GameState.story_seen.append(str(event.id))
	GameState.gold = 268.0
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	var initial_slaps := GameState.round_slaps
	var initial_radius := GameState.slap_radius()
	var hud := main.find_child("CityHUD", true, false) as Control
	check(main.get_global_rect().encloses(hud.get_global_rect()), "HUD fits the actual viewport")
	check(hud.size.y <= 94.0, "HUD remains compact")
	check(main._bar.size.y <= 112.0, "The whole portrait bar shrinks to 112 pixels")
	var safe_rect: Rect2 = main.get_global_rect().grow(-16.0)
	var footer_safe := Rect2(safe_rect.position, safe_rect.size + Vector2(0, 8))
	for node in main.find_children("*", "Control", true, false):
		if node.is_visible_in_tree() and (node is BaseButton or node is ScrollBar or node == main._minimap):
			var bounds: Rect2 = footer_safe if main._bar.is_ancestor_of(node) else safe_rect
			check(bounds.encloses(node.get_global_rect()), "Interactive control stays inside its HUD or centered footer safe area: " + str(node.name))
	check(main._minimap.size.is_equal_approx(Vector2(220, 96)), "Permanent minimap retains its compact 220 by 96 size")
	var to_table: Transform2D = main._table.get_global_transform().affine_inverse()
	var top_blank: Vector2 = to_table * (main.global_position + Vector2(main.size.x * 0.5, 4))
	var bottom_blank: Vector2 = to_table * (main.global_position + Vector2(main.size.x * 0.5, main.size.y - 4))
	check(not main._over_camera_ui(top_blank) and not main._over_camera_ui(bottom_blank), "Blank fixed HUD edges do not block navigation")
	for button in [main._btn_upgrade, main._btn_map, main._btn_home, main._btn_drawer]:
		check(not button.visible, "Active round hides rest navigation: " + button.text)
	check(not main._btn_pool.visible and main._home.find_child("ReturnToMain", true, false) == null, "Active round exposes no pool or retired navigation")
	var carry_before: Array = GameState.carry.duplicate()
	var teammate = main._slot_row.get_child(1)
	check(not teammate._can_drop_data(Vector2.ZERO, {"paan_kind": "pool", "id": "G00"}), "Active team slots reject drop input")
	var slot_click := InputEventMouseButton.new()
	slot_click.button_index = MOUSE_BUTTON_LEFT
	slot_click.pressed = true
	teammate._gui_input(slot_click)
	main._deploy_at("G00", 0)
	main._undeploy("G00")
	check(GameState.carry == carry_before, "Active team remains read-only through click and direct handlers")
	main._set_pool(true)
	main._open_upgrade()
	main._open_shop()
	main._open_city()
	main._open_map()
	check(not main._pool.visible and not main._home.visible and not main._shop.visible and not main._city.visible and not main._map_layer.visible and main.find_child("StoryDiary", true, false) == null, "Management handlers cannot open during battle")
	check(main._btn_retreat.visible and hud.get_global_rect().encloses(main._btn_retreat.get_global_rect()), "Rest button remains visible inside HUD")
	if _gpu: await move_mouse(main._btn_retreat.get_global_rect().get_center())
	await snapshot("play.png")
	await click(main._btn_retreat)
	check(main._home.visible and not GameState.in_battle, "Rest button settles the round and opens camp")
	check(main._home.find_child("CampPractice", true, false) == null and main._home.find_child("CampAutomation", true, false) == null, "Camp has no repeat-practice or auto-slap controls")
	await snapshot("camp.png")
	await click(main._home._hub_tiles.upgrade)
	check(main._home._upgrade_page.is_visible_in_tree(), "Camp upgrade tile opens the real upgrade page")
	check(main._home._secondary_action == null or not main._home._secondary_action.visible, "Upgrade page avoids a redundant upgrade navigation button")
	check(GameState.round_slaps == initial_slaps, "Upgrade UI click never slaps a city card")
	var page = main._home._upgrade_page
	for retired in ["auto", "auto_next", "auto_power"]:
		check(not page.cards.has(retired), "Retired automatic slapping upgrade is absent: " + retired)
	check(not page.cards.has("idle"), "Offline income upgrades remain retired")
	GameState.skill_points = 1
	main._home.refresh()
	page.select_upgrade("radius")
	await frames()
	check(not page._buy_button.disabled, "Available upgrade is purchasable")
	await snapshot("upgrade.png")
	var cost := GameState.upgrade_cost("radius")
	var old_gold := GameState.gold
	await click(page._buy_button)
	check(GameState.upgrade_level("radius") == 1 and GameState.slap_radius() > initial_radius, "Purchase works through the decorated button")
	check(GameState.skill_points == 0 and cost == 1 and is_equal_approx(GameState.gold, old_gold), "Actual purchase consumes one skill point and preserves gold")
	check(page._receipt.text.contains("Lv.1") and page._receipt.text.contains("余 0 技能点"), "Successful purchase shows the new level and remaining skill points")
	GameState.gold = 0.0
	main._home.refresh()
	var before_radius := GameState.slap_radius()
	await click(page._buy_button)
	check(GameState.slap_radius() == before_radius, "Disabled visual state prevents a second purchase")
	await snapshot("upgrade-unaffordable.png")
	var return_button := main._home.find_child("ReturnToCamp", true, false) as Button
	await click(return_button)
	check(main._home.visible and main._home._section == "hub", "Section return stays in the rest hub")
	check(not GameState.in_battle, "Returning to the rest hub does not start combat")
	await frames()
	await click(main._home._primary_action)
	check(GameState.in_battle and not main._home.visible, "Camp start button opens the next round")
	main._btn_pool.pressed.emit()
	await frames()
	check(not main._pool.visible, "Hidden pool handler stays closed during battle")
	check(GameState.round_slaps == initial_slaps, "Footer click never slaps a card")
	var mini = main._minimap
	check(mini.find_child("MapTitle", true, false) == null, "Minimap has no title row after continuing combat")
	var map_size: Vector2 = mini.size
	var focus: Vector2 = main._screen_to_world(main._table.size * 0.5)
	check(mini.find_child("ToggleMap", true, false) == null, "Minimap has no collapse button")
	for down in [true, false]:
		var frame_click := InputEventMouseButton.new()
		frame_click.button_index = MOUSE_BUTTON_LEFT
		frame_click.pressed = down
		frame_click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		frame_click.position = mini.global_position + Vector2(4, 4)
		frame_click.global_position = frame_click.position
		if _gpu: get_viewport().push_input(frame_click, true)
		else:
			frame_click.position -= mini.global_position
			mini._gui_input(frame_click)
	await frames(2)
	check(mini.size.is_equal_approx(map_size) and main._screen_to_world(main._table.size * 0.5).distance_to(focus) < 0.1, "Frame click preserves minimap size and camera focus")
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_M
		key.pressed = down
		if _gpu: get_viewport().push_input(key, true)
		else: main._input(key)
		await frames(2)
	check(mini.size.is_equal_approx(map_size) and main._screen_to_world(main._table.size * 0.5).distance_to(focus) < 0.1, "M key preserves minimap size and camera focus")
	await snapshot("minimap.png")
	print("[UI interaction v2.5] checks=%d failures=%d actual_gui=%s" % [checks, failures, str(_gpu)])
	get_tree().quit(1 if failures > 0 else 0)
