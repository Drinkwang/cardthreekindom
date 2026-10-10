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
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
		await frames(3)

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
	check(main._bar.size.y <= 120.0, "Portrait bar remains compact")
	for button in [main._btn_upgrade, main._btn_map, main._btn_home, main._btn_city, main._btn_drawer, main._btn_retreat]:
		check(hud.get_global_rect().encloses(button.get_global_rect()), "HUD navigation remains visible: " + button.text)
	if _gpu: await move_mouse(main._btn_upgrade.get_global_rect().get_center())
	await snapshot("play.png")
	await click(main._btn_upgrade)
	check(main._home.visible and main._home._upgrade_page.is_visible_in_tree(), "Prominent upgrade button opens the real upgrade page")
	check(not main._home._secondary_action.visible, "Upgrade page avoids a redundant upgrade navigation button")
	check(GameState.round_slaps == initial_slaps, "Upgrade UI click never slaps a city card")
	var page = main._home._upgrade_page
	page.select_upgrade("radius")
	await frames()
	check(not page.cards.radius.button.disabled, "Available upgrade is purchasable")
	await snapshot("upgrade.png")
	var cost := GameState.upgrade_cost("radius")
	var old_gold := GameState.gold
	await click(page.cards.radius.button)
	check(GameState.upgrade_level("radius") == 1 and GameState.slap_radius() > initial_radius, "Purchase works through the decorated button")
	check(is_equal_approx(GameState.gold, old_gold - cost), "Actual purchase deducts its exact cost")
	check(page._receipt.text.contains("已升级"), "Successful purchase shows its receipt")
	GameState.gold = 0.0
	main._home.refresh()
	var before_radius := GameState.slap_radius()
	await click(page.cards.radius.button)
	check(GameState.slap_radius() == before_radius, "Disabled visual state prevents a second purchase")
	await snapshot("upgrade-unaffordable.png")
	var return_button := main._home.find_child("ReturnToMain", true, false) as Button
	await click(return_button)
	check(not main._home.visible, "Return button still works through the new paper frame")
	await click(main._btn_pool)
	check(main._pool.visible, "Pool toggle works through the new footer")
	check(GameState.round_slaps == initial_slaps, "Footer click never slaps a card")
	await click(main._btn_pool)
	await click(main._minimap.toggle_button)
	check(not main._minimap.expanded, "Decorated minimap still collapses")
	await snapshot("folded.png")
	await click(main._minimap.toggle_button)
	check(main._minimap.expanded, "Decorated minimap still expands")
	print("[UI interaction v2.5] checks=%d failures=%d actual_gui=%s" % [checks, failures, str(_gpu)])
	get_tree().quit(1 if failures > 0 else 0)
