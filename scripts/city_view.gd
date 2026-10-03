extends PanelContainer
class_name PaanCity
## 《拍案三国》全屏「城建」覆盖层（v0.9）。
##
## 挂机是奖励，不是开场背景板。城池 = 地基（只给槽位，本身不产钱）；
## 建筑 = 产钱实体（离线也产）。这里是你「一统荆州之后」真正经营的地方。
##   左栏：已克服的城池，按郡县分组 —— 点一处，中间看它的细节
##   中栏：选中城池的槽位网格（放建筑 / 强化建筑 / 拆除）
##   右栏：产出总览 + 建筑合成 + 仓库里躺着的建筑
##
## 与「大本营 / 荆州舆图」互斥，三者都是盖在桌面之上的覆盖层。

signal closed()                  # 收起
signal request_home()            # 回大本营

const START := 1
# ── S5「90 年代怀旧印刷」纸面配色 ────────────────────────────────
# 深色主题是给屏幕的，这套是给纸的：所有文字都是「纸上的墨」。
# 底色与 ui/panel.png 的主色对齐 —— 拿不到纹理时回退成纯色也不会跳色。
const BG_DIR := "res://assets/bg/"
const UI_DIR := "res://assets/ui/"
const PANEL_MARGIN := 14.0                       # ui/panel.png（源 112×112，边框 14px）
const PAPER := Color(0.933, 0.894, 0.796)        # 中性新闻纸（= ui/panel.png 主色）
const PAPER_ROW := Color(0.973, 0.945, 0.874)    # 行卡：纸上更亮的一小片
const PAPER_RULE := Color(0.580, 0.440, 0.240)   # 纸上墨线（赭墨）
const ACCENT := Color(0.72, 0.28, 0.12)          # 朱红 / 印泥
const INK := Color(0.17, 0.13, 0.10)             # 墨
const INK2 := Color(0.30, 0.24, 0.18)            # 次重墨
const DIM := Color(0.45, 0.39, 0.31)             # 淡墨
const GOOD := Color(0.13, 0.34, 0.21)            # 深墨绿
const WARN := Color(0.60, 0.37, 0.06)            # 赭黄
const BAD := Color(0.62, 0.17, 0.13)             # 朱
const COIN := Color(0.62, 0.44, 0.05)            # 金 → 深金
const ROUTE_COLOR := {
	"魏线": Color(0.15, 0.27, 0.52),
	"蜀线": Color(0.62, 0.18, 0.14),
	"吴线": Color(0.09, 0.37, 0.33),
	"群雄线": Color(0.52, 0.36, 0.06),
	"通用": Color(0.42, 0.40, 0.36),
	"起点": Color(0.42, 0.40, 0.36),
}

var _title: Label
var _stats: Label
var _list_box: VBoxContainer
var _detail_box: VBoxContainer
var _side_box: VBoxContainer
var _foot: Label
var _sel := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_bg_rect("city.png"))   # 古城图：城建就是荆州城的舆图底
	_build()


## 打开：先撑满再刷内容（隐藏中的全屏覆盖层锚点不结算，复用 reveal/home 的同一套修法）。
func open_city() -> void:
	_fit_to_parent()
	visible = true
	refresh()
	_fit_to_parent()


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


# =====================================================================
# 静态骨架
# =====================================================================
func _build() -> void:
	# 四周留缝：底图要能从纸边透出来，「摊在桌上」才成立
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 12)
	outer.add_theme_constant_override("margin_right", 12)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 12)
	add_child(outer)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	outer.add_child(vb)
	vb.add_child(_build_top())

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	vb.add_child(mid)

	# 左：城池列表
	var lp := PanelContainer.new()
	lp.custom_minimum_size = Vector2(300, 0)
	lp.add_theme_stylebox_override("panel", _paper_panel())
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(lscroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	lscroll.add_child(_list_box)
	mid.add_child(lp)

	# 中：选中城池细节
	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.add_theme_stylebox_override("panel", _paper_panel())
	var mscroll := ScrollContainer.new()
	mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mp.add_child(mscroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 7)
	mscroll.add_child(_detail_box)
	mid.add_child(mp)

	# 右：产出总览 + 合成 + 仓库
	var rp := PanelContainer.new()
	rp.custom_minimum_size = Vector2(340, 0)
	rp.add_theme_stylebox_override("panel", _paper_panel())
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rscroll)
	_side_box = VBoxContainer.new()
	_side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_box.add_theme_constant_override("separation", 6)
	rscroll.add_child(_side_box)
	mid.add_child(rp)

	# 底：提示
	var bot := PanelContainer.new()
	bot.custom_minimum_size = Vector2(0, 46)
	bot.add_theme_stylebox_override("panel", _paper_panel())
	_foot = _mk_label("", 13, INK2)
	bot.add_child(_foot)
	vb.add_child(bot)


