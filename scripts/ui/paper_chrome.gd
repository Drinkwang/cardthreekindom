extends Control
## 纸纹和边缘装饰位于父背景上方、内容节点下方，不接收输入。
const Art = preload("res://scripts/ui/print_art.gd")
const GRAIN_PATH := "res://assets/art_v3/ui/paper_grain.svg"

var variant: String = "paper"
var emblem_kind: String = "coin"
static var _grain: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	resized.connect(queue_redraw)
	if variant == "emblem":
		return
	custom_minimum_size = Vector2.ZERO
	var host: Control = get_parent() as Control
	if host != null:
		host.resized.connect(_fit_parent)
		if host is Container:
			(host as Container).sort_children.connect(_fit_parent, CONNECT_DEFERRED)
		_fit_parent()
		if host is Button:
			var host_button: Button = host as Button
			host_button.mouse_entered.connect(queue_redraw)
			host_button.mouse_exited.connect(queue_redraw)
			host_button.button_down.connect(queue_redraw)
			host_button.button_up.connect(queue_redraw)
			host_button.focus_entered.connect(queue_redraw)
			host_button.focus_exited.connect(queue_redraw)
	if _grain == null and ResourceLoader.exists(GRAIN_PATH):
		_grain = load(GRAIN_PATH) as Texture2D


func _fit_parent() -> void:
	var host: Control = get_parent() as Control
	if host == null or variant == "emblem":
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	if variant == "emblem":
		_draw_emblem()
		return
	var is_button: bool = variant == "button" or variant == "primary_button"
	var inner: Rect2 = Rect2(Vector2.ZERO, size).grow(-4.5)
	if _grain != null:
		draw_texture_rect(_grain, Rect2(Vector2.ONE, size - Vector2(2, 2)), true,
			Color(1, 1, 1, 0.28 if is_button else 0.44))
	if inner.size.x < 1.0 or inner.size.y < 1.0:
		return
	var ink: Color = Color(Art.GOLD, 0.66)
	var is_primary: bool = variant == "primary_button"
	if is_primary:
		ink = Color(Art.PAPER_LIGHT, 0.70)
	if get_parent() is Button and (get_parent() as Button).disabled:
		ink.a *= 0.45
	if is_button:
		draw_rect(inner, ink, false, 1.0)
		_draw_corners(inner, ink, 4.0)
		return
	draw_rect(inner, Color(Art.RULE, 0.50), false, 1.0)
	_draw_corners(inner, ink, 9.0 if size.y > 70.0 else 6.0)
	if variant == "header":
		draw_line(Vector2(0, size.y - 1.5), Vector2(size.x, size.y - 1.5), Art.INK, 1.0)
		draw_line(Vector2(0, size.y - 3.5), Vector2(size.x, size.y - 3.5), Color(Art.GOLD, 0.65), 1.0)
	elif variant == "footer":
		draw_line(Vector2(0, 1.5), Vector2(size.x, 1.5), Art.INK, 1.0)
		draw_line(Vector2(0, 3.5), Vector2(size.x, 3.5), Color(Art.GOLD, 0.65), 1.0)
	elif variant == "card":
		draw_line(Vector2(7, 7), Vector2(size.x - 7, 7), Color(Art.GOLD, 0.78), 1.0)


func _draw_corners(rect: Rect2, tint: Color, arm: float) -> void:
	var directions: Array[Vector2] = [Vector2.ONE, Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for direction: Vector2 in directions:
		var at: Vector2 = Vector2(rect.position.x if direction.x > 0.0 else rect.end.x,
			rect.position.y if direction.y > 0.0 else rect.end.y)
		draw_line(at, at + Vector2(arm * direction.x, 0), tint, 1.5, true)
		draw_line(at, at + Vector2(0, arm * direction.y), tint, 1.5, true)
		if arm > 6.0:
			var step: Vector2 = at + direction * 3.0
			draw_line(step, step + Vector2((arm - 3.0) * direction.x, 0), tint, 1.0, true)
			draw_line(step, step + Vector2(0, (arm - 3.0) * direction.y), tint, 1.0, true)
			draw_circle(at + direction * (arm + 2.0), 1.3, tint)


func _draw_emblem() -> void:
	var unit: float = minf(size.x, size.y) / 34.0
	var center: Vector2 = size * 0.5
	draw_set_transform(center, 0.0, Vector2.ONE * unit)
	match emblem_kind:
		"coin":
			_draw_coin()
		"clock":
			_draw_clock()
		"range":
			_draw_range()
		"palm":
			_draw_palm()
		"upgrade":
			_draw_upgrade()
		_:
			_draw_range()
	draw_set_transform(Vector2.ZERO)


func _draw_coin() -> void:
	draw_circle(Vector2(0, 1.5), 14.0, Color(Art.INK, 0.16))
	draw_circle(Vector2.ZERO, 13.0, Color("d6b36b"))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 48, Color("715228"), 1.5, true)
	draw_arc(Vector2.ZERO, 10.3, 0.0, TAU, 48, Color("f4da9a"), 1.5, true)
	draw_arc(Vector2.ZERO, 8.3, 0.0, TAU, 48, Color("9c7636"), 1.0, true)
	draw_rect(Rect2(Vector2(-3.3, -3.3), Vector2(6.6, 6.6)), Art.PAPER_LIGHT)
	draw_rect(Rect2(Vector2(-3.3, -3.3), Vector2(6.6, 6.6)), Color("715228"), false, 1.2)
	for i: int in 4:
		var angle: float = i * PI * 0.5
		var along: Vector2 = Vector2.from_angle(angle)
		var side: Vector2 = Vector2(-along.y, along.x)
		draw_line(along * 5.8 - side * 1.6, along * 5.8 + side * 1.6, Color("80602d"), 1.2, true)
		draw_line(along * 5.1, along * 7.6, Color("80602d"), 1.2, true)


