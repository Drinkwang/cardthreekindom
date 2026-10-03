extends Control
## 《拍案三国》单界面 —— 桌面拍卡（v0.8「局内刷 + 局外升级」）。
##
## 主界面就是一张桌子：卡牌正面朝上、歪歪斜斜散在桌面上，等你来拍。
##   单击         = 轻拍（×1.0 伤害，1 耐力）
##   按住拖拽划过 = 重拍（×2.5 伤害，每张 2 耐力）—— 一巴掌扇过去，一排卡一起翻
## 血量拍光的卡会当场翻面转走，收进你的卡组。
##
## 耐力耗尽 -> 强制结算 -> 弹出「大本营」覆盖层（升级树 / 上阵 / 装备 / 出征）。
## 拍翻整桌 -> 弹出「荆州舆图」覆盖层（挑下一桌）。
## 卡包 / 招降 / 合成 / 城建 / 路线 / 收藏 收进右侧抽屉，不抢桌面。
## 未来"背面朝上"的伏兵牌，只需要在 _mk_card 里不画卡面即可（见 TODO 注释）。

# 路线色。S5 起换成**纸上能压住的深色版** —— 原来的亮色是给深色主题的，
# 落在米色纸上（星级、图例、路线行）对比度只有 2~3:1，读不动。
const ROUTE_COLOR := {
	"魏线": Color(0.15, 0.27, 0.52),
	"蜀线": Color(0.62, 0.18, 0.14),
	"吴线": Color(0.09, 0.37, 0.33),
	"群雄线": Color(0.52, 0.36, 0.06),
	"通用": Color(0.42, 0.40, 0.36),
	"起点": Color(0.42, 0.40, 0.36),
	"现实线": Color(0.37, 0.21, 0.47),
}

const CARD_SIZE := Vector2(106, 146)             # 初始/保底尺寸
const CARD_MIN_W := 92.0                         # 牌张数多时最小宽度
const CARD_MAX_W := 200.0                        # 桌上只有两三张时最大宽度
const CARD_RATIO := 1.38                         # 高 / 宽
const CARD_BG := Color(0.945, 0.925, 0.878)      # 纸牌本色
const CARD_INK := Color(0.13, 0.12, 0.11)        # 卡面字色
const CARD_DIM := Color(0.42, 0.40, 0.37)        # 卡面次级字色
const TABLE_BG := Color(0.115, 0.135, 0.125)     # 桌布
const LOG_MAX := 3
const DRAG_THRESHOLD := 7.0                       # 超过这个位移才算"拖拽"，否则算单击
const SAMPLE_STEP := 6.0                          # 拖拽轨迹采样间隔（像素）
# 与 GameState 保持同步（避免通过 autoload 实例取常量）
const START_REGION := 1
const HERO_ALWAYS := "I01"          # 主角卡：固定上阵、不占携带位、不可卸下
const HEAVY_MULT := 2.5
const HEAVY_STAMINA := 2

# ── S5「90 年代怀旧印刷」美术资源 ────────────────────────────────────
const BG_DIR := "res://assets/bg/"
const UI_DIR := "res://assets/ui/"
const TEX_DIR := "res://assets/tex/"
const CARD_DIR := "res://assets/cards/"
# ⚠️ 九宫格边距必须等于源纹理上的**真实**边框宽度（纹理就是按这些尺寸生成的）
const FRAME_MARGIN := 16.0      # cardface_*.png（源 128×176，边框 16px）
const PANEL_MARGIN := 14.0      # panel.png（源 112×112，边框 14px）
const BTN_MARGIN := 6.0         # btn_*.png（源 40×40，边框 6px）
                                # ⚠️ 按钮边框不能大：顶栏按钮只有 ~28px 高，
                                #    九宫格的角是 1:1 画的，边框一大按钮横向就被撑爆（顶栏会溢出屏）
# 纸面上的印墨字色（换成纸底 UI 后，字必须由浅转深，否则看不见）
const INK := Color(0.17, 0.13, 0.10)
const INK_DIM := Color(0.40, 0.34, 0.27)
const INK_SOFT := Color(0.53, 0.46, 0.37)
# 纸色（= ui/panel.png 主色）。原来用 accent.darkened(0.74) 做"强调底色"，
# 那是给深色主题的；纸面上必须反过来 —— 往纸色提亮，再用 accent 描边。
const PAPER := Color(0.933, 0.894, 0.796)

# ---------- 桌面 ----------
var _table: Control
var _cards: Array = []                            # 与 GameState.battle 一一对应
var _shown_gen := -1
var _banner: Label

# ---------- 拖拽状态 ----------
var _mouse_down := false                          # 左键是否按住（决定要不要跟踪轨迹）
var _press_index := -1
var _press_pos := Vector2.ZERO
var _drag_last := Vector2.ZERO
var _is_dragging := false
var _drag_hit := {}

# ---------- 顶栏 ----------
var _lbl_region: Label
var _lbl_stamina: Label
var _lbl_dmg: Label
var _lbl_gold: Label
var _lbl_progress: Label
var _lbl_hint: Label
var _stamina_bar: ProgressBar
var _btn_drawer: Button
var _btn_retreat: Button

# ---------- 抽屉 / 舆图 / 翻牌 ----------
var _drawer: PanelContainer
var _drawer_open := false
var _tabs: TabContainer
var _shop_boxes := {}

var _btn_map: Button
var _btn_home: Button
var _btn_city: Button
var _map_layer: Control
var _map_view: PaanMapView
var _map_left: VBoxContainer
var _map_right: VBoxContainer
var _map_title: Label
var _map_progress: Label
var _map_legend: Label
var _map_foot: Label
var _sel_idx := -1

var _home: PaanHome
var _city: PaanCity

var _reveal: PaanReveal

var _log_lbl: Label
var _log_lines: Array = []
var _was_in_battle := false
var _offline_shown := false

# ---------- 底部上阵条（v1.0）----------
# 用户要求：「带领的武将在 UI 下方」「玩家可以查看已有卡池的将兵，移动到 UI 下方，拖过去」。
# ⚠️ 主界面铁律 = 第一眼必须看到满桌的牌 —— 所以卡池**默认收起**，只留一条窄上阵栏常驻。
var _bar: PanelContainer
var _slot_row: HBoxContainer
var _lbl_bar: Label
var _btn_pool: Button
var _pool: PanelContainer
var _pool_box: HBoxContainer
var _pool_open := false
var _bar_sig := ""                                # 上阵名单的指纹，变了才重建槽位
var _pool_sig := ""                               # 卡池内容的指纹，变了才重建牌
const POOL_H := 130.0                             # 卡池条高度（展开时才占位；含横向滚动条）
const SLOT_W := 74.0                              # 单个上阵槽宽度


func _ready() -> void:
	_build()
	GameState.changed.connect(_on_changed)
	GameState.map_changed.connect(_on_map_changed)
	GameState.shop_changed.connect(_refresh_shop)
	GameState.message.connect(_append_log)
	_on_map_changed()
	_refresh_shop()
	_on_changed()
	if GameState.offline_report != "" and not _offline_shown:
		_offline_shown = true
		_append_log(GameState.offline_report)


# =====================================================================
# 静态布局
# =====================================================================
func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# S5：整棵子树的按钮统一换成印刷纸按钮（已在按钮上加过 override 的除外）
	var th := _paper_button_theme()
	if th != null:
		theme = th

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_topbar())

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	mid.add_child(_build_table())
	_drawer = _build_drawer()
	mid.add_child(_drawer)
	root.add_child(mid)

	_pool = _build_pool()
	root.add_child(_pool)
	root.add_child(_build_bottombar())

	# 覆盖层：舆图 / 大本营 / 城建（在下），翻牌揭示（最上）
	_map_layer = _build_map_layer()
	add_child(_map_layer)
	_home = PaanHome.new()
	_home.deploy.connect(_on_home_deploy)
	_home.request_map.connect(_open_map)
	_home.request_city.connect(_open_city)
	_home.closed.connect(_close_home)
	add_child(_home)
	_home.visible = false
	_city = PaanCity.new()
	_city.closed.connect(_close_city)
	_city.request_home.connect(_open_home)
	add_child(_city)
	_city.visible = false
	_reveal = PaanReveal.new()
	add_child(_reveal)

	_set_drawer(false)


