extends Control
## 城池总览的坐标始终来自世界坐标，缩放、平移不会改变卡牌红点的位置。
const Art = preload("res://scripts/ui/print_art.gd")
const UISkin = preload("res://scripts/ui/ui_skin.gd")
const CityTerrainView = preload("res://scripts/ui/city_terrain_view.gd")
const MAP_SIZE := Vector2(220, 96)
const VIEW_INK := Color("21665b")

signal navigate_requested(world_point: Vector2)
signal zone_selected(zone_index: int)

var world_size := Vector2.ONE
var view_rect := Rect2()
var card_positions: Array[Vector2] = []
var zones: Array[Dictionary] = []
var events: Array = []
var map_area := Rect2()
var _terrain: Control
var _markers: Control
var _paper: StyleBox
var _dragging := false
var city_index := 1


func _ready() -> void:
	theme = Art.theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	var paper := UISkin.lacquer_panel(8, 2)
	paper.shadow_color = Color(Color.BLACK, 0.42)
	paper.shadow_size = 6
	paper.shadow_offset = Vector2(2, 4)
	_paper = paper
	UISkin.chrome(self, "lacquer")
	_terrain = CityTerrainView.new()
	_terrain.name = "TerrainArt"
	_terrain.z_index = 0
	add_child(_terrain)
	_markers = Control.new()
	_markers.name = "Markers"
	_markers.z_index = 1
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.draw.connect(_draw_markers)
	add_child(_markers)
	resized.connect(_layout)
	custom_minimum_size = MAP_SIZE
	size = MAP_SIZE
	_layout()


func set_world(_texture: Texture2D, extent: Vector2) -> void:
	world_size = Vector2(maxf(extent.x, 1.0), maxf(extent.y, 1.0))
	_layout()


func set_city_index(value: int) -> void:
	if city_index == value: return
	city_index = value
	_layout()


func update_view(world_rect: Rect2, positions: Array[Vector2]) -> void:
	if view_rect == world_rect and card_positions == positions:
		return
	view_rect = world_rect
	card_positions.assign(positions)
	if _markers != null: _markers.queue_redraw()


func set_zones(details: Array[Dictionary]) -> void:
	if zones == details: return
	zones = details.duplicate(true)
	if _markers != null: _markers.queue_redraw()


func set_events(entries: Array) -> void:
	if events == entries: return
	events = entries.duplicate(true)
	if _markers != null: _markers.queue_redraw()


func _layout() -> void:
	var available := Rect2(Vector2(10, 10), Vector2(maxf(1, size.x - 20), maxf(1, size.y - 20)))
	var fit_scale := minf(available.size.x / world_size.x, available.size.y / world_size.y)
	map_area = Rect2(available.position + (available.size - world_size * fit_scale) * 0.5,
		world_size * fit_scale)
	if _terrain != null:
		_terrain.position = map_area.position
		_terrain.size = map_area.size
		_terrain.set_terrain(world_size, city_index)
	if _markers != null:
		_markers.size = size
		_markers.queue_redraw()
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and map_area.has_point(event.position):
				_dragging = true
				var world := minimap_to_world(event.position)
				navigate_requested.emit(world)
				for zone in zones:
					var bounds: Rect2 = zone.get("rect", Rect2())
					if bounds.has_point(world):
						zone_selected.emit(int(zone["zone"]))
						break
			elif not event.pressed:
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			navigate_requested.emit(minimap_to_world(event.position))
		accept_event()


func _draw() -> void:
	if size.x < 116.0 or size.y < 70.0:
		return
	if _paper != null:
		draw_style_box(_paper, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(map_area.position + Vector2(2, 3), map_area.size).grow(2), Color(Color.BLACK, 0.30))
	draw_rect(map_area.grow(4), UISkin.LACQUER_RULE, false, 1.0)
	draw_rect(map_area.grow(3), UISkin.LACQUER_GOLD, false, 1.0)
	draw_rect(map_area.grow(1), UISkin.LACQUER, false, 1.0)
	draw_rect(map_area, Art.PAPER)


func _draw_markers() -> void:
	var visible_rect := view_rect.intersection(Rect2(Vector2.ZERO, world_size))
	if visible_rect.has_area():
		var displayed := Rect2(world_to_minimap(visible_rect.position),
			visible_rect.size / world_size * map_area.size)
		_markers.draw_rect(displayed, Color(VIEW_INK, 0.10))
		_markers.draw_rect(displayed, Art.PAPER_LIGHT, false, 4.0)
		_markers.draw_rect(displayed, VIEW_INK, false, 2.0)
	for point in card_positions:
		if Rect2(Vector2.ZERO, world_size).has_point(point):
			var at := world_to_minimap(point)
			_markers.draw_circle(at + Vector2(0.7, 0.8), 3.8, Color(Art.INK, 0.42))
			_markers.draw_circle(at, 3.6, Art.PAPER_LIGHT)
	for point in card_positions:
		if Rect2(Vector2.ZERO, world_size).has_point(point):
			_markers.draw_circle(world_to_minimap(point), 2.6, Art.RED)
	for event in events:
		if str(event.get("status", "")) in ["done", "claimed"]: continue
		var point: Vector2 = event.get("point", Vector2.ZERO)
		if not Rect2(Vector2.ZERO, world_size).has_point(point): continue
		var at := world_to_minimap(point)
		if str(event.get("kind", "")) in ["chest", "treasure"]:
			_markers.draw_rect(Rect2(at - Vector2(3.5, 3.5), Vector2(7, 7)), Color("d5a542"))
			_markers.draw_rect(Rect2(at - Vector2(3.5, 3.5), Vector2(7, 7)), Art.INK, false, 1.0)
		else:
			_markers.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -4), at + Vector2(4, 0), at + Vector2(0, 4), at + Vector2(-4, 0)]), Color("294a80"))
	for zone in zones:
		var bounds: Rect2 = zone.get("rect", Rect2())
		var area := Rect2(world_to_minimap(bounds.position), bounds.size / world_size * map_area.size)
		var cleared := bool(zone.get("cleared", false))
		var difficulty := clampi(int(zone.get("difficulty", 1)), 1, 5)
		var tint: Color = [Color("5a806b"), Color("8c9560"), Color("b79748"), Color("b6713e"), Color("a33d29")][difficulty - 1]
		if cleared: tint = VIEW_INK
		_markers.draw_rect(area, Color(Art.DIM, 0.5), false, 0.7)
		if area.size.y < 34.0 or area.size.x < 42.0:
			continue
		var tag_width := minf(38.0, area.size.x - 4.0)
		var tag := Rect2(area.position + Vector2(2, 2), Vector2(tag_width, 13))
		_markers.draw_rect(tag, Color(Art.PAPER_LIGHT, 0.94))
		var label := "%02d ✓" % (int(zone["zone"]) + 1) if cleared else "%02d·难%d" % [int(zone["zone"]) + 1, difficulty]
		if tag_width < 38.0:
			label = "%d✓" % (int(zone["zone"]) + 1) if cleared else "%d·%d" % [int(zone["zone"]) + 1, difficulty]
		_markers.draw_string(Art.body_font(), tag.position + Vector2(1, 10), label, HORIZONTAL_ALIGNMENT_LEFT, tag_width - 2, 9, tint.darkened(0.25))
