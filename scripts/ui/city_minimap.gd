extends Control
## 城池总览的坐标始终来自世界坐标，缩放、平移不会改变卡牌红点的位置。
const Art = preload("res://scripts/ui/print_art.gd")
const EXPANDED_SIZE := Vector2(220, 185)
const COLLAPSED_SIZE := Vector2(86, 34)
const VIEW_INK := Color("21665b")

signal navigate_requested(world_point: Vector2)
signal expanded_changed(is_expanded: bool)

var expanded := true
var world_size := Vector2.ONE
var view_rect := Rect2()
var card_positions: Array[Vector2] = []
var map_area := Rect2()
var toggle_button: Button
var _title: Label
var _texture: Texture2D
var _paper: StyleBox
var _dragging := false
var _city_title := ""
var _header_hovered := false
var _toggle_chrome: Control


func _ready() -> void:
	theme = Art.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	var paper := Art.panel(Color("f6e9c9"), 8, Art.INK, 2)
	paper.shadow_color = Color("2b211a", 0.32)
	paper.shadow_size = 6
	paper.shadow_offset = Vector2(2, 4)
	_paper = paper
	_title = Art.label(_title_text(), 16)
	_title.name = "MapTitle"
	_title.clip_text = true
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_title.tooltip_text = "收起小地图（M）"
	_title.gui_input.connect(_on_title_input)
	_title.mouse_entered.connect(_set_header_hovered.bind(true))
	_title.mouse_exited.connect(_set_header_hovered.bind(false))
	_title.add_theme_font_override("font", Art.title_font())
	add_child(_title)
	toggle_button = Button.new()
	toggle_button.name = "ToggleMap"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.focus_mode = Control.FOCUS_NONE
	toggle_button.add_theme_font_size_override("font_size", 12)
	toggle_button.add_theme_color_override("font_color", Art.INK)
	toggle_button.add_theme_color_override("font_hover_color", Art.RED)
	toggle_button.add_theme_color_override("font_pressed_color", Art.PAPER_LIGHT)
	_toggle_chrome = Control.new()
	_toggle_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toggle_chrome.draw.connect(_draw_toggle_chrome)
	toggle_button.add_child(_toggle_chrome)
	toggle_button.mouse_entered.connect(_toggle_chrome.queue_redraw)
	toggle_button.mouse_exited.connect(_toggle_chrome.queue_redraw)
	toggle_button.button_down.connect(_toggle_chrome.queue_redraw)
	toggle_button.button_up.connect(_toggle_chrome.queue_redraw)
	toggle_button.pressed.connect(toggle)
	add_child(toggle_button)
	resized.connect(_layout)
	_apply_expanded()


func set_world(texture: Texture2D, extent: Vector2) -> void:
	_texture = texture
	world_size = Vector2(maxf(extent.x, 1.0), maxf(extent.y, 1.0))
	_layout()


func set_city_title(city_name: String) -> void:
	var next_title := city_name.strip_edges()
	if _city_title == next_title:
		return
	_city_title = next_title
	if _title != null:
		_title.text = _title_text()
	queue_redraw()


func _title_text() -> String:
	return "城池总览" if _city_title.is_empty() else _city_title + "全图"


func update_view(world_rect: Rect2, positions: Array[Vector2]) -> void:
	if view_rect == world_rect and card_positions == positions:
		return
	view_rect = world_rect
	card_positions.assign(positions)
	queue_redraw()


func requested_size() -> Vector2:
	return EXPANDED_SIZE if expanded else COLLAPSED_SIZE


func toggle() -> void:
	set_expanded(not expanded)


func set_expanded(value: bool) -> void:
	if expanded == value:
		return
	expanded = value
	_dragging = false
	_apply_expanded()
	expanded_changed.emit(expanded)


func _apply_expanded() -> void:
	custom_minimum_size = requested_size()
	size = requested_size()
	if toggle_button != null:
		toggle_button.text = "收起 M" if expanded else "地图 M"
		toggle_button.tooltip_text = "收起小地图（M）" if expanded else "展开小地图（M）"
		_style_toggle()
		_toggle_chrome.queue_redraw()
	if _title != null:
		_title.visible = expanded
	_layout()