func _build_top() -> Control:
	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(0, 58)
	top.add_theme_stylebox_override("panel", _paper_panel())
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	top.add_child(th)

	_title = _mk_label("城建", 22, ACCENT)
	th.add_child(_title)
	_stats = _mk_label("", 14, INK2)
	th.add_child(_stats)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp)

	var bh := Button.new()
	bh.text = "大本营"
	bh.pressed.connect(func(): request_home.emit())
	th.add_child(bh)

	var bc := Button.new()
	bc.text = "✕  收起"
	bc.pressed.connect(func(): closed.emit())
	th.add_child(bc)
	return top


# =====================================================================
# 刷新
# =====================================================================
func refresh() -> void:
	if _list_box == null:
		return
	_ensure_sel()
	_stats.text = "已克服 %d 处　·　建筑产出 %s / 小时　·　离线效率 %.0f%%　·　金币 %s" % [
		GameState.cleared_count(), GameState.fmt(GameState.gold_per_hour()),
		GameState.offline_efficiency() * 100.0, GameState.fmt(GameState.gold)]
	_fill_list()
	_fill_detail()
	_fill_side()
	_foot.text = "城池只给槽位（地基），建筑才是产钱实体 —— 离线也在产。" \
		+ "　·　强化的等级跟着建筑走，拆了就作废"


## 选中项兜底：没选 / 选的城池已不在列表里 -> 取第一处已克服城池。
func _ensure_sel() -> void:
	var list := _cleared_regions()
	if list.is_empty():
		_sel = -1
		return
	var found := false
	for r in list:
		if int(r["idx"]) == _sel:
			found = true
			break
	if not found:
		_sel = int(list[0]["idx"])


func _cleared_regions() -> Array:
	var out := []
	for r in GameData.regions:
		var i := int(r["idx"])
		if i != START and GameState.region_status(i) == "cleared":
			out.append(r)
	return out


# ---------------------------------------------------------------- 左：城池列表
func _fill_list() -> void:
	_clear(_list_box)
	_list_box.add_child(_mk_label("已克服的城池", 17, ACCENT))
	_list_box.add_child(_mk_label("按郡县分组。点一处看它的槽位与建筑。", 11, DIM))

	if not GameState.city_unlocked():
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _flat(WARN.lerp(PAPER, 0.86), WARN, 1, 6))
		var vb := VBoxContainer.new()
		p.add_child(vb)
		vb.add_child(_mk_label("城建尚未解锁", 14, WARN))
		vb.add_child(_mk_label(GameState.city_unlock_text(), 12, INK2))
		vb.add_child(_mk_label("先把前几桌拍完 —— 挂机是克服之后的奖励。", 11, DIM))
		_list_box.add_child(p)
		return

	var list := _cleared_regions()
	if list.is_empty():
		_list_box.add_child(_mk_label("还没有已克服的城池。", 12, WARN))
		return

	# 按郡县分组（保持 GameData.regions 的原始顺序）
	var groups := {}
	var order := []
	for r in list:
		var cty := str(r.get("county", "?"))
		if not groups.has(cty):
			groups[cty] = []
			order.append(cty)
		(groups[cty] as Array).append(r)

	for cty in order:
		_list_box.add_child(_mk_label(str(cty), 13, INK2))
		for r in groups[cty]:
			_list_box.add_child(_mk_city_row(r))


