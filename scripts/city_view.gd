extends Control
class_name PaanCity
const Art = preload("res://scripts/ui/print_art.gd")
const Traits = preload("res://scripts/building_traits.gd")
signal closed()
signal request_home()
signal request_map()
signal deploy(idx: int)
const START := 1
const INK := Color("2b211a")
const INK2 := Color("554634")
const DIM := Color("74654f")
const ACCENT := Color("9d3d2e")
const COIN := Color("927029")
var _title: Label
var _stats: Label
var _list_box: VBoxContainer
var _detail_box: VBoxContainer
var _side_box: HBoxContainer
var _combo_box: VBoxContainer
var _combo_yield: VBoxContainer
var _combo_actions: VBoxContainer
var _foot: Label
var _outcome_box: HBoxContainer
var _income: Label
var _city_picker: OptionButton
var _list_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _side_scroll: ScrollContainer
var _combo_scroll: ScrollContainer
var _tab_buttons: Dictionary = {}
var _sel := -1
var _slot := 0
var _warehouse_tab := "仓库"
var _content_key := ""
var _outcome_key := ""
var _toast: Label
var _layout_height := 0
var _refresh_after_drag := false

class BuildingArrow extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(76, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var ink := Color("ac3a27")
		var tip := maxf(7.0, size.y - 1.0)
		draw_line(Vector2(38, 0), Vector2(38, tip - 5), ink, 2)
		draw_colored_polygon(PackedVector2Array([Vector2(33, tip - 6), Vector2(43, tip - 6), Vector2(38, tip)]), ink)

class BuildingCard extends Button:
	var host: Control
	var building_id := ""
	var quality := 0
	var slot := -1
	func _get_drag_data(_position: Vector2) -> Variant:
		if building_id == "" or disabled:
			return null
		var preview := preload("res://scripts/ui/print_art.gd").image(building_id, Vector2(100, 100))
		set_drag_preview(preview)
		return {"kind": "building_card", "id": building_id, "quality": quality, "city": host._sel if slot >= 0 else -1, "slot": slot}
	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		if slot < 0 or not data is Dictionary or data.get("kind", "") != "building_card":
			return false
		if int(data.get("city", -1)) == host._sel:
			return true
		return building_id == "" and int(data.get("city", -1)) == -1 and not GameState.city_buildings(host._sel).has(str(data.get("id", "")))
	func _drop_data(_position: Vector2, data: Variant) -> void:
		if int(data.get("city", -1)) == host._sel:
			GameState.move_building_slot(host._sel, int(data["slot"]), slot)
			host._slot = slot
			host.refresh()
		else:
			host._on_place(str(data["id"]), int(data["quality"]), slot)

func _ready() -> void:
	theme = Art.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = Art.background("table")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_build()
	resized.connect(_on_layout_resized)
	refresh()

func open_city() -> void:
	_fit_to_parent()
	visible = true
	refresh()

func _fit_to_parent() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_parent() is Control:
		set_deferred("size", (get_parent() as Control).size)

func _build() -> void:
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 16)
	add_child(outer)
	var frame := _panel(10)
	outer.add_child(frame)
	var page := _column()
	page.add_theme_constant_override("separation", 8)
	frame.add_child(page)
	page.add_child(_build_top())
	var body := HBoxContainer.new()
	body.name = "BaseBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	page.add_child(body)
	var center := _panel(10)
	center.name = "CityManagement"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_detail_scroll = _scroll()
	_detail_scroll.resized.connect(_on_layout_resized)
	center.add_child(_detail_scroll)
	_detail_box = _column()
	_detail_scroll.add_child(_detail_box)
	var right := _panel(10)
	right.name = "BuildingLedger"
	right.custom_minimum_size.x = 330
	body.add_child(right)
	var ledger := _column()
	ledger.add_theme_constant_override("separation", 5)
	right.add_child(ledger)
	_combo_scroll = _scroll()
	ledger.add_child(_combo_scroll)
	_combo_box = _column()
	_combo_box.add_theme_constant_override("separation", 5)
	_combo_scroll.add_child(_combo_box)
	_combo_yield = _column()
	_combo_yield.name = "BuildingComboYieldDock"
	ledger.add_child(_combo_yield)
	_combo_actions = _column()
	_combo_actions.name = "BuildingComboActions"
	ledger.add_child(_combo_actions)
	var warehouse := _panel(8)
	warehouse.name = "BuildingWarehouse"
	warehouse.custom_minimum_size.y = 125
	page.add_child(warehouse)
	var stock := _column()
	warehouse.add_child(stock)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	stock.add_child(tabs)
	tabs.add_child(_label("建筑仓库", 23, ACCENT))
	for tab in ["仓库", "合成"]:
		var button := Button.new()
		button.name = "BuildingWarehouseTab" if tab == "仓库" else "BuildingSynthesisTab"
		button.text = "建筑卡" if tab == "仓库" else "同名合成"
		button.toggle_mode = true
		button.add_theme_font_override("font", Art.title_font())
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_stylebox_override("pressed", Art.panel(ACCENT, 8, ACCENT, 1))
		button.add_theme_color_override("font_pressed_color", Art.PAPER_LIGHT)
		button.pressed.connect(_on_tab.bind(tab))
		_tab_buttons[tab] = button
		tabs.add_child(button)
	_toast = _label("拖入空槽或点击卡牌装配 · 同城同名1张", 12, DIM)
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_toast)
	_side_scroll = _scroll()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_side_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stock.add_child(_side_scroll)
	_side_box = HBoxContainer.new()
	_side_box.add_theme_constant_override("separation", 9)
	_side_scroll.add_child(_side_box)
	var result := _panel(12)
	result.name = "BaseOutcome"
	result.custom_minimum_size.y = 68
	page.add_child(result)
	_outcome_box = HBoxContainer.new()
	_outcome_box.add_theme_constant_override("separation", 12)
	result.add_child(_outcome_box)