func _draw_clock() -> void:
	var ink: Color = Art.INK
	draw_arc(Vector2(0, 1), 11.5, 0.0, TAU, 48, ink, 1.7, true)
	draw_arc(Vector2(0, 1), 9.1, 0.0, TAU, 48, Color(Art.GOLD, 0.50), 1.0, true)
	draw_line(Vector2(0, -10.5), Vector2(0, -14), ink, 2.0, true)
	draw_line(Vector2(-3.5, -14), Vector2(3.5, -14), ink, 2.0, true)
	draw_line(Vector2(7.8, -8), Vector2(10, -10.2), ink, 2.0, true)
	for i: int in 12:
		var angle: float = i * TAU / 12.0 - PI * 0.5
		var along: Vector2 = Vector2.from_angle(angle)
		draw_line(Vector2(0, 1) + along * 7.6, Vector2(0, 1) + along * 9.0,
			Color(Art.INK, 0.7), 1.0, true)
	draw_line(Vector2(0, 1), Vector2(0, -5), ink, 1.8, true)
	draw_line(Vector2(0, 1), Vector2(5.2, 3.5), Art.RED, 1.8, true)
	draw_circle(Vector2(0, 1), 1.6, ink)


func _draw_range() -> void:
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 48, Art.RED, 1.6, true)
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 36, Color(Art.GOLD, 0.65), 1.0, true)
	draw_circle(Vector2.ZERO, 2.0, Art.INK)
	for i: int in 4:
		var direction: Vector2 = Vector2.from_angle(i * PI * 0.5)
		draw_line(direction * 9.5, direction * 14.0, Art.INK, 1.3, true)


func _draw_palm() -> void:
	draw_arc(Vector2(0, 1), 14.0, 0.1, PI - 0.1, 30, Color(Art.GOLD, 0.55), 1.0, true)
	var outline := PackedVector2Array([Vector2(-7, 8), Vector2(-10, 1), Vector2(-8, -1),
		Vector2(-5, 2), Vector2(-5, -8), Vector2(-2, -9), Vector2(-2, -3),
		Vector2(-2, -12), Vector2(1, -12), Vector2(1, -3), Vector2(1, -10),
		Vector2(4, -10), Vector2(4, -2), Vector2(4, -7), Vector2(7, -7),
		Vector2(7, 3), Vector2(4, 9), Vector2(-7, 8)])
	draw_colored_polygon(outline, Color(Art.RED, 0.14))
	draw_polyline(outline, Art.RED, 1.5, true)
	draw_line(Vector2(-5, 6), Vector2(4, 6), Color(Art.GOLD, 0.7), 1.0, true)


func _draw_upgrade() -> void:
	draw_line(Vector2(-12, 11), Vector2(12, 11), Art.GOLD, 1.0, true)
	draw_rect(Rect2(Vector2(-10, 4), Vector2(5, 5)), Color(Art.GOLD, 0.60))
	draw_rect(Rect2(Vector2(-2.5, 0), Vector2(5, 9)), Color(Art.GOLD, 0.80))
	draw_rect(Rect2(Vector2(5, -4), Vector2(5, 13)), Art.GOLD)
	draw_line(Vector2(-8, -3), Vector2(6, -11), Art.RED, 1.7, true)
	draw_line(Vector2(6, -11), Vector2(1, -11), Art.RED, 1.7, true)
	draw_line(Vector2(6, -11), Vector2(4.5, -6), Art.RED, 1.7, true)