func _mk_city_row(r: Dictionary) -> Control:
	var idx := int(r["idx"])
	var arr := GameState.city_buildings(idx)
	var slots := GameState.city_slots(idx)
	var out := 0.0
	for k in range(arr.size()):
		out += GameState.building_output(idx, k)
	var sel := idx == _sel

	var b := Button.new()
	b.text = "%s　%d/%d 槽　%s/时" % [
		str(r.get("name", "?")), arr.size(), slots, GameState.fmt(out)]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 34)
	b.toggle_mode = true
	b.button_pressed = sel
	if sel:
		b.add_theme_color_override("font_color", ACCENT)
	b.pressed.connect(_on_pick.bind(idx))
	return b


# ---------------------------------------------------------------- 中：城池细节
func _fill_detail() -> void:
	_clear(_detail_box)
	if _sel <= 0:
		_detail_box.add_child(_mk_label("选一处城池", 17, ACCENT))
		if not GameState.city_unlocked():
			_detail_box.add_child(_mk_label(GameState.city_unlock_text(), 12, WARN))
		else:
			_detail_box.add_child(_mk_label("左侧还没有可经营的城池。", 12, DIM))
		return

	var r := GameData.region(_sel)
	var route := str(r.get("route", ""))
	var accent: Color = ROUTE_COLOR.get(route, Color.GRAY)

	# 标题卡
	var head := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.lerp(PAPER, 0.86)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	head.add_theme_stylebox_override("panel", sb)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 3)
	head.add_child(hv)
	hv.add_child(_mk_label("%s · %s" % [r.get("county", ""), r.get("name", "?")], 21, INK))
	hv.add_child(_mk_label("%s　·　%s　·　%s" % [route, r.get("faction", ""), r.get("chapter", "")],
		12, DIM))

	var arr := GameState.city_buildings(_sel)
	var slots := GameState.city_slots(_sel)
	var city_out := 0.0
	for k in range(arr.size()):
		city_out += GameState.building_output(_sel, k)
	hv.add_child(_mk_label("槽位 %d / %d　·　本城产出 %s / 小时" % [
		arr.size(), slots, GameState.fmt(city_out)], 13, COIN))
	_detail_box.add_child(head)

	# 槽位网格
	_detail_box.add_child(_mk_label("槽位（放建筑 / 强化 / 拆除）", 12, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for k in range(slots):
		grid.add_child(_mk_slot_card(_sel, k, k < arr.size()))
	_detail_box.add_child(grid)

	if arr.size() < slots:
		_detail_box.add_child(_mk_label("空槽 %d 个 —— 去开卡包拿建筑卡，或「合成」升级。" % (slots - arr.size()),
			11, WARN))


func _mk_slot_card(idx: int, slot: int, occupied: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not occupied:
		p.add_theme_stylebox_override("panel",
			_flat(PAPER, PAPER_RULE, 1, 6))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		p.add_child(vb)
		vb.add_child(_mk_label("空槽 · 第 %d 格" % (slot + 1), 12, DIM))
		vb.add_child(_mk_empty_slot_menu(idx))
		return p

	var barr := GameState.city_buildings(idx)
	if slot < 0 or slot >= barr.size():
		return p
	var bid := str(barr[slot])
	var bd := GameData.building(bid)
	var lv := GameState.building_lv(idx, slot)
	var maxed := GameState.building_lv_maxed(idx, slot)
	var cost := GameState.building_lv_cost(idx, slot)
	var afford := GameState.gold >= float(cost)
	var star := int(bd.get("star", 1))
	var out := GameState.building_output(idx, slot)
	var unique := bool(bd.get("unique", false))

	var border := accent_for_star(star)
	p.add_theme_stylebox_override("panel", _flat(border.lerp(PAPER, 0.86), border, 1, 6))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	p.add_child(vb)

	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	trow.add_child(_mk_label("%s %s" % [str(bd.get("name", "?")), GameData.star_text(star)], 15, INK))
	var tsp := Control.new()
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tsp)
	trow.add_child(_mk_label("Lv.%d/%d" % [lv, GameState.BUILDING_LV_MAX],
		12, ACCENT if not maxed else DIM))
	vb.add_child(trow)

	var eff := str(bd.get("effect", ""))
	if eff != "" and eff != "-":
		vb.add_child(_mk_label(eff, 11, DIM))
	vb.add_child(_mk_label("当前产出 %s / 小时" % GameState.fmt(out), 13, COIN))
	if unique:
		vb.add_child(_mk_label("★ 唯一建筑", 11, WARN))

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)

	var up := Button.new()
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if maxed:
		up.text = "强化已满"
		up.disabled = true
	else:
		up.text = "强化 Lv.%d　%d 金" % [lv + 1, cost]
		up.disabled = not afford
		up.pressed.connect(_on_upgrade.bind(idx, slot))
	brow.add_child(up)

	var rm := Button.new()
	rm.text = "拆除"
	rm.tooltip_text = "拆下来，卡回仓库（强化等级作废）"
	rm.pressed.connect(_on_remove.bind(idx, slot))
	brow.add_child(rm)
	vb.add_child(brow)
	return p


func _mk_empty_slot_menu(idx: int) -> Control:
	var menu := MenuButton.new()
	menu.text = "＋ 放置建筑"
	menu.custom_minimum_size = Vector2(0, 34)
	menu.disabled = not GameState.city_unlocked()
	var pop := menu.get_popup()
	pop.clear()
	var any := false
	for id in GameState.owned.keys():
		var c := GameData.card(str(id))
		if str(c.get("type", "")) != "建筑" or int(GameState.owned[id]) <= 0:
			continue
		any = true
		pop.add_item("%s %s　%s" % [str(c.get("name", "?")),
			GameData.star_text(int(c.get("star", 0))), str(c.get("effect", ""))])
		pop.set_item_metadata(pop.item_count - 1, str(id))
	if not any:
		pop.add_item("（没有建筑卡，去开卡包）")
		pop.set_item_disabled(0, true)
	pop.id_pressed.connect(func(pid: int):
		var md = pop.get_item_metadata(pid)
		if md != null:
			GameState.place_building(idx, str(md)))
	return menu


# ---------------------------------------------------------------- 右：产出 + 合成 + 仓库
func _fill_side() -> void:
	_clear(_side_box)

	# 产出总览
	_side_box.add_child(_mk_label("产出总览", 17, ACCENT))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		_flat(PAPER_ROW, PAPER_RULE, 1, 6))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 3)
	p.add_child(pv)
	pv.add_child(_mk_label("全场 %s 金币 / 小时" % GameState.fmt(GameState.gold_per_hour()), 16, COIN))
	pv.add_child(_mk_label("离线效率 %.0f%%　·　离线上限 %.0f 小时　·　每趟回来离线也结算" % [
		GameState.offline_efficiency() * 100.0, GameState.offline_cap_hours()], 12, INK2))
	var filled := 0
	var total_slots := 0
	for r in _cleared_regions():
		var idx2 := int(r["idx"])
		filled += GameState.city_buildings(idx2).size()
		total_slots += GameState.city_slots(idx2)
	pv.add_child(_mk_label("已放置建筑 %d / %d 槽" % [filled, total_slots], 12, INK))
	_side_box.add_child(p)

	# 建筑合成
	_side_box.add_child(_mk_label("", 6))
	_side_box.add_child(_mk_label("建筑合成", 17, ACCENT))
	_side_box.add_child(_mk_label("3 张同星建筑 + 金币 → 1 张高一星建筑（只在建筑卡里合成）。", 11, DIM))
	var any_synth := false
	for star in range(1, 6):
		var pool := GameState.building_star_pool(star)
		if pool.is_empty():
			continue
		any_synth = true
		_side_box.add_child(_mk_synth_row(star, pool.size()))
	if not any_synth:
		_side_box.add_child(_mk_label("仓库里还没有建筑卡。去商店开卡包。", 12, WARN))

	# 仓库建筑
	_side_box.add_child(_mk_label("", 6))
	_side_box.add_child(_mk_label("仓库里的建筑", 17, ACCENT))
	var rows := 0
	for id in GameState.owned.keys():
		var c := GameData.card(str(id))
		if c.is_empty() or str(c.get("type", "")) != "建筑":
			continue
		var cnt := int(GameState.owned[id])
		if cnt <= 0:
			continue
		rows += 1
		var row := HBoxContainer.new()
		var lb := _mk_label("%s %s ×%d" % [str(c.get("name", "?")),
			GameData.star_text(int(c.get("star", 0))), cnt], 12,
			INK2)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		row.add_child(_mk_label(str(c.get("effect", "")), 11, DIM))
		_side_box.add_child(row)
	if rows == 0:
		_side_box.add_child(_mk_label("（空）", 12, DIM))