func _build_top() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 60
	row.add_theme_constant_override("separation", 12)
	row.add_child(Art.stamp("城", Vector2(43, 48)))
	var title := _column()
	_title = _label("基建 · 建筑构筑", 34)
	title.add_child(_title)
	title.add_child(_label("装配建筑卡，让产出接起来", 12, DIM))
	row.add_child(title)
	_list_box = _column()
	_list_box.name = "CityBook"
	_list_box.custom_minimum_size.x = 172
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_list_box)
	_stats = _label("", 15, INK2)
	row.add_child(_stats)
	var back := Button.new()
	back.name = "BaseReturnToCamp"
	back.text = "← 返回大本营"
	back.custom_minimum_size = Vector2(159, 44)
	back.pressed.connect(func(): request_home.emit())
	row.add_child(back)
	return row

func refresh() -> void:
	if _detail_box == null:
		return
	# 装配或布局变化可能在拖放回调内发出 changed；保留当前鼠标目标直到拖放结束。
	if get_viewport().gui_is_dragging():
		_refresh_after_drag = true
		return
	_refresh_after_drag = false
	_ensure_sel()
	var key := JSON.stringify([GameState.cities, GameState.city_quality, GameState.building_refined, _building_stock(), _sel, _slot, _warehouse_tab, GameState.bonus, _card_height()])
	if key != _content_key:
		_content_key = key
		var horizontal := _side_scroll.scroll_horizontal
		_fill_list()
		_fill_detail()
		_fill_combo()
		_fill_side()
		_side_scroll.set_deferred("scroll_horizontal", horizontal)
	_stats.text = "金币 %s" % GameState.fmt(GameState.gold)
	if is_instance_valid(_income):
		_income.text = "全城产出 %s / 分" % GameState.fmt(GameState.gold_per_hour() / 60.0)
	for tab in _tab_buttons:
		(_tab_buttons[tab] as Button).button_pressed = tab == _warehouse_tab
	var result_key := JSON.stringify([GameState.last_outcome, GameState.in_battle, GameState.battle_region])
	if result_key != _outcome_key:
		_outcome_key = result_key
		_fill_outcome()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _refresh_after_drag:
		call_deferred("refresh")

