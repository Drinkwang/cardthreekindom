extends ScrollContainer
## 练掌堂：静态卡片与实时数据分开，购买后不重建节点或跳动滚动位置。
const Art = preload("res://scripts/ui/print_art.gd")
const UISkin = preload("res://scripts/ui/ui_skin.gd")
const CORE := ["power", "speed", "radius", "stamina"]
const CORE_ART := {
	"power": "res://assets/art_v9/upgrade_power.png",
	"speed": "res://assets/art_v9/upgrade_speed.png",
	"radius": "res://assets/art_v10/upgrade_radius.png",
	"stamina": "res://assets/art_v9/upgrade_duration.png",
}
const CORE_COPY := {
	"power": ["拍力", "一掌翻厚牌", "单拍更强，厚牌更快翻"],
	"speed": ["拍速", "连拍聚铜钱", "同样时间，多拍几次"],
	"radius": ["范围", "圈住更多将牌", "扩大光标圆圈，一掌拍中更多卡"],
	"stamina": ["时长", "漏尽再收钱", "延长一轮，多留赚钱时间"],
}
const GROUPS := [
	{"title": "自动经营", "mark": "自", "ids": ["auto", "auto_next", "auto_power", "idle"]},
	{"title": "武将协力", "mark": "将", "ids": ["carry", "equip", "troops"]},
	{"title": "翻牌收成", "mark": "财", "ids": ["crit", "fortune"]},
]
const ADV_COPY := {
	"auto": ["自动拍", "休息时也能拍牌赚钱；拍力为手动的25%，节奏较慢。"],
	"auto_next": ["自动续轮", "自动轮结束后休息4秒，接着再开一轮。"],
	"auto_power": ["自动助力", "提高自动拍力，自动经营也能更快翻牌。"],
	"idle": ["离线经营", "增加离线收益效率和可结算的离线时长。"],
	"carry": ["同行将位", "多带一名武将或士卒，他们的能力会助你拍牌。"],
	"equip": ["武将装备", "每位武将依次解锁兵器、铠甲、坐骑、兵书、宝物。"],
	"troops": ["武将带兵", "每位武将多一个兵位，麾下士卒不占同行将位。"],
	"crit": ["暴击", "提高翻牌暴击的机会，基础暴击为双倍伤害。"],
	"fortune": ["财路", "相同的翻牌和伤害，收获更多金币。"],
}
var cards: Dictionary = {}
var selected_id := "power"
var _content: VBoxContainer
var _core_grid: GridContainer
var _summary: Label
var _detail: Label
var _receipt: Label
var _art_height := -1.0

func _ready() -> void:
	theme = Art.theme()
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_theme_constant_override("scrollbar_separation", 8)
	var bar := get_v_scroll_bar()
	bar.custom_minimum_size.x = 10
	for state in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var color := Color("ded4bf") if state == "scroll" else Art.RED if state == "grabber_pressed" else Color("9f8b68")
		var style := Art.panel(color, 3, color, 0)
		style.content_margin_left = 4
		style.content_margin_right = 4
		bar.add_theme_stylebox_override(state, style)
	_build()
	resized.connect(_fit_art)
	refresh()
	_fit_art.call_deferred()

