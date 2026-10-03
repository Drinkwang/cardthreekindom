class_name PaanReveal
extends Control
## 翻牌揭示覆盖层 —— 开卡包 / 合成 / 招降 共用同一套特效。
##
## 流程：卡背朝上摆一排 → 逐张翻转揭示（稀有度越高，光效越亮）→
##       若最高星 >= 4，最后对该卡做一次放大特写 + 光环爆发。
## 操作：点任意处推进一张；「全部翻开」直接亮完；「跳过」关掉。
##
## 用法：
##     var rv := PaanReveal.new()
##     add_child(rv)
##     rv.finished.connect(func(): ...)
##     rv.open("襄阳卡包", [id1, id2, ...])

signal finished

# 星级 -> 稀有度配色。S5 起改用**印刷版**色（与 game/assets/ui/cardface_*.png 的印框同色），
# 这样揭示出来的卡和桌上卡框的星级颜色是同一套，不会"揭晓时一个色、落桌后另一个色"。
const RARITY := {
	1: Color(0.58, 0.58, 0.55),
	2: Color(0.26, 0.47, 0.28),
	3: Color(0.21, 0.36, 0.55),
	4: Color(0.41, 0.28, 0.55),
	5: Color(0.68, 0.52, 0.20),
	6: Color(0.69, 0.28, 0.44),
}

const BG_DIR := "res://assets/bg/"
const CARD_DIR := "res://assets/cards/"

const CARD := Vector2(152, 212)
const CARD_BG := Color(0.945, 0.925, 0.878)
const CARD_INK := Color(0.13, 0.12, 0.11)
const CARD_DIM := Color(0.42, 0.40, 0.37)
const SHOWCASE_MIN_STAR := 4          # 达到这个星级才做单张特写

# 揭示层不是"黑幕"：同一张课桌的延续，灯光暗下来而已
const DIM_COLOR := Color(0.11, 0.08, 0.05, 0.72)


func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

var _ids: Array = []
var _slots: Array = []
var _title := ""
var _sub := ""
var _next := 0
var _flipping := false
var _gap := 0.0
var _showcase_done := false
var _showcasing := false
var _closing := false
var _close_tween: Tween

var _root_box: VBoxContainer
var _row: HBoxContainer
var _hint: Label
var _btn_all: Button
var _dim: ColorRect


static func rarity_color(star: int) -> Color:
	return RARITY.get(star, RARITY[1])


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)


# =====================================================================
# 打开 / 关闭
# =====================================================================
func open(title: String, ids: Array, sub: String = "") -> void:
	_title = title
	_sub = sub
	_ids = ids.duplicate()
	_next = 0
	_flipping = false
	_gap = 0.75
	_showcase_done = false
	_showcasing = false
	_closing = false
	# 万一上一次关闭的淡出还在跑，先掐掉，否则它会把刚打开的覆盖层又藏起来
	if _close_tween != null and _close_tween.is_valid():
		_close_tween.kill()
	modulate.a = 1.0
	_fit_to_parent()
	_build()
	visible = true
	_fit_to_parent()
	set_process(true)


## 覆盖层初始是隐藏的，全屏锚点不会自动结算 —— 打开时改成左上锚点并显式撑满。
## （父控件尺寸可能还是 0，所以退化到视口尺寸。）
func _fit_to_parent() -> void:
	var ps := get_viewport_rect().size
	var p := get_parent()
	if p is Control:
		var psz: Vector2 = (p as Control).size
		if psz.x > 2.0 and psz.y > 2.0:
			ps = psz
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = ps


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_slots.clear()

	# 桌面底图：牌是摊在同一张课桌上的，不是浮在黑幕里
	var bt := _tex(BG_DIR + "table.png")
	if bt != null:
		var bg := TextureRect.new()
		bg.texture = bt
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	# 灯光压暗（暖墨色，不是纯黑）
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_root_box = VBoxContainer.new()
	_root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_root_box.add_theme_constant_override("separation", 14)
	_root_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_box)

	var t := Label.new()
	t.text = _title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color(0.97, 0.95, 0.88))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_box.add_child(t)

	if _sub != "":
		var s := Label.new()
		s.text = _sub
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_font_size_override("font_size", 14)
		s.add_theme_color_override("font_color", Color(0.66, 0.67, 0.70))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root_box.add_child(s)

	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_box.add_child(wrap)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_row)

	for i in range(_ids.size()):
		var slot := _mk_slot(str(_ids[i]))
		_slots.append(slot)
		_row.add_child(slot["wrap"])

	_hint = Label.new()
	_hint.text = "点击推进　·　「全部翻开」直接亮完"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.70, 0.71, 0.74))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_box.add_child(_hint)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 10)
	_root_box.add_child(btns)
	_btn_all = Button.new()
	_btn_all.text = "全部翻开"
	_btn_all.pressed.connect(_reveal_all)
	btns.add_child(_btn_all)
	var bskip := Button.new()
	bskip.text = "跳过"
	bskip.pressed.connect(_close)
	btns.add_child(bskip)


