extends Control
## 圆形修炼图只选择技能，所有升级集中在右侧的一处按钮。
const Art = preload("res://scripts/ui/print_art.gd")
const UISkin = preload("res://scripts/ui/ui_skin.gd")
const IDS := ["power", "speed", "radius", "stamina", "carry", "crit", "fortune", "equip", "troops"]
const ICON_CELLS := {"power": 0, "speed": 1, "radius": 2, "stamina": 3, "carry": 4, "crit": 5, "fortune": 6, "equip": 7, "troops": 8}
const CORE_ART := {
	"power": "res://assets/art_v9/upgrade_power.png",
	"speed": "res://assets/art_v9/upgrade_speed.png",
	"radius": "res://assets/art_v10/upgrade_radius.png",
	"stamina": "res://assets/art_v9/upgrade_duration.png",
}
const COPY := {
	"power": ["拍力", "每次拍击更有力。", "每级拍力 ×1.12"],
	"speed": ["拍速", "缩短两次拍击之间的间隔。", "每级拍击频率 ×1.08"],
	"radius": ["范围", "一掌覆盖更多场上卡牌。", "每级拍击半径 +6"],
	"stamina": ["时长", "延长一局的拍击时间。", "每级一局时长 +2 秒"],
	"carry": ["携带位", "增加上阵武将或士卒的位置。", "每级携带位 +1"],
	"crit": ["暴击", "拍击有机会造成双倍伤害。", "每级暴击率 +4%"],
	"fortune": ["财路", "增加拍击敌牌获得的金币。", "每级掉金加成 +20%"],
	"equip": ["装备槽", "依次解锁兵器、铠甲、坐骑、兵书、宝物。", "每级解锁一个装备部位"],
	"troops": ["武将带兵", "士卒跟随武将上阵，不占携带位。", "每级每位武将 +1 兵位"],
}
const POSITIONS := {
	"speed": Vector2(0.10, 0.18), "crit": Vector2(0.48, 0.18), "equip": Vector2(0.78, 0.18),
	"power": Vector2(0.26, 0.49), "radius": Vector2(0.63, 0.43), "troops": Vector2(0.89, 0.53),
	"stamina": Vector2(0.10, 0.80), "carry": Vector2(0.47, 0.80), "fortune": Vector2(0.73, 0.82),
}
var cards: Dictionary = {}
var selected_id := "power"
var _graph: Control
var _detail_panel: PanelContainer
var _picture: TextureRect
var _detail_title: Label
var _level: Label
var _value: Label
var _gain: Label
var _description: Label
var _requirement: Label
var _summary: Label
var _buy_button: Button
var _receipt: Label


func _ready() -> void:
	theme = Art.theme()
	_build()
	resized.connect(_fit)
	refresh()
	_fit.call_deferred()


func _build() -> void:
	var row := HBoxContainer.new()
	row.name = "CultivationLayout"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var chart := PanelContainer.new()
	chart.name = "CultivationChart"
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.add_theme_stylebox_override("panel", UISkin.panel(Art.PAPER_LIGHT, 7, Art.RED, 1))
	UISkin.chrome(chart, "paper")
	row.add_child(chart)
	_graph = Control.new()
	_graph.name = "SkillGraph"
	_graph.clip_contents = true
	_graph.draw.connect(_draw_graph)
	_graph.resized.connect(_layout_nodes)
	chart.add_child(_graph)
	var terrain := TextureRect.new()
	terrain.show_behind_parent = true
	var landscape := "res://assets/art_v13/cultivation_landscape.png"
	if ResourceLoader.exists(landscape): terrain.texture = load(landscape) as Texture2D
	terrain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	terrain.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph.add_child(terrain)
	for id in IDS:
		var node := SkillNode.new()
		node.name = "SkillNode_" + id
		node.set_meta("upgrade_card_id", id)
		node.caption = str(COPY[id][0])
		node.artwork = _texture(id)
		node.pressed.connect(select_upgrade.bind(id))
		_graph.add_child(node)
		cards[id] = {"panel": node, "art_button": node, "state": node.status_label}
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "SelectedSkill"
	_detail_panel.add_theme_stylebox_override("panel", UISkin.panel(Art.PAPER_LIGHT, 12, Art.RED, 1))
	UISkin.chrome(_detail_panel, "paper")
	row.add_child(_detail_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_detail_panel.add_child(column)
	var title := HBoxContainer.new()
	_detail_title = _label("", 27, Art.RED, true)
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(_detail_title)
	_summary = _label("", 14, Art.DIM)
	title.add_child(_summary)
	column.add_child(title)
	_picture = TextureRect.new()
	_picture.name = "SkillIllustration"
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_picture)
	_level = _label("", 23, Art.INK, true)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_level)
	_value = _label("", 22, Color("265341"), true)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_value)
	_gain = _label("", 14, Art.INK)
	_gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_gain)
	column.add_child(Art.divider())
	_description = _label("", 14, Art.DIM)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	_requirement = _label("", 13, Art.RED)
	_requirement.name = "SkillRequirement"
	_requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_requirement)
	_buy_button = Button.new()
	_buy_button.name = "BuySelectedSkill"
	_buy_button.set_meta("skill_purchase", true)
	_buy_button.custom_minimum_size.y = 47
	UISkin.button(_buy_button, true)
	_buy_button.add_theme_font_size_override("font_size", 22)
	_buy_button.pressed.connect(func(): _buy(selected_id))
	column.add_child(_buy_button)
	_receipt = _label("", 12, Art.DIM)
	_receipt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_receipt)