func _build() -> void:
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	add_child(_content)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	heading.add_child(UISkin.emblem("palm", Vector2(42, 42)))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(_label("练掌堂 · 一掌一进境", 25, Art.INK, true))
	_summary = _label("", 13, Art.DIM)
	words.add_child(_summary)
	heading.add_child(words)
	_content.add_child(heading)
	_core_grid = GridContainer.new()
	_core_grid.name = "CoreUpgrades"
	_core_grid.columns = 4
	_core_grid.add_theme_constant_override("h_separation", 14)
	_core_grid.add_theme_constant_override("v_separation", 14)
	_core_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_core_grid)
	for id in CORE:
		_core_grid.add_child(_core_card(id))
	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", UISkin.panel(Color("f4ead2"), 10, Art.RULE, 1))
	var notes := VBoxContainer.new()
	notes.add_theme_constant_override("separation", 3)
	_detail = _label("", 13, Art.INK)
	_receipt = _label("点插画查看提升，点金币按钮购买。", 12, Art.DIM)
	notes.add_child(_detail)
	notes.add_child(_receipt)
	note.add_child(notes)
	_content.add_child(note)
	_content.add_child(Art.divider())
	_content.add_child(_label("进阶修炼", 25, Art.RED, true))
	_content.add_child(_label("向下滚动查看进阶本领；完成新野牌堆进度、点亮所需前置后即可学习。", 13, Art.DIM))
	for group in GROUPS:
		var group_heading := HBoxContainer.new()
		group_heading.add_theme_constant_override("separation", 10)
		group_heading.add_child(Art.stamp(str(group.mark), Vector2(24, 24)))
		group_heading.add_child(_label(str(group.title), 18, Art.INK, true))
		var rule := Art.divider()
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_heading.add_child(rule)
		_content.add_child(group_heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for id in group.ids:
			grid.add_child(_advanced_card(str(id), str(group.mark)))
		_content.add_child(grid)
	_content.add_child(_label("金币、修炼和城池进度自动保存。整备完成后，可在下方再来一轮。", 12, Art.DIM))

func _core_card(id: String) -> Control:
	var panel := PanelContainer.new()
	panel.name = "UpgradeCard_" + id
	panel.set_meta("upgrade_card_id", id)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var art_button := Button.new()
	art_button.name = "UpgradeArt_" + id
	art_button.clip_contents = true
	art_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_button.tooltip_text = "查看" + str(CORE_COPY[id][0]) + "的提升"
	art_button.add_theme_stylebox_override("normal", UISkin.panel(Art.PAPER_LIGHT, 0, Art.RULE, 1))
	art_button.add_theme_stylebox_override("hover", UISkin.panel(Art.PAPER_LIGHT, 0, Art.RED, 2))
	art_button.add_theme_stylebox_override("pressed", UISkin.panel(Art.PAPER_LIGHT, 0, Art.RED, 2))
	art_button.add_theme_stylebox_override("focus", UISkin.panel(Color.TRANSPARENT, 0, Art.RED, 2))
	art_button.pressed.connect(select_upgrade.bind(id))
	var picture := TextureRect.new()
	picture.name = "Illustration"
	picture.texture = load(CORE_ART[id]) as Texture2D if ResourceLoader.exists(CORE_ART[id]) else null
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_button.add_child(picture)
	var art_chrome := UISkin.chrome(art_button, "paper")
	art_button.move_child(art_chrome, art_button.get_child_count() - 1)
	var selection := _art_tag(art_button, "已选中", Vector2(7, 7), false)
	var level := _label("", 12, Art.PAPER_LIGHT)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var level_tag := _tag(level, Color("463528"), Color("a88653"))
	level_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	level_tag.offset_left = -75
	level_tag.offset_right = -7
	level_tag.offset_top = 7
	level_tag.offset_bottom = 31
	art_button.add_child(level_tag)
	var caption := _art_tag(art_button, str(CORE_COPY[id][1]), Vector2(7, -30), true)
	caption.self_modulate.a = 0.95
	column.add_child(art_button)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 6)
	var name_label := _label(str(CORE_COPY[id][0]), 25, Art.INK, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	var state := _label("", 11, Art.RED)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var state_tag := _tag(state, Color("eee0bd"), Art.RULE)
	state_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(state_tag)
	column.add_child(title)
	var data_panel := PanelContainer.new()
	data_panel.add_theme_stylebox_override("panel", _inset_style())
	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", 3)
	var value := _label("", 18, Art.INK)
	data.add_child(value)
	var gain := _label("", 12, Color("315d43"))
	data.add_child(gain)
	data_panel.add_child(data)
	column.add_child(data_panel)
	var buy := _purchase_button(id)
	column.add_child(buy)
	cards[id] = {"panel": panel, "level": level, "value": value, "gain": gain, "button": buy,
		"picture": picture, "art_button": art_button, "core": true,
		"selection": selection, "state": state, "state_tag": state_tag}
	return panel

func _advanced_card(id: String, mark: String) -> Control:
	var panel := PanelContainer.new()
	panel.name = "UpgradeCard_" + id
	panel.set_meta("upgrade_card_id", id)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 9)
	heading.add_child(Art.stamp(mark, Vector2(30, 33)))
	var title := _label(str(ADV_COPY[id][0]), 20, Art.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var level := _label("", 11, Art.PAPER_LIGHT)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var level_tag := _tag(level, Color("5d4c36"), Color("ad926a"))
	level_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(level_tag)
	var state := _label("", 11, Art.RED)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var state_tag := _tag(state, Color("eee0bd"), Art.RULE)
	state_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(state_tag)
	column.add_child(heading)
	column.add_child(_label(str(ADV_COPY[id][1]), 13, Art.DIM))
	var data_panel := PanelContainer.new()
	data_panel.add_theme_stylebox_override("panel", _inset_style())
	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", 3)
	var value := _label("", 14, Art.INK)
	data.add_child(value)
	var gain := _label("", 12, Art.DIM)
	data.add_child(gain)
	data_panel.add_child(data)
	column.add_child(data_panel)
	var buy := _purchase_button(id)
	column.add_child(buy)
	cards[id] = {"panel": panel, "level": level, "value": value, "gain": gain, "button": buy,
		"core": false, "state": state, "state_tag": state_tag, "title": title}
	return panel

func _purchase_button(id: String) -> Button:
	var button := Button.new()
	button.name = "BuyUpgrade_" + id
	button.set_meta("upgrade_id", id)
	UISkin.button(button, true, true)
	button.custom_minimum_size.y = 38
	button.add_theme_font_override("font", Art.title_font())
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_constant_override("icon_max_width", 16)
	button.add_theme_constant_override("h_separation", 7)
	button.pressed.connect(_buy.bind(id))
	return button

func _tag(label: Label, fill: Color, accent: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _tag_style(fill, accent))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.add_child(label)
	return badge

func _tag_style(fill: Color, accent: Color) -> StyleBoxFlat:
	var style := UISkin.panel(fill, 6, accent, 1)
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

func _art_tag(parent: Control, text: String, offset: Vector2, bottom: bool) -> Control:
	var label := _label(text, 11, Art.PAPER_LIGHT if not bottom else Art.INK)
	var badge := _tag(label, Art.RED if not bottom else Art.PAPER_LIGHT, Color("cfb98a"))
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT if bottom else Control.PRESET_TOP_LEFT)
	badge.position = offset
	badge.custom_minimum_size.y = 24
	parent.add_child(badge)
	return badge

