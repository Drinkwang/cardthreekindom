extends Control
class_name PaanDeck
## 构筑页：将牌与真实能力分开绘制，金币变化不会重建牌格或滚动位置。

const Art = preload("res://scripts/ui/print_art.gd")
const SCENE_PATH := "res://assets/art_v7/deck_scene.png"
const SCENE_FALLBACK := "res://assets/art_v5/deck_scene.png"
const FILTERS := ["全部", "雷印", "烈火", "追击", "士兵"]

signal changed

var _selected := ""
var _tab := "上阵"
var _filter := "全部"
var _query := ""
var _signature := ""
var _root: VBoxContainer
var _pool: GridContainer
var _pool_note: Label
var _cultivate: Button
var _power: Label
var _fusion_note: Label
var _add_button: Button
var _traits: Script


func _ready() -> void:
	theme = Art.theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 410)
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	if _traits == null and ResourceLoader.exists("res://scripts/build_traits.gd"):
		_traits = load("res://scripts/build_traits.gd") as Script
	if _selected == "" or int(GameState.owned.get(_selected, 0)) <= 0:
		_selected = str(GameState.carry[0]) if not GameState.carry.is_empty() else _first_owned()
	var qualities := {}
	for id in GameState.owned:
		if GameState.is_hero(str(id)):
			qualities[str(id)] = [GameState.hero_quality(str(id)), GameState.hero_fusion_stock(str(id))]
	var next := str([GameState.carry, GameState.owned, qualities,
		GameState.hero_equip, GameState.hero_troops, GameState.carry_max(),
		GameState.equip_slots(), GameState.troop_slots(), _selected, _tab])
	if next == _signature and _root != null:
		refresh_values()
		return
	_signature = next
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cultivate = null
	_add_button = null
	_power = null
	_fusion_note = null
	_pool = null
	_root = VBoxContainer.new()
	_root.name = "DeckLayout"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)
	_build_slots()
	_build_tabs()
	var body := HBoxContainer.new()
	body.name = "DeckBody"
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(body)
	body.add_child(_build_selected())
	if _tab == "上阵":
		var right := VBoxContainer.new()
		right.name = "DeckWarehouseColumn"
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override("separation", 8)
		body.add_child(right)
		_build_team(right)
		_build_warehouse(right)
	else:
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override("separation", 8)
		body.add_child(right)
		if _tab == "装备":
			_build_equipment(right)
		else:
			_build_troops(right)
	refresh_values()


func refresh_values() -> void:
	if _cultivate != null and is_instance_valid(_cultivate):
		var stock := GameState.hero_fusion_stock(_selected)
		var available := GameState.can_fuse_hero(_selected)
		_cultivate.text = "同名合成  3 → 1" if available else "同名合成  %d / 3" % stock
		_cultivate.disabled = not available
		_cultivate.tooltip_text = "同名同品质的 3 张自由库存合成 1 张更高品质；不花金币。上阵和附着中的卡不会被消耗。"
	if _power != null and is_instance_valid(_power):
		_power.text = "战力 %s   ·   %s" % [_number(GameState.hero_card_power(_selected)),
			GameState.hero_quality_name(_selected)] if GameState.is_hero(_selected) else "战力 %s   ·   士兵素材" % _number(GameState.hero_card_power(_selected))
	if _fusion_note != null and is_instance_valid(_fusion_note):
		_fusion_note.text = "同名合成：3 张原版 → 精制，3 张精制 → 珍藏。\n品质只提高自身战力，接招条件保持不变。"
	if _add_button != null and is_instance_valid(_add_button):
		var full := GameState.carry.size() >= GameState.carry_max()
		var assigned := GameState.in_troops(_selected)
		_add_button.disabled = full or assigned
		_add_button.text = "已在武将麾下" if assigned else ("阵位已满，先卸下一张" if full else "上阵")


func _first_owned() -> String:
	for id in GameState.owned:
		if GameState.is_carryable(str(id)) and int(GameState.owned[id]) > 0:
			return str(id)
	return ""


