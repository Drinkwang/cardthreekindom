extends Control
## 每次拍击只显示一张屏幕空间收据；相机缩放不会改变字号。
const Art = preload("res://scripts/ui/print_art.gd")

var damage_text := ""
var gold_text := ""
var hit_count := 0
var damage := 0.0
var gold := 0.0
var impact_radius := 34.0
var progress := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	if damage_text.is_empty():
		damage_text = _number(damage)
	if gold_text.is_empty():
		gold_text = _number(gold)
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, 1.0, 0.78)
	tween.tween_callback(queue_free)

func _advance(value: float) -> void:
	progress = value
	queue_redraw()

func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, round(value)) else "%.1f" % value

func _draw() -> void:
	var font := Art.theme().default_font
	var headline := "+%s 金" % gold_text
	var detail := "拍中 %d 张  ·  伤害 %s" % [hit_count, damage_text]
	var width := maxf(126, maxf(font.get_string_size(headline, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 34, font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 22))
	var rise := 14.0 * (1.0 - pow(1.0 - progress, 2.0))
	var receipt := Rect2(Vector2(-width * 0.5, -impact_radius - 63.0 - rise), Vector2(width, 49))
	# 场地边缘也保留整张收据；粒子仍以真实拍击点为中心。
	var host := get_parent() as Control
	if host != null:
		receipt.position.x = clampf(receipt.position.x, 8.0 - position.x, maxf(8.0 - position.x, host.size.x - position.x - width - 8.0))
		receipt.position.y = clampf(receipt.position.y, 8.0 - position.y, maxf(8.0 - position.y, host.size.y - position.y - receipt.size.y - 8.0))
	var opacity := 1.0 - smoothstep(0.55, 1.0, progress)
	var shadow := Rect2(receipt.position + Vector2(2, 3), receipt.size)
	draw_style_box(_paper_style(Color(Art.INK, opacity * 0.15), Color.TRANSPARENT), shadow)
	draw_style_box(_paper_style(Color(Art.PAPER_LIGHT, opacity * 0.97), Color(Art.RULE, opacity * 0.9)), receipt)
	draw_line(receipt.position + Vector2(7, 6), receipt.position + Vector2(7, receipt.size.y - 6), Color(Art.RED, opacity), 2.0, true)
	var title_width := font.get_string_size(headline, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var detail_width := font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, receipt.position + Vector2((width - title_width) * 0.5, 22), headline, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(Art.GOLD, opacity))
	draw_string(font, receipt.position + Vector2((width - detail_width) * 0.5, 40), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Art.INK, opacity))
	_draw_coin_flecks(opacity)

func _paper_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

func _draw_coin_flecks(opacity: float) -> void:
	# 少量铜钱沿两侧散开，固定屏幕尺寸，避免在放大视野中遮住卡面。
	for i in range(5):
		var side := -1.0 if i % 2 == 0 else 1.0
		var coin_pos := Vector2(side * (12.0 + float(i) * 4.0 + progress * 22), -8.0 - progress * (25.0 + float(i) * 5.0) + progress * progress * 23)
		var fade := opacity * (1.0 - progress * 0.45)
		draw_circle(coin_pos + Vector2(0.8, 1), 3.6, Color(Art.INK, fade * 0.2))
		draw_circle(coin_pos, 3.4, Color("c8a254", fade))
		draw_arc(coin_pos, 3.2, 0, TAU, 12, Color(Art.GOLD, fade), 0.8, true)
		draw_rect(Rect2(coin_pos - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(Art.PAPER_LIGHT, fade))