func _inset_style() -> StyleBoxFlat:
	var style := UISkin.panel(Color("eaddbd"), 7, Color("cbb991"), 1)
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _fit_art() -> void:
	if cards.is_empty(): return
	_core_grid.columns = 4 if size.x >= 1000.0 else 2
	var height := clampf(size.y * 0.29, 112.0, 172.0)
	if is_equal_approx(height, _art_height): return
	_art_height = height
	for id in CORE:
		cards[id].art_button.custom_minimum_size.y = height

func refresh() -> void:
	if cards.is_empty(): return
	_summary.text = "金币 %s　·　拍力 %s　·　%.2f 拍 / 秒　·　范围半径 %s　·　下轮 %s 秒" % [_number(GameState.gold), _number(GameState.click_damage()), 1.0 / GameState.slap_interval(), _number(GameState.slap_radius()), _number(GameState.round_duration_value())]
	for id in cards:
		_refresh_card(str(id))
	_update_detail()
	_fit_art()

func _refresh_card(id: String) -> void:
	var card: Dictionary = cards[id]
	var maxed := GameState.upgrade_maxed(id)
	var locked := not GameState.skill_req_met(id)
	var cost := GameState.upgrade_cost(id)
	var afford := GameState.gold >= float(cost)
	card.level.text = "Lv.%d" % GameState.upgrade_level(id)
	if id in ["auto", "auto_next"]: card.level.text = "已学会" if maxed else "未学会"
	if bool(card.core):
		var preview := GameState.upgrade_preview(id)
		var now: Dictionary = preview.current
		var next: Dictionary = preview.next
		match id:
			"power":
				card.value.text = "%s → %s / 拍" % [_number(now.damage), _number(next.damage)]
				card.gain.text = "轻拍伤害 +%s" % _number(float(next.damage) - float(now.damage))
			"speed":
				card.value.text = "%.2f → %.2f 秒 / 拍" % [now.interval, next.interval]
				card.gain.text = "每秒 %.2f → %.2f 拍" % [now.frequency, next.frequency]
			"radius":
				var radius_now := float(now.radius)
				var radius_next := float(next.radius)
				var area_gain := (radius_next * radius_next / (radius_now * radius_now) - 1.0) * 100.0
				card.value.text = "半径 %s → %s" % [_number(radius_now), _number(radius_next)]
				card.gain.text = "直径 %s → %s · 覆盖 +%.1f%%" % [_number(radius_now * 2.0), _number(radius_next * 2.0), area_gain]
			"stamina":
				card.value.text = "%s → %s 秒 / 轮" % [_number(now.duration), _number(next.duration)]
				card.gain.text = "轻拍上限约 %d → %d 次" % [now.slaps, next.slaps]
	else:
		var definition := GameState.up_def(id)
		var current := GameState.upgrade_value(id)
		var next_value := current if maxed else GameState.upgrade_next_value(id)
		var unit := str(definition.get("unit", ""))
		card.value.text = "%s → %s %s" % [_number(current), _number(next_value), unit]
		if id in ["auto", "auto_next"]: card.value.text = "已开启" if maxed else "一次解锁，持续生效"
		card.gain.text = _requirement_text(id) if locked else ("已完成这项修炼" if maxed else "点亮后帮助拍牌与经营")
	var button: Button = card.button
	button.disabled = maxed or locked or not afford
	if maxed:
		button.text = "已学会" if id in ["auto", "auto_next"] else "已满级"
	elif locked:
		button.text = "尚未解锁"
	elif not afford:
		button.text = "%d 金币 · 还差 %s" % [cost, _number(float(cost) - GameState.gold)]
	else:
		button.text = "%s · %d 金币" % ["学会" if id in ["auto", "auto_next"] else "升级", cost]
	button.tooltip_text = _requirement_text(id) if locked else ("已达到这项修炼的上限" if maxed else "购买" + _name(id) + "，费用 %d 金币" % cost)
	var status := "已满级" if maxed else "待解锁" if locked else "金币不足" if not afford else "可升级"
	if id in ["auto", "auto_next"] and maxed: status = "已学会"
	var status_ink := Color("456250") if maxed else Art.DIM if locked else Art.RED if not afford else Color("47604e")
	card.state.text = status
	card.state.add_theme_color_override("font_color", status_ink)
	var status_fill := Color("e0e7d2") if maxed else Color("e5dfce") if locked else Color("f0decd") if not afford else Color("e4ead5")
	card.state_tag.add_theme_stylebox_override("panel", _tag_style(status_fill, Color(status_ink, 0.5)))
	var selected := id == selected_id
	var accent := Art.RED if selected else Color("b5a079")
	var paper := Color("fbf2dc") if selected else Color("eee6d1") if locked else Art.PAPER_LIGHT
	var card_style := UISkin.panel(paper, 10, accent, 2 if selected else 1)
	card_style.shadow_size = 5 if selected else 3
	card_style.shadow_color = Color(0.12, 0.08, 0.04, 0.20)
	card_style.shadow_offset = Vector2(1, 3)
	card.panel.add_theme_stylebox_override("panel", card_style)
	var fill := Color("d4cbb8") if locked else Color("d5dbc7") if maxed else Color("e2cfb2") if not afford else (Art.RED if bool(card.core) else Color("456454"))
	var border := Color("b6a78e") if button.disabled else fill.darkened(0.20)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var button_fill := fill.lightened(0.08) if state == "hover" else fill.darkened(0.08) if state == "pressed" else fill
		var style := UISkin.panel(button_fill, 7, border, 1)
		style.shadow_size = 0 if state in ["pressed", "disabled"] else 2
		style.shadow_offset = Vector2(0, 2)
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Art.PAPER_LIGHT)
	button.add_theme_color_override("font_disabled_color", Color("675a43"))
	button.add_theme_font_size_override("font_size", 14 if not afford and not locked and not maxed else 17)
	button.icon = Art.nav_icon("gold") if not locked and not maxed else null
	button.add_theme_color_override("icon_normal_color", Color("efd69e"))
	button.add_theme_color_override("icon_hover_color", Art.PAPER_LIGHT)
	button.add_theme_color_override("icon_disabled_color", Color("927747"))
	if bool(card.core):
		card.selection.visible = selected
		card.picture.modulate = Color(0.80, 0.80, 0.80) if maxed else Color.WHITE
	else:
		card.title.add_theme_color_override("font_color", Art.DIM if locked else Art.INK)