func _build_slots() -> void:
	var compact := get_viewport_rect().size.y <= 740.0
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 9)
	_root.add_child(heading)
	heading.add_child(Art.stamp("阵", Vector2(29, 30)))
	var title := _title("上阵将牌", 23)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(Art.label("%d / %d  ·  主角常驻，另有携带位" % [GameState.carry.size(), GameState.carry_max()], 13, Art.DIM))
	heading.add_child(_carry_menu())
	var strip := HBoxContainer.new()
	strip.name = "DeckSlots"
	strip.add_theme_constant_override("separation", 9)
	_root.add_child(strip)
	for i in range(GameState.carry_max()):
		var id := str(GameState.carry[i]) if i < GameState.carry.size() else ""
		var button := Button.new()
		button.name = "DeckSlot_%d" % i
		button.custom_minimum_size = Vector2(0, 90 if compact else 108)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("deck_slot", i)
		button.set_meta("card_id", id)
		_style_card(button, int(GameData.card(id).get("star", 1)), id == _selected)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		strip.add_child(button)
		var inset := MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			inset.add_theme_constant_override("margin_" + side, 7)
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(inset)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(row)
		if id == "":
			var empty := VBoxContainer.new()
			empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			empty.add_theme_constant_override("separation", 7)
			row.add_child(empty)
			var plus := _title("＋", 38)
			plus.add_theme_color_override("font_color", Art.DIM)
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_child(plus)
			var caption := _title("空阵位", 18)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_child(caption)
			var count := Art.label("挑一张将牌", 12, Art.DIM)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_child(count)
			button.pressed.connect(_focus_warehouse)
		else:
			row.add_theme_constant_override("separation", 8)
			var portrait := _portrait(id, Vector2(72, 72) if compact else Vector2(84, 84))
			row.add_child(portrait)
			var texts := VBoxContainer.new()
			texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
			texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(texts)
			texts.add_theme_constant_override("separation", 5)
			texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var name_label := _title(GameData.card_name(id), 21)
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			texts.add_child(name_label)
			texts.add_child(Art.label(GameData.star_text(int(GameData.card(id).get("star", 1))), 12, Art.GOLD))
			var role := Art.label(_trait_tag(id), 12, Art.RED)
			role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			texts.add_child(role)
			button.tooltip_text = _trait_description(id)
			button.pressed.connect(_select.bind(id))
		_ignore_mouse(inset)


func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_root.add_child(row)
	for tab in ["上阵", "装备", "带兵"]:
		var button := Button.new()
		button.text = {"上阵": "将牌组合", "装备": "武将装备", "带兵": "武将带兵"}[tab]
		button.name = "DeckTab_%s" % tab
		button.set_meta("deck_tab", tab)
		button.custom_minimum_size = Vector2(123, 32)
		button.add_theme_font_override("font", Art.title_font())
		button.add_theme_font_size_override("font_size", 19)
		if tab == _tab:
			_style_primary(button, 19, 8)
		button.pressed.connect(_change_tab.bind(tab))
		row.add_child(button)
	var note := Art.label("星级决定能力，同名合成提高品质", 13, Art.DIM)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(note)