func _fit() -> void:
	if _detail_panel == null: return
	_detail_panel.custom_minimum_size.x = clampf(size.x * 0.27, 278.0, 340.0)
	_picture.custom_minimum_size.y = clampf(size.y * 0.30, 98.0, 190.0)
	_layout_nodes()


func _layout_nodes() -> void:
	if cards.is_empty(): return
	var diameter := clampf((_graph.size.y - 80.0) / 3.0 - 22.0, 65.0, 113.0)
	var plot := Rect2(13.0, 11.0, maxf(1, _graph.size.x - 26), maxf(1, _graph.size.y - 83))
	for id in IDS:
		var node: SkillNode = cards[id].panel
		node.diameter = diameter * (1.13 if id == "power" else 1.0)
		node.size = Vector2(node.diameter + 14.0, node.diameter + 64.0)
		var center: Vector2 = plot.position + Vector2(POSITIONS[id]) * plot.size
		node.position = center - Vector2(node.size.x * 0.5, node.diameter * 0.5 + 4.0)
		node.arrange()
	_graph.queue_redraw()


func _draw_graph() -> void:
	for id in IDS:
		for requirement in GameState.skill_reqs(id):
			var from: SkillNode = cards[str(requirement)].panel
			var to: SkillNode = cards[id].panel
			var start := from.position + Vector2(from.size.x * 0.5, from.diameter * 0.5 + 4)
			var end := to.position + Vector2(to.size.x * 0.5, to.diameter * 0.5 + 4)
			var direction := (end - start).normalized()
			start += direction * (from.diameter * 0.5 + 6)
			end -= direction * (to.diameter * 0.5 + 8)
			var learned := GameState.upgrade_level(str(requirement)) > 0
			var ink := Art.RED if learned else Color("9d8566")
			var bend := direction.orthogonal() * minf(start.distance_to(end) * 0.10, 28.0)
			var points := PackedVector2Array()
			for step in 25:
				var t := float(step) / 24.0
				points.append(start.lerp(end, t) + bend * sin(t * PI))
			if learned: _graph.draw_polyline(points, ink, 2.3, true)
			else:
				for segment in range(0, points.size() - 1, 2): _graph.draw_line(points[segment], points[segment + 1], ink, 1.4, true)
			var tangent := (points[-1] - points[-2]).normalized()
			var side := tangent.orthogonal() * 4.5
			_graph.draw_colored_polygon(PackedVector2Array([end, end - tangent * 11.0 + side, end - tangent * 11.0 - side]), ink)
	_graph.draw_rect(Rect2(7, _graph.size.y - 28, 239, 22), Color(Art.PAPER_LIGHT, 0.92))
	_graph.draw_string(Art.body_font(), Vector2(13, _graph.size.y - 11), "✓ 已修习      ↑ 可升级      锁 未解锁", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Art.DIM)


func refresh() -> void:
	if cards.is_empty(): return
	for id in IDS:
		var node: SkillNode = cards[id].panel
		var maxed := GameState.upgrade_maxed(id)
		var locked := not GameState.skill_req_met(id)
		var afford := GameState.skill_points >= GameState.upgrade_cost(id)
		node.selected = id == selected_id
		node.locked = locked
		node.learned = GameState.upgrade_level(id) > 0
		node.available = not maxed and not locked and afford
		node.level = GameState.upgrade_level(id)
		node.status_label.text = "已满级" if maxed else "待解锁" if locked else "技能点不足" if not afford else "可升级"
		node.tooltip_text = _requirement_text(id) if locked else "%s · Lv.%d" % [_name(id), node.level]
		node.arrange()
	_update_detail()
	_graph.queue_redraw()


