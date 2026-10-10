extends Node
## 全城探索整合：不遮挡散牌、边缘平移、真实小地图和720像素高度。
## Godot --headless --path . tests/CityExplorationTest.tscn -- --test-profile
const Story = preload("res://scripts/story_book.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	for i in range(6):
		await get_tree().process_frame

func fixture() -> void:
	GameState.set_process(false)
	GameState.new_game()
	GameState.stop_automation(false)
	GameState.narrative_paused = false
	GameState.carry.clear()
	GameState.up["crit"] = 0
	GameState.story_seen.clear()
	for event in Story.events():
		GameState.story_seen.append(str(event.id))

func approximate_rect(a: Rect2, b: Rect2, tolerance: float = 0.02) -> bool:
	return a.position.distance_to(b.position) <= tolerance and a.size.distance_to(b.size) <= tolerance

func world_view(main) -> Rect2:
	var top_left: Vector2 = main._screen_to_world(Vector2.ZERO)
	var bottom_right: Vector2 = main._screen_to_world(main._table.size)
	return Rect2(top_left, bottom_right - top_left)

func card_bounds(card: Dictionary) -> Rect2:
	var half: Vector2 = card.size * 0.5
	var rot := float(card.rot)
	var extent := Vector2(absf(cos(rot)) * half.x + absf(sin(rot)) * half.y,
		absf(sin(rot)) * half.x + absf(cos(rot)) * half.y)
	var center: Vector2 = card.rest_pos + half
	return Rect2(center - extent, extent * 2.0)

func centres(main) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for card in main._cards:
		points.append(card.rest_pos + card.size * 0.5)
	return points

func contains_point(points: Array, expected: Vector2) -> bool:
	for point in points:
		if point.distance_to(expected) < 0.02:
			return true
	return false

func map_matches_scene(main, label: String) -> void:
	var mini = main._minimap
	var world_size: Vector2 = main._world_size
	var expected: Rect2 = world_view(main).intersection(Rect2(Vector2.ZERO, world_size))
	check(mini.world_size.is_equal_approx(world_size), label + "小地图和真实城池尺寸相同")
	check(approximate_rect(mini.view_rect.intersection(Rect2(Vector2.ZERO, world_size)), expected), label + "小地图视口矩形来自实际摄像机")
	var expected_points: Array[Vector2] = []
	for i in range(main._cards.size()):
		if float(GameState.battle[i].hp) > 0.0:
			expected_points.append(main._cards[i].rest_pos + main._cards[i].size * 0.5)
	check(mini.card_positions.size() == expected_points.size(), label + "小地图包含每张存活牌且不添假点")
	var all_present := true
	for point in expected_points:
		all_present = all_present and contains_point(mini.card_positions, point)
	check(all_present, label + "每个小地图红点对应一张实际城牌")
	var view_in_map: Rect2 = Rect2(mini.world_to_minimap(expected.position),
		mini.world_to_minimap(expected.end) - mini.world_to_minimap(expected.position))
	var visible_count := 0
	var mapped_count := 0
	for point in expected_points:
		if expected.has_point(point): visible_count += 1
		if view_in_map.has_point(mini.world_to_minimap(point)): mapped_count += 1
	check(visible_count == mapped_count, label + "视口框内红点与当前可见牌对应")
	for point in [Vector2.ZERO, world_size * 0.5, world_size]:
		check(mini.minimap_to_world(mini.world_to_minimap(point)).distance_to(point) < 0.02, label + "地图世界坐标可以往返")

func mouse_click(main, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	main._on_table_input(event)
	event.pressed = false
	main._on_table_input(event)

func place_guard_card(main, point: Vector2) -> void:
	# 将可击中的真牌移到UI下面，确认阻挡输入并非因为那里没有牌。
	var card: Dictionary = main._cards[0]
	var center: Vector2 = main._screen_to_world(point)
	card.rest_pos = center - card.size * 0.5
	card.node.position = card.rest_pos
	card.dead = false
	card.node.visible = true
	GameState.battle[0].hp = 10000.0
	GameState.battle[0].hp_max = 10000.0

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "全城探索测试隔离正式存档")
	fixture()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	main.set_process(false)
	await _test_distribution(main)
	await _test_camera_and_map(main)
	await _test_edge_pan(main)
	await _test_minimap_input(main)
	await _test_compact_window(main)
	main.queue_free()
	await frames()
	print("[City exploration] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_distribution(main) -> void:
	check(main._world_size.x > 1280 and main._world_size.y > 800, "城池世界确实大于整个游戏屏幕")
	var largest := 0
	for region in GameData.regions:
		var idx := int(region.idx)
		for other in GameData.regions:
			GameState.region_state[int(other.idx)] = "cleared" if int(other.idx) != idx else "available"
		GameState.table_wins[idx] = 0
		check(GameState.start_battle(idx), "城池%d完整牌堆可开启" % idx)
		main._close_home()
		GameState.narrative_paused = false
		await frames()
		var world_size: Vector2 = main._world_size
		largest = maxi(largest, main._cards.size())
		check(main._cards.size() == GameState.battle.size(), "城池%d实际铺出所有剩余牌" % idx)
		var bounds: Array[Rect2] = []
		var enclosed := true
		var spread := Rect2()
		for i in range(main._cards.size()):
			var bound: Rect2 = card_bounds(main._cards[i])
			bounds.append(bound)
			enclosed = enclosed and Rect2(Vector2.ZERO, world_size).grow(0.01).encloses(bound)
			spread = bound if i == 0 else spread.merge(bound)
		check(enclosed, "城池%d每张旋转牌完整位于城内" % idx)
		var overlap_pair := ""
		for i in range(bounds.size()):
			for j in range(i + 1, bounds.size()):
				if bounds[i].intersects(bounds[j]):
					overlap_pair = "%d/%d" % [i, j]
					break
			if overlap_pair != "": break
		check(overlap_pair == "", "城池%d旋转牌的外框两两不遮挡%s" % [idx, overlap_pair])
		check(spread.size.x > world_size.x * 0.50 and spread.size.y > world_size.y * 0.45, "城池%d牌散布到多个城区，没有又堆在中央" % idx)
	check(largest >= 180, "不重叠检查覆盖后期至少180张牌的城池")
	var before: Array[Vector2] = centres(main)
	var before_rot: Array[float] = []
	for card in main._cards: before_rot.append(float(card.rot))
	GameState.retreat()
	check(GameState.start_battle(21), "未拍牌的同城再次开轮")
	main._close_home()
	GameState.narrative_paused = false
	await frames()
	check(centres(main) == before, "同城重复开轮保持确定的散牌位置")
	var same_rotation: bool = before_rot.size() == main._cards.size()
	for i in range(main._cards.size()):
		same_rotation = same_rotation and is_equal_approx(before_rot[i], float(main._cards[i].rot))
	check(same_rotation, "同城重新开轮不会随机产生旋转交叠")

func reset_first_city(main) -> void:
	fixture()
	main._close_home()
	main._reset_camera()
	main._focus_starting_district()
	GameState.narrative_paused = false

func _test_camera_and_map(main) -> void:
	reset_first_city(main)
	await frames()
	var anchor: Vector2 = main._table.size * 0.5
	var world_anchor: Vector2 = main._screen_to_world(anchor)
	var initial_view: Rect2 = world_view(main)
	check(initial_view.size.x < main._world_size.x and initial_view.size.y < main._world_size.y, "默认镜头只看部分城池，需要探索屏幕外区域")
	var outside := 0
	for point in centres(main):
		if not initial_view.has_point(point): outside += 1
	check(outside > 0, "开局确有牌位于屏幕之外")
	map_matches_scene(main, "默认")
	var gold: float = GameState.gold
	var slaps: int = GameState.round_slaps
	var radius: float = GameState.slap_radius()
	var previous_zoom: float = main._camera_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = anchor
	wheel.pressed = true
	main._on_table_input(wheel)
	await frames()
	check(main._camera_zoom > previous_zoom, "真实滚轮输入放大城池镜头")
	check(main._world_to_screen(world_anchor).distance_to(anchor) < 0.02, "滚轮放大保持鼠标下的世界点")
	check(GameState.gold == gold and GameState.round_slaps == slaps, "滚轮缩放不拍牌不发金币")
	check(is_equal_approx(GameState.slap_radius(), radius), "缩放镜头不偷偷升级实际命中半径")
	var enlarged_view: Rect2 = world_view(main)
	check(enlarged_view.size.x < initial_view.size.x and enlarged_view.size.y < initial_view.size.y, "放大后实际视野和地图视口框缩小")
	map_matches_scene(main, "放大后")
	main._camera_pan = Vector2(-90, -60)
	main._apply_camera()
	await frames()
	check(world_view(main).position.distance_to(enlarged_view.position) > 1.0, "移动镜头实际显示另一片世界区域")
	map_matches_scene(main, "平移后")
	for pan in [Vector2(100000, 100000), Vector2(-100000, -100000)]:
		main._camera_pan = pan
		main._apply_camera()
		var clamped: Rect2 = world_view(main)
		check(clamped.position.x >= -0.02 and clamped.position.y >= -0.02 and clamped.end.x <= main._world_size.x + 0.02 and clamped.end.y <= main._world_size.y + 0.02, "镜头平移到极限也不越出城池")
	main._reset_camera()
	await frames()
	var world_center: Vector2 = main._world_size * 0.5
	check(is_equal_approx(main._camera_zoom, 1.0) and main._world_to_screen(world_center).distance_to(anchor) < 0.02, "归中恢复全城视野和真实世界中心")
	map_matches_scene(main, "全城归中后")

func _test_edge_pan(main) -> void:
	reset_first_city(main)
	await frames()
	# 四向位移检查从可自由平移的城中心开始，不把合法边界夹取误判成失效。
	main._navigate_minimap(main._world_size * 0.5)
	var area: Vector2 = main._table.size
	var gold: float = GameState.gold
	var slaps: int = GameState.round_slaps
	var before: Rect2 = world_view(main)
	main._advance_edge_pan(0.35, Vector2(4, area.y * 0.5))
	check(world_view(main).position.x < before.position.x - 1.0, "不按鼠标键，靠近左边缘会自动看向西城区")
	before = world_view(main)
	main._advance_edge_pan(0.35, Vector2(area.x - 4, area.y * 0.5))
	check(world_view(main).position.x > before.position.x + 1.0, "靠近右边缘会自动看向东城区")
	before = world_view(main)
	main._advance_edge_pan(0.35, Vector2(area.x * 0.5, 4))
	check(world_view(main).position.y < before.position.y - 1.0, "靠近上边缘会自动看向北城区")
	before = world_view(main)
	main._advance_edge_pan(0.35, Vector2(area.x * 0.5, area.y - 4))
	check(world_view(main).position.y > before.position.y + 1.0, "靠近下边缘会自动看向南城区")
	before = world_view(main)
	main._advance_edge_pan(0.5, area * 0.5)
	check(approximate_rect(world_view(main), before), "鼠标回到画面中央后停止平移")
	main._advance_edge_pan(0.5, Vector2(-4, area.y * 0.5))
	check(approximate_rect(world_view(main), before), "鼠标离开游玩视口后停止平移")
	var mini_point: Vector2 = main._minimap.position + Vector2(main._minimap.size.x - 4, 8)
	check(main._over_camera_ui(mini_point), "边缘附近小地图区域被识别为UI")
	main._advance_edge_pan(0.5, mini_point)
	check(approximate_rect(world_view(main), before), "鼠标停在小地图上不会带走镜头")
	var tool_point: Vector2 = main._camera_toolbar.position + Vector2(main._camera_toolbar.size.x - 4, main._camera_toolbar.size.y * 0.5)
	check(main._over_camera_ui(tool_point), "边缘附近缩放控制被识别为UI")
	main._advance_edge_pan(0.5, tool_point)
	check(approximate_rect(world_view(main), before), "操作缩放按钮时停止边缘平移")
	main._open_home()
	main._advance_edge_pan(0.5, Vector2(4, area.y * 0.5))
	check(approximate_rect(world_view(main), before), "整备刚打开的同一帧也不平移镜头")
	main._close_home()
	GameState.narrative_paused = false
	main._cursor_preview = Vector2(area.x - 4, area.y * 0.5)
	main._window_focused = false
	main._process(0.2)
	check(approximate_rect(world_view(main), before), "游戏失去窗口焦点后不继续边缘平移")
	main._window_focused = true
	main._process(0.2)
	check(world_view(main).position.x > before.position.x + 1.0, "真实主场景process连接鼠标边缘平移")
	main._cursor_preview = Vector2(-1, -1)
	check(GameState.gold == gold and GameState.round_slaps == slaps, "探索平移不拍卡、不产生金币")
	map_matches_scene(main, "边缘探索后")

func _test_minimap_input(main) -> void:
	var mini = main._minimap
	var snapshot: Rect2 = world_view(main)
	var gold: float = GameState.gold
	var slaps: int = GameState.round_slaps
	check(mini.expanded and mini.toggle_button != null, "默认展开真实小地图并有收起按钮")
	mini.toggle_button.pressed.emit()
	await frames()
	check(not mini.expanded and mini.size.x < 100 and mini.size.y < 40, "收起按钮实际折成小入口")
	check(approximate_rect(world_view(main), snapshot), "收起小地图不移动或缩放摄像机")
	var collapsed_point: Vector2 = mini.position + mini.size * 0.5
	place_guard_card(main, collapsed_point)
	check(main._area_targets(main._screen_to_world(collapsed_point), GameState.slap_radius()).has(0), "收起入口后有可命中牌作为输入阻挡对照")
	mouse_click(main, collapsed_point)
	check(GameState.gold == gold and GameState.round_slaps == slaps, "收起的小地图入口不穿透拍牌")
	mini.toggle_button.pressed.emit()
	await frames()
	check(mini.expanded and mini.map_area.has_area(), "入口按钮实际重新展开地图")
	check(approximate_rect(world_view(main), snapshot), "展开小地图仍保留原来的镜头位置")
	var map_point: Vector2 = mini.position + mini.map_area.get_center()
	place_guard_card(main, map_point)
	mouse_click(main, map_point)
	check(GameState.gold == gold and GameState.round_slaps == slaps and is_zero_approx(GameState.slap_cooldown_left), "点击地图的真牌点也不穿透发钱或占冷却")
	var destination: Vector2 = main._world_size * 0.5 + Vector2(100, 70)
	var navigation := InputEventMouseButton.new()
	navigation.button_index = MOUSE_BUTTON_LEFT
	navigation.position = mini.world_to_minimap(destination)
	navigation.pressed = true
	mini._gui_input(navigation)
	navigation.pressed = false
	mini._gui_input(navigation)
	check(world_view(main).get_center().distance_to(destination) < 0.02, "实际点击地图按真实世界点移动摄像机")
	check(GameState.gold == gold and GameState.round_slaps == slaps, "地图导航也不拍牌发钱")
	map_matches_scene(main, "小地图导航后")
	reset_first_city(main)
	await frames()
	var killed_center: Vector2 = main._cards[0].rest_pos + main._cards[0].size * 0.5
	var before: int = mini.card_positions.size()
	GameState.up.power = 90
	check(GameState.attack(0), "小地图存活点验证实际翻掉一张牌")
	main._cursor_preview = main._table.size * 0.5
	main._process(0.06)
	await frames()
	check(mini.card_positions.size() == before - 1 and not contains_point(mini.card_positions, killed_center), "翻牌后真实小地图删除该牌点")
	main._cursor_preview = Vector2(-1, -1)

func _test_compact_window(main) -> void:
	reset_first_city(main)
	main.size = Vector2(1280, 720)
	await frames()
	var table_rect: Rect2 = Rect2(Vector2.ZERO, main._table.size)
	check(table_rect.encloses(main._minimap.get_rect()), "720高度小地图完整落在游玩视口内")
	check(table_rect.encloses(main._camera_toolbar.get_rect()), "720高度缩放按钮完整可见")
	check(main._minimap.position.x >= main._table.size.x * 0.5 and main._minimap.position.y < main._table.size.y * 0.5, "小地图停留在批准的右上角位置")
	check(not main._minimap.get_rect().intersects(main._camera_toolbar.get_rect()), "小地图和缩放控制互不遮挡")
	map_matches_scene(main, "720高度")