func _build_selected() -> Control:
	var panel := PanelContainer.new()
	panel.name = "DeckSelected"
	panel.custom_minimum_size = Vector2(312, 0)
	panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 12, Art.RED, 1))
	_add_paper(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.name = "DeckSelectedScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	scroll.add_child(content)
	if _selected == "":
		content.add_child(_title("尚无将牌", 25))
		content.add_child(_wrap("先到婆婆的商店买卡包，再来配一套上阵将牌。", 16, Art.DIM))
		return panel
	var card := GameData.card(_selected)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var portrait_frame := PanelContainer.new()
	portrait_frame.add_theme_stylebox_override("panel", Art.card_frame(int(card.get("star", 1))))
	header.add_child(portrait_frame)
	var compact := get_viewport_rect().size.y <= 740.0
	var portrait := Art.image(_selected, Vector2(116, 148) if compact else Vector2(144, 184))
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_frame.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	header.add_child(info)
	var selected_name := _title(GameData.card_name(_selected), 25)
	selected_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(selected_name)
	info.add_child(Art.label(GameData.star_text(int(card.get("star", 1))), 14, Art.GOLD))
	info.add_child(Art.label("%s · %s" % [str(card.get("faction", "")), str(card.get("type", ""))], 12, Art.DIM))
	info.add_child(_role_label(_trait_tag(_selected), 13))
	_power = _wrap("", 12, Art.DIM)
	info.add_child(_power)
	var ability := _trait(_selected)
	if not ability.is_empty():
		content.add_child(_title(str(ability.get("title", ability.get("name", "构筑能力"))), 18))
	content.add_child(_wrap(_trait_description(_selected), 13))
	var effect := GameData.effect_text(card)
	if not ability.is_empty() and effect not in ["", "-"]:
		content.add_child(_wrap("原有被动：" + effect, 12, Art.DIM))
	if GameState.is_hero(_selected):
		_fusion_note = _wrap("", 12, Art.DIM)
		_fusion_note.name = "DeckFusionRules"
		content.add_child(_fusion_note)
	var actions := HBoxContainer.new()
	actions.name = "DeckSelectedActions"
	actions.custom_minimum_size.y = 36
	actions.add_theme_constant_override("separation", 7)
	layout.add_child(actions)
	if GameState.is_hero(_selected):
		_cultivate = Button.new()
		_cultivate.name = "DeckCultivate"
		_cultivate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cultivate.custom_minimum_size.y = 36
		_cultivate.add_theme_font_override("font", Art.title_font())
		_cultivate.add_theme_font_size_override("font_size", 18)
		_cultivate.pressed.connect(_fuse)
		actions.add_child(_cultivate)
	if GameState.in_carry(_selected):
		var remove := Button.new()
		remove.name = "DeckRemove"
		remove.text = "卸下"
		remove.custom_minimum_size = Vector2(64, 36)
		remove.pressed.connect(_remove)
		actions.add_child(remove)
	else:
		_add_button = Button.new()
		_add_button.name = "DeckAdd"
		_add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_button.custom_minimum_size.y = 36
		_style_primary(_add_button, 19, 8)
		_add_button.pressed.connect(_add)
		actions.add_child(_add_button)
	return panel


func _build_team(parent: VBoxContainer) -> void:
	var compact := get_viewport_rect().size.y <= 740.0
	var panel := PanelContainer.new()
	panel.name = "DeckTeamSummary"
	panel.custom_minimum_size.y = 98 if compact else 106
	panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 9, Art.RED))
	parent.add_child(panel)
	_add_paper(panel)
	var path := SCENE_PATH if ResourceLoader.exists(SCENE_PATH) else SCENE_FALLBACK
	if ResourceLoader.exists(path):
		var scene := TextureRect.new()
		scene.name = "DeckSceneIllustration"
		scene.texture = load(path) as Texture2D
		scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.modulate = Color(1, 1, 1, 0.14)
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(scene)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	var summary: Dictionary = {}
	if _traits != null and _traits.has_method("team_summary"):
		var raw: Variant = _traits.call("team_summary", GameState.carry)
		if raw is Dictionary:
			summary = raw
	var text := VBoxContainer.new()
	text.custom_minimum_size.x = 232
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 5)
	layout.add_child(text)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 7)
	title_row.add_child(Art.stamp("联", Vector2(27, 29)))
	title_row.add_child(_title(str(summary.get("title", "我的将牌组合")), 23))
	text.add_child(title_row)
	var description := _wrap(str(summary.get("description", "配上产生状态和收尾的将牌，拍击时自动联动。")), 12)
	description.custom_minimum_size.x = 232
	description.max_lines_visible = 2 if compact else 3
	text.add_child(description)
	if not compact:
		text.add_child(Art.label("起手附印  →  接招引爆", 12, Art.DIM))
	var chains_row := HBoxContainer.new()
	chains_row.name = "DeckComboScroll"
	chains_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chains_row.add_theme_constant_override("separation", 8)
	layout.add_child(chains_row)
	var chains := 0
	for pair in [["G04", "G05", "雷印"], ["G30", "G40", "烈火"], ["G20", "G24", "追击"]]:
		if not GameState.carry.has(pair[0]) and not GameState.carry.has(pair[1]):
			continue
		chains += 1
		var chain := VBoxContainer.new()
		chain.name = "DeckCombo_" + str(pair[2])
		chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chain.add_theme_constant_override("separation", 3)
		chains_row.add_child(chain)
		var banner := HBoxContainer.new()
		var tag := Art.label(str(pair[2]), 13, Art.RED)
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banner.add_child(tag)
		var complete := GameState.carry.has(pair[0]) and GameState.carry.has(pair[1])
		banner.add_child(Art.label("✓ 接招" if complete else "缺搭档", 11, Art.RED if complete else Art.DIM))
		chain.add_child(banner)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.add_child(_combo_actor(str(pair[0])))
		var arrow := _title("→", 23)
		arrow.add_theme_color_override("font_color", Art.RED)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(arrow)
		row.add_child(_combo_actor(str(pair[1])))
		chain.add_child(row)
	if chains == 0:
		var hint := _wrap("选一位起手将，再配一位接招将。\n雷印、烈火、追击可以混搭。", 14, Art.DIM)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chains_row.add_child(hint)
	panel.tooltip_text = _list_text(summary.get("missing", "")) + "\n按各自的触发条件自动接招"