func select_upgrade(id: String) -> void:
	if not cards.has(id): return
	if selected_id != id: _receipt.text = ""
	selected_id = id
	refresh()


func _update_detail() -> void:
	var id := selected_id
	var maxed := GameState.upgrade_maxed(id)
	var locked := not GameState.skill_req_met(id)
	var cost := GameState.upgrade_cost(id)
	var afford := GameState.skill_points >= cost
	var level := GameState.upgrade_level(id)
	_detail_title.text = _name(id)
	_summary.text = "技能点 %d" % GameState.skill_points
	_picture.texture = _texture(id)
	_level.text = "Lv.%d → Lv.%d" % [level, level if maxed else level + 1]
	var current := GameState.upgrade_value(id)
	var next_value := current if maxed else GameState.upgrade_next_value(id)
	match id:
		"power": _value.text = "× %s → × %s" % [_number(current), _number(next_value)]
		"speed": _value.text = "%.2f → %.2f 秒 / 拍" % [1.0 / current, 1.0 / next_value]
		"radius": _value.text = "半径 %s → %s" % [_number(current), _number(next_value)]
		"stamina":
			var preview := GameState.upgrade_preview(id)
			_value.text = "%s → %s 秒 / 局" % [_number(float(preview.current.duration)), _number(float(preview.next.duration))]
		"crit", "fortune": _value.text = "%s%% → %s%%" % [_number(current), _number(next_value)]
		_: _value.text = "%s → %s %s" % [_number(current), _number(next_value), str(GameState.up_def(id).get("unit", ""))]
	_gain.text = str(COPY[id][2])
	_description.text = str(COPY[id][1])
	_requirement.text = _requirement_text(id) if locked else "已修至当前上限" if maxed else "技能点不足" if not afford else ""
	_buy_button.disabled = maxed or locked or not afford or GameState.in_battle
	_buy_button.text = "已满级" if maxed else "尚未解锁" if locked else "升级 · %d 技能点" % cost
	_buy_button.tooltip_text = _requirement_text(id) if locked else ""


func _buy(id: String) -> void:
	if id != selected_id: select_upgrade(id)
	if GameState.buy_upgrade(id):
		_receipt.text = "%s Lv.%d · 余 %d 技能点" % [_name(id), GameState.upgrade_level(id), GameState.skill_points]
	refresh()


func _texture(id: String) -> Texture2D:
	var atlas_path := "res://assets/art_v13/skill_icons.png"
	if ResourceLoader.exists(atlas_path):
		var atlas := load(atlas_path) as Texture2D
		var cell := atlas.get_size() / 3.0
		var index: int = ICON_CELLS[id]
		var icon := AtlasTexture.new()
		icon.atlas = atlas
		icon.region = Rect2(Vector2(index % 3, index / 3) * cell, cell)
		icon.filter_clip = true
		return icon
	if id in CORE_ART: return load(CORE_ART[id]) as Texture2D
	match id:
		"carry": return Art.nav_icon("cards")
		"crit": return Art.texture("E01")
		"fortune": return Art.nav_icon("gold")
		"equip": return Art.texture("E03")
		"troops": return Art.texture("G04")
	return null


func _name(id: String) -> String:
	return str(COPY[id][0])


func _requirement_text(id: String) -> String:
	return GameState.skill_req_text(id).replace("清除新野卡堆前3段", "征服新野前3区")


func _label(text: String, font_size: int, color: Color, title: bool = false) -> Label:
	var label := Art.label(text, font_size, color)
	if title: label.add_theme_font_override("font", Art.title_font())
	return label


func _number(value: float) -> String:
	if absf(value) >= 10000.0: return GameState.fmt(value)
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")