func _mk_synth_row(star: int, have: int) -> Control:
	var need := 3
	var cost := GameState.synth_building_cost(star)
	var can := have >= need and GameState.gold >= float(cost)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		_flat(PAPER_ROW, PAPER_RULE, 1, 6))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	p.add_child(hb)

	hb.add_child(_mk_label("%s → %s" % [GameData.star_text(star), GameData.star_text(star + 1)],
		13, INK))
	var lb := _mk_label("%d/%d 张" % [have, need], 12, GOOD if have >= need else WARN)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lb)

	var b := Button.new()
	if star >= 6:
		b.text = "已到顶"
		b.disabled = true
	else:
		b.text = "合成 %d" % cost
		b.disabled = not can
		b.pressed.connect(_on_synth.bind(star))
	hb.add_child(b)
	return p


# =====================================================================
# 回调
# =====================================================================
func _on_pick(idx: int) -> void:
	_sel = idx
	refresh()


func _on_upgrade(idx: int, slot: int) -> void:
	if GameState.upgrade_building(idx, slot):
		refresh()


func _on_remove(idx: int, slot: int) -> void:
	GameState.remove_building(idx, slot)
	refresh()


func _on_synth(star: int) -> void:
	if GameState.synth_buildings(star) != "":
		refresh()


# =====================================================================
# 小工具（覆盖层自带一份，避免与 main.gd 互相依赖）
# =====================================================================
func accent_for_star(star: int) -> Color:
	match star:
		1: return Color(0.42, 0.40, 0.36)   # ★1 灰
		2: return Color(0.14, 0.36, 0.22)   # ★2 绿
		3: return Color(0.15, 0.27, 0.52)   # ★3 蓝
		4: return Color(0.36, 0.20, 0.46)   # ★4 紫
		5: return Color(0.58, 0.41, 0.05)   # ★5 金
		6: return Color(0.60, 0.20, 0.36)   # ★6 红
	return Color(0.42, 0.40, 0.36)