func _combo_actor(id: String) -> Control:
	var actor := VBoxContainer.new()
	actor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actor.add_theme_constant_override("separation", 2)
	var icon_size := 40 if get_viewport_rect().size.y <= 740.0 else 48
	var portrait := _portrait(id, Vector2(icon_size, icon_size))
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not GameState.in_carry(id):
		portrait.modulate = Color(0.85, 0.79, 0.70, 0.52)
	actor.add_child(portrait)
	var label := _title(GameData.card_name(id), 15)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actor.add_child(label)
	actor.tooltip_text = _trait_description(id)
	return actor


func _build_warehouse(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "DeckWarehousePanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 8, Art.RULE))
	parent.add_child(panel)
	_add_paper(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	content.add_child(tools)
	var title := _title("将牌仓库", 23)
	tools.add_child(title)
	var filter := OptionButton.new()
	filter.name = "DeckFilter"
	filter.custom_minimum_size.y = 32
	for item in FILTERS:
		filter.add_item(item)
	filter.select(maxi(0, FILTERS.find(_filter)))
	filter.item_selected.connect(_filter_changed)
	tools.add_child(filter)
	var search := LineEdit.new()
	search.name = "DeckSearch"
	search.custom_minimum_size.y = 32
	search.placeholder_text = "找武将 / 能力"
	search.text = _query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(_search_changed)
	tools.add_child(search)
	_pool_note = Art.label("", 12, Art.DIM)
	_pool_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(_pool_note)
	var scroll := ScrollContainer.new()
	scroll.name = "DeckWarehouseScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_pool = GridContainer.new()
	_pool.name = "DeckWarehouse"
	_pool.columns = 3
	_pool.add_theme_constant_override("h_separation", 8)
	_pool.add_theme_constant_override("v_separation", 8)
	_pool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pool)
	_render_pool()


func _render_pool() -> void:
	if _pool == null:
		return
	for child in _pool.get_children():
		_pool.remove_child(child)
		child.queue_free()
	var cards: Array[String] = []
	for id in GameState.owned:
		var who := str(id)
		if int(GameState.owned[id]) <= 0 or not GameState.is_carryable(who):
			continue
		var text := GameData.card_name(who) + _trait_description(who) + _trait_tag(who)
		if _query != "" and not text.contains(_query):
			continue
		if _filter == "士兵" and not GameState.is_troop(who):
			continue
		if _filter not in ["全部", "士兵"] and not _matches_filter(who):
			continue
		cards.append(who)
	cards.sort_custom(func(a: String, b: String) -> bool:
		if GameState.in_carry(a) != GameState.in_carry(b):
			return not GameState.in_carry(a)
		return GameState.hero_card_power(a) > GameState.hero_card_power(b))
	_pool_note.text = "共 %d 种将牌  ·  点击纸牌，查看接招与配套" % cards.size()
	if cards.is_empty():
		var empty := _wrap("没有符合筛选的将牌。可以清除筛选，或到商店补充卡包。", 14, Art.DIM)
		empty.custom_minimum_size = Vector2(180, 0)
		_pool.add_child(empty)
	for id in cards:
		_pool.add_child(_warehouse_card(id))


func _warehouse_card(id: String) -> Button:
	var compact := get_viewport_rect().size.y <= 740.0
	var card := GameData.card(id)
	var button := Button.new()
	button.name = "DeckHero_" + id
	button.set_meta("card_id", id)
	button.custom_minimum_size = Vector2(0, 88 if compact else 96)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_card(button, int(card.get("star", 1)), id == _selected)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = "%s\n%s\n持有 %d 张%s" % [GameData.card_name(id), _trait_description(id), int(GameState.owned.get(id, 0)), " · " + GameState.hero_quality_name(id) + " · 可合成库存 %d / 3" % GameState.hero_fusion_stock(id) if GameState.is_hero(id) else ""]
	button.pressed.connect(_select.bind(id))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	row.add_child(_portrait(id, Vector2(70, 70) if compact else Vector2(78, 78)))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 3)
	row.add_child(texts)
	var title := _title(GameData.card_name(id), 23)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var rarity := GameData.star_text(int(card.get("star", 1)))
	if GameState.is_hero(id) and GameState.hero_quality(id) > 0:
		rarity += "  · " + GameState.hero_quality_name(id)
	texts.add_child(Art.label(rarity, 12, Art.GOLD))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 4)
	texts.add_child(footer)
	var tag := Art.label(_trait_tag(id), 12, Art.RED)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(tag)
	var status := "已上阵" if GameState.in_carry(id) else "可上阵"
	if GameState.in_troops(id):
		status = "已派兵"
	footer.add_child(Art.label(status, 11, Art.DIM))
	_ignore_mouse(margin)
	return button