func _building_stock() -> Dictionary:
	var result := {}
	for building in GameData.buildings:
		var id := str(building["id"])
		result[id] = int(GameState.owned.get(id, 0))
	return result

func _cleared_regions() -> Array:
	var result := []
	for region in GameData.regions:
		if int(region["idx"]) != START and GameState.region_status(int(region["idx"])) == "cleared":
			result.append(region)
	return result

func _ensure_sel() -> void:
	var regions := _cleared_regions()
	if not GameState.city_unlocked() or regions.is_empty():
		_sel = -1
		_slot = 0
		return
	if not regions.any(func(region): return int(region["idx"]) == _sel):
		_sel = int(regions[0]["idx"])
	_slot = clampi(_slot, 0, GameState.city_slots(_sel) - 1)

func _fill_list() -> void:
	_clear(_list_box)
	_city_picker = OptionButton.new()
	_city_picker.name = "CitySelector"
	_city_picker.custom_minimum_size.y = 34
	for region in _cleared_regions():
		var idx := int(region["idx"])
		_city_picker.add_item(str(region.get("name", "?")), idx)
		if idx == _sel:
			_city_picker.select(_city_picker.item_count - 1)
	_city_picker.disabled = _sel < 0
	_city_picker.item_selected.connect(func(item): _on_pick(_city_picker.get_item_id(item)))
	_list_box.add_child(_city_picker)

func _fill_detail() -> void:
	_clear(_detail_box)
	if _sel < 0:
		_detail_box.add_child(_label("克服三处，开启建筑构筑", 25, ACCENT))
		_detail_box.add_child(Art.image("B06", Vector2(0, 170)))
		_detail_box.add_child(_wrapped(GameState.city_unlock_text(), 16, DIM))
		return
	var heading := _heading("筑", "已装配 %d / %d" % [GameState.city_used_slots(_sel), GameState.city_slots(_sel)])
	heading.add_child(_label("点击查看 · 拖动换位", 12, DIM))
	_detail_box.add_child(heading)
	var grid := GridContainer.new()
	grid.name = "CitySlots"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for slot in range(GameState.city_slots(_sel)):
		grid.add_child(_slot_card(slot))
	_detail_box.add_child(grid)
	_detail_box.add_child(_label("—  换卡即重算组合  ·  追加不触发追加  —", 11, DIM))

