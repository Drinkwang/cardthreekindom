extends Node

func frames(count: int = 5) -> void:
	for i in range(count):
		await get_tree().process_frame

func drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	get_viewport().push_input(down)
	await frames(2)
	for step in range(1, 21):
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(step) / 20)
		motion.global_position = motion.position
		motion.relative = (to - from) / 20
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion)
		await frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = to
	up.global_position = to
	get_viewport().push_input(up)
	await frames()

func _ready() -> void:
	GameState.new_game()
	GameState.set_process(false)
	GameState.leave_battle()
	for idx in [2, 3, 4]:
		GameState.region_state[idx] = "cleared"
	GameState.owned = {"B06": 1, "B08": 1}
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._open_city()
	await frames()
	var city = main._city
	var source: Control = city.find_child("PlaceBuildingB06", true, false)
	var target: Control = city.find_child("CitySlot5", true, false)
	await drag(source.get_global_rect().get_center(), target.get_global_rect().get_center())
	var equipped := GameState._building_at(2, 5) == "B06" and GameState.building_stock("B06") == 0
	if not equipped:
		push_error("真实鼠标拖拽未装配到第六槽")
	else:
		source = city.find_child("CitySlot5", true, false)
		target = city.find_child("CitySlot0", true, false)
		await drag(source.get_global_rect().get_center(), target.get_global_rect().get_center())
	var moved := GameState._building_at(2, 0) == "B06" and GameState._building_at(2, 5) == ""
	if not moved:
		push_error("真实鼠标拖拽未移动已装配卡")
	print("BUILDING DRAG: warehouse=%s, city_move=%s" % [equipped, moved])
	get_tree().quit(0 if equipped and moved else 1)