# =====================================================================
# 卡牌节点
# =====================================================================
func _mk_slot(card_id: String) -> Dictionary:
	var c := GameData.card(card_id)
	var star := int(c.get("star", 1))
	var accent := rarity_color(star)

	var wrap := Control.new()
	wrap.custom_minimum_size = CARD
	wrap.size = CARD
	wrap.pivot_offset = CARD * 0.5
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 卡背直接用美术资源（512×712 RGBA，四角已抠透明）
	var back := _mk_face(Color(0.62, 0.52, 0.36), Color(0.36, 0.26, 0.14), 2,
		CARD_DIR + "cardback.png")
	var bl := Label.new()
	bl.text = "拍"
	bl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.add_theme_font_size_override("font_size", 34)
	# 卡背正中是一枚浅色圆牌，字落在圆牌上 —— 用墨色才看得见
	bl.add_theme_color_override("font_color", Color(0.30, 0.22, 0.10))
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(bl)
	wrap.add_child(back)

	var front := _mk_face(CARD_BG, accent, 3 if star >= SHOWCASE_MIN_STAR else 2)
	front.visible = false
	var fv := VBoxContainer.new()
	fv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fv.offset_left = 10.0
	fv.offset_right = -10.0
	fv.offset_top = 9.0
	fv.offset_bottom = -9.0
	fv.add_theme_constant_override("separation", 2)
	fv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(fv)

	var nm := Label.new()
	nm.text = str(c.get("name", "?"))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# autowrap 的 Label 必须给明确宽度，否则容器会把它算成"每行一个字"的超高最小值
	nm.custom_minimum_size = Vector2(132, 22)
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", CARD_INK)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(nm)

	var st := Label.new()
	st.text = GameData.star_text(star)
	st.add_theme_font_size_override("font_size", 15)
	st.add_theme_color_override("font_color", accent.darkened(0.30))
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(st)

	var tp := Label.new()
	tp.text = "%s · %s" % [c.get("type", ""), c.get("route", "")]
	tp.add_theme_font_size_override("font_size", 12)
	tp.add_theme_color_override("font_color", CARD_DIM)
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(tp)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(sp)

	var eff := Label.new()
	eff.text = str(c.get("effect", ""))
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.custom_minimum_size = Vector2(0, 52)
	eff.add_theme_font_size_override("font_size", 11)
	eff.add_theme_color_override("font_color", CARD_DIM)
	eff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(eff)

	wrap.add_child(front)   # 关键：正面必须进树，翻面才会显形
	return {"wrap": wrap, "back": back, "front": front, "star": star, "id": card_id}


## 卡面用 Panel（不是 PanelContainer）—— PanelContainer 会被子节点最小高度撑开，
## 在 212px 的窄牌里会被标签挤成 500 高。Panel 只吃锚点，配合 clip_contents 保证不溢出。
func _mk_face(bg: Color, border: Color, bw: int, tex_path: String = "") -> Panel:
	var p := Panel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 有美术就用美术（卡背）：整张拉伸，四角由图片自带的 alpha 决定
	var t: Texture2D = null
	if tex_path != "":
		t = _tex(tex_path)
	if t != null:
		var st := StyleBoxTexture.new()
		st.texture = t
		st.set_texture_margin_all(0.0)
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 9
		st.content_margin_bottom = 9
		p.add_theme_stylebox_override("panel", st)
		return p

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if bw >= 3:
		sb.shadow_color = border * Color(1, 1, 1, 0.55)
		sb.shadow_size = 14
	sb.shadow_color = sb.shadow_color if bw >= 3 else Color(0, 0, 0, 0.45)
	sb.shadow_size = 14 if bw >= 3 else 6
	p.add_theme_stylebox_override("panel", sb)
	return p


# =====================================================================
# 逐张揭示
# =====================================================================
func _process(delta: float) -> void:
	if _closing or _showcase_done:
		return
	if _showcasing:
		return
	if _flipping:
		return
	if _next < _slots.size():
		_gap -= delta
		if _gap <= 0.0:
			_flip_next()
	else:
		_after_all_revealed()


func _flip_next() -> void:
	if _next >= _slots.size():
		return
	var slot: Dictionary = _slots[_next]
	_next += 1
	_flipping = true
	_flip_slot(slot, func():
		_flipping = false
		_gap = 0.20)


