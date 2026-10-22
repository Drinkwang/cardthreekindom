class_name PaanMapEventLayer
extends Control
## 事件卡只绘制；输入由主牌桌统一命中测试，护卫从不进入敌牌数组。

const Art = preload("res://scripts/ui/print_art.gd")
const SIZE := Vector2(178, 182)
const TARGET_INK := Color("21665b")

var _entries: Array[Dictionary] = []
var _render_points: Dictionary = {}
var _frame: StyleBox
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	_frame = Art.card_frame(3)
	_font = Art.title_font()
	queue_redraw()

func setup(entries: Array) -> void:
	_entries.assign(entries)
	_render_points.clear()
	for entry in _entries: _render_points[str(entry["id"])] = Vector2(entry["point"])
	queue_redraw()

func update_entries(entries: Array) -> void:
	if _entries == entries: return
	_entries.assign(entries)
	var present := {}
	for entry in _entries:
		var id := str(entry["id"])
		present[id] = true
		if not _render_points.has(id): _render_points[id] = Vector2(entry["point"])
	for id in _render_points.keys():
		if not present.has(id): _render_points.erase(id)
	queue_redraw()

func hit_test(world_point: Vector2) -> String:
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		if str(entry.get("status", "")) == "done": continue
		var point: Vector2 = entry["point"]
		if str(entry.get("kind", "")) == "escort" and str(entry.get("status", "")) == "active":
			if point.distance_to(world_point) <= float(entry.get("near_radius", 160.0)): return str(entry["id"])
		var rect: Rect2 = entry.get("rect", Rect2(point - SIZE * 0.5, SIZE))
		if rect.has_point(world_point): return str(entry["id"])
	return ""

func _process(delta: float) -> void:
	var moved := false
	for entry in _entries:
		var id := str(entry["id"])
		var current: Vector2 = _render_points.get(id, entry["point"])
		var target: Vector2 = entry["point"]
		if current.distance_squared_to(target) < 0.04:
			_render_points[id] = target
			continue
		_render_points[id] = current.lerp(target, 1.0 - exp(-delta * 16.0))
		moved = true
	if moved: queue_redraw()

func _draw() -> void:
	if _frame == null or _font == null: return
	for entry in _entries:
		var point: Vector2 = _render_points.get(str(entry["id"]), entry["point"])
		if str(entry["kind"]) == "escort": _draw_escort_goal(entry, point)
		var rect := Rect2(point - SIZE * 0.5, SIZE)
		var done := str(entry.get("status", "")) == "done"
		draw_style_box(_frame, rect)
		var texture := Art.texture(str(entry.get("card_id", "B11")))
		if texture != null:
			var image_size := texture.get_size()
			image_size *= minf((SIZE.x - 24) / image_size.x, 73.0 / image_size.y)
			var image_pos := rect.position + Vector2((SIZE.x - image_size.x) * 0.5, 37 + (73 - image_size.y) * 0.5)
			draw_texture_rect(texture, Rect2(image_pos, image_size), false, Color(1, 1, 1, 0.45 if done else 1.0))
		_draw_line_text(str(entry.get("title", "地图事件")), rect.position + Vector2(0, 27), 22, Art.DIM if done else Art.RED)
		_draw_line_text(str(entry.get("progress_text", "")), rect.position + Vector2(0, 130), 15, Art.INK)
		_draw_line_text(str(entry.get("hint", "")), rect.position + Vector2(0, 150), 15, Art.DIM)
		_draw_line_text(str(entry.get("reward_text", "")), rect.position + Vector2(0, 172), 16, Art.GOLD)
		if done:
			draw_circle(rect.position + Vector2(SIZE.x - 22, 57), 18, TARGET_INK)
			draw_string(_font, rect.position + Vector2(SIZE.x - 35, 64), "领", HORIZONTAL_ALIGNMENT_CENTER, 26, 20, Art.PAPER_LIGHT)

func _draw_line_text(text: String, at: Vector2, font_size: int, color: Color) -> void:
	while text.length() > 1 and _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > SIZE.x - 12:
		text = text.left(text.length() - 1)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, font_size, color)

func _draw_escort_goal(entry: Dictionary, point: Vector2) -> void:
	var target: Vector2 = entry.get("target", point)
	draw_circle(target, 55, Color(TARGET_INK, 0.14))
	draw_arc(target, 55, 0, TAU, 48, TARGET_INK, 4, true)
	draw_string(_font, target + Vector2(-42, 8), "送达点", HORIZONTAL_ALIGNMENT_CENTER, 84, 23, TARGET_INK)
	if str(entry.get("status", "")) == "done": return
	var direction := (target - point).normalized()
	var start := point + direction * 110.0
	var end := target - direction * 65.0
	if start.distance_to(end) < 12.0 or (end - start).dot(direction) <= 0.0: return
	draw_line(start, end, TARGET_INK, 5, true)
	var side := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([end, end - direction * 22 + side * 12, end - direction * 22 - side * 12]), TARGET_INK)