func _slot_card(slot: int) -> Control:
	var id := GameState._building_at(_sel, slot)
	var button := BuildingCard.new()
	button.host = self
	button.slot = slot
	button.building_id = id
	button.quality = GameState.building_quality(_sel, slot)
	button.name = "CitySlot%d" % slot
	button.custom_minimum_size = Vector2(180, _card_height())
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_slot.bind(slot))
	button.add_theme_stylebox_override("normal", _card_style(slot == _slot))
	button.add_theme_stylebox_override("hover", _card_style(true))
	button.add_theme_stylebox_override("pressed", _card_style(true))
	var inner := _card_interior(button)
	if id == "":
		var space := Control.new()
		space.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner.add_child(space)
		var cross := _label("＋", 44, Color("aa9676"))
		cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(cross)
		var caption := _label("装配建筑", 22, DIM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(caption)
		var hint := _label("拖入建筑卡 / 选择仓库卡", 11, DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(hint)
		var bottom_space := Control.new()
		bottom_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner.add_child(bottom_space)
	else:
		var scene := Art.scenic(id, Vector2(0, int(_card_height() * 0.58)))
		scene.name = "BuildingScene" + id
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scene.clip_contents = true
		inner.add_child(scene)
		var badge := PanelContainer.new()
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -4
		badge.offset_top = 4
		badge.add_theme_stylebox_override("panel", Art.panel(Color("f4e5c5"), 5, COIN, 1))
		badge.add_child(_label(Traits.quality_name(button.quality), 10, COIN))
		scene.add_child(badge)
		var title := HBoxContainer.new()
		title.add_theme_constant_override("separation", 7)
		inner.add_child(title)
		var name := _label(GameData.card_name(id), 24 if _card_height() >= 180 else 21)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_child(name)
		var stars := _label(GameData.star_text(int(GameData.building(id).get("star", 1))), 17 if _card_height() >= 180 else 15, COIN)
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.add_child(stars)
		inner.add_child(_wrapped(_short_effect(id, button.quality), 12, INK2))
		button.tooltip_text = "%s·%s\n%s" % [GameData.card_name(id), Traits.quality_name(button.quality), GameData.effect_text(GameData.building(id))]
	_ignore_mouse(inner)
	return button

func _fill_combo() -> void:
	_clear(_combo_box)
	_clear(_combo_yield)
	_clear(_combo_actions)
	_combo_box.add_child(_heading("链", "当前组合"))
	_income = _label("", 13, COIN)
	_income.name = "BaseIncome"
	_combo_box.add_child(_income)
	if _sel < 0:
		_combo_box.add_child(_wrapped("先克服城池，再装配建筑卡。", 14, DIM))
		return
	var combo := GameState.city_combo(_sel)
	var chain := VBoxContainer.new()
	chain.name = "BuildingComboChain"
	chain.add_theme_constant_override("separation", 2)
	_combo_box.add_child(chain)
	for source in combo["sources"]:
		_append_chain(chain, _chain_card(str(source["id"]), "基础产出 %s 金币 / 10秒" % _number(float(source["base"])), true))
	var equipped := GameState.city_buildings(_sel)
	for slot in range(equipped.size()):
		var id := str(equipped[slot])
		var rule: Dictionary = Traits.RULES.get(id, {})
		if rule.has("flat") or rule.has("tag_pct") or rule.has("all_pct") or rule.has("diverse_pct"):
			_append_chain(chain, _chain_card(id, _short_effect(id, GameState.building_quality(_sel, slot)), float(combo["normal"]) > 0.0))
	for repeat in combo["repeats"]:
		var subtotal := float(repeat["value"]) / (1.0 + float(combo["extra_pct"]))
		var description := "每%d次，额外结算 %s 金币" % [int(repeat["period"]), _number(subtotal)] if repeat["active"] else "等待产出来源 / 所需类型"
		_append_chain(chain, _chain_card(str(repeat["id"]), description, bool(repeat["active"])))
	var functions := _column()
	functions.add_theme_constant_override("separation", 4)
	for slot in range(equipped.size()):
		var id := str(equipped[slot])
		var rule: Dictionary = Traits.RULES.get(id, {})
		if rule.has("extra_pct"):
			_append_chain(chain, _chain_card(id, _short_effect(id, GameState.building_quality(_sel, slot)), combo["repeats"].any(func(repeat): return bool(repeat["active"]))))
		elif id != "" and rule.is_empty():
			functions.add_child(_chain_card(id, _short_effect(id, GameState.building_quality(_sel, slot)), true))
	if functions.get_child_count() > 0:
		_combo_box.add_child(_label("全局助力", 14, COIN))
		_combo_box.add_child(functions)
	else:
		functions.free()
	var summary := _panel(7)
	summary.name = "BuildingComboYield"
	var total := _column()
	total.add_theme_constant_override("separation", 4)
	summary.add_child(total)
	var preview := _income_preview(combo)
	var cycle := _label("组合循环 · 每%d秒" % int(preview["seconds"]), 13, INK2)
	cycle.name = "BuildingComboPeriod"
	total.add_child(cycle)
	var formula := _label(str(preview["formula"]), 19, ACCENT)
	formula.name = "BuildingComboFormula"
	formula.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	formula.tooltip_text = str(preview["formula"])
	total.add_child(formula)
	var ribbon := PanelContainer.new()
	ribbon.name = "BuildingComboIncomeRibbon"
	ribbon.add_theme_stylebox_override("panel", Art.panel(Color("f1ddba"), 5, Color("c59d6d"), 1))
	var per_minute := float(combo["hourly"]) / 60.0
	var displayed_income := _number(per_minute) if per_minute < 10000.0 else GameState.fmt(per_minute)
	var average := _label("平均产出 %s 金币 / 分" % displayed_income, 22, ACCENT)
	average.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	average.tooltip_text = average.text
	ribbon.add_child(average)
	total.add_child(ribbon)
	_combo_yield.add_child(summary)
	if float(combo["normal"]) <= 0:
		var missing := _label("缺少产出来源：需要搭配产出卡。", 12, DIM)
		missing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_combo_yield.add_child(missing)
	else:
		var note := "追加不再触发追加。"
		if float(combo["extra_pct"]) > 0 and not combo["repeats"].is_empty():
			note = "追加总倍率 ×%s；追加不再触发追加。" % _number(1.0 + float(combo["extra_pct"]))
		_combo_yield.add_child(_label(note, 11, DIM))
	_combo_actions.add_child(_selected_slot())

func _income_preview(combo: Dictionary) -> Dictionary:
	# 与真实结算共用 payout；按完整周期取样，合成品相与全局助力均计入。
	var cycles := 1
	for repeat in combo["repeats"]:
		if not bool(repeat["active"]):
			continue
		var period := int(repeat["period"])
		var a := cycles
		var b := period
		while b != 0:
			var remainder := a % b
			a = b
			b = remainder
		cycles = int(float(cycles * period) / maxi(1, a))
	var local_hourly := float(combo["average"]) * 360.0
	var global_scale := float(combo["hourly"]) / local_hourly if local_hourly > 0 else 1.0
	var amount := Traits.payout(combo, 0, cycles) * global_scale
	var formula := ""
	if cycles <= 5:
		var payouts := PackedStringArray()
		for step in range(cycles):
			payouts.append(_number(Traits.payout(combo, step, 1) * global_scale))
		formula = " + ".join(payouts)
		formula += " = %s 金币" % _number(amount) if cycles > 1 else " 金币"
	else:
		var basic := float(combo["normal"]) * cycles * global_scale
		formula = "基础 %s + 追加 %s = %s 金币" % [_number(basic), _number(amount - basic), _number(amount)]
	return {"seconds": int(cycles * Traits.CYCLE), "formula": formula}

func _selected_slot() -> Control:
	var panel := _panel(7)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var id := GameState._building_at(_sel, _slot)
	if id == "":
		var empty := _label("空槽 %d · 选择仓库卡装配" % (_slot + 1), 14, DIM)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(empty)
		return panel
	var quality := GameState.building_quality(_sel, _slot)
	var column := _column()
	column.add_theme_constant_override("separation", 1)
	row.add_child(column)
	column.add_child(_label(GameData.card_name(id), 19))
	column.add_child(_label("%s · 数值 ×%.2f" % [Traits.quality_name(quality), Traits.quality_mult(quality)], 10, DIM))
	var remove := Button.new()
	remove.name = "RemoveSelectedBuilding"
	remove.text = "卸下" + GameData.card_name(id)
	remove.custom_minimum_size.y = 30
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove.add_theme_font_override("font", Art.title_font())
	remove.add_theme_font_size_override("font_size", 18)
	remove.pressed.connect(_on_remove.bind(_sel, _slot))
	row.add_child(remove)
	return panel

func _fill_side() -> void:
	_clear(_side_box)
	if _warehouse_tab == "合成":
		_toast.text = "3张同名同品相 → 1张更高品相 · 只吃仓库卡，不扣金币"
		for building in GameData.buildings:
			var id := str(building["id"])
			for quality in [0, 1]:
				if GameState.building_stock(id, quality) > 0:
					_side_box.add_child(_fusion_card(id, quality))
	else:
		_toast.text = "30种建筑 · 拖入空槽或点击装配 · 已装配卡受保护"
		for building in GameData.buildings:
			var id := str(building["id"])
			for quality in [2, 1, 0]:
				if GameState.building_stock(id, quality) > 0:
					_side_box.add_child(_warehouse_card(id, quality))
	if _side_box.get_child_count() == 0:
		_side_box.add_child(_label("仓库暂无可用材料；去商店开建筑卡包，或卸下建筑。", 15, DIM))

func _warehouse_card(id: String, quality: int) -> Control:
	var button := BuildingCard.new()
	button.host = self
	button.building_id = id
	button.quality = quality
	button.name = "PlaceBuilding" + id + ("Q%d" % quality if quality > 0 else "")
	button.custom_minimum_size = Vector2(184, 83)
	button.disabled = _sel < 0 or GameState.city_used_slots(_sel) >= GameState.city_slots(_sel) or GameState.city_buildings(_sel).has(id)
	button.tooltip_text = GameData.effect_text(GameData.building(id)) + ("\n同城已装配；可在合成页升级仓库副本" if _sel >= 0 and GameState.city_buildings(_sel).has(id) else "\n点击或拖入空槽装配")
	button.pressed.connect(_on_place.bind(id, quality, -1))
	button.add_theme_stylebox_override("normal", _card_style(false))
	button.add_theme_stylebox_override("hover", _card_style(true))
	button.add_theme_stylebox_override("pressed", _card_style(true))
	button.add_theme_stylebox_override("disabled", _card_style(false))
	if button.disabled:
		button.modulate = Color("c9bca4")
	var inner := _card_interior(button)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	inner.add_child(row)
	var scene := Art.image(id, Vector2(67, 64))
	scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene.clip_contents = true
	row.add_child(scene)
	var words := _column()
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	words.add_child(_label(GameData.card_name(id), 20))
	words.add_child(_label(GameData.star_text(int(GameData.building(id).get("star", 1))), 13, COIN))
	words.add_child(_label("%s ×%d" % [Traits.quality_name(quality), GameState.building_stock(id, quality)], 12, DIM))
	_ignore_mouse(inner)
	return button

func _fusion_card(id: String, quality: int) -> Control:
	var panel := _panel(7)
	panel.custom_minimum_size.x = 238
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var scene := Art.image(id, Vector2(60, 72))
	scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene.clip_contents = true
	row.add_child(scene)
	var column := _column()
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	var have := GameState.building_stock(id, quality)
	var name := _label(GameData.card_name(id) + "  " + GameData.star_text(int(GameData.building(id).get("star", 1))), 18)
	column.add_child(name)
	column.add_child(_label("%s×3 → %s×1" % [Traits.quality_name(quality), Traits.quality_name(quality + 1)], 12, COIN))
	var button := Button.new()
	button.name = "FuseBuilding%sQ%d" % [id, quality]
	button.text = "合成 · 材料 %d / 3" % have if have >= 3 else "还差%d张%s" % [3 - have, Traits.quality_name(quality)]
	button.disabled = have < 3
	button.add_theme_font_override("font", Art.title_font())
	button.add_theme_font_size_override("font_size", 16)
	button.tooltip_text = "数值 ×%.2f → ×%.2f · 名称、星级与技能保留\n只消耗仓库材料，已装配卡受到保护。" % [Traits.quality_mult(quality), Traits.quality_mult(quality + 1)]
	button.pressed.connect(_on_fuse.bind(id, quality))
	column.add_child(button)
	return panel


func _fill_outcome() -> void:
	_clear(_outcome_box)
	var result: Dictionary = GameState.last_outcome
	var idx := int(result.get("region", 0))
	var valid := idx > 0 and not GameData.region(idx).is_empty() and str(result.get("result", "")) in ["cleared", "settled"]
	var headline := "建筑替你积累，整备好再出发"
	var detail := "装配建筑形成组合；卸下保留品相。同名合成只消耗仓库卡。"
	var mark := "营"
	var primary_text := "返回大本营"
	var primary: Callable = func(): request_home.emit()
	var secondary_text := "大地图"
	var secondary: Callable = func(): request_map.emit()
	if GameState.in_battle:
		headline = "%s · 本轮还在进行" % GameData.region(GameState.battle_region).get("name", "牌桌")
		detail = "剩余 %.1f 秒 · 已赚 %s 金币；返回牌桌继续拍击。" % [GameState.round_seconds_left, GameState.fmt(GameState.run_gold)]
	elif valid:
		mark = "财"
		headline = "%s · 本轮已收钱" % GameData.region(idx).get("name", "?")
		detail = "收获 %s 金币　·　%d 次拍击　·　清桌 %d 次" % [GameState.fmt(float(result.get("gold", 0))), int(result.get("slaps", 0)), int(result.get("tables_flipped", 0))]
		primary_text = "再来一轮"
		primary = _on_deploy.bind(idx)
	_outcome_box.add_child(Art.stamp(mark, Vector2(43, 52)))
	var words := _column()
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(_label(headline, 28))
	_foot = _wrapped(detail, 13, INK2)
	words.add_child(_foot)
	_outcome_box.add_child(words)
	var action := Button.new()
	action.name = "BaseOutcomePrimary"
	action.text = primary_text
	action.custom_minimum_size = Vector2(158, 48)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action.add_theme_font_override("font", Art.title_font())
	action.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed"]:
		action.add_theme_stylebox_override(state, Art.panel(Art.RED, 12, Art.RED, 1))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		action.add_theme_color_override(state, Art.PAPER_LIGHT)
	action.pressed.connect(primary)
	_outcome_box.add_child(action)
	if secondary.is_valid():
		var other := Button.new()
		other.name = "BaseOutcomeSecondary"
		other.text = secondary_text
		other.custom_minimum_size = Vector2(120, 48)
		other.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		other.add_theme_font_override("font", Art.title_font())
		other.add_theme_font_size_override("font_size", 21)
		other.pressed.connect(secondary)
		_outcome_box.add_child(other)



func _on_pick(idx: int) -> void:
	_sel = idx
	_slot = 0
	refresh()

func _on_slot(slot: int) -> void:
	_slot = slot
	refresh()

func _on_tab(tab: String) -> void:
	_warehouse_tab = tab
	_side_scroll.scroll_horizontal = 0
	refresh()

func _on_place(id: String, quality: int = 0, target: int = -1) -> void:
	if target < 0 and GameState._building_at(_sel, _slot) == "":
		target = _slot
	if GameState.place_building(_sel, id, quality, target):
		_slot = GameState.city_buildings(_sel).find(id)
	refresh()

func _on_remove(idx: int, slot: int) -> void:
	GameState.remove_building(idx, slot)
	refresh()

func _on_fuse(id: String, quality: int) -> void:
	GameState.fuse_building(id, quality)
	refresh()

func _on_deploy(idx: int) -> void:
	if GameState.region_status(idx) == "available":
		deploy.emit(idx)
	else:
		request_map.emit()

func _on_layout_resized() -> void:
	var height := _card_height()
	if height != _layout_height:
		_layout_height = height
		refresh()

func _card_height() -> int:
	var height := size.y if size.y > 0 else get_viewport_rect().size.y
	var card_height := int((height - 420.0) * 0.5)
	if is_instance_valid(_detail_scroll) and _detail_scroll.size.y > 0:
		card_height = mini(card_height, int((_detail_scroll.size.y - 76.0) * 0.5))
	return clampi(card_height, 145, 230)

func _chain_card(id: String, description: String, active: bool) -> Control:
	var button := Button.new()
	button.name = "ComboBuilding" + id
	var compact := _card_height() < 165
	button.custom_minimum_size.y = 41 if compact else 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", Art.panel(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", Art.panel(Art.PAPER, 0, Art.RULE, 1))
	button.add_theme_stylebox_override("pressed", Art.panel(Art.PAPER, 0, ACCENT, 1))
	button.pressed.connect(func():
		var slot := GameState.city_buildings(_sel).find(id)
		if slot >= 0:
			_on_slot(slot))
	button.tooltip_text = GameData.effect_text(GameData.building(id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(row)
	var image := Art.scenic(id, Vector2(76, 41 if compact else 46))
	image.clip_contents = true
	row.add_child(image)
	var words := _column()
	words.add_theme_constant_override("separation", 1)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	words.add_child(_label(GameData.card_name(id), 18 if compact else 21, INK if active else DIM))
	words.add_child(_wrapped(description, 10 if compact else 11, INK2 if active else DIM))
	_ignore_mouse(row)
	return button

func _append_chain(chain: VBoxContainer, card: Control) -> void:
	if chain.get_child_count() > 0:
		var arrow := BuildingArrow.new()
		arrow.name = "BuildingComboArrow%d" % chain.get_child_count()
		if _card_height() < 165:
			arrow.custom_minimum_size.y = 10
		chain.add_child(arrow)
	chain.add_child(card)

func _short_effect(id: String, quality: int) -> String:
	var rule: Dictionary = Traits.RULES.get(id, {})
	var scale := Traits.quality_mult(quality)
	if float(rule.get("base", 0.0)) > 0.0:
		if rule.has("period"):
			return "10秒产%s金币 · 三类型追加%s%%" % [_number(float(rule["base"]) * scale), _number(float(rule["repeat"]) * scale * 100.0)]
		return "每10秒产出 %s 金币" % _number(float(rule["base"]) * scale)
	if rule.has("flat"):
		return "%s每次产出 +%s 金币" % [str(rule.get("target", "全部")), _number(float(rule["flat"]) * scale)]
	if rule.has("tag_pct"):
		return "%s基础产出 +%s%%" % [str(rule.get("target", "全部")), _number(float(rule["tag_pct"]) * scale * 100.0)]
	if rule.has("all_pct"):
		return "同城基础产出 +%s%%" % _number(float(rule["all_pct"]) * scale * 100.0)
	if rule.has("diverse_pct"):
		return "每种产出类型，基础收益 +%s%%" % _number(float(rule["diverse_pct"]) * scale * 100.0)
	if rule.has("extra_pct"):
		return "追加结算收益 ×%s" % _number(1.0 + float(rule["extra_pct"]) * scale)
	if rule.has("period"):
		var target := "" if str(rule.get("target", "全部")) == "全部" else str(rule["target"])
		return "每%d次%s产出，追加 %s%%" % [int(rule["period"]), target, _number(float(rule["repeat"]) * scale * 100.0)]
	var building := GameData.building(id)
	var amount := _number(float(building.get("effect_value", 0.0)) * scale)
	match str(building.get("effect_type", "none")):
		"combat_power_pct": return "卡组战力 +%s%%" % amount
		"pack_price_pct": return "卡包价格 −%s%%" % amount
		"offline_hours": return "离线时长 +%s 小时" % amount
		"stamina_flat": return "每轮时长 +%s 秒" % _number(float(building.get("effect_value", 0.0)) * scale * 2.0)
		"building_output_pct": return "全城建筑收益 +%s%%" % amount
		"equip_pct": return "装备效果 +%s%%" % amount
		"ransom_pct": return "招降成本 −%s%%" % amount
	return GameData.effect_text(building)

func _number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func _card_style(selected: bool) -> StyleBox:
	var style := Art.panel(Art.PAPER_LIGHT, 7, ACCENT if selected else Color("c5a479"), 2 if selected else 1)
	style.grain = Art.paper_background()
	style.shadow_color = Color(0.17, 0.08, 0.03, 0.14)
	style.shadow_size = 2
	style.shadow_offset = Vector2(1, 2)
	return style

func _panel(padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := Art.panel(Art.PAPER_LIGHT, padding, Art.RED, 1)
	style.grain = Art.paper_background()
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _card_interior(button: Control) -> VBoxContainer:
	var box := _column()
	button.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 9
	box.offset_top = 7
	box.offset_right = -9
	box.offset_bottom = -7
	box.add_theme_constant_override("separation", 3)
	return box

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _scroll() -> ScrollContainer:
	var node := ScrollContainer.new()
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node

func _column() -> VBoxContainer:
	var node := VBoxContainer.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_constant_override("separation", 7)
	return node

func _label(text: String, font_size: int = 14, color: Color = INK) -> Label:
	var label := Art.label(text, font_size, color)
	if font_size >= 17:
		label.add_theme_font_override("font", Art.title_font())
	return label

func _wrapped(text: String, font_size: int = 14, color: Color = INK) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _heading(mark: String, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Art.stamp(mark, Vector2(30, 34)))
	row.add_child(_label(title, 25))
	return row

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