func _mk_label(text: String, size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _flat(bg: Color, border: Color, w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# =====================================================================
# S5 纸质感资源（覆盖层自带一份，避免与 main.gd 互相依赖）
# =====================================================================
var _tex_cache := {}


func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


## 纸九宫格。margin 必须**等于源纹理上的真实边框宽度** ——
## ⚠️ Godot 4 的 StyleBoxTexture 没有 texture_scale，九宫格的角是按源纹理 1:1 画的，
##    想改边框粗细只能重新生成对应尺寸的纹理，不能在运行时缩放。
func _paper(path: String, margin: float) -> StyleBox:
	var t := _tex(path)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(margin)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## 覆盖层的「纸面板」：一整块纸，内边距放宽（列里塞的东西比按钮里多）。
## 拿不到纹理就回退成暖纸纯色 —— 没图也能跑。
func _paper_panel() -> StyleBox:
	var sb := _paper(UI_DIR + "panel.png", PANEL_MARGIN)
	if sb != null:
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		return sb
	return _flat(PAPER, PAPER_RULE, 1, 0)


## 全幅背景贴图（旧屋书桌 / 古城图）
func _bg_rect(name: String) -> TextureRect:
	var bg := TextureRect.new()
	bg.texture = _tex(BG_DIR + name)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg

