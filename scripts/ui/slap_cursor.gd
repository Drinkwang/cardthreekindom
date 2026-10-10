extends Control
## 瞄准圈使用屏幕半径；真实范围由主场景换算到世界坐标后结算。
const Art = preload("res://scripts/ui/print_art.gd")
var center := Vector2.ZERO
var radius := 34.0
var targets := 0
var cooldown := 0.0
var outlines: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	visible = false

func _draw() -> void:
	var ink := Art.RED if cooldown <= 0.001 else Art.DIM
	for outline in outlines:
		if outline.size() < 3:
			continue
		draw_colored_polygon(outline, Color("dfb254", 0.10))
		var closed := PackedVector2Array(outline)
		closed.append(closed[0])
		draw_polyline(closed, Color("f8f0dc", 0.8), 3.0, true)
		draw_polyline(closed, Color(ink, 0.75), 1.2, true)
	draw_circle(center, radius, Color(ink, 0.06))
	draw_arc(center, radius, 0, TAU, 72, Art.PAPER_LIGHT, 3.8, true)
	draw_arc(center, radius, 0, TAU, 72, ink, 1.6, true)
	# 刻度和准心只辅助瞄准，拍击判定始终使用传入的 radius。
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.from_angle(angle)
		draw_line(center + direction * (radius + 2.5), center + direction * (radius + 7.0), Art.PAPER_LIGHT, 3.0, true)
		draw_line(center + direction * (radius + 2.5), center + direction * (radius + 7.0), ink, 1.0, true)
		draw_line(center + direction * 3.8, center + direction * 7.0, ink, 1.0, true)
	draw_circle(center, 1.3, ink)
	if cooldown > 0.001:
		draw_arc(center, radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cooldown), 64, Art.RED, 2.2, true)
	var text := "%d 张" % targets
	var font := Art.theme().default_font
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var badge := _counter_badge_rect(text_width)
	draw_style_box(_badge_style(ink), badge)
	var text_pos := badge.position + Vector2(6, 14)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)

func _counter_badge_rect(text_width: float) -> Rect2:
	var dimensions := Vector2(text_width + 12, 20)
	var target_bounds := Rect2(center, Vector2.ZERO)
	for outline in outlines:
		for point in outline:
			target_bounds = target_bounds.expand(point)
	var positions: Array[Vector2] = [
		Vector2(maxf(center.x + radius + 11, target_bounds.end.x + 8), center.y - 10),
		Vector2(minf(center.x - radius - dimensions.x - 11, target_bounds.position.x - dimensions.x - 8), center.y - 10),
		Vector2(center.x - dimensions.x * 0.5, minf(center.y - radius - 30, target_bounds.position.y - 28)),
		Vector2(center.x - dimensions.x * 0.5, maxf(center.y + radius + 11, target_bounds.end.y + 8))]
	var host := get_parent() as Control
	if host == null or host.size.x < dimensions.x + 16 or host.size.y < dimensions.y + 16:
		return Rect2(positions[0], dimensions)
	var available := Rect2(Vector2.ONE * 8, host.size - Vector2.ONE * 16)
	for at in positions:
		var candidate := Rect2(at, dimensions)
		if available.encloses(candidate) and not target_bounds.grow(5).intersects(candidate): return candidate
	var fallback := positions[0]
	fallback.x = clampf(fallback.x, 8, maxf(8, host.size.x - dimensions.x - 8))
	fallback.y = clampf(fallback.y, 8, maxf(8, host.size.y - dimensions.y - 8))
	return Rect2(fallback, dimensions)

func _badge_style(ink: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Art.PAPER_LIGHT, 0.93)
	style.border_color = Color(ink, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

class Pulse extends Control:
	var radius := 34.0
	var progress := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 50
		var tween := create_tween()
		tween.tween_method(_advance, 0.0, 1.0, 0.4)
		tween.tween_callback(queue_free)
	func _advance(value: float) -> void:
		progress = value
		queue_redraw()
	func _draw() -> void:
		var fade := 1.0 - progress
		var wave := radius * (1.0 + progress * 0.16)
		draw_circle(Vector2.ZERO, radius, Color("9d3d2e", fade * fade * 0.15))
		# 有留白的朱砂印痕，避免把装饰波纹误读成扩大后的拍击范围。
		for i in range(6):
			var start := float(i) * TAU / 6.0 + 0.08
			draw_arc(Vector2.ZERO, wave, start, start + TAU / 6.0 - 0.18, 14, Color("f8f0dc", fade * 0.85), 3.8, true)
			draw_arc(Vector2.ZERO, wave, start, start + TAU / 6.0 - 0.18, 14, Color("9d3d2e", fade), 1.7, true)
			draw_arc(Vector2.ZERO, wave * 0.84, start + 0.12, start + 0.55, 9, Color("9d3d2e", fade * 0.35), 1.0, true)
		for i in range(12):
			var angle := float(i) * 2.39996
			var direction := Vector2.from_angle(angle)
			var distance := radius * (0.5 + float(i % 4) * 0.12 + progress * 0.42)
			var dot := direction * distance
			var ink_size := 1.5 + float(i % 3) * 0.65
			draw_circle(dot, ink_size * (1.0 - progress * 0.45), Color("9d3d2e", fade * 0.7))
		for i in range(8):
			var direction := Vector2.from_angle(float(i) * TAU / 8.0 + 0.22)
			var paper_pos := direction * radius * (0.78 + progress * 0.52) + Vector2(0, progress * progress * 9)
			var paper := PackedVector2Array([
				paper_pos + Vector2(-2.5, -1.5).rotated(float(i) + progress),
				paper_pos + Vector2(3.0, -1.0).rotated(float(i) + progress),
				paper_pos + Vector2(1.0, 2.5).rotated(float(i) + progress),
			])
			draw_colored_polygon(paper, Color("f8f0dc", fade * 0.95))