func _layout() -> void:
	if toggle_button != null:
		toggle_button.position = Vector2(size.x - 76, 4) if expanded else Vector2.ZERO
		toggle_button.size = Vector2(72, 28) if expanded else size
	if _title != null:
		_title.position = Vector2(30, 6)
		_title.size = Vector2(maxf(0, size.x - 115), 24)
	var available := Rect2(Vector2(10, 39), Vector2(maxf(1, size.x - 20), maxf(1, size.y - 70)))
	var fit_scale := minf(available.size.x / world_size.x, available.size.y / world_size.y)
	map_area = Rect2(available.position + (available.size - world_size * fit_scale) * 0.5,
		world_size * fit_scale)
	queue_redraw()


func world_to_minimap(world_point: Vector2) -> Vector2:
	return map_area.position + world_point / world_size * map_area.size


func minimap_to_world(local_point: Vector2) -> Vector2:
	var normalized := (local_point - map_area.position) / map_area.size.max(Vector2.ONE)
	return Vector2(clampf(normalized.x, 0.0, 1.0), clampf(normalized.y, 0.0, 1.0)) * world_size


func is_pointer_over(global_point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(global_point)


func _process(_delta: float) -> void:
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		toggle()
	_title.accept_event()


func _gui_input(event: InputEvent) -> void:
	if not expanded:
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.position.y < 34.0:
				toggle()
			elif event.pressed and map_area.has_point(event.position):
				_dragging = true
				navigate_requested.emit(minimap_to_world(event.position))
			elif not event.pressed:
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			navigate_requested.emit(minimap_to_world(event.position))
		accept_event()


func _draw() -> void:
	if not expanded or size.x < 116.0 or size.y < 70.0:
		return
	if _paper != null:
		draw_style_box(_paper, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(Art.GOLD, 0.78), false, 1.0)
	draw_rect(Rect2(Vector2(7, 7), size - Vector2(14, 14)), Color(Art.RULE, 0.42), false, 1.0)
	_draw_frame_corners()
	# 题签和纸卷端头在地图外缘，留出完整点位与视野矩形。
	draw_rect(Rect2(Vector2(9, 8), Vector2(size.x - 90, 22)), Color(Art.GOLD, 0.06))
	draw_line(Vector2(10, 34), Vector2(size.x - 10, 34), Color(Art.GOLD, 0.75), 1.0)
	draw_line(Vector2(10, 35), Vector2(size.x - 10, 35), Color(Art.PAPER_LIGHT, 0.9), 1.0)
	_draw_seal(Vector2(12, 11), Vector2(13, 15), Art.RED.lightened(0.10) if _header_hovered else Art.RED)
	draw_string(Art.title_font(), Vector2(13, 23), "图", HORIZONTAL_ALIGNMENT_CENTER, 11, 11, Art.PAPER_LIGHT)
	draw_rect(Rect2(map_area.position + Vector2(2, 3), map_area.size).grow(2), Color(Art.INK, 0.20))
	draw_rect(map_area.grow(4), Color(Art.INK, 0.80), false, 1.0)
	draw_rect(map_area.grow(3), Art.GOLD, false, 1.0)
	draw_rect(map_area.grow(1), Art.INK, false, 1.0)
	draw_rect(map_area, Art.PAPER)
	if _texture != null:
		draw_texture_rect(_texture, map_area, false, Color(1, 1, 1, 0.96))
	var visible_rect := view_rect.intersection(Rect2(Vector2.ZERO, world_size))
	if visible_rect.has_area():
		var displayed := Rect2(world_to_minimap(visible_rect.position),
			visible_rect.size / world_size * map_area.size)
		draw_rect(displayed, Color(VIEW_INK, 0.10))
		draw_rect(displayed, Art.PAPER_LIGHT, false, 4.0)
		draw_rect(displayed, VIEW_INK, false, 2.0)
	for point in card_positions:
		if Rect2(Vector2.ZERO, world_size).has_point(point):
			var at := world_to_minimap(point)
			draw_circle(at + Vector2(0.7, 0.8), 3.8, Color(Art.INK, 0.42))
			draw_circle(at, 3.6, Art.PAPER_LIGHT)
			draw_circle(at, 2.6, Art.RED)
	var font := Art.body_font()
	draw_line(Vector2(10, size.y - 26), Vector2(size.x - 10, size.y - 26), Color(Art.GOLD, 0.66), 1.0)
	draw_line(Vector2(10, size.y - 25), Vector2(size.x - 10, size.y - 25), Color(Art.PAPER_LIGHT, 0.90), 1.0)
	draw_circle(Vector2(14, size.y - 14), 2.6, Art.RED)
	draw_string(font, Vector2(22, size.y - 10), "卡牌", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Art.INK)
	draw_rect(Rect2(Vector2(58, size.y - 18), Vector2(8, 8)), VIEW_INK, false, 1.5)
	draw_string(font, Vector2(72, size.y - 10), "视野", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Art.INK)
	draw_string(font, Vector2(size.x - 82, size.y - 10), "点击 / 拖动", HORIZONTAL_ALIGNMENT_RIGHT, 70, 10, Art.DIM)


func _draw_frame_corners() -> void:
	var directions: Array[Vector2] = [Vector2.ONE, Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for direction in directions:
		var corner := Vector2(6 if direction.x > 0 else size.x - 6,
			6 if direction.y > 0 else size.y - 6)
		var tint := Color(Art.GOLD, 0.92)
		draw_line(corner, corner + Vector2(7 * direction.x, 0), tint, 1.0)
		draw_line(corner, corner + Vector2(0, 7 * direction.y), tint, 1.0)
		draw_line(corner + Vector2(3 * direction.x, 3 * direction.y),
			corner + Vector2(7 * direction.x, 3 * direction.y), tint, 1.0)
		draw_line(corner + Vector2(3 * direction.x, 3 * direction.y),
			corner + Vector2(3 * direction.x, 7 * direction.y), tint, 1.0)


func _set_header_hovered(value: bool) -> void:
	if _header_hovered == value:
		return
	_header_hovered = value
	_title.add_theme_color_override("font_color", Art.RED if value else Art.INK)
	queue_redraw()


func _style_toggle() -> void:
	var normal := Art.panel(Art.PAPER_LIGHT, 5, Art.GOLD, 1)
	var hover := Art.panel(Color("fff5dd"), 5, Art.RED, 2)
	var pressed := Art.panel(Art.RED, 5, Art.INK, 1)
	for box in [normal, hover]:
		box.shadow_color = Color(Art.INK, 0.22)
		box.shadow_size = 2
		box.shadow_offset = Vector2(0, 2)
	if not expanded:
		normal.border_color = Art.INK
		normal.set_border_width_all(2)
		for box in [normal, hover, pressed]:
			box.content_margin_left = 25
			box.content_margin_right = 7
	toggle_button.add_theme_stylebox_override("normal", normal)
	toggle_button.add_theme_stylebox_override("hover", hover)
	toggle_button.add_theme_stylebox_override("pressed", pressed)
	toggle_button.alignment = HORIZONTAL_ALIGNMENT_CENTER if expanded else HORIZONTAL_ALIGNMENT_RIGHT
	toggle_button.add_theme_font_size_override("font_size", 12 if expanded else 13)


func _draw_seal(at: Vector2, extent: Vector2, tint: Color) -> void:
	draw_rect(Rect2(at, extent), tint)
	draw_rect(Rect2(at + Vector2(2, 2), extent - Vector2(4, 4)), Color(Art.PAPER_LIGHT, 0.80), false, 1.0)


func _draw_toggle_chrome() -> void:
	if expanded or _toggle_chrome == null or _toggle_chrome.size.x < 40 or _toggle_chrome.size.y < 24:
		return
	var pressed := toggle_button.is_pressed()
	var seal_tint := Art.PAPER_LIGHT if pressed else Art.RED
	var seal := Rect2(Vector2(7, 8), Vector2(15, 18))
	_toggle_chrome.draw_rect(seal, seal_tint)
	_toggle_chrome.draw_rect(seal.grow(-2), Art.RED if pressed else Art.PAPER_LIGHT, false, 1.0)
	var ink := Art.RED if pressed else Art.PAPER_LIGHT
	_toggle_chrome.draw_line(Vector2(11, 13), Vector2(18, 13), ink, 1.0)
	_toggle_chrome.draw_line(Vector2(11, 18), Vector2(18, 18), ink, 1.0)
	_toggle_chrome.draw_line(Vector2(14, 11), Vector2(14, 23), ink, 1.0)
	var outline := Art.PAPER_LIGHT if pressed else Art.GOLD
	_toggle_chrome.draw_rect(Rect2(Vector2(4, 4), _toggle_chrome.size - Vector2(8, 8)), Color(outline, 0.70), false, 1.0)
