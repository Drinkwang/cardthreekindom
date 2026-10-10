extends Control
## 印刷墨点、纸屑和掌风：只呈现已发生的拍击，不产生额外伤害。
var heavy := false
var finisher := false
var progress := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(240, 200) if finisher else Vector2(160, 140)
	pivot_offset = size * 0.5
	z_index = 1
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, 1.0, 0.62 if finisher else 0.38)
	tween.tween_callback(queue_free)

func _advance(value: float) -> void:
	progress = value
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var fade := 1.0 - progress
	var reach := (55.0 if heavy else 32.0) * (0.3 + progress)
	var ink := Color("9d3d2e") if heavy else Color("302821")
	for i in range(11 if heavy else 7):
		var angle := float(i) * 2.399 + 0.23
		var direction := Vector2.from_angle(angle)
		var start := center + direction * reach * 0.42
		var end := center + direction * reach * (0.75 + float(i % 3) * 0.15)
		draw_line(start, end, Color(ink, fade * 0.85), (2.6 if heavy else 1.4) * fade + 0.3, true)
		var dot := center + direction * (reach + i * 1.7)
		draw_circle(dot, (2.0 if i % 2 == 0 else 1.0) * fade, Color("e6d6b8", fade * 0.95))
	if heavy:
		var curve := PackedVector2Array()
		for i in range(21):
			var t := float(i) / 20.0
			curve.append(center + Vector2((t - 0.25) * 90.0, sin(t * PI) * -18.0) * (0.6 + progress))
		draw_polyline(curve, Color("c9a267", fade), 2.8 * fade + 0.4, true)
		draw_polyline(curve, Color("f4e5bd", fade * 0.45), 1.0, true)
	if finisher:
		for lane in range(3):
			var sweep := PackedVector2Array()
			for i in range(32):
				var t := float(i) / 31.0
				var x := (t - 0.5) * 180.0 * (0.7 + progress * 0.3)
				var y := sin(t * TAU + lane * 0.5) * (12.0 + lane * 5.0)
				sweep.append(center + Vector2(x, y))
			draw_polyline(sweep, Color("b28c4a", fade * 0.65), 4.0 - lane, true)