func _flip_slot(slot: Dictionary, on_done: Callable) -> void:
	var wrap: Control = slot["wrap"]
	var star := int(slot["star"])
	var accent := rarity_color(star)
	# 高星卡翻出来时先"卡一下"，再"啪"地亮出来 —— 这是开包的节奏感
	var hold := 0.30 if star >= SHOWCASE_MIN_STAR else 0.10
	var tw := wrap.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(wrap, "scale:x", 0.05, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		(slot["back"] as Control).visible = false
		(slot["front"] as Control).visible = true
		if star >= SHOWCASE_MIN_STAR:
			_burst(wrap, accent, 2.6))
	tw.tween_property(wrap, "scale:x", 1.0, 0.19).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(on_done)


func _burst(anchor: Control, col: Color, mult: float = 2.0) -> void:
	# 一圈扩散的光环。挂在覆盖层根上 —— 不能挂进 _row（HBox 会把它当子项重排）。
	var ring := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(col.r, col.g, col.b, 0.95)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(CARD.x * 0.5))
	ring.add_theme_stylebox_override("panel", sb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)
	ring.size = anchor.size
	ring.pivot_offset = anchor.size * 0.5
	ring.global_position = anchor.global_position
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(mult, mult), 0.42)
	tw.tween_property(ring, "modulate:a", 0.0, 0.42)
	tw.chain().tween_callback(ring.queue_free)


func _reveal_all() -> void:
	if _showcase_done or _showcasing:
		return
	for i in range(_slots.size()):
		var slot: Dictionary = _slots[i]
		if (slot["front"] as Control).visible:
			continue
		(slot["back"] as Control).visible = false
		(slot["front"] as Control).visible = true
		var wrap: Control = slot["wrap"]
		var tw := wrap.create_tween()
		tw.tween_property(wrap, "scale", Vector2(1.15, 1.15), 0.08)
		tw.tween_property(wrap, "scale", Vector2(1.0, 1.0), 0.10)
	_next = _slots.size()
	_flipping = false
	_after_all_revealed()


func _after_all_revealed() -> void:
	if _showcase_done:
		return
	var best := -1
	var best_star := 0
	for i in range(_slots.size()):
		var s := int(_slots[i]["star"])
		if s > best_star:
			best_star = s
			best = i
	if best < 0 or best_star < SHOWCASE_MIN_STAR:
		_showcase_done = true
		_hint.text = "点任意处继续"
		_btn_all.visible = false
		return
	_run_showcase(best)


func _run_showcase(i: int) -> void:
	_showcase_done = true
	_showcasing = true
	_btn_all.visible = false
	var slot: Dictionary = _slots[i]
	var wrap: Control = slot["wrap"]
	var star := int(slot["star"])
	var accent := rarity_color(star)
	var c := GameData.card(str(slot["id"]))
	_hint.text = "%s　%s　—— 点任意处继续" % [
		c.get("name", "?"), GameData.star_text(star)]

	# 该卡放大、上浮、发光
	var tw := wrap.create_tween()
	tw.tween_property(wrap, "scale", Vector2(1.42, 1.42), 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(wrap, "position:y", wrap.position.y - 26.0, 0.30)
	tw.tween_callback(func():
		_flash(accent))
	tw.tween_interval(0.85)
	tw.tween_callback(func(): _showcasing = false)


func _flash(col: Color) -> void:
	_dim.color = Color(col.r * 0.28, col.g * 0.24, col.b * 0.18, 0.88)
	for k in range(3):
		var ring := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(col.r, col.g, col.b, 0.9 - float(k) * 0.25)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(320)
		ring.add_theme_stylebox_override("panel", sb)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ring)
		ring.size = Vector2(200, 200)
		ring.position = size * 0.5 - Vector2(100, 100)
		ring.pivot_offset = Vector2(100, 100)
		var tw := ring.create_tween()
		tw.tween_interval(0.10 * float(k))
		tw.set_parallel(true)
		tw.tween_property(ring, "scale", Vector2(4.2, 4.2), 0.70)
		tw.tween_property(ring, "modulate:a", 0.0, 0.70)
		tw.chain().tween_callback(ring.queue_free)


# =====================================================================
# 交互
# =====================================================================
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_advance()


func _advance() -> void:
	if _closing:
		return
	if _showcasing:
		_showcasing = false
		_showcase_done = true
		_hint.text = "点任意处继续"
		return
	if _next < _slots.size():
		# 翻一半就直接亮完（不耐烦的玩家不该被动画卡住）
		_flip_next()
		_reveal_all()
		return
	_close()


func _close() -> void:
	if _closing:
		return
	_closing = true
	set_process(false)
	if is_inside_tree():
		_close_tween = create_tween()
		_close_tween.tween_property(self, "modulate:a", 0.0, 0.16)
		_close_tween.tween_callback(func():
			visible = false
			modulate.a = 1.0
			finished.emit())
	else:
		finished.emit()
