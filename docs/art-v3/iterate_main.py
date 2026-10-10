"""Apply the isolated presentation revision to main.gd; does not touch game data."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
path = root / 'scripts/main.gd'
source = path.read_text(encoding='utf-8')
if 'var _lbl_route: Label' in source:
    raise SystemExit('Main presentation revision already applied')

def replace_function(name, body):
    global source
    pattern = re.compile(r'^func ' + re.escape(name) + r'\(.*?(?=^func |^class |\Z)', re.M | re.S)
    source, count = pattern.subn(lambda _: body.strip() + '\n\n\n', source, count=1)
    if count != 1:
        raise RuntimeError('Missing function: ' + name)

source = source.replace('var _lbl_progress: Label', 'var _lbl_progress: Label\nvar _lbl_route: Label\nvar _lbl_combo: Label\nvar _lbl_income: Label')
source = source.replace('const SLOT_W := 96.0', 'const SLOT_W := 122.0')

replace_function('_build_topbar', '''func _build_topbar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 86
	panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER, 12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	var masthead := PanelContainer.new()
	masthead.custom_minimum_size.x = 152
	masthead.add_theme_stylebox_override("panel", Art.panel(Art.RED, 7, Art.RED, 2))
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	masthead.add_child(brand)
	var title := Art.label("拍案三国", 28, Art.PAPER_LIGHT)
	title.add_theme_font_override("font", Art.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(title)
	var sub := Art.label("操 场 就 是 荆 州", 10, Art.PAPER_LIGHT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(sub)
	hb.add_child(masthead)
	hb.add_child(_vsep())
	var place := VBoxContainer.new()
	place.custom_minimum_size.x = 105
	place.alignment = BoxContainer.ALIGNMENT_CENTER
	place.add_theme_constant_override("separation", 3)
	hb.add_child(place)
	_lbl_region = Art.label("", 26)
	_lbl_region.add_theme_font_override("font", Art.title_font())
	place.add_child(_lbl_region)
	_lbl_route = Art.label("", 11, Art.DIM)
	place.add_child(_lbl_route)
	hb.add_child(_vsep())
	var stamina := VBoxContainer.new()
	stamina.custom_minimum_size.x = 143
	stamina.alignment = BoxContainer.ALIGNMENT_CENTER
	stamina.add_theme_constant_override("separation", 3)
	hb.add_child(stamina)
	_lbl_stamina = Art.label("", 16)
	stamina.add_child(_lbl_stamina)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.custom_minimum_size = Vector2(143, 8)
	_stamina_bar.show_percentage = false
	stamina.add_child(_stamina_bar)
	_lbl_combo = Art.label("", 11, Art.DIM)
	stamina.add_child(_lbl_combo)
	hb.add_child(_vsep())
	var money := VBoxContainer.new()
	money.custom_minimum_size.x = 140
	money.alignment = BoxContainer.ALIGNMENT_CENTER
	money.add_theme_constant_override("separation", 3)
	hb.add_child(money)
	_lbl_gold = Art.label("", 18)
	_lbl_gold.clip_text = true
	money.add_child(_lbl_gold)
	_lbl_dmg = Art.label("", 11, Art.DIM)
	money.add_child(_lbl_dmg)
	_lbl_income = Art.label("", 10, Art.GOLD)
	money.add_child(_lbl_income)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(space)
	_btn_map = _nav_button("舆图", "map", _open_map)
	hb.add_child(_btn_map)
	_btn_home = _nav_button("大本营", "home", _open_home)
	hb.add_child(_btn_home)
	_btn_city = _nav_button("城建", "city", _open_city)
	hb.add_child(_btn_city)
	_btn_drawer = _nav_button("卡铺", "shop", func(): _set_drawer(not _drawer_open))
	hb.add_child(_btn_drawer)
	_btn_retreat = Button.new()
	_btn_retreat.text = "收桌"
	_btn_retreat.custom_minimum_size = Vector2(50, 40)
	_btn_retreat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn_retreat.tooltip_text = "结算这一趟已打出的伤害，回大本营"
	_btn_retreat.pressed.connect(func(): GameState.retreat())
	hb.add_child(_btn_retreat)
	var menu := Button.new()
	menu.text = "封面"
	menu.custom_minimum_size = Vector2(46, 40)
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.pressed.connect(func():
		GameState.save_game()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	hb.add_child(menu)
	return panel


func _nav_button(title: String, kind: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.icon = Art.nav_icon(kind)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 34)
	button.add_theme_font_override("font", Art.title_font())
	button.add_theme_font_size_override("font_size", 15)
	button.custom_minimum_size = Vector2(82 if title.length() < 3 else 96, 56)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_stylebox_override("normal", Art.panel(Color(0, 0, 0, 0), 3, Art.RULE, 0))
	button.tooltip_text = "打开" + title
	button.pressed.connect(action)
	return button''')

replace_function('_build_bottombar', '''func _build_bottombar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 153
	panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER, 12, Art.RULE, 2))
	_bar = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var legend := VBoxContainer.new()
	legend.custom_minimum_size.x = 50
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_child(Art.stamp("上阵", Vector2(44, 74)))
	_lbl_bar = Art.label("", 10, Art.DIM)
	_lbl_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_child(_lbl_bar)
	hb.add_child(legend)
	_slot_row = HBoxContainer.new()
	_slot_row.add_theme_constant_override("separation", 8)
	_slot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_slot_row)
	_btn_pool = Button.new()
	_btn_pool.text = "卡池 ▾"
	_btn_pool.custom_minimum_size = Vector2(74, 0)
	_btn_pool.add_theme_font_override("font", Art.title_font())
	_btn_pool.add_theme_font_size_override("font_size", 20)
	_btn_pool.tooltip_text = "展开已有将兵，把牌拖到上阵槽"
	_btn_pool.pressed.connect(func(): _set_pool(not _pool_open))
	hb.add_child(_btn_pool)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vb.add_child(footer)
	_lbl_hint = Art.label("", 11, Art.DIM)
	_lbl_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_hint.clip_text = true
	footer.add_child(_lbl_hint)
	_log_lbl = Art.label("", 10, Art.DIM)
	_log_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_log_lbl.clip_text = true
	_log_lbl.custom_minimum_size.x = 270
	footer.add_child(_log_lbl)
	_lbl_progress = Art.label("", 10, Art.DIM)
	_lbl_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_lbl_progress)
	return panel''')

replace_function('_slot_style', '''func _slot_style(filled: bool, locked: bool) -> StyleBox:
	if filled:
		return Art.card_frame(2 if locked else 1)
	return Art.panel(Art.PAPER_LIGHT.darkened(0.025), 8, Art.RULE, 0)''')

replace_function('_mk_slot_node', '''func _mk_slot_node(card_id: String, slot_index: int, locked: bool) -> Control:
	var filled := card_id != ""
	var slot := _Slot.new()
	slot.host = self
	slot.card_id = card_id
	slot.slot_index = slot_index
	slot.locked = locked
	slot.custom_minimum_size = Vector2(SLOT_W, 109)
	slot.add_theme_stylebox_override("panel", _slot_style(filled, locked))
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(v)
	if not filled:
		var plus := Art.label("＋", 28, Art.RULE)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.size_flags_vertical = Control.SIZE_EXPAND_FILL
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(plus)
		var tip := Art.label("拖入将兵", 11, Art.DIM)
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tip)
		slot.add_child(EmptySlotOutline.new())
		slot.tooltip_text = "空携带位 %d／%d：从卡池拖入将兵" % [slot_index + 1, GameState.carry_max()]
		return slot
	var c := GameData.card(card_id)
	var nm := Art.label(str(c.get("name", card_id)), 13)
	nm.add_theme_font_override("font", Art.title_font())
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	v.add_child(nm)
	var portrait := Art.image(card_id, Vector2(0, 62))
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.clip_contents = true
	v.add_child(portrait)
	var eqn := GameState.hero_equip_of(card_id).size()
	var tpn := GameState.hero_troops_of(card_id).size()
	var star := int(c.get("star", 1))
	var marks := (" 装%d" % eqn if eqn > 0 else "") + (" 兵%d" % tpn if tpn > 0 else "")
	var row := Art.label(("固定 " if locked else "★%d " % star) + _fmt_pow(GameState.hero_card_power(card_id)) + marks, 10, Art.GOLD if locked else Art.DIM)
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.clip_text = true
	v.add_child(row)
	if locked:
		slot.tooltip_text = "主角「%s」固定上阵，不占携带位。拍力 %s" % [c.get("name", card_id), _fmt_pow(GameState.hero_card_power(card_id))]
	else:
		var detail := str(c.get("effect", ""))
		var eq_names: Array[String] = []
		for eid in GameState.hero_equip_of(card_id):
			eq_names.append(GameData.card_name(str(eid)))
		if not eq_names.is_empty():
			detail += "\\n装备：" + "、".join(eq_names)
		var troop_names: Array[String] = []
		for tid in GameState.hero_troops_of(card_id):
			troop_names.append(GameData.card_name(str(tid)))
		if not troop_names.is_empty():
			detail += "\\n带兵：" + "、".join(troop_names)
		slot.tooltip_text = "%s · ★%d · 拍力 %s\\n%s\\n点一下卸下，拖动替换" % [c.get("name", card_id), star, _fmt_pow(GameState.hero_card_power(card_id)), detail]
	return slot''')

replace_function('_update_topbar', '''func _update_topbar() -> void:
	if GameState.in_battle:
		var r := GameData.region(GameState.battle_region)
		var route := str(r.get("route", ""))
		_lbl_region.text = str(r.get("name", "?"))
		_lbl_route.text = "%s · 第 %d 趟" % [route, GameState.runs]
		_lbl_region.add_theme_color_override("font_color", Art.INK)
		var alive := 0
		for e in GameState.battle:
			if float(e["hp"]) > 0.0:
				alive += 1
		_lbl_stamina.text = "耐力  %d / %d" % [GameState.stamina, GameState.stamina_max]
		_lbl_combo.text = "连击 %d · 还剩 %d 张" % [GameState.combo, alive]
		_stamina_bar.max_value = max(1, GameState.stamina_max)
		_stamina_bar.value = GameState.stamina
		_stamina_bar.visible = true
		_btn_retreat.visible = true
	else:
		_lbl_region.text = "收桌整备"
		_lbl_route.text = "下一桌，接着来"
		_lbl_stamina.text = "耐力  已收桌"
		_lbl_combo.text = "前往大本营或舆图"
		_stamina_bar.visible = false
		_btn_retreat.visible = false
	_lbl_dmg.text = "轻 %s · 重 %s" % [_fmt_pow(GameState.click_damage()), _fmt_pow(GameState.click_damage() * HEAVY_MULT)]
	_lbl_gold.text = "金币  " + GameState.fmt(GameState.gold)
	_lbl_income.text = "城建 %s / 时" % GameState.fmt(GameState.gold_per_hour())
	_lbl_progress.text = "Lv.%d  ·  上阵 %d/%d  ·  拍力 %s  ·  荆州 %d/%d" % [GameState.player_level(), GameState.carry.size(), GameState.carry_max(), _fmt_pow(GameState.deck_power()), GameState.cleared_count(), GameState.total_field_regions()]
	var hint := "单击轻拍 · 按住划过重拍 ×2.5（每张 2 耐力）"
	if not GameState.city_unlocked():
		hint += " · " + GameState.city_unlock_text()
	_lbl_hint.text = hint''')

replace_function('_mk_card', '''func _mk_card(i: int) -> Dictionary:
	var e: Dictionary = GameState.battle[i]
	var id := str(e["card_id"])
	var c := GameData.card(id)
	var star_n := clampi(int(c.get("star", 1)), 1, 6)
	var boss := bool(e["boss"])
	var rot := clampf(float(e.get("rot", 0.0)) * 0.30, -0.032, 0.032)
	var node := Panel.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_meta("paan_card", true)
	node.add_theme_stylebox_override("panel", Art.card_frame(star_n, boss))
	node.add_child(Art.decorate(star_n))
	node.size = CARD_SIZE
	node.rotation = rot
	var portrait := Art.image(id, Vector2.ZERO)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.clip_contents = true
	node.add_child(portrait)
	var seal := PanelContainer.new()
	var color: Color = Art.ROUTES.get(str(c.get("route", "")), Art.DIM)
	seal.add_theme_stylebox_override("panel", Art.panel(color, 1, color, 1))
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var faction := Art.label(Art.faction_label(str(c.get("route", ""))), 12, Art.PAPER_LIGHT)
	faction.add_theme_font_override("font", Art.title_font())
	faction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	faction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(faction)
	node.add_child(seal)
	var top := Art.label(str(c.get("name", "?")), 13)
	top.add_theme_font_override("font", Art.title_font())
	top.clip_text = true
	node.add_child(top)
	var star := Art.label(GameData.star_text(star_n), 9, Art.GOLD)
	node.add_child(star)
	var typ := Art.label("主桌" if boss else "", 8, Art.RED)
	typ.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	node.add_child(typ)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", Art.panel(Color("3b3229"), 0, Color("3b3229"), 0))
	bar.add_theme_stylebox_override("fill", Art.panel(Art.RED, 0, Art.RED, 0))
	node.add_child(bar)
	var hpt := Art.label("", 8, Art.DIM)
	hpt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	node.add_child(hpt)
	return {"node": node, "bar": bar, "hpt": hpt, "dead": false,
		"rot": rot, "size": CARD_SIZE, "fonts": {top: 13, star: 9, typ: 8, hpt: 8, faction: 12},
		"portrait": portrait, "top": top, "star": star, "type": typ, "seal": seal}''')

replace_function('_layout_cards', '''func _layout_cards() -> void:
	var area := _table.size
	if area.x <= 60.0 or area.y <= 60.0 or _cards.is_empty():
		return
	var metrics := Art.deck_metrics(_cards.size(), area, CARD_RATIO)
	var sz: Vector2 = metrics["card_size"]
	var k := clampf(sz.x / CARD_SIZE.x, 0.65, 1.65)
	for i in range(_cards.size()):
		var card: Dictionary = _cards[i]
		card["size"] = sz
		var node: Control = card["node"]
		node.size = sz
		node.pivot_offset = sz * 0.5
		for lbl in card["fonts"].keys():
			(lbl as Label).add_theme_font_size_override("font_size", maxi(8, roundi(float(card["fonts"][lbl]) * k)))
		var margin := 7.0 * k
		card["seal"].position = Vector2(margin, 6 * k)
		card["seal"].size = Vector2(20, 25) * k
		card["top"].position = Vector2(margin + 25 * k, 4 * k)
		card["top"].size = Vector2(sz.x - margin * 2 - 25 * k, 18 * k)
		card["star"].position = Vector2(margin + 25 * k, 21 * k)
		card["star"].size = Vector2(sz.x - margin * 2 - 25 * k, 11 * k)
		card["portrait"].position = Vector2(margin, 34 * k)
		card["portrait"].size = Vector2(sz.x - margin * 2, maxf(20, sz.y - 58 * k))
		card["type"].position = Vector2(margin, sz.y - 19 * k)
		card["type"].size = Vector2(29 * k, 11 * k)
		card["bar"].position = Vector2(margin, sz.y - 22 * k)
		card["bar"].size = Vector2(sz.x - margin * 2, 5 * k)
		card["hpt"].position = Vector2(margin + 30 * k, sz.y - 16 * k)
		card["hpt"].size = Vector2(sz.x - margin * 2 - 30 * k, 11 * k)
		node.position = Art.deck_position(i, _cards.size(), area, metrics)''')

source = source.replace('_lbl_bar.text = "出征\\n%d/%d"', '_lbl_bar.text = "%d/%d"')
source = source.replace('_btn_drawer.text = "卡铺 / 图鉴" if not open else "收起卡铺"', '_btn_drawer.text = "卡铺" if not open else "收起"')
source = source.replace('panel.add_child(_bg_rect("table.png"))', '''var background := _bg_rect("table.png")
		var new_path := "res://assets/art_v3/backgrounds/table_playground.png"
		if ResourceLoader.exists(new_path):
			background.texture = load(new_path)
		panel.add_child(background)
		var shade := ColorRect.new()
		shade.color = Color(0.08, 0.045, 0.02, 0.11)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(shade)''')
source = source.replace('card.custom_minimum_size = Vector2(100, 120)', 'card.custom_minimum_size = Vector2(110, 128)')
source = source.replace('Art.image(id, Vector2(0, 52))', 'Art.image(id, Vector2(0, 68))')

source += '''

class EmptySlotOutline extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)
	func _draw() -> void:
		var rect := Rect2(Vector2(5, 5), size - Vector2(10, 10))
		var color := Color("a18c6b")
		for pair in [[rect.position, Vector2(rect.end.x, rect.position.y)],
			[Vector2(rect.end.x, rect.position.y), rect.end],
			[rect.end, Vector2(rect.position.x, rect.end.y)],
			[Vector2(rect.position.x, rect.end.y), rect.position]]:
			draw_dashed_line(pair[0], pair[1], color, 1.0, 4.0)
'''
path.write_text(source, encoding='utf-8', newline='\n')
print('Updated main presentation without changing gameplay data.')