class SkillNode extends Button:
	var diameter := 90.0
	var caption := ""
	var artwork: Texture2D
	var selected := false
	var locked := false
	var learned := false
	var available := false
	var level := 0
	var status_label := Label.new()
	var _image: TextureRect
	var _caption: Label
	var _level: Label
	var _badge: Label
	var _caption_height := 30.0

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus"]: add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_image = TextureRect.new()
		_image.texture = artwork
		_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mask := Shader.new()
		mask.code = "shader_type canvas_item; uniform vec4 source_uv = vec4(0.0,0.0,1.0,1.0); void fragment(){ vec2 local_uv=(UV-source_uv.xy)/source_uv.zw; COLOR.a *= 1.0-smoothstep(0.485,0.497,length(local_uv-vec2(0.5))); }"
		var circle_material := ShaderMaterial.new()
		circle_material.shader = mask
		if artwork is AtlasTexture:
			var sheet := artwork as AtlasTexture
			var extent := sheet.atlas.get_size()
			circle_material.set_shader_parameter("source_uv", Vector4(sheet.region.position.x / extent.x, sheet.region.position.y / extent.y, sheet.region.size.x / extent.x, sheet.region.size.y / extent.y))
		_image.material = circle_material
		add_child(_image)
		_caption = Art.label(caption, 21, Art.INK)
		_caption.add_theme_font_override("font", Art.title_font())
		_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_caption.clip_text = true
		_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(_caption)
		_level = Art.label("", 13, Art.INK)
		_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_level)
		_badge = Art.label("", 17, Art.PAPER_LIGHT)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_badge)
		status_label.visible = false
		add_child(status_label)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		arrange()

	func arrange() -> void:
		if _image == null: return
		var left := (size.x - diameter) * 0.5
		_image.position = Vector2(left + 5, 9)
		_image.size = Vector2.ONE * (diameter - 10)
		_image.modulate = Color(0.72, 0.68, 0.61, 0.85) if locked else Color.WHITE
		_caption.add_theme_font_size_override("font_size", 18 if diameter < 80 else 21)
		_caption_height = maxf(30.0, _caption.get_minimum_size().y + 4.0)
		_caption.position = Vector2(2, diameter + 7)
		_caption.size = Vector2(size.x - 4, _caption_height)
		_caption.add_theme_color_override("font_color", Art.PAPER_LIGHT if selected else Art.DIM if locked else Art.INK)
		_level.text = "未解锁" if locked else "Lv.%d" % level
		_level.position = Vector2(0, diameter + 9 + _caption_height)
		_level.size = Vector2(size.x, maxf(19.0, _level.get_minimum_size().y))
		_badge.text = "锁" if locked else "↑" if available else "✓" if learned else "·"
		_badge.position = Vector2(left + diameter - 18, diameter - 18)
		_badge.size = Vector2(25, 25)
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Art.DIM if locked else Color("b87a28") if available else Art.RED
		badge_style.set_corner_radius_all(13)
		badge_style.set_border_width_all(2)
		badge_style.border_color = Art.PAPER_LIGHT
		_badge.add_theme_stylebox_override("normal", badge_style)
		queue_redraw()

	func _has_point(point: Vector2) -> bool:
		var center := Vector2(size.x * 0.5, diameter * 0.5 + 4)
		if point.distance_to(center) <= diameter * 0.5 + 6: return true
		return _caption != null and (_caption.get_rect().has_point(point) or _level.get_rect().has_point(point) or _badge.get_rect().has_point(point))

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, diameter * 0.5 + 4)
		var ink := Art.RED if selected else Art.DIM if locked else Art.INK
		if selected: draw_circle(center, diameter * 0.5 + 5, Color("d4b566"))
		draw_circle(center, diameter * 0.5 + 1.5, Art.PAPER_LIGHT)
		draw_arc(center, diameter * 0.5, 0, TAU, 96, ink, 2.5 if selected else 1.4, true)
		draw_arc(center, diameter * 0.5 - 4, 0, TAU, 96, ink, 1, true)
		if is_hovered() or has_focus(): draw_arc(center, diameter * 0.5 + 3, 0, TAU, 96, Art.RED, 1.1, true)
		var caption_rect := Rect2(Vector2(2, diameter + 6), Vector2(size.x - 4, _caption_height + 2))
		draw_style_box(UISkin.panel(Art.RED if selected else Art.PAPER_LIGHT, 0, ink, 1), caption_rect)
		var badge_center := Vector2((size.x - diameter) * 0.5 + diameter - 5.5, diameter - 5.5)
		draw_circle(badge_center, 14, Art.PAPER_LIGHT)
		draw_circle(badge_center, 11.5, Art.DIM if locked else Color("b87a28") if available else Art.RED)
