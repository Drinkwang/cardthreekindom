extends Node

var checks := 0
var failures := 0
var output := ""
var main

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 4) -> void:
	for frame in range(count): await get_tree().process_frame

func snapshot(filename: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(filename)) == OK, "保存原生界面 " + filename)

func local_point(global_point: Vector2) -> Vector2:
	return main._table.get_global_transform().affine_inverse() * global_point

func mouse_button(point: Vector2, button: MouseButton, down: bool, mask: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.button_mask = mask
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func mouse_motion(point: Vector2, delta: Vector2 = Vector2.ZERO, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = delta
	event.button_mask = mask
	get_viewport().push_input(event, true)

func space_key(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = down
	get_viewport().push_input(event, true)

func click(point: Vector2) -> void:
	mouse_motion(point)
	mouse_button(point, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	mouse_button(point, MOUSE_BUTTON_LEFT, false)
	await frames()

func combat_state() -> Dictionary:
	return {"gold": GameState.gold, "slaps": GameState.round_slaps, "damage": GameState.run_damage,
		"hp": GameState.battle.map(func(enemy): return float(enemy.hp)), "runs": GameState.runs}

func unchanged(before: Dictionary, message: String) -> void:
	check(combat_state() == before and GameState.in_battle and GameState.round_active, message)

func center_camera() -> void:
	main._camera_pan = Vector2.ZERO
	main._apply_camera()

func camera_button(text: String) -> Button:
	for button in main._camera_toolbar.find_children("*", "Button", true, false):
		if button.text == text: return button
	return null

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "RTS镜头测试必须使用 --test-profile 隔离存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): output = argument.substr(10)
	GameState.set_process(false)
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		GameState.new_game()
		GameState.narrative_paused = false
		main = load("res://scenes/Main.tscn").instantiate()
		add_child(main)
		await frames(8)
		main.set_process(false)
		main._window_focused = true
		var initial_zone := GameState.next_zone(GameState.battle_region)
		var initial_target: Vector2 = GameState.zone_rect(GameState.battle_region, initial_zone).get_center()
		check(main._viewport_world_rect().has_point(initial_target), "%d高度初次布局的默认视野包含首个未清分区中心" % height)
		var table_size: Vector2 = main._table.size
		main._table.size.y = 238
		main._table.size = table_size
		check(main._viewport_world_rect().get_center().distance_to(initial_target) <= 1.0, "%d高度临时小视口夹取后仍恢复目标焦点" % height)
		await test_edges(height)
		await test_window_exit(height)
		test_edge_drag_guard(height)
		await test_ui_and_zoom(height)
		await test_dragging(height)
		await test_cancellation(height)
		await test_left_click(height)
		main.queue_free()
		await frames()
	print("[RTS camera] checks=%d failures=%d actual_gui=%s" % [checks, failures, str(DisplayServer.get_name() != "headless")])
	get_tree().quit(1 if failures > 0 else 0)

func test_edges(height: int) -> void:
	var window: Rect2 = main.get_global_rect()
	var center := window.get_center()
	var entries := [
		["左", Vector2(window.position.x + 2, center.y), Vector2.LEFT],
		["右", Vector2(window.end.x - 2, center.y), Vector2.RIGHT],
		["上", Vector2(center.x, window.position.y + 2), Vector2.UP],
		["下", Vector2(center.x, window.end.y - 2), Vector2.DOWN],
		["上阵条下", Vector2(main._slot_row.get_global_rect().get_center().x, window.end.y - 2), Vector2.DOWN],
		["小地图下", Vector2(main._minimap.get_global_rect().get_center().x, window.end.y - 2), Vector2.DOWN]]
	var before := combat_state()
	for entry in entries:
		center_camera()
		var pointer: Vector2 = entry[1]
		mouse_motion(pointer)
		var direction: Vector2 = main._edge_direction(pointer)
		check(not direction.is_zero_approx(), "%d高度窗口%s边缘可导航" % [height, entry[0]])
		if entry[0] in ["上", "下"]:
			check(not main._table.get_global_rect().has_point(pointer), "%d高度%s滚屏在地图之外的HUD边沿触发" % [height, entry[0]])
		var focus: Vector2 = main._viewport_world_rect().get_center()
		main._advance_edge_pan(0.04, local_point(pointer))
		var movement: Vector2 = main._viewport_world_rect().get_center() - focus
		check(movement.dot(entry[2]) > 1.0, "%d高度窗口%s边缘立即按正确方向滚屏" % [height, entry[0]])
		check(main._edge_hint != null and main._edge_hint.visible, "%d高度%s边滚屏显示方向提示" % [height, entry[0]])
		check(main._table.get_global_rect().encloses(main._edge_hint.get_global_rect()) and not main._camera_toolbar.get_global_rect().intersects(main._edge_hint.get_global_rect()), "%d高度%s边方向提示不覆盖上下HUD或缩放按钮" % [height, entry[0]])
		if entry[0] == "上": await snapshot("rts-camera-arrow-%d.png" % height)
		var stopped: Vector2 = main._camera_pan
		main._advance_edge_pan(0.04, local_point(center))
		main._advance_edge_pan(0.3, local_point(center))
		check(main._camera_pan.is_equal_approx(stopped), "%d高度离开%s边缘立即停止，没有惯性" % [height, entry[0]])
		check(not main._edge_hint.visible, "%d高度离开%s边缘隐藏方向提示" % [height, entry[0]])
	center_camera()
	var outside := Vector2(window.position.x - 2, center.y)
	mouse_motion(outside)
	check(main._edge_direction(outside).is_zero_approx(), "%d高度窗口外不继续导航" % height)
	var pan: Vector2 = main._camera_pan
	main._advance_edge_pan(0.3, local_point(outside))
	check(main._camera_pan.is_equal_approx(pan), "%d高度移出窗口不滚屏" % height)
	unchanged(before, "%d高度四向镜头导航不拍牌、不发钱、不结束战斗" % height)
	await snapshot("rts-camera-edges-%d.png" % height)

func test_window_exit(height: int) -> void:
	center_camera()
	var before := combat_state()
	var edge := Vector2(main.get_global_rect().end.x - 2, main._table.get_global_rect().get_center().y)
	mouse_motion(edge)
	main._advance_edge_pan(0.04, local_point(edge))
	check(main._mouse_in_window and main._edge_hint.visible, "%d高度离窗前边缘缓存确实处于导航状态" % height)
	get_window().mouse_exited.emit()
	var stopped: Vector2 = main._camera_pan
	main._advance_edge_pan(0.04, local_point(edge))
	main._process(0.04)
	check(not main._mouse_in_window and main._camera_pan.is_equal_approx(stopped) and not main._edge_hint.visible, "%d高度窗口mouse_exited后缓存边缘不再滚屏" % height)
	mouse_motion(main._table.get_global_rect().get_center())
	mouse_motion(edge)
	main._advance_edge_pan(0.04, local_point(edge))
	check(main._mouse_in_window and main._camera_pan.distance_to(stopped) > 1.0, "%d高度鼠标重新进入后恢复边缘导航" % height)
	main._advance_edge_pan(0.04, main._table.size * 0.5)
	unchanged(before, "%d高度离窗及恢复不拍牌、不发钱、不结束本轮" % height)
	await frames()

func test_edge_drag_guard(height: int) -> void:
	center_camera()
	var before := combat_state()
	var edge := Vector2(main.get_global_rect().position.x + 2, main._table.get_global_rect().get_center().y)
	check(main._table.get_global_rect().has_point(edge), "%d高度中键防绕过检查使用地图内的窗口滚屏外圈" % height)
	mouse_motion(edge)
	mouse_button(edge, MOUSE_BUTTON_MIDDLE, true, MOUSE_BUTTON_MASK_MIDDLE)
	check(not main._panning, "%d高度窗口滚屏外圈的中键事件不能通过GUI回落启动拖图" % height)
	mouse_button(edge, MOUSE_BUTTON_MIDDLE, false)
	var legacy_event := InputEventMouseButton.new()
	legacy_event.button_index = MOUSE_BUTTON_MIDDLE
	legacy_event.position = local_point(edge)
	legacy_event.pressed = true
	legacy_event.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	main._on_table_input(legacy_event)
	check(not main._panning, "%d高度旧_on_table_input入口也不能绕过16像素边缘启动拖图" % height)
	mouse_button(edge, MOUSE_BUTTON_MIDDLE, false)
	unchanged(before, "%d高度边缘中键拒绝不造成战斗副作用" % height)

func test_ui_and_zoom(height: int) -> void:
	var before := combat_state()
	var safe_area: Rect2 = main.get_global_rect().grow(-16)
	var footer_safe := Rect2(safe_area.position, safe_area.size + Vector2(0, 8))
	for control in [main._btn_retreat, main._minimap, main._slot_row.get_child(0)]:
		var bounds: Rect2 = footer_safe if main._bar.is_ancestor_of(control) else safe_area
		check(bounds.encloses(control.get_global_rect()), "%d高度交互控件%s位于顶部或居中底栏安全区内" % [height, control.name])
		var pointer: Vector2 = control.get_global_rect().get_center()
		check(main._edge_direction(pointer).is_zero_approx(), "%d高度悬停%s不导航" % [height, control.name])
	center_camera()
	var plus := camera_button("+")
	var minus := camera_button("−")
	var reset := camera_button("回目标区")
	check(plus != null and minus != null and reset != null, "%d高度缩放工具包含加减与回目标区按钮" % height)
	if plus != null:
		var pointer := plus.get_global_rect().get_center()
		mouse_motion(pointer)
		main._update_slap_cursor(local_point(pointer))
		var zoom: float = main._camera_zoom
		mouse_button(pointer, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
		mouse_button(pointer, MOUSE_BUTTON_LEFT, false)
		check(main._camera_zoom > zoom, "%d高度真实点击加号只放大镜头" % height)
		check(not main._slap_cursor.visible and not main._cursor_hidden and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%d高度点击加号同一帧不把拍击圈跳到地图中心" % height)
		await frames()
	if minus != null:
		await click(minus.get_global_rect().get_center())
	await click(main._minimap.global_position + main._minimap.world_to_minimap(main._world_size * 0.5))
	var minimap_point: Vector2 = main._minimap.global_position + main._minimap.world_to_minimap(main._world_size * 0.5)
	mouse_motion(minimap_point)
	mouse_button(minimap_point, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	check(main._minimap._dragging, "%d高度真实按下小地图进入拖图" % height)
	var minimap_edge := Vector2(main.get_global_rect().end.x - 2, main._table.get_global_rect().get_center().y)
	mouse_motion(minimap_edge, minimap_edge - minimap_point, MOUSE_BUTTON_MASK_LEFT)
	var minimap_pan: Vector2 = main._camera_pan
	main._advance_edge_pan(0.04, local_point(minimap_edge))
	check(main._camera_pan.is_equal_approx(minimap_pan), "%d高度小地图拖动优先于窗口边缘滚屏" % height)
	mouse_button(minimap_edge, MOUSE_BUTTON_LEFT, false)
	check(not main._minimap._dragging, "%d高度小地图在图外松手不残留拖动" % height)
	await click(main._slot_row.get_child(0).get_global_rect().get_center())
	unchanged(before, "%d高度缩放、小地图和只读上阵点击不拍牌、不发钱、不打断本轮" % height)
	center_camera()
	var anchor: Vector2 = main._table.size * 0.5 + Vector2(52, 24)
	var global_anchor: Vector2 = main._table.get_global_transform() * anchor
	var world_anchor: Vector2 = main._screen_to_world(anchor)
	var zoom_before: float = main._camera_zoom
	mouse_motion(global_anchor)
	mouse_button(global_anchor, MOUSE_BUTTON_WHEEL_UP, true)
	mouse_button(global_anchor, MOUSE_BUTTON_WHEEL_UP, false)
	check(main._camera_zoom > zoom_before, "%d高度真实滚轮事件放大镜头" % height)
	check(main._world_to_screen(world_anchor).distance_to(anchor) <= 1.0, "%d高度非边界滚轮缩放的鼠标世界锚点误差不超过1像素" % height)
	var pointer: Vector2 = main.get_global_rect().get_center()
	pointer.x = main.get_global_rect().end.x - 2
	var panned: Vector2 = main._camera_pan
	main._advance_edge_pan(0.016, local_point(pointer))
	check(main._camera_pan.is_equal_approx(panned), "%d高度缩放手势优先于同帧边缘滚屏" % height)
	if reset != null:
		await click(reset.get_global_rect().get_center())
		check(is_equal_approx(main._camera_zoom, main.DEFAULT_ZOOM), "%d高度回目标区恢复默认倍率" % height)
		var zone := GameState.next_zone(GameState.battle_region)
		var target: Vector2 = GameState.zone_rect(GameState.battle_region, zone).get_center()
		check(main._viewport_world_rect().has_point(target), "%d高度回目标区能看到当前未清分区" % height)
	unchanged(before, "%d高度全部缩放操作保持战斗资产与拍击次数不变" % height)

func test_dragging(height: int) -> void:
	var before := combat_state()
	for kind in ["中键", "空格左键"]:
		center_camera()
		var origin: Vector2 = main._table.get_global_rect().get_center()
		var destination := Vector2(origin.x + 70, main._table.global_position.y - 20)
		var button := MOUSE_BUTTON_MIDDLE if kind == "中键" else MOUSE_BUTTON_LEFT
		var mask := MOUSE_BUTTON_MASK_MIDDLE if kind == "中键" else MOUSE_BUTTON_MASK_LEFT
		if kind == "空格左键": space_key(true)
		mouse_motion(origin)
		mouse_button(origin, button, true, mask)
		check(main._panning, "%d高度%s从地图启动拖图" % [height, kind])
		var drag_zoom: float = main._camera_zoom
		mouse_button(origin, MOUSE_BUTTON_WHEEL_UP, true, mask)
		mouse_button(origin, MOUSE_BUTTON_WHEEL_UP, false, mask)
		check(main._panning and is_equal_approx(main._camera_zoom, drag_zoom), "%d高度%s拖图优先于滚轮缩放" % [height, kind])
		var pan: Vector2 = main._camera_pan
		mouse_motion(destination, destination - origin, mask)
		check(not main._table.get_global_rect().has_point(destination), "%d高度%s拖图测试点确实进入顶部HUD" % [height, kind])
		check(main._panning and main._camera_pan.distance_to(pan) > 1.0, "%d高度%s跨HUD保持捕获并继续移动镜头" % [height, kind])
		var hud_point: Vector2 = main._btn_retreat.get_global_rect().get_center()
		mouse_motion(hud_point, hud_point - destination, mask)
		destination = hud_point
		if kind == "中键":
			mouse_button(destination, MOUSE_BUTTON_LEFT, true, mask | MOUSE_BUTTON_MASK_LEFT)
			mouse_button(destination, MOUSE_BUTTON_LEFT, false, mask)
			check(main._panning and GameState.in_battle and not main._home.visible, "%d高度中键拖图中点击HUD休息按钮不会触发按钮" % height)
		var dragged: Vector2 = main._camera_pan
		main._advance_edge_pan(0.04, local_point(Vector2(2, origin.y)))
		check(main._camera_pan.is_equal_approx(dragged), "%d高度%s拖图优先于边缘滚屏" % [height, kind])
		mouse_button(destination, button, false)
		if kind == "空格左键": space_key(false)
		check(not main._panning, "%d高度%s在HUD松开即结束拖图" % [height, kind])
		check(GameState.in_battle and not main._home.visible, "%d高度%s在休息按钮上松开不误触结束本轮" % [height, kind])
		var stopped: Vector2 = main._camera_pan
		mouse_motion(origin, origin - destination)
		main._advance_edge_pan(0.3, local_point(origin))
		check(main._camera_pan.is_equal_approx(stopped), "%d高度%s结束后无拖尾或惯性" % [height, kind])
		unchanged(before, "%d高度%s拖图全程不拍牌、不发钱、不打断战斗" % [height, kind])
	await snapshot("rts-camera-drag-%d.png" % height)

func test_cancellation(height: int) -> void:
	var before := combat_state()
	var origin: Vector2 = main._table.get_global_rect().get_center()
	mouse_motion(origin)
	mouse_button(origin, MOUSE_BUTTON_MIDDLE, true, MOUSE_BUTTON_MASK_MIDDLE)
	check(main._panning, "%d高度失焦检查前真实启动拖图" % height)
	main._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not main._panning, "%d高度窗口失焦立即取消拖图" % height)
	var pan: Vector2 = main._camera_pan
	mouse_motion(origin + Vector2(40, 30), Vector2(40, 30), MOUSE_BUTTON_MASK_MIDDLE)
	main._advance_edge_pan(0.04, local_point(Vector2(2, origin.y)))
	check(main._camera_pan.is_equal_approx(pan), "%d高度失焦后鼠标移动与边缘均不带动镜头" % height)
	mouse_button(origin, MOUSE_BUTTON_MIDDLE, false)
	main._notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	mouse_motion(origin)
	mouse_button(origin, MOUSE_BUTTON_MIDDLE, true, MOUSE_BUTTON_MASK_MIDDLE)
	check(main._panning, "%d高度覆盖页检查前可重新开始拖图" % height)
	main._home.visible = true
	main._process(0.016)
	check(not main._panning and not main._edge_hint.visible, "%d高度覆盖页出现立即取消拖图与边移提示" % height)
	pan = main._camera_pan
	mouse_motion(origin + Vector2(30, 20), Vector2(30, 20), MOUSE_BUTTON_MASK_MIDDLE)
	main._advance_edge_pan(0.04, local_point(Vector2(2, origin.y)))
	check(main._camera_pan.is_equal_approx(pan), "%d高度覆盖页中移动及贴边不改变镜头" % height)
	mouse_button(origin, MOUSE_BUTTON_MIDDLE, false)
	main._home.visible = false
	GameState.narrative_paused = false
	main._process(0.0)
	unchanged(before, "%d高度取消拖图不产生拍牌收益或结束本轮" % height)

func test_left_click(height: int) -> void:
	main._navigate_minimap(GameState.get_enemy_world_center(0))
	var pointer: Vector2 = main._table.get_global_transform() * main._world_to_screen(GameState.get_enemy_world_center(0))
	var pan: Vector2 = main._camera_pan
	var slaps := GameState.round_slaps
	GameState.slap_cooldown_left = 0.0
	await click(pointer)
	check(GameState.round_slaps == slaps + 1, "%d高度普通左键仍真实拍牌一次" % height)
	check(main._camera_pan.is_equal_approx(pan) and not main._panning, "%d高度普通左键不启动拖图或平移镜头" % height)