func _portrait(id: String, minimum: Vector2) -> TextureRect:
	# 图集头像共用头肩画幅；士兵仍使用自己的完整卡面。
	var portrait := Art.portrait_icon(id, minimum) if GameState.is_hero(id) else Art.image(id, minimum)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return portrait


func _portrait_texture(id: String) -> Texture2D:
	if not GameState.is_hero(id):
		return Art.texture(id)
	var icon := Art.portrait_icon(id, Vector2(32, 32))
	var texture: Texture2D = icon.texture
	icon.free()
	return texture


func _build_equipment(parent: VBoxContainer) -> void:
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 9)
	heading.add_child(Art.stamp("器", Vector2(30, 33)))
	heading.add_child(_title("装备巢 · 只作用于这名武将", 25))
	parent.add_child(heading)
	parent.add_child(_wrap("一件装备只在一名武将身上；选择其他武将的装备会直接转移。", 13, Art.DIM))
	if not GameState.has_equip_nest(_selected):
		parent.add_child(_wrap("只有武将拥有装备巢。点击上方武将，再给他搭配装备。", 16, Art.DIM))
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	scroll.add_child(content)
	for subtype in GameState.EQUIP_SLOTS:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 11, Art.RULE))
		content.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var title := _title(str(subtype), 20)
		title.custom_minimum_size = Vector2(65, 0)
		row.add_child(title)
		if not GameState.is_slot_unlocked(str(subtype)):
			row.add_child(Art.label("未解锁 · 在升级页开放装备槽", 14, Art.DIM))
			continue
		var id := GameState.hero_equipped_in_slot(_selected, str(subtype))
		if id != "":
			row.add_child(Art.image(id, Vector2(55, 59)))
		var caption := _wrap("空槽 · " + str(GameState.EQUIP_SLOT_DESC.get(subtype, "")) if id == "" else GameData.card_name(id) + "  " + GameData.effect_text(GameData.card(id)), 14)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		row.add_child(_equipment_menu(str(subtype)))
		if id != "":
			var remove := Button.new()
			remove.name = "DeckUnequip_" + id
			remove.text = "卸下"
			remove.pressed.connect(_unequip.bind(id))
			row.add_child(remove)


func _equipment_menu(subtype: String) -> MenuButton:
	var menu := MenuButton.new()
	menu.name = "DeckEquipMenu_" + subtype
	menu.text = "选择装备"
	menu.custom_minimum_size = Vector2(100, 36)
	menu.add_theme_font_override("font", Art.title_font())
	menu.add_theme_font_size_override("font_size", 19)
	var popup := menu.get_popup()
	for id in GameState.owned:
		var card := GameData.card(str(id))
		if int(GameState.owned[id]) <= 0 or str(card.get("type", "")) != "装备" or str(card.get("subtype", "")) != subtype:
			continue
		var owner := GameState.equip_owner(str(id))
		var tag := "" if owner == "" or owner == _selected else "（在%s身上）" % GameData.card_name(owner)
		popup.add_icon_item(Art.texture(str(id)), GameData.card_name(str(id)) + "  " + GameData.effect_text(card) + tag)
		popup.set_item_metadata(popup.item_count - 1, str(id))
	if popup.item_count == 0:
		popup.add_item("仓库暂无该类装备")
		popup.set_item_disabled(0, true)
	popup.id_pressed.connect(_equip_pick.bind(popup))
	return menu