func _build_topbar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 54)
	panel.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.30,
			Color(0.16, 0.16, 0.17), Color(0.30, 0.30, 0.32), 1, 0))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	panel.add_child(hb)

	_lbl_region = _mk_label("", 17, INK)
	hb.add_child(_lbl_region)
	hb.add_child(_vsep())

	_stamina_bar = ProgressBar.new()
	_stamina_bar.custom_minimum_size = Vector2(130, 22)
	_stamina_bar.show_percentage = false
	hb.add_child(_stamina_bar)
	_lbl_stamina = _mk_label("耐力", 12)
	hb.add_child(_lbl_stamina)
	hb.add_child(_vsep())

	_lbl_dmg = _mk_label("", 12)
	hb.add_child(_lbl_dmg)
	hb.add_child(_vsep())

	# 金币与挂机产出合成一格，给顶栏省出空间（大本营 / 舆图 / 撤退 都要塞在这一行）
	_lbl_gold = _mk_label("", 12)
	hb.add_child(_lbl_gold)
	hb.add_child(_vsep())

	_lbl_progress = _mk_label("", 12)
	hb.add_child(_lbl_progress)

	_btn_retreat = Button.new()
	_btn_retreat.text = "撤退"
	_btn_retreat.tooltip_text = "这一趟不打了，把已打出的战果换成金币，回大本营"
	_btn_retreat.pressed.connect(func(): GameState.retreat())
	_btn_retreat.visible = false
	hb.add_child(_btn_retreat)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	_btn_home = Button.new()
	_btn_home.text = "大本营"
	_btn_home.pressed.connect(_open_home)
	hb.add_child(_btn_home)

	_btn_city = Button.new()
	_btn_city.text = "城建"
	_btn_city.tooltip_text = "全屏城建：已克服的城池里放建筑、强化、合成"
	_btn_city.pressed.connect(_open_city)
	hb.add_child(_btn_city)

	_btn_map = Button.new()
	_btn_map.text = "舆图"
	_btn_map.tooltip_text = "打开荆州舆图（挑下一桌）"
	_btn_map.pressed.connect(_open_map)
	hb.add_child(_btn_map)

	_btn_drawer = Button.new()
	_btn_drawer.text = "商店"
	_btn_drawer.pressed.connect(func(): _set_drawer(not _drawer_open))
	hb.add_child(_btn_drawer)

	var btn_reset := Button.new()
	btn_reset.text = "重开"
	btn_reset.pressed.connect(func():
		GameState.hard_reset()
		_close_home()
		_close_map()
		_close_city()
		_log_lines.clear()
		_render_log())
	hb.add_child(btn_reset)
	return panel


func _build_table() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 牌桌底：优先铺 S5 的「旧木课桌」实拍底图；没图就回退原来的深色桌布
	if _tex(BG_DIR + "table.png") != null:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		panel.add_child(_bg_rect("table.png"))
	else:
		panel.add_theme_stylebox_override("panel", _flat(TABLE_BG, Color(0.24, 0.28, 0.26), 1, 0))

	var layer := Control.new()
	layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.clip_contents = false
	layer.set_meta("paan_table", true)
	layer.gui_input.connect(_on_table_input)
	layer.resized.connect(_layout_cards)
	panel.add_child(layer)
	_table = layer

	_banner = _mk_label("", 20, Color(0.92, 0.90, 0.84))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.visible = false
	layer.add_child(_banner)
	return panel


func _build_drawer() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(392, 0)
	panel.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.30,
			Color(0.15, 0.15, 0.16), Color(0.30, 0.30, 0.32), 1, 0))
	panel.clip_contents = true

	_tabs = TabContainer.new()
	panel.add_child(_tabs)
	for nm in ["卡包", "招降", "合成", "城建", "路线", "收藏"]:
		var body := VBoxContainer.new()
		body.name = nm
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 4)
		scroll.add_child(box)
		_shop_boxes[nm] = box
		_tabs.add_child(body)

	return panel


func _build_bottombar() -> Control:
	## v1.0：底部常驻「出征」栏 + 操作提示。原来只有一行提示，
	## 现在上面加一行上阵槽位 —— 玩家一眼能看到自己带了哪些将兵（用户要求）。
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 84)
	panel.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.26,
			Color(0.16, 0.16, 0.17), Color(0.30, 0.30, 0.32), 1, 0))
	_bar = panel

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	# ── 第一行：出征的武将 / 士卒 ──
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	_lbl_bar = _mk_label("出征", 12, INK)
	_lbl_bar.custom_minimum_size = Vector2(58, 0)
	_lbl_bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_lbl_bar)

	_slot_row = HBoxContainer.new()
	_slot_row.add_theme_constant_override("separation", 6)
	_slot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_slot_row)

	_btn_pool = Button.new()
	_btn_pool.text = "卡池 ▾"
	_btn_pool.tooltip_text = "展开已有将兵 —— 把牌**拖**到左边的槽位上阵"
	_btn_pool.pressed.connect(func(): _set_pool(not _pool_open))
	hb.add_child(_btn_pool)

	# ── 第二行：操作提示 + 战报 ──
	# ⚠️ 顶栏寸土寸金的老问题在这里也一样：这一行整体不能再高，
	#    否则牌桌（主界面铁律里的主角）会被挤扁。
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 18)
	vb.add_child(hb2)

	_lbl_hint = _mk_label("", 12, Color(0.24, 0.33, 0.22))
	_lbl_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_hint.clip_text = true
	hb2.add_child(_lbl_hint)

	_log_lbl = _mk_label("", 11, INK_SOFT)
	_log_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_log_lbl.clip_text = true
	_log_lbl.custom_minimum_size = Vector2(400, 0)
	hb2.add_child(_log_lbl)
	return panel


func _build_pool() -> PanelContainer:
	## 卡池条：默认收起（主界面铁律 —— 第一眼必须看到满桌的牌）。
	## 展开时插在牌桌下方（不是覆盖层），牌桌自然缩短，不会挡住任何一张牌。
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, POOL_H)
	panel.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.26,
			Color(0.16, 0.16, 0.17), Color(0.30, 0.30, 0.32), 1, 0))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)

	var head := VBoxContainer.new()
	head.custom_minimum_size = Vector2(58, 0)
	head.add_child(_mk_label("卡池", 12, INK))
	head.add_child(_mk_label("待命", 10, INK_SOFT))
	head.add_child(_mk_label("拖→", 10, Color(0.24, 0.33, 0.22)))
	hb.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(scroll)

	_pool_box = HBoxContainer.new()
	_pool_box.add_theme_constant_override("separation", 6)
	_pool_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(_pool_box)

	panel.visible = false
	return panel


func _set_pool(open: bool) -> void:
	_pool_open = open
	_pool.visible = open
	_btn_pool.text = "卡池 ▴" if open else "卡池 ▾"
	if open:
		_rebuild_pool()
	_layout_cards()


func _set_drawer(open: bool) -> void:
	_drawer_open = open
	_drawer.visible = open
	_btn_drawer.text = "商店" if not open else "收起"
	if open:
		_layout_cards()


# =====================================================================
# 底部上阵条：槽位 + 卡池（v1.0）
# =====================================================================
## 由 _on_changed() 调用。用一个"指纹"串判断要不要重建 —— 拍卡时 changed 每一下都发，
## 每次都重建 7 个槽位 + 几十张卡池牌会白烧 CPU（也让人眼看到闪烁）。
func _refresh_deploy_bar() -> void:
	var sig := "%d|%d" % [GameState.carry.size(), GameState.carry_max()]
	for id in GameState.carry:
		var sid := str(id)
		sig += "|" + sid
		# v1.1：装备/兵的数量也要进指纹 —— 不然在大本营挂了装备回来，槽位上还是旧数字
		sig += ":%d:%d" % [GameState.hero_equip_of(sid).size(), GameState.hero_troops_of(sid).size()]
	if sig != _bar_sig:
		_bar_sig = sig
		_rebuild_slots()
		_pool_sig = ""                 # 上阵名单变了 → 卡池里的「待命」集合也变了
	if _pool_open:
		_rebuild_pool()


func _rebuild_slots() -> void:
	_clear(_slot_row)
	var cap := GameState.carry_max()
	_lbl_bar.text = "出征\n%d/%d" % [GameState.carry.size(), cap]
	# 主角固定位：永远在最左，不占携带位、点不掉、拖不进（铁律 5：主角固定不占位不可卸）
	_slot_row.add_child(_mk_slot_node(HERO_ALWAYS, -1, true))
	for i in range(cap):
		var id := str(GameState.carry[i]) if i < GameState.carry.size() else ""
		_slot_row.add_child(_mk_slot_node(id, i, false))


## 战力显示。
## ⚠️ 不能直接用 GameState.fmt() —— 它是给金币用的（四舍五入到整数），
##    而士兵战力是 0.2 / 0.6 / 2.0 这种小数：0.2 会显示成 "0"，看起来像废牌，
##    玩家会以为「士卒」根本没用（用户明确要求要能看清自己带的将兵）。
##    所以战力 < 10 时保留一位小数。
func _fmt_pow(v: float) -> String:
	if absf(v) < 10.0:
		return "%.1f" % v
	return GameState.fmt(v)