func select_upgrade(id: String) -> void:
	if not cards.has(id): return
	selected_id = id
	refresh()

func _update_detail() -> void:
	if selected_id in CORE:
		var rule := "延长的时间从下一轮开始。" if selected_id == "stamina" else "购买后按当前牌组重新计算。"
		if selected_id == "radius":
			rule = "单击拍击圈内卡牌，扩圈立即生效。镜头缩放只改变显示大小，实际范围不变。"
		_detail.text = "%s · %s。%s" % [_name(selected_id), str(CORE_COPY[selected_id][2]), rule]
	else:
		_detail.text = "%s · %s" % [_name(selected_id), str(ADV_COPY[selected_id][1])]

func _buy(id: String) -> void:
	selected_id = id
	if GameState.buy_upgrade(id):
		_receipt.text = "已升级%s至 Lv.%d，金币已扣除。" % [_name(id), GameState.upgrade_level(id)]
	refresh()

func _name(id: String) -> String:
	return str(CORE_COPY[id][0]) if id in CORE else str(ADV_COPY[id][0])

func _requirement_text(id: String) -> String:
	var text := GameState.skill_req_text(id)
	for key in ADV_COPY:
		text = text.replace(str(GameState.up_def(str(key)).get("name", key)), _name(str(key)))
	return text

func _label(text: String, font_size: int, color: Color, title: bool = false) -> Label:
	var label := Art.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if title: label.add_theme_font_override("font", Art.title_font())
	return label

func _number(value: float) -> String:
	if absf(value) >= 10000.0: return GameState.fmt(value)
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