func _build_troops(parent: VBoxContainer) -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 9)
	title_row.add_child(Art.stamp("兵", Vector2(30, 33)))
	title_row.add_child(_title("带兵 · 补齐武将的配套", 25))
	parent.add_child(title_row)
	parent.add_child(_wrap("麾下士兵不占阵位；同一张士兵不会同时上阵和带兵。", 13, Art.DIM))
	if not GameState.is_hero(_selected):
		parent.add_child(_wrap("点击上方武将，查看他的兵位。士兵自身不能带兵。", 16, Art.DIM))
		return
	var cap := GameState.troop_cap(_selected)
	if cap <= 0:
		parent.add_child(_wrap("尚未学会带兵。先到升级页解锁「武将带兵」。", 16, Art.DIM))
		return
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var count := Art.label("麾下 %d / %d" % [GameState.hero_troops_of(_selected).size(), cap], 15)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(count)
	heading.add_child(_troop_menu())
	var scroll := ScrollContainer.new()
	scroll.name = "DeckTroopScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	scroll.add_child(content)
	for id in GameState.hero_troops_of(_selected):
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 10))
		content.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		panel.add_child(row)
		row.add_child(Art.image(str(id), Vector2(75, 86)))
		var caption := _wrap("%s  %s\n战力 %s" % [GameData.card_name(str(id)), GameData.star_text(int(GameData.card(str(id)).get("star", 1))), GameState.fmt(GameState.hero_card_power(str(id)))], 15)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var remove := Button.new()
		remove.name = "DeckTroopRemove_" + str(id)
		remove.text = "撤兵"
		remove.pressed.connect(_troop_remove.bind(str(id)))
		row.add_child(remove)
	if GameState.hero_troops_of(_selected).is_empty():
		content.add_child(_wrap("兵位空着。把仓库中的士兵派到这名武将麾下。", 16, Art.DIM))


func _troop_menu() -> MenuButton:
	var menu := MenuButton.new()
	menu.name = "DeckTroopMenu"
	menu.text = "＋ 派兵"
	menu.custom_minimum_size = Vector2(112, 36)
	_style_primary(menu, 20, 9)
	menu.disabled = GameState.hero_troops_of(_selected).size() >= GameState.troop_cap(_selected)
	var popup := menu.get_popup()
	for id in GameState.owned:
		var who := str(id)
		if int(GameState.owned[id]) <= 0 or not GameState.is_troop(who) or GameState.troop_owner(who) == _selected:
			continue
		var owner := GameState.troop_owner(who)
		var tag := "" if owner == "" else "（在%s麾下，需先撤兵）" % GameData.card_name(owner)
		popup.add_icon_item(_portrait_texture(who), GameData.card_name(who) + " " + GameData.star_text(int(GameData.card(who).get("star", 1))) + tag)
		popup.set_item_metadata(popup.item_count - 1, who)
		popup.set_item_disabled(popup.item_count - 1, owner != "")
	if popup.item_count == 0:
		popup.add_item("仓库暂无可派士兵")
		popup.set_item_disabled(0, true)
	popup.id_pressed.connect(_troop_pick.bind(popup))
	return menu


func _carry_menu() -> MenuButton:
	var menu := MenuButton.new()
	menu.name = "DeckCarryMenu"
	menu.text = "＋ 上阵"
	menu.disabled = GameState.carry.size() >= GameState.carry_max()
	var popup := menu.get_popup()
	for id in GameState.owned:
		var who := str(id)
		if int(GameState.owned[id]) <= 0 or not GameState.is_carryable(who) or GameState.in_carry(who):
			continue
		var owner := GameState.troop_owner(who)
		var tag := "" if owner == "" else "（在%s麾下，需先撤兵）" % GameData.card_name(owner)
		popup.add_icon_item(_portrait_texture(who), GameData.card_name(who) + " " + GameData.star_text(int(GameData.card(who).get("star", 1))) + tag)
		popup.set_item_metadata(popup.item_count - 1, who)
		popup.set_item_disabled(popup.item_count - 1, owner != "")
	if popup.item_count == 0:
		popup.add_item("没有可上阵的将牌，去商店买卡包")
		popup.set_item_disabled(0, true)
	popup.id_pressed.connect(_carry_pick.bind(popup))
	return menu


func _trait(id: String) -> Dictionary:
	if _traits != null and _traits.has_method("describe"):
		var raw: Variant = _traits.call("describe", id)
		if raw is Dictionary:
			return raw
	return {}


func _trait_tag(id: String) -> String:
	var ability := _trait(id)
	if not ability.is_empty():
		return str(ability.get("tag", ability.get("role", "辅助")))
	return "士兵素材" if GameState.is_troop(id) else "战力被动"


func _trait_description(id: String) -> String:
	var ability := _trait(id)
	if not ability.is_empty():
		return str(ability.get("description", ability.get("summary", "")))
	var text := GameData.effect_text(GameData.card(id))
	return "提供上阵战力，可同名合成并搭配装备。" if text in ["", "-"] else text


func _list_text(value: Variant) -> String:
	if value is Array or value is PackedStringArray:
		var parts := PackedStringArray()
		for item in value:
			parts.append(str(item))
		return " · ".join(parts)
	return str(value)


func _matches_filter(id: String) -> bool:
	if _filter == "雷印":
		return id in ["G04", "G05"] or _trait_tag(id).contains("雷")
	if _filter == "烈火":
		return id in ["G30", "G40"] or _trait_tag(id).contains("火")
	if _filter == "追击":
		return id in ["G20", "G24"] or _trait_tag(id).contains("追")
	return true


func _title(text: String, font_size: int) -> Label:
	var label := Art.label(text, font_size)
	label.add_theme_font_override("font", Art.title_font())
	return label


func _role_label(text: String, font_size: int = 13) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Art.panel(Color("f3e4c6"), 4, Color("baa178"), 1))
	var label := Art.label(text, font_size, Art.RED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _style_card(button: Button, star: int, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := Art.card_frame(star)
		box.border_color = Art.RED if selected or state in ["hover", "focus"] else Art.RULE
		box.set_border_width_all(2 if selected or state == "focus" else 1)
		box.bg_color = Color("fff5db") if state == "hover" else Art.PAPER_LIGHT
		if state == "pressed":
			box.bg_color = Color("ead9b7")
		box.shadow_size = 4 if selected else 2
		box.shadow_offset = Vector2(1, 2)
		button.add_theme_stylebox_override(state, box)


func _style_primary(button: Button, font_size: int = 21, padding: int = 9) -> void:
	button.add_theme_font_override("font", Art.title_font())
	button.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, Art.panel(Art.RED.darkened(0.08 if state != "normal" else 0.0), padding, Art.RED, 1))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Art.PAPER_LIGHT)


func _add_paper(panel: PanelContainer) -> void:
	var paper := TextureRect.new()
	paper.name = "DeckPaperBackdrop"
	paper.texture = Art.paper_background()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.modulate = Color(1, 1, 1, 0.43)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(paper)


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _wrap(text: String, font_size: int, color: Color = Art.INK) -> Label:
	var label := Art.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _select(id: String) -> void:
	_selected = id
	refresh()


func _change_tab(tab: String) -> void:
	_tab = tab
	refresh()


func _filter_changed(index: int) -> void:
	_filter = FILTERS[index]
	_render_pool()


func _search_changed(text: String) -> void:
	_query = text
	_render_pool()


func _focus_warehouse() -> void:
	_tab = "上阵"
	refresh()
	var search := find_child("DeckSearch", true, false) as LineEdit
	if search != null:
		search.grab_focus()


func _complete(ok: bool) -> void:
	if ok:
		refresh()
		changed.emit()


func _fuse() -> void:
	_complete(GameState.fuse_hero(_selected))


func _number(value: float) -> String:
	return "%.2f" % value if value < 10.0 and not is_equal_approx(value, roundf(value)) else GameState.fmt(value)


func _remove() -> void:
	_complete(GameState.carry_remove(_selected))


func _add() -> void:
	_complete(GameState.carry_add(_selected))


func _unequip(id: String) -> void:
	_complete(GameState.unequip_from(_selected, id))


func _troop_remove(id: String) -> void:
	_complete(GameState.troop_remove(_selected, id))


func _carry_pick(index: int, popup: PopupMenu) -> void:
	var id := str(popup.get_item_metadata(popup.get_item_index(index)))
	if GameState.carry_add(id):
		_selected = id
		_complete(true)


func _equip_pick(index: int, popup: PopupMenu) -> void:
	var id := str(popup.get_item_metadata(popup.get_item_index(index)))
	_complete(GameState.equip_to(_selected, id))


func _troop_pick(index: int, popup: PopupMenu) -> void:
	var id := str(popup.get_item_metadata(popup.get_item_index(index)))
	_complete(GameState.troop_put(_selected, id))