func _slot_style(filled: bool, locked: bool) -> StyleBox:
	if locked:
		return _flat(Color(0.90, 0.86, 0.76), Color(0.52, 0.44, 0.30), 2, 3)
	if filled:
		return _flat(PAPER, Color(0.45, 0.38, 0.28), 1, 3)
	return _flat(Color(0.855, 0.825, 0.760), Color(0.60, 0.55, 0.47), 1, 3)


func _mk_slot_node(card_id: String, slot_index: int, locked: bool) -> Control:
	var filled := card_id != ""
	var slot := _Slot.new()
	slot.host = self
	slot.card_id = card_id
	slot.slot_index = slot_index
	slot.locked = locked
	slot.custom_minimum_size = Vector2(SLOT_W, 46)
	slot.add_theme_stylebox_override("panel", _slot_style(filled, locked))
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(v)

	if not filled:
		var dash := _mk_label("空位", 10, INK_SOFT)
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(dash)
		slot.tooltip_text = "空携带位 %d／%d\n把「卡池」里的将兵拖到这里" % [
			slot_index + 1, GameState.carry_max()]
		return slot

	var c := GameData.card(card_id)
	var nm := _mk_label(str(c.get("name", card_id)), 11, INK)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	var star := "★%d" % int(c.get("star", 1))
	# v1.1：在槽位上直接标出「这个将身上挂了几件装备 / 带了几个兵」——
	# 用户要求「玩家可以明确看到自己出征的武将和士卒」，挂在将身上的兵也得看得见。
	var marks := ""
	var eqn := GameState.hero_equip_of(card_id).size()
	if eqn > 0:
		marks += " 装%d" % eqn
	var tpn := GameState.hero_troops_of(card_id).size()
	if tpn > 0:
		marks += " 兵%d" % tpn
	var pw := _mk_label("%s %s%s" % [star, _fmt_pow(GameState.hero_card_power(card_id)), marks],
		9, INK_DIM)
	pw.clip_text = true
	pw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pw)

	if locked:
		var lock := _mk_label("主角 · 固定", 9, Color(0.42, 0.32, 0.16))
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(lock)
		slot.tooltip_text = "主角「%s」：固定上阵，不占携带位，卸不下来。\n战力 %s" % [
			str(c.get("name", card_id)), _fmt_pow(GameState.hero_card_power(card_id))]
	else:
		# v1.1：把装备巢与兵位一并列进悬浮说明 —— 一眼看全"这个将身上有什么"
		var detail := str(c.get("effect", ""))
		var eq_ids := GameState.hero_equip_of(card_id)
		if not eq_ids.is_empty():
			var en := []
			for eid in eq_ids:
				en.append(GameData.card_name(str(eid)))
			detail += "\n装备巢：" + "、".join(en)
		var tp_ids := GameState.hero_troops_of(card_id)
		if not tp_ids.is_empty():
			var tn := []
			for tid in tp_ids:
				tn.append(GameData.card_name(str(tid)))
			detail += "\n兵位：" + "、".join(tn)
		elif GameState.is_hero(card_id) and GameState.troop_slots() > 0:
			detail += "\n（兵位空着 · 大本营可派兵）"
		slot.tooltip_text = "%s · ★%d · 战力 %s\n%s\n\n点一下 = 卸下（退回卡池）" % [
			str(c.get("name", card_id)), int(c.get("star", 1)),
			_fmt_pow(GameState.hero_card_power(card_id)), detail]
	return slot


## 卡池内容指纹：持有数量 / 武将等级 / 上阵名单，任一变化都要重画。
func _pool_signature() -> String:
	var ids := []
	for id in GameState.owned.keys():
		var sid := str(id)
		# ⚠️ v1.1：挂在武将麾下带兵的士卒**不进卡池** —— 它们已经"在用"了，
		#    拖也拖不动（carry_add 会拒收），留在池里只会让人以为点了没反应。
		if not GameState.is_carryable(sid) or int(GameState.owned.get(sid, 0)) <= 0 \
				or GameState.in_troops(sid):
			continue
		ids.append("%s:%d:%d" % [sid, int(GameState.owned.get(sid, 0)), GameState.hero_level(sid)])
	ids.sort()
	return "|".join(ids) + "||" + "|".join(GameState.carry)


func _rebuild_pool() -> void:
	var sig := _pool_signature()
	if sig == _pool_sig:
		return
	_pool_sig = sig
	_clear(_pool_box)

	var ids := []
	for id in GameState.owned.keys():
		var sid := str(id)
		if GameState.is_carryable(sid) and int(GameState.owned.get(sid, 0)) > 0 \
				and not GameState.in_carry(sid) and not GameState.in_troops(sid):
			ids.append(sid)

	if ids.is_empty():
		var tip := "卡池里没有待命的将兵 —— 去「商店 → 卡包」开几包，或把上阵的槽位点掉。"
		_pool_box.add_child(_mk_label(tip, 12, INK_DIM))
		return

	# 战力从高到低，一眼看出谁是主力
	ids.sort_custom(func(a: String, b: String) -> bool:
		return GameState.hero_card_power(a) > GameState.hero_card_power(b))
	for id in ids:
		_pool_box.add_child(_mk_pool_card(id))


func _mk_pool_card(id: String) -> Control:
	var c := GameData.card(id)
	var route := str(c.get("route", ""))
	var col: Color = ROUTE_COLOR.get(route, INK_DIM)
	var card := _PoolCard.new()
	card.host = self
	card.card_id = id
	card.custom_minimum_size = Vector2(86, 92)
	card.add_theme_stylebox_override("panel", _flat(PAPER, col, 1, 3))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s · %s · ★%d\n路线 %s\n战力 %s\n%s\n\n拖到左边的槽位上阵" % [
		str(c.get("name", id)), str(c.get("type", "")), int(c.get("star", 1)),
		route, _fmt_pow(GameState.hero_card_power(id)), str(c.get("effect", ""))]

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	var nm := _mk_label(str(c.get("name", id)), 12, INK)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	var l2 := _mk_label("★%d %s" % [int(c.get("star", 1)), str(c.get("type", ""))], 9, INK_SOFT)
	l2.clip_text = true
	l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l2)

	var l3 := _mk_label("战力 %s" % _fmt_pow(GameState.hero_card_power(id)), 10, INK)
	l3.clip_text = true
	l3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l3)

	var l4 := _mk_label(route, 9, col)
	l4.clip_text = true
	l4.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l4)

	var n := int(GameState.owned.get(id, 0))
	if n > 1:
		var l5 := _mk_label("×%d" % n, 9, INK_DIM)
		l5.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l5)
	return card


## 拖过来的牌落到第 index 个槽位。落点已有人 = 换人（旧的回卡池）。
func _deploy_at(id: String, index: int) -> void:
	var cap := GameState.carry_max()
	if index < 0 or index >= cap:
		GameState.carry_add(id)                  # 兜底：当追加处理
		return
	var occupant := str(GameState.carry[index]) if index < GameState.carry.size() else ""
	if occupant != "" and occupant != id:
		GameState.carry_remove(occupant)
	GameState.carry_put(id, index)


func _undeploy(id: String) -> void:
	if GameState.carry_remove(id):
		_pool_sig = ""                            # 有人退回卡池 → 卡池要重画


## 拖拽时跟着鼠标走的小纸片。用 Label 而不是真实卡面 —— 拖拽预览在
## 独立图层上，用九宫格纹理容易被拉伸糊掉，也拖慢拖拽起手。
func _drag_preview(id: String) -> Control:
	var c := GameData.card(id)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(PAPER, INK_DIM, 1, 3))
	p.modulate = Color(1.0, 1.0, 1.0, 0.92)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_mk_label(str(c.get("name", id)), 12, INK))
	v.add_child(_mk_label("战力 %s" % _fmt_pow(GameState.hero_card_power(id)), 10, INK_DIM))
	return p


# =====================================================================
# 小工具
# =====================================================================
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


func _vsep() -> Control:
	var s := VSeparator.new()
	s.custom_minimum_size = Vector2(2, 0)
	return s


# ── S5 纸质感资源加载 ────────────────────────────────────────────────
var _tex_cache := {}


func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


## 纸质感九宫格。margin 必须**等于源纹理上的真实边框宽度**。
## ⚠️ Godot 4 的 StyleBoxTexture **没有 texture_scale**，九宫格的角是按源纹理 1:1 画的，
##    想改变边框粗细只能**重新生成对应尺寸的纹理**，不能在运行时缩放。
## margin 若小于真实边框，卡框内框线会被当成"中心"拉伸糊掉。
## 找不到纹理时返回 null —— 调用方负责回退到 _flat()，这样没图也能跑。
func _paper(path: String, margin: float, _scale: float = 1.0) -> StyleBox:
	var t := _tex(path)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(margin)
	# 内容内边距压小：顶栏很挤，纸张边框再吃掉 10px/边就会把按钮撑到溢出
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


## 面板用的纸底：拿不到纹理就回退到原来的纯色 StyleBoxFlat
func _paper_or_flat(path: String, margin: float, scale: float,
		bg: Color, border: Color, w: int, radius: int) -> StyleBox:
	var sb := _paper(path, margin, scale)
	if sb != null:
		return sb
	return _flat(bg, border, w, radius)


## 全幅背景贴图（牌桌 / 舆图等），等比铺满
func _bg_rect(name: String) -> TextureRect:
	var bg := TextureRect.new()
	bg.texture = _tex(BG_DIR + name)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## S5：把所有 Button 换成印刷纸按钮。挂在根节点上，子树自动继承。
## 拿不到纹理就返回 null（调用方不设 theme，等于保持原样）。
func _paper_button_theme() -> Theme:
	var margin := BTN_MARGIN
	var sets := {
		"normal": "btn_normal.png",
		"hover": "btn_hover.png",
		"pressed": "btn_press.png",
		"disabled": "btn_disabled.png",
		"focus": "btn_hover.png",
	}
	var th := Theme.new()
	var any := false
	for key in sets.keys():
		var sb := _paper(UI_DIR + str(sets[key]), margin)
		if sb != null:
			th.set_stylebox(str(key), "Button", sb)
			any = true
	if not any:
		return null
	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", Color(0.22, 0.13, 0.04))
	th.set_color("font_pressed_color", "Button", Color(0.10, 0.06, 0.02))
	th.set_color("font_focus_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color(0.56, 0.50, 0.42))

	# ⚠️ TabContainer 自带一块深色底板（跟 Button 不是同一套 stylebox）。
	# 不清掉的话，商店抽屉的纸面会被它压成灰的、里面的按钮文字也跟着发白。
	# 只设 Button 是治不到的 —— 2026-09-26 踩中。
	th.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	var tabs := {
		"tab_selected": "btn_press.png",
		"tab_unselected": "btn_normal.png",
		"tab_hovered": "btn_hover.png",
		"tab_disabled": "btn_disabled.png",
	}
	for key in tabs.keys():
		var tsb := _paper(UI_DIR + str(tabs[key]), margin)
		if tsb != null:
			th.set_stylebox(str(key), "TabContainer", tsb)
	th.set_color("font_selected_color", "TabContainer", INK)
	th.set_color("font_unselected_color", "TabContainer", INK_DIM)
	th.set_color("font_hovered_color", "TabContainer", INK)
	th.set_color("font_disabled_color", "TabContainer", Color(0.56, 0.50, 0.42))
	return th


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# =====================================================================
# 高频刷新：顶栏 + 卡牌血量
# =====================================================================
func _on_changed() -> void:
	_update_topbar()
	_refresh_deploy_bar()
	if _shown_gen != GameState.battle_gen:
		_shown_gen = GameState.battle_gen
		_rebuild_cards()
	else:
		_update_cards()

	# 从"桌上有牌"变成"桌上没牌"：
	#   拍翻整桌 -> 推「荆州舆图」（挑下一桌）
	#   耐力耗尽 -> 推「大本营」（升级 / 上阵 / 再出征）
	if _was_in_battle and not GameState.in_battle:
		if GameState.end_reason == "cleared":
			_sel_idx = -1                  # 重选默认节点：优先刚解锁的邻居
			_open_map()
		else:
			_open_home()
	elif _map_layer != null and _map_layer.visible:
		_refresh_map_panels()
	elif _home != null and _home.visible:
		_home.refresh()
	elif _city != null and _city.visible:
		_city.refresh()
	_was_in_battle = GameState.in_battle
	_update_banner()


func _update_topbar() -> void:
	var in_b := GameState.in_battle
	if in_b:
		var r := GameData.region(GameState.battle_region)
		var route: String = r.get("route", "")
		_lbl_region.text = "【%s】%s" % [route, r.get("name", "?")]
		_lbl_region.add_theme_color_override("font_color", ROUTE_COLOR.get(route, Color.WHITE))
		var alive := 0
		for e in GameState.battle:
			if float(e["hp"]) > 0.0:
				alive += 1
		_lbl_stamina.text = "耐力 %d/%d  连击 %d  剩 %d 张" % [
			GameState.stamina, GameState.stamina_max, GameState.combo, alive]
		_stamina_bar.max_value = max(1, GameState.stamina_max)
		_stamina_bar.value = GameState.stamina
		_stamina_bar.visible = true
		if _btn_retreat != null:
			_btn_retreat.visible = true
	else:
		_lbl_region.text = "桌上没有牌"
		_lbl_region.add_theme_color_override("font_color", Color(0.38, 0.33, 0.26))
		_lbl_stamina.text = "点「大本营」整备升级，或从「荆州舆图」挑一桌"
		_stamina_bar.visible = false
		if _btn_retreat != null:
			_btn_retreat.visible = false

	_lbl_dmg.text = "轻拍 %.1f / 重拍 %.1f" % [
		GameState.click_damage(), GameState.click_damage() * HEAVY_MULT]
	_lbl_gold.text = "金币 %s (%s/时)" % [
		GameState.fmt(GameState.gold), GameState.fmt(GameState.gold_per_hour())]
	# 顶栏寸土寸金：全角空格（　）在这个字号下约 12px，换半角能省下几十像素，
	# 否则最右的「重开」会被挤出屏幕。改动这几行文案前先截图确认顶栏没溢出。
	_lbl_progress.text = "Lv.%d  第 %d 趟  上阵 %d/%d  战力 %.1f  克服 %d/%d" % [
		GameState.player_level(), GameState.runs, GameState.carry.size(), GameState.carry_max(),
		GameState.deck_power(), GameState.cleared_count(), GameState.total_field_regions()]

	var dm := "单击 = 轻拍（1 耐力）　·　按住划过卡牌 = 重拍 ×%.0f（%d 耐力/张，可一次扇翻一排）" % [
		HEAVY_MULT, HEAVY_STAMINA]
	if not GameState.city_unlocked():
		dm += "　·　城建：%s" % GameState.city_unlock_text()
	_lbl_hint.text = dm


func _update_banner() -> void:
	if GameState.in_battle:
		_banner.visible = false
		return
	_banner.visible = true
	if GameState.cleared_count() >= GameState.total_field_regions():
		_banner.text = "荆州八郡已定。\n卡盒合上。"
	elif GameState.end_reason == "settled":
		_banner.text = "耐力耗尽，这一趟收桌了。\n点顶部「大本营」升级 / 换人，再去拍下一桌"
	else:
		_banner.text = "桌上没有牌。\n点顶部「大本营」整备，或「荆州舆图」挑一桌"


# =====================================================================
# 桌面：铺牌 / 重建
# =====================================================================
func _rebuild_cards() -> void:
	for c in _table.get_children():
		if c == _banner:
			continue
		_table.remove_child(c)
		c.queue_free()
	_cards.clear()
	if not GameState.in_battle or GameState.battle.is_empty():
		return
	for i in range(GameState.battle.size()):
		var card := _mk_card(i)
		_cards.append(card)
		_table.add_child(card["node"])
	_layout_cards()
	for i in range(_cards.size()):
		_update_card(i)


func _card_size_for(n: int, area: Vector2) -> Vector2:
	# 牌越少，牌越大 —— 三张牌也要把整张桌子撑起来，别让桌面显得空
	if n <= 0:
		return CARD_SIZE
	var aspect := area.x / maxf(1.0, area.y)
	var cols := maxi(1, int(ceil(sqrt(float(n) * aspect))))
	var rows := maxi(1, int(ceil(float(n) / float(cols))))
	var w := minf(area.x / float(cols) * 0.62, area.y / float(rows) * 0.52)
	w = clampf(w, CARD_MIN_W, CARD_MAX_W)
	return Vector2(w, w * CARD_RATIO)


func _mk_card(i: int) -> Dictionary:
	var e: Dictionary = GameState.battle[i]
	var c := GameData.card(e["card_id"])
	var route: String = c.get("route", "通用")
	var accent: Color = ROUTE_COLOR.get(route, Color(0.6, 0.6, 0.6))
	var boss := bool(e["boss"])
	var sz := CARD_SIZE

	var node := PanelContainer.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE    # 输入统一交给桌面层做命中测试
	node.set_meta("paan_card", true)
	node.custom_minimum_size = sz
	node.size = sz
	node.pivot_offset = sz * 0.5
	node.rotation = float(e.get("rot", 0.0))

	# S5：按稀有度套印刷卡面（★1..★6 -> cardface_N.png 九宫格）
	var star_n: int = clampi(int(c.get("star", 1)), 1, 6)
	var sb: StyleBox = _paper(UI_DIR + "cardface_%d.png" % star_n, FRAME_MARGIN)
	if sb == null:
		# 没有美术资源时的回退：原来的纯色卡面
		var fb := StyleBoxFlat.new()
		fb.bg_color = CARD_BG
		fb.border_color = accent
		fb.set_border_width_all(3 if boss else 2)
		fb.set_corner_radius_all(8)
		fb.shadow_color = Color(0, 0, 0, 0.40)         # 让牌"压在桌面上"
		fb.shadow_size = 7
		fb.shadow_offset = Vector2(2, 3)
		fb.content_margin_left = 9
		fb.content_margin_right = 9
		fb.content_margin_top = 8
		fb.content_margin_bottom = 8
		sb = fb
	else:
		# 印刷框本身有宽度，卡面文字要往里收，别压到边框上
		sb.content_margin_left = 17
		sb.content_margin_right = 16
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
	node.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 1)
	node.add_child(vb)

	var fonts := {}

	# TODO(未来)：背面朝上的伏兵牌 —— 这里改成画一张牌背，玩家拍开才 reveal
	var top := Label.new()
	top.text = ("关底·" if boss else "") + str(c.get("name", "?"))
	top.custom_minimum_size = Vector2(0, 22)           # autowrap 必须有最小高度，否则会被压成 0
	top.add_theme_color_override("font_color", CARD_INK)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(top)
	fonts[top] = 15

	var star := Label.new()
	star.text = GameData.star_text(int(c.get("star", 0)))
	star.add_theme_color_override("font_color", accent.darkened(0.28))
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(star)
	fonts[star] = 13

	var typ := Label.new()
	typ.text = str(c.get("type", "")) + "　" + route
	typ.add_theme_color_override("font_color", CARD_DIM)
	typ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(typ)
	fonts[typ] = 11

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sp)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 13)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = Color(0.759, 0.702, 0.588)       # 印在纸上的浅凹槽
	bar_sb.border_color = Color(0.427, 0.365, 0.286)
	bar_sb.set_border_width_all(1)
	bar_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bar_sb)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.612, 0.208, 0.173)      # 做旧朱红，不是屏幕红
	fill_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill_sb)
	vb.add_child(bar)

	var hpt := Label.new()
	hpt.add_theme_color_override("font_color", CARD_DIM)
	hpt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hpt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hpt)
	fonts[hpt] = 11

	return {
		"node": node, "bar": bar, "hpt": hpt, "dead": false,
		"rot": float(e.get("rot", 0.0)), "size": sz, "fonts": fonts,
	}


func _layout_cards() -> void:
	var area := _table.size
	if area.x <= 60.0 or area.y <= 60.0 or _cards.is_empty():
		return
	var sz := _card_size_for(_cards.size(), area)
	var k := clampf(sz.x / CARD_SIZE.x, 0.85, 1.55)
	for i in range(_cards.size()):
		var card: Dictionary = _cards[i]
		card["size"] = sz
		var node: Control = card["node"]
		node.custom_minimum_size = sz
		node.size = sz
		node.pivot_offset = sz * 0.5
		var fonts: Dictionary = card["fonts"]
		for lbl in fonts.keys():
			(lbl as Label).add_theme_font_size_override("font_size", int(round(float(fonts[lbl]) * k)))
		if card["dead"] or i >= GameState.battle.size():
			continue
		var e: Dictionary = GameState.battle[i]
		node.position = Vector2(
			float(e.get("nx", 0.5)) * (area.x - sz.x),
			float(e.get("ny", 0.5)) * (area.y - sz.y))


func _update_card(i: int) -> void:
	if i < 0 or i >= _cards.size() or i >= GameState.battle.size():
		return
	var card: Dictionary = _cards[i]
	if card["dead"]:
		return
	var e: Dictionary = GameState.battle[i]
	var hp := maxf(0.0, float(e["hp"]))
	var hp_max := maxf(1.0, float(e["hp_max"]))
	var bar: ProgressBar = card["bar"]
	bar.max_value = hp_max
	bar.value = hp
	var hpt: Label = card["hpt"]
	hpt.text = "%s / %s" % [GameState.fmt(hp), GameState.fmt(hp_max)]


func _update_cards() -> void:
	for i in range(_cards.size()):
		_update_card(i)


# =====================================================================
# 输入：单击轻拍 / 按住拖拽重拍
# =====================================================================
func _on_table_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_mouse_down = true
			_press_pos = mb.position
			_drag_last = mb.position
			_is_dragging = false
			_drag_hit = {}
			_press_index = _hit_index_at(mb.position)
		else:
			if not _is_dragging and _press_index >= 0:
				_slap(_press_index, false, mb.position)     # 没拖动 = 单击 = 轻拍
			_mouse_down = false
			_press_index = -1
			_is_dragging = false
			_drag_hit = {}
		return

	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		# 只要左键还按着就跟踪轨迹 —— 允许从空白处起手，一巴掌扇过整张桌子
		if not _mouse_down:
			return
		var mpos := mm.position
		if not _is_dragging:
			if mpos.distance_to(_press_pos) < DRAG_THRESHOLD:
				return
			_is_dragging = true                             # 升级为拖拽重拍
			if _press_index >= 0:
				_drag_hit[_press_index] = true
				_slap(_press_index, true, _press_pos)
		# 沿轨迹采样，划过哪张拍哪张（一次拖拽内每张只吃一次）
		var dist: float = mpos.distance_to(_drag_last)
		var steps := int(max(1.0, ceil(dist / SAMPLE_STEP)))
		for s in range(1, steps + 1):
			var p: Vector2 = _drag_last.lerp(mpos, float(s) / float(steps))
			var idx := _hit_index_at(p)
			if idx >= 0 and not _drag_hit.has(idx):
				_drag_hit[idx] = true
				_slap(idx, true, p)
		_drag_last = mpos


func _hit_index_at(local_pos: Vector2) -> int:
	var best := -1
	var best_d := 1e20
	for i in range(_cards.size()):
		var card: Dictionary = _cards[i]
		if card["dead"]:
			continue
		var node: Control = card["node"]
		if not node.visible:
			continue
		var sz: Vector2 = card["size"]
		# 在卡牌自身的（未旋转）坐标系里做判定 —— 不依赖引擎的变换栈
		var local := (local_pos - node.position - sz * 0.5).rotated(-node.rotation)
		if absf(local.x) <= sz.x * 0.5 and absf(local.y) <= sz.y * 0.5:
			# 重叠时取离牌心最近的那张（上层被压住的牌只算边角）
			var d := local.length()
			if d < best_d:
				best_d = d
				best = i
	return best


func _slap(i: int, heavy: bool, pos: Vector2) -> void:
	if not GameState.in_battle or i < 0 or i >= GameState.battle.size():
		return
	if float(GameState.battle[i]["hp"]) <= 0.0 or GameState.stamina <= 0:
		return
	if not GameState.attack(i, heavy):
		return
	# 飘字只往桌面上挂，安全；但 attack() 可能在耐力耗尽那一刻「结算收桌」，
	# 卡片节点会被整体重建 —— 拖拽没结束就要重新确认，否则索引越界。
	_spawn_impact(pos, i, heavy)
	if i < _cards.size() and i < GameState.battle.size() and not bool(_cards[i]["dead"]):
		_shake(i, heavy)
		if float(GameState.battle[i]["hp"]) <= 0.0:
			_flip_card(i)


func _shake(i: int, heavy: bool) -> void:
	var card: Dictionary = _cards[i]
	var node: Control = card["node"]
	var base := node.position
	var amp := 7.0 if heavy else 3.0
	var tw := node.create_tween()
	tw.tween_property(node, "position", base + Vector2(amp, -amp * 0.4), 0.04)
	tw.tween_property(node, "position", base + Vector2(-amp * 0.7, amp * 0.3), 0.05)
	tw.tween_property(node, "position", base, 0.07)


func _spawn_impact(pos: Vector2, i: int, heavy: bool) -> void:
	var info: Dictionary = GameState.last_slap
	var tag := str(info.get("tag", ""))
	var txt := "-%s" % GameState.fmt(float(info.get("damage", 0.0)))
	if tag != "":
		txt = "%s %s" % [tag, txt]

	var lbl := _mk_label(txt, 20 if heavy else 14,
		Color(0.98, 0.78, 0.28) if tag != "" else (Color(0.96, 0.45, 0.38) if heavy else Color(0.90, 0.88, 0.84)))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = pos + Vector2(-18, -26)
	_table.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -46), 0.55)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(lbl.queue_free)

	if heavy:
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0, 0, 0, 0)
		rsb.border_color = Color(0.92, 0.42, 0.36, 0.95)
		rsb.set_border_width_all(2)
		rsb.set_corner_radius_all(22)
		var rp := PanelContainer.new()
		rp.add_theme_stylebox_override("panel", rsb)
		rp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rp.position = pos - Vector2(22, 22)
		rp.size = Vector2(44, 44)
		rp.pivot_offset = Vector2(22, 22)
		_table.add_child(rp)
		var rtw := rp.create_tween()
		rtw.set_parallel(true)
		rtw.tween_property(rp, "scale", Vector2(2.0, 2.0), 0.35)
		rtw.tween_property(rp, "modulate:a", 0.0, 0.35)
		rtw.chain().tween_callback(rp.queue_free)


func _flip_card(i: int) -> void:
	var card: Dictionary = _cards[i]
	if card["dead"]:
		return
	card["dead"] = true
	var node: Control = card["node"]
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "rotation", float(card.get("rot", 0.0)) + PI, 0.38)
	tw.tween_property(node, "scale", Vector2(0.35, 0.35), 0.38)
	tw.tween_property(node, "modulate:a", 0.0, 0.38)
	tw.chain().tween_callback(func(): node.visible = false)


# =====================================================================
# 荆州舆图（全屏覆盖层）
# =====================================================================
func _build_map_layer() -> Control:
	var layer := PanelContainer.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_theme_stylebox_override("panel",
		_paper_or_flat(TEX_DIR + "paper.png", 0.0, 1.0,
			Color(0.90, 0.86, 0.75), Color(0.20, 0.21, 0.24), 0, 0))
	layer.visible = false

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	layer.add_child(vb)

	# ---- 顶栏 ----
	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(0, 58)
	top.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.30,
			Color(0.12, 0.13, 0.15), Color(0.26, 0.27, 0.31), 1, 0))
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	top.add_child(th)
	_map_title = _mk_label("荆州舆图", 22, INK)
	th.add_child(_map_title)
	_map_progress = _mk_label("", 14, INK_DIM)
	th.add_child(_map_progress)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp)
	_map_legend = _mk_label("", 13, INK_SOFT)
	th.add_child(_map_legend)
	var bc := Button.new()
	bc.text = "✕  收起舆图"
	bc.pressed.connect(_close_map)
	th.add_child(bc)
	vb.add_child(top)

	# ---- 三栏 ----
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	vb.add_child(mid)

	var lp := PanelContainer.new()
	lp.custom_minimum_size = Vector2(318, 0)
	lp.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.30,
			Color(0.11, 0.12, 0.135), Color(0.22, 0.23, 0.26), 1, 0))
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(lscroll)
	_map_left = VBoxContainer.new()
	_map_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_left.add_theme_constant_override("separation", 3)
	lscroll.add_child(_map_left)
	mid.add_child(lp)

	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.add_theme_stylebox_override("panel",
		_paper_or_flat(TEX_DIR + "paper.png", 0.0, 1.0,
			Color(0.90, 0.86, 0.75), Color(0.20, 0.21, 0.24), 1, 0))
	_map_view = PaanMapView.new()
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.region_chosen.connect(_on_map_chosen)
	mp.add_child(_map_view)
	mid.add_child(mp)

	var rp := PanelContainer.new()
	rp.custom_minimum_size = Vector2(330, 0)
	rp.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.30,
			Color(0.11, 0.12, 0.135), Color(0.22, 0.23, 0.26), 1, 0))
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rscroll)
	_map_right = VBoxContainer.new()
	_map_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_right.add_theme_constant_override("separation", 6)
	rscroll.add_child(_map_right)
	mid.add_child(rp)

	# ---- 底栏 ----
	var bot := PanelContainer.new()
	bot.custom_minimum_size = Vector2(0, 46)
	bot.add_theme_stylebox_override("panel",
		_paper_or_flat(UI_DIR + "panel.png", PANEL_MARGIN, 0.26,
			Color(0.12, 0.13, 0.15), Color(0.26, 0.27, 0.31), 1, 0))
	_map_foot = _mk_label("", 13, Color(0.24, 0.33, 0.22))
	bot.add_child(_map_foot)
	vb.add_child(bot)

	return layer


func _open_map() -> void:
	_close_home()
	_close_city()
	_map_layer.visible = true
	if _sel_idx <= 0:
		_sel_idx = _default_region()
	_map_view.select(_sel_idx)
	_map_view._recompute()
	_refresh_map_panels()


func _close_map() -> void:
	_map_layer.visible = false


# =====================================================================
# 大本营（全屏覆盖层）：升级树 / 上阵 / 装备 / 出征
# =====================================================================
func _open_home() -> void:
	if _home == null:
		return
	_close_map()
	_close_city()
	_home.open_home()


func _close_home() -> void:
	if _home != null:
		_home.visible = false


# =====================================================================
# 城建（全屏覆盖层）：城池 / 建筑 / 更换 / 合成
# =====================================================================
func _open_city() -> void:
	if _city == null:
		return
	_close_map()
	_close_home()
	_city.open_city()


func _close_city() -> void:
	if _city != null:
		_city.visible = false


func _on_home_deploy(idx: int) -> void:
	if GameState.start_battle(idx):
		_close_home()
		_append_log("铺桌：「%s」%d 张牌摆上桌面" % [
			GameData.region(idx).get("name", "?"), GameState.battle.size()])


func _default_region() -> int:
	if GameState.in_battle:
		return GameState.battle_region
	# 刚拍完的那一桌：优先把它刚解锁的邻居推出来，让玩家顺着线往下走
	var from := GameState.battle_region
	if from > 0:
		for n in GameData.region(from).get("unlocks", []):
			var j := int(n)
			if GameState.region_status(j) == "available":
				return j
	for r in GameData.regions:
		var i := int(r["idx"])
		if GameState.region_status(i) == "available":
			return i
	return GameState.START_REGION


func _on_map_changed() -> void:
	if _map_layer != null and _map_layer.visible:
		_refresh_map_panels()


func _on_map_chosen(idx: int) -> void:
	_sel_idx = idx
	_refresh_map_panels()


func _on_map_deploy(idx: int) -> void:
	if GameState.start_battle(idx):
		_close_map()
		var r := GameData.region(idx)
		_append_log("铺桌：「%s」%d 张牌摆上桌面" % [
			r.get("name", "?"), GameState.battle.size()])


func _refresh_map_panels() -> void:
	if _map_layer == null or not _map_layer.visible:
		return
	var total := GameState.total_field_regions()
	var done := GameState.cleared_count()
	_map_progress.text = "已克服  %d / %d" % [done, total]

	var parts := []
	for rt in GameState.ROUTES:
		var n := 0
		var c := 0
		for r in GameData.regions:
			if str(r.get("route", "")) == rt:
				n += 1
				if GameState.region_status(int(r["idx"])) == "cleared":
					c += 1
		parts.append("%s %d/%d" % [rt, c, n])
	_map_legend.text = "　".join(parts)

	_map_foot.text = "亮起的节点可以立刻开打　·　点节点看详情，点「铺这一桌」把牌铺到桌面上" \
		+ "　·　当前：%s" % (_region_brief(_sel_idx) if _sel_idx > 0 else "未选")

	_fill_map_left()
	_fill_map_right()


func _region_brief(idx: int) -> String:
	if idx <= 0:
		return "—"
	var r := GameData.region(idx)
	return "%s（%s）" % [r.get("name", "?"), r.get("route", "")]


func _fill_map_left() -> void:
	_clear(_map_left)
	_map_left.add_child(_mk_label("郡 · 势力 归属", 15, INK))
	_map_left.add_child(_mk_label("同一个郡的节点在图上会抱成一团领土色块", 11,
		INK_SOFT))

	# 按路线分组列出郡
	var by_route := {}
	for r in GameData.regions:
		var rt := str(r.get("route", "通用"))
		if not by_route.has(rt):
			by_route[rt] = {}
		var cnty := str(r.get("county", "?"))
		if not by_route[rt].has(cnty):
			by_route[rt][cnty] = []
		by_route[rt][cnty].append(int(r["idx"]))

	for rt in GameState.ROUTES:
		if not by_route.has(rt):
			continue
		var accent: Color = ROUTE_COLOR.get(rt, Color.GRAY)
		var cnties: Dictionary = by_route[rt]
		var n_all := 0
		var n_done := 0
		for k in cnties.keys():
			for idx in cnties[k]:
				n_all += 1
				if GameState.region_status(int(idx)) == "cleared":
					n_done += 1
		var head := _mk_label("● %s　%d/%d" % [rt, n_done, n_all], 14)
		head.add_theme_color_override("font_color", accent)
		_map_left.add_child(head)
		for k in cnties.keys():
			var ids: Array = cnties[k]
			var d := 0
			for idx in ids:
				if GameState.region_status(int(idx)) == "cleared":
					d += 1
			var row := _mk_label("　　%s　%d/%d" % [k, d, ids.size()], 12, Color(0.38, 0.33, 0.26))
			_map_left.add_child(row)

	_map_left.add_child(_mk_label("", 8))
	_map_left.add_child(_mk_label("图例", 13, INK))
	# 图例的「●」是当**文字**画的，所以在纸上要能读 —— 用压深版，不用节点上的亮色
	for kv in [["已克服", Color(0.18, 0.44, 0.26)], ["可挑战（亮）", Color(0.66, 0.50, 0.06)],
			["未解锁（灰）", Color(0.36, 0.34, 0.30)]]:
		_map_left.add_child(_mk_label("　● %s" % kv[0], 12, kv[1]))
	_map_left.add_child(_mk_label("　── 已通行的相邻连通", 12, Color(0.42, 0.34, 0.18)))
	_map_left.add_child(_mk_label("　- - 尚未打通的相邻", 12, INK_SOFT))
	_map_left.add_child(_mk_label("　〜 长江 / 汉水", 12, Color(0.20, 0.34, 0.52)))


func _fill_map_right() -> void:
	_clear(_map_right)
	var idx := _sel_idx
	if idx <= 0:
		_map_right.add_child(_mk_label("点舆图上的一个节点", 13, Color(0.40, 0.34, 0.27)))
		return
	var r := GameData.region(idx)
	var status := GameState.region_status(idx)
	var route := str(r.get("route", ""))
	var accent: Color = ROUTE_COLOR.get(route, Color.GRAY)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.lerp(PAPER, 0.88)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	panel.add_child(pv)
	pv.add_child(_mk_label("%d. %s" % [idx, r.get("name", "?")], 20, INK))
	pv.add_child(_mk_label("%s　·　%s　·　%s" % [
		route, r.get("county", ""), r.get("difficulty", "")], 12, Color(0.34, 0.29, 0.23)))
	_map_right.add_child(panel)

	# v1.0：新野已经不是"桌上没有牌"的序章了，删掉原先那条特殊分支，
	# 让它和别的区域一样走下面的「守军 / 总血量 / 需要几拍」。

	_map_right.add_child(_mk_label("守军　%d 张" % int(r.get("enemy_count", 0)), 14))
	_map_right.add_child(_mk_label("总血量　%s" % GameState.fmt(float(r.get("total_hp", 0))), 14))
	_map_right.add_child(_mk_label("你的耐力　%d 次拍击" % GameState.stamina_max_value(), 14))
	_map_right.add_child(_mk_label("你的伤害　%.1f / 拍" % GameState.click_damage(), 14))
	var need_slaps := GameState.slaps_needed(idx)
	var my_stamina := GameState.stamina_max_value()
	var vtxt := "约需 %d 拍 —— 够打" % need_slaps
	var vcol := Color(0.13, 0.34, 0.21)
	if need_slaps > my_stamina:
		vtxt = "约需 %d 拍 —— 还差 %d 拍，先升级或换一处" % [need_slaps, need_slaps - my_stamina]
		vcol = Color(0.62, 0.24, 0.19)
	_map_right.add_child(_mk_label(vtxt, 14, vcol))
	_map_right.add_child(_mk_label("推荐战力　%s　·　你的战力 %.1f" % [
		GameState.fmt(float(r.get("power", 0))), GameState.deck_power()], 13,
		Color(0.28, 0.32, 0.38)))
	_map_right.add_child(_mk_label("每次进场满血重来 —— 打不完就是白打，只有金币带得走", 11,
		Color(0.44, 0.36, 0.22)))
	_map_right.add_child(_mk_label("", 6))

	var city := str(r.get("city", ""))
	if GameState.city_unlocked():
		_map_right.add_child(_mk_label("克服后：获得城池卡「%s」　建筑槽位 %d" % [
			city, GameState.city_slots(idx)], 12, Color(0.30, 0.34, 0.24)))
	else:
		_map_right.add_child(_mk_label("克服后：解锁相邻区域（城池要等 %s）" % GameState.city_unlock_text(),
			12, Color(0.45, 0.36, 0.15)))

	var unlocked_names := []
	for n in r.get("unlocks", []):
		unlocked_names.append(str(GameData.region(int(n)).get("name", "?")))
	if not unlocked_names.is_empty():
		_map_right.add_child(_mk_label("打通后开启：%s" % _join_str(unlocked_names, "、"), 12,
			Color(0.40, 0.35, 0.28)))

	var need := []
	for n in r.get("unlocked_by", []):
		if not GameState._is_cleared(int(n)):
			need.append(str(GameData.region(int(n)).get("name", "?")))
	if not need.is_empty():
		_map_right.add_child(_mk_label("还需先打通：%s" % _join_str(need, "、"), 12,
			Color(0.58, 0.28, 0.22)))

	_map_right.add_child(_mk_label("", 8))
	if status == "available":
		var b := Button.new()
		b.text = "铺这一桌  ▶"
		b.custom_minimum_size = Vector2(0, 46)
		b.pressed.connect(func(): _on_map_deploy(idx))
		_map_right.add_child(b)
	elif status == "cleared":
		_map_right.add_child(_mk_label("✓ 这一桌已经拍完了", 14, Color(0.48, 0.86, 0.56)))
		_map_right.add_child(_mk_label("敌人不再刷新 —— 它已归入城建，是挂机地基而不是刷钱场。", 11,
			Color(0.40, 0.35, 0.28)))
		var arr := GameState.city_buildings(idx)
		if arr.size() > 0:
			_map_right.add_child(_mk_label("城池建筑 %d/%d" % [arr.size(), GameState.city_slots(idx)],
				12, Color(0.40, 0.35, 0.28)))
	else:
		_map_right.add_child(_mk_label("🔒 未解锁", 14, Color(0.45, 0.40, 0.33)))


# =====================================================================
# 开包 / 招降 / 合成 —— 都要放翻牌特效
# =====================================================================
func _play_reveal(title: String, ids: Array, sub: String) -> void:
	if _reveal == null or ids.is_empty():
		return
	_reveal.open(title, ids, sub)


func _do_buy_pack(i: int) -> void:
	var got := GameState.buy_pack(i)
	if got.is_empty():
		return
	var nm: String = GameData.packs[i].get("name", "卡包")
	var high := 0
	for id in got:
		high = maxi(high, int(GameData.card(id).get("star", 0)))
	_play_reveal("开「%s」" % nm, got, "%d 张　最高 %s" % [got.size(), GameData.star_text(high)])


func _do_ransom(id: String) -> void:
	var nm := GameData.card_name(id)
	if GameState.ransom(id):
		_play_reveal("招降 · %s" % nm, [id], "入我帐下")


func _do_synth(star: int) -> void:
	var got := GameState.synthesize(star)
	if got == "":
		return
	_play_reveal("合成 · %s" % GameData.star_text(star + 1), [got], "3 张 %s 熔铸而成" % GameData.star_text(star))


# =====================================================================
# 抽屉其余页
# =====================================================================
func _refresh_shop() -> void:
	_fill_packs()
	_fill_ransom()
	_fill_synth()
	_fill_cities()
	_fill_routes()
	_fill_collection()


func _fill_packs() -> void:
	var box: VBoxContainer = _shop_boxes["卡包"]
	_clear(box)
	box.add_child(_mk_label("卡包按区域（郡）解锁：走哪条线，就开得出那条线的武将。价格 ×2.4 递增。", 12))
	for i in range(GameData.packs.size()):
		var p: Dictionary = GameData.packs[i]
		var unlocked := GameState.pack_unlocked(i)
		var price := GameState.pack_price(i)
		var bought := int(GameState.pack_bought.get(p.get("name", ""), 0))
		var b := Button.new()
		b.text = "%s　（%s）　%d 金币　已开 %d" % [
			p.get("name", "?"), p.get("scope", ""), price, bought]
		b.disabled = not unlocked or GameState.gold < float(price)
		b.pressed.connect(_do_buy_pack.bind(i))
		box.add_child(b)


func _fill_ransom() -> void:
	var box: VBoxContainer = _shop_boxes["招降"]
	_clear(box)
	if GameState.captured.is_empty():
		box.add_child(_mk_label("囚禁台是空的。拍翻 ★★★ 及以上武将后，他们会出现在这里。", 12))
		return
	box.add_child(_mk_label("囚禁台（%d 名）", GameState.captured.size(), Color(0.38, 0.33, 0.26)))
	var seen := {}
	for id in GameState.captured:
		if seen.has(id):
			continue
		seen[id] = true
		var cnt := 0
		for x in GameState.captured:
			if x == id:
				cnt += 1
		var cost := GameState.ransom_cost(id)
		var c := GameData.card(id)
		var b := Button.new()
		b.text = "%s %s　[%s]　招降 %d 金币%s" % [
			c.get("name", "?"), GameData.star_text(int(c.get("star", 0))),
			c.get("route", ""), cost, ("　x%d" % cnt) if cnt > 1 else ""]
		b.disabled = GameState.gold < float(cost)
		b.pressed.connect(func(): _do_ransom(id))
		box.add_child(b)


func _fill_synth() -> void:
	var box: VBoxContainer = _shop_boxes["合成"]
	_clear(box)
	box.add_child(_mk_label("3 张同星级卡 + 金币 → 随机 1 张高一星级卡。", 12))
	for star in range(1, 6):
		var cands := GameState._star_candidates(star)
		var cost := GameState.synth_cost(star)
		var b := Button.new()
		b.text = "★%d ×3　→　★%d（%d 金币）　持有 %d 张" % [star, star + 1, cost, cands.size()]
		b.disabled = cands.size() < 3 or GameState.gold < float(cost)
		b.pressed.connect(func(): _do_synth(star))
		box.add_child(b)


func _fill_cities() -> void:
	var box: VBoxContainer = _shop_boxes["城建"]
	_clear(box)
	box.add_child(_mk_label("城池 = 地基（只提供槽位，本身不产钱）；建筑 = 产钱实体。", 12))
	if not GameState.city_unlocked():
		box.add_child(_mk_label("尚未解锁　·　%s" % GameState.city_unlock_text(), 14, Color(0.50, 0.36, 0.10)))
		box.add_child(_mk_label("先把前几桌拍完 —— 本作故意让挂机晚一点登场。", 12, Color(0.44, 0.39, 0.32)))
		return

	box.add_child(_mk_label("建筑产出 %s / 小时　·　离线效率 %.0f%%" % [
		GameState.fmt(GameState.gold_per_hour()), GameState.offline_efficiency() * 100.0], 13,
		Color(0.13, 0.34, 0.21)))

	var b := Button.new()
	b.text = "打开全屏城建（放建筑 / 强化 / 合成）"
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(func():
		_set_drawer(false)
		_open_city())
	box.add_child(b)

	# 一览：每处已克服城池的槽位占用（v1.0：新野克服后也在此列，它也有 1 个槽位）
	for r in GameData.regions:
		var i := int(r["idx"])
		if GameState.region_status(i) != "cleared":
			continue
		var arr := GameState.city_buildings(i)
		var slots := GameState.city_slots(i)
		box.add_child(_mk_label("%s　%s　槽位 %d/%d　%s/时" % [
			str(r.get("county", "")), str(r.get("name", "?")), arr.size(), slots,
			GameState.fmt(city_output(i))], 12, Color(0.28, 0.36, 0.28)))


func city_output(idx: int) -> float:
	var total := 0.0
	for k in range(GameState.city_buildings(idx).size()):
		total += GameState.building_output(idx, k)
	return total


func _fill_routes() -> void:
	var box: VBoxContainer = _shop_boxes["路线"]
	_clear(box)
	box.add_child(_mk_label("选路线 = 选武将池 + 选 combo 方向 + 选难度手感。软锁：都能走，专精有奖励。", 12))
	for rt in GameData.routes:
		box.add_child(_mk_route_row(rt))


func _mk_route_row(rt: Dictionary) -> Control:
	var name: String = rt.get("name", "")
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROUTE_COLOR.get(name, Color.GRAY).lerp(PAPER, 0.88)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = ROUTE_COLOR.get(name, Color.GRAY)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(_mk_label("%s　%s　难度 %s" % [
		name, rt.get("counties", ""), rt.get("difficulty", "")], 14))
	vb.add_child(_mk_label("combo：%s" % rt.get("combo", ""), 12, Color(0.38, 0.33, 0.26)))
	var bond := GameState.bond_tier(name)
	vb.add_child(_mk_label("亲和 %d　·　羁绊 %s　·　卡组内同线 %d 张" % [
		int(GameState.affinity.get(name, 0)),
		["未触发", "一档（3 张）", "二档（6 张）"][bond],
		GameState.route_unit_count(name)], 12, Color(0.38, 0.33, 0.26)))
	return panel


func _fill_collection() -> void:
	var box: VBoxContainer = _shop_boxes["收藏"]
	_clear(box)
	var by_type := {}
	for id in GameState.owned.keys():
		var c := GameData.card(id)
		if c.is_empty():
			continue
		var t: String = c.get("type", "?")
		if not by_type.has(t):
			by_type[t] = []
		by_type[t].append({"c": c, "n": int(GameState.owned[id])})

	var order := ["初始武将", "士兵", "武将", "装备", "城池", "建筑"]
	var summary := []
	for t in order:
		if by_type.has(t):
			var n := 0
			for e in by_type[t]:
				n += int(e["n"])
			summary.append("%s %d 种/%d 张" % [t, by_type[t].size(), n])
	box.add_child(_mk_label("持有：" + _join_str(summary, "　"), 12))
	box.add_child(_mk_label("上阵战力 %.1f（倍率 ×%.2f）—— 只有大本营里「上阵」的卡才算战力" % [
		GameState.deck_power(), GameState.power_multiplier()], 12, Color(0.30, 0.34, 0.24)))

	for t in order:
		if not by_type.has(t):
			continue
		box.add_child(_mk_label("— %s —" % t, 13, Color(0.34, 0.29, 0.23)))
		for e in by_type[t]:
			var c: Dictionary = e["c"]
			box.add_child(_mk_label("　%s x%d　%s　[%s]　%s" % [
				c.get("name", "?"), e["n"], GameData.star_text(int(c.get("star", 0))),
				c.get("route", ""), c.get("effect", "")], 11, Color(0.42, 0.37, 0.30)))


# =====================================================================
# 战报
# =====================================================================
func _append_log(t: String) -> void:
	_log_lines.append(t)
	while _log_lines.size() > LOG_MAX:
		_log_lines.pop_front()
	_render_log()


func _render_log() -> void:
	if _log_lbl == null:
		return
	_log_lbl.text = "　·　".join(_log_lines)


func _join_str(arr: Array, sep: String) -> String:
	var s := ""
	for i in range(arr.size()):
		if i > 0:
			s += sep
		s += str(arr[i])
	return s


# =====================================================================
# 底部上阵条：拖拽源 / 落点（v1.0）
# =====================================================================
## ⚠️ 用**内部类**而不是新建 class_name 脚本 —— 新 class_name 会写进全局类缓存，
##    没跑 `--import` 就直接报 `Could not find type`（本项目已经踩过两次）。
## ⚠️ 这些控件的**子 Label 必须 mouse_filter = IGNORE**：Godot 只问鼠标下**最上面那个**
##    Control 要不要 `_get_drag_data()`，不会往上冒泡 —— 子 Label 吃掉了按下事件，
##    父容器就永远收不到拖拽起手。

## 卡池里的一张将兵牌：拖出去 → 落到槽位上阵。
class _PoolCard extends PanelContainer:
	# ⚠️ host **不能**标注成 Control：那样分析器会在 `host._drag_preview()` 上报
	#    "Function not found in base Control"，因为它只知道 Control 的成员。
	#    留成 Variant 走动态派发，才能在运行时调到父脚本 main.gd 的方法。
	var host = null                     # 即 main.gd（父脚本）
	var card_id := ""

	func _get_drag_data(_at: Vector2) -> Variant:
		if card_id == "" or host == null:
			return null
		# ⚠️ set_drag_preview() 只在**真实拖拽会话**里合法，否则引擎会打
		#    "Condition !get_viewport()->gui_is_dragging() is true" 的 ERROR。
		#    自检（无头）会直接调 _get_drag_data() 来验 payload —— 那时没有拖拽会话，
		#    所以必须先问一句。（已实测：真实拖拽时 gui_is_dragging() 确实是 true，
		#    所以这个守卫不会让预览消失。）
		var vp := get_viewport()
		if vp != null and vp.gui_is_dragging():
			set_drag_preview(host._drag_preview(card_id))
		# 用带 kind 的字典而不是裸 id：防止"把卡池牌拖到卡池上"被当成一次成功操作
		return {"paan_kind": "pool", "id": card_id}


## 一个上阵槽位。收卡池来的牌；左键点一下 = 卸下。主角位 locked，两点都不响应。
class _Slot extends PanelContainer:
	var host = null                     # main.gd（同上，必须留 Variant）
	var card_id := ""
	var slot_index := -1
	var locked := false

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if locked or host == null:
			return false
		return data is Dictionary and str((data as Dictionary).get("paan_kind", "")) == "pool"

	func _drop_data(_at: Vector2, data: Variant) -> void:
		host._deploy_at(str((data as Dictionary).get("id", "")), slot_index)

	func _gui_input(ev: InputEvent) -> void:
		if locked or card_id == "":
			return
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				host._undeploy(card_id)
				accept_event()
