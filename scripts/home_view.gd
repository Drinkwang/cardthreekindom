extends PanelContainer
class_name PaanHome
## 《拍案三国》大本营 —— 全屏覆盖层。
##
## 这是「局与局之间」的落脚点：耐力耗尽 -> 强制结算 -> 回到这里。
##   左栏：技能树（v1.1 分三层 + 浅前置）—— 耐力 / 拍力 / 携带位 / 暴击 / 财路 /
##        挂机效率 / 装备槽 / **武将带兵**；金币的主去处
##   中栏：出征（上一次结算战报 + 推荐目标 + 出战 / 打开舆图）
##   右栏：上阵（携带位 + 逐个武将升级 + **每个武将各自的装备巢与兵位**）/ 城建入口
##
## 主界面永远是一张桌子；大本营只是盖在它上面的另一层，不替代拍卡。

signal deploy(idx: int)          # 出战某个区域
signal request_map()             # 打开荆州舆图
signal request_city()            # 打开全屏城建
signal closed()                  # 收起大本营

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
	"现实线": Color(0.37, 0.21, 0.47),
}

var _title: Label
var _stats: Label
var _up_box: VBoxContainer
var _mid_box: VBoxContainer
var _right_box: VBoxContainer
var _foot: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_bg_rect("home.png"))   # 旧屋书桌：大本营 = 把一堆摊开的纸铺在桌上
	_build()


## 打开：先撑满再刷内容。
## 覆盖层初始是隐藏的，全屏锚点不会自动结算 —— 复用 reveal_view 的同一套修法。
func open_home() -> void:
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

	# 左：升级树
	var lp := PanelContainer.new()
	lp.custom_minimum_size = Vector2(392, 0)
	lp.add_theme_stylebox_override("panel", _paper_panel())
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(lscroll)
	_up_box = VBoxContainer.new()
	_up_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_up_box.add_theme_constant_override("separation", 6)
	lscroll.add_child(_up_box)
	mid.add_child(lp)

	# 中：出征
	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.add_theme_stylebox_override("panel", _paper_panel())
	var mscroll := ScrollContainer.new()
	mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mp.add_child(mscroll)
	_mid_box = VBoxContainer.new()
	_mid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mid_box.add_theme_constant_override("separation", 6)
	mscroll.add_child(_mid_box)
	mid.add_child(mp)

	# 右：上阵 / 装备 / 城建
	var rp := PanelContainer.new()
	rp.custom_minimum_size = Vector2(380, 0)
	rp.add_theme_stylebox_override("panel", _paper_panel())
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rscroll)
	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 5)
	rscroll.add_child(_right_box)
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

	_title = _mk_label("大本营", 22, ACCENT)
	th.add_child(_title)
	_stats = _mk_label("", 14, INK2)
	th.add_child(_stats)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp)

	var bmap := Button.new()
	bmap.text = "荆州舆图"
	bmap.pressed.connect(func(): request_map.emit())
	th.add_child(bmap)

	var bcity := Button.new()
	bcity.text = "城建"
	bcity.pressed.connect(func(): request_city.emit())
	th.add_child(bcity)

	var bc := Button.new()
	bc.text = "✕  收起"
	bc.pressed.connect(func(): closed.emit())
	th.add_child(bc)
	return top


# =====================================================================
# 刷新
# =====================================================================
func refresh() -> void:
	if _up_box == null:
		return
	_title.text = "大本营"
	_stats.text = "Lv.%d　·　第 %d 趟　·　金币 %s　·　战力 %.1f　·　耐力 %d" % [
		GameState.player_level(), GameState.runs, GameState.fmt(GameState.gold),
		GameState.deck_power(), GameState.stamina_max_value()]
	_fill_upgrades()
	_fill_mid()
	_fill_right()
	_foot.text = "升级 → 出征 → 耐力耗尽强制结算 → 回大本营。金币是唯一带得出来的东西。" \
		+ "　·　未克服的区域每次进场都满血重来"


func _fill_upgrades() -> void:
	_clear(_up_box)
	_up_box.add_child(_mk_label("技能树", 17, ACCENT))
	_up_box.add_child(_mk_label("金币的主去处。局与局之间，你在这里变强。", 11, DIM))
	_up_box.add_child(_mk_label("上层先点亮一个，下层才会开。前置只要求「点亮过一次」，不卡等级。", 11, DIM))
	# v1.1：从平铺列表改成**分层技能树**（层级 / 前置见 GameState.SKILL_TREE）。
	for t in GameState.SKILL_TIERS:
		var nodes: Array = GameState.skills_of_tier(int(t))
		if nodes.is_empty():
			continue
		var got := GameState.skill_tier_progress(int(t))
		var hd := HBoxContainer.new()
		hd.add_theme_constant_override("separation", 6)
		var tl := _mk_label(str(GameState.SKILL_TIER_NAME.get(int(t), "第 %d 层" % t)), 14, ACCENT)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hd.add_child(tl)
		hd.add_child(_mk_label("%d/%d 已点亮" % [got, nodes.size()], 11,
			GOOD if got >= nodes.size() else DIM))
		_up_box.add_child(hd)
		# ⚠️ skills_of_tier() 给的是**技能 id（字符串）**，不是数值定义 ——
		#    必须用 up_def() 换成 UPGRADES 里的字典，否则 _mk_upgrade_row 类型不匹配。
		for sid in nodes:
			var u := GameState.up_def(str(sid))
			if not u.is_empty():
				_up_box.add_child(_mk_upgrade_row(u))
		_up_box.add_child(_mk_label("", 4))


func _mk_upgrade_row(u: Dictionary) -> Control:
	var id := str(u["id"])
	var lv := GameState.upgrade_level(id)
	var maxed := GameState.upgrade_maxed(id)
	var cur := GameState.upgrade_value(id)
	# ⚠️ 不能用 cur + step ——「拍力」v1.0 起是复利（×factor/级），加 step 会算错。
	var nxt := GameState.upgrade_next_value(id)
	var cost := GameState.upgrade_cost(id)
	var afford := GameState.gold >= float(cost)
	# v1.1：技能树前置（浅门槛 —— 前置点亮过一次即可）
	var locked := not GameState.skill_req_met(id)

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		_flat(PAPER if locked else PAPER_ROW, PAPER_RULE, 1, 6))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	p.add_child(hb)

	var nm := _mk_label(str(u["name"]), 15, DIM if locked else INK)
	nm.custom_minimum_size = Vector2(72, 0)
	hb.add_child(nm)

	var lvl := _mk_label("Lv.%d" % lv, 11, DIM)
	lvl.custom_minimum_size = Vector2(40, 0)
	hb.add_child(lvl)

	var vt := "%s → %s" % [_fmtv(cur, u), "满" if maxed else _fmtv(nxt, u)]
	var val := _mk_label(vt, 13, DIM if (maxed or locked) else (GOOD if afford else WARN))
	val.custom_minimum_size = Vector2(132, 0)
	hb.add_child(val)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)

	var b := Button.new()
	if maxed:
		b.text = "已满级"
		b.disabled = true
	elif locked:
		b.text = "未解锁"
		b.disabled = true
	else:
		b.text = "升级 %d" % cost
		b.disabled = not afford
		b.pressed.connect(_on_buy.bind(id))
	hb.add_child(b)

	wrap.add_child(p)
	wrap.add_child(_mk_label("　" + str(u["desc"]), 11, DIM))
	if locked:
		wrap.add_child(_mk_label("　※ " + GameState.skill_req_text(id), 11, WARN))
	return wrap


func _fill_mid() -> void:
	_clear(_mid_box)
	_mid_box.add_child(_mk_label("出征", 17, ACCENT))

	if GameState.last_settle != "":
		_mid_box.add_child(_mk_label("上一次结算", 11, DIM))
		var lb := _mk_label(GameState.last_settle, 12, INK2)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size = Vector2(320, 0)
		_mid_box.add_child(lb)

	var idx := recommend_region()
	if idx <= 0:
		_mid_box.add_child(_mk_label("", 8))
		_mid_box.add_child(_mk_label("荆州八郡已定 —— 没有可挑战的区域了。", 15, GOOD))
		return

	var r := GameData.region(idx)
	var route := str(r.get("route", ""))
	var accent: Color = ROUTE_COLOR.get(route, Color.GRAY)
	var total_hp := float(r.get("total_hp", 0))
	var dmg := GameState.click_damage()
	var stamina := GameState.stamina_max_value()
	var cap := dmg * float(stamina)
	var need := GameState.slaps_needed(idx)

	_mid_box.add_child(_mk_label("下一桌（推荐 · 守军最薄的一处）", 11, DIM))
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.lerp(PAPER, 0.86)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 3)
	p.add_child(pv)
	pv.add_child(_mk_label("%d. %s" % [idx, r.get("name", "?")], 20, INK))
	pv.add_child(_mk_label("%s　·　%s　·　%s" % [route, r.get("county", ""), r.get("difficulty", "")], 12,
		DIM))
	pv.add_child(_mk_label("守军 %d 张　·　总血量 %s" % [int(r.get("enemy_count", 0)), GameState.fmt(total_hp)],
		13, INK))
	pv.add_child(_mk_label("你的伤害 %s / 拍　·　耐力 %d → 最多打出 %s" % [
		_pw(dmg), stamina, GameState.fmt(cap)], 13, INK))
	var verdict := "约需 %d 拍 —— 够了，能清" % need
	var vcol := GOOD
	if need > stamina:
		verdict = "约需 %d 拍 —— 还差 %d 拍，先升级或换一处" % [need, need - stamina]
		vcol = BAD
	pv.add_child(_mk_label(verdict, 14, vcol))
	if GameState.city_unlocked():
		pv.add_child(_mk_label("克服后：得城池卡「%s」· 建筑槽位 %d" % [
			r.get("city", ""), GameState.city_slots(idx)], 12, GOOD))
	_mid_box.add_child(p)

	_mid_box.add_child(_mk_label("", 6))
	var bd := Button.new()
	bd.text = "出  战  ▶"
	bd.custom_minimum_size = Vector2(0, 52)
	bd.pressed.connect(_on_deploy.bind(idx))
	_mid_box.add_child(bd)

	var bm := Button.new()
	bm.text = "打开荆州舆图（挑别处）"
	bm.custom_minimum_size = Vector2(0, 38)
	bm.pressed.connect(func(): request_map.emit())
	_mid_box.add_child(bm)

	_mid_box.add_child(_mk_label("", 8))
	_mid_box.add_child(_mk_label("可挑战的区域", 11, DIM))
	for rr in GameData.regions:
		var i := int(rr["idx"])
		if GameState.region_status(i) != "available":
			continue
		var row := HBoxContainer.new()
		var lb := _mk_label("%s　%s　总血 %s" % [rr.get("name", "?"), rr.get("route", ""),
			GameState.fmt(float(rr.get("total_hp", 0)))], 12, INK2)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		var bb := Button.new()
		bb.text = "出战"
		bb.pressed.connect(_on_deploy.bind(i))
		row.add_child(bb)
		_mid_box.add_child(row)


func _fill_right() -> void:
	_clear(_right_box)

	# ---- 上阵 ----
	_right_box.add_child(_mk_label("上阵（携带位）", 17, ACCENT))
	_right_box.add_child(_mk_label("只有上阵的卡才算战力与被动；仓库里堆着的不算。", 11, DIM))
	var hero := GameData.card(GameState.HERO_ALWAYS)
	_right_box.add_child(_mk_label("● %s　主角 · 常驻不占位　战力 %s" % [
		hero.get("name", "?"), _pw(GameState.hero_power())], 12, INK))
	for id in GameState.carry:
		_right_box.add_child(_mk_carry_row(str(id)))
	var full := GameState.carry.size() >= GameState.carry_max()
	_right_box.add_child(_mk_label("携带位 %d / %d　（升级「携带位」可到 %d）" % [
		GameState.carry.size(), GameState.carry_max(), 6], 12, DIM if full else GOOD))
	_right_box.add_child(_mk_carry_menu())

	# ---- 装备巢：⚠️ v1.1 每将独立 ----
	# 用户纠错：装备不是「一个城里共用的 5 格」，而是**每个武将各自一套**。
	# 所以这里不再列 5 个全局槽位 —— 装备巢直接长在每个武将行下面（见 _mk_carry_row）。
	_right_box.add_child(_mk_label("", 8))
	_right_box.add_child(_mk_label("装备巢 · 每将独立", 17, ACCENT))
	if GameState.equip_slots() <= 0:
		_right_box.add_child(_mk_label("尚未解锁 —— 点亮技能树「装备槽」依次开启五部位。", 12, WARN))
	else:
		_right_box.add_child(_mk_label("已解锁 %d / 5 部位　·　每个武将各一套（士兵没有装备巢）" % [
			GameState.equip_slots()], 11, GOOD))
	_right_box.add_child(_mk_label("装备卡只从卡包开出，不再摆在桌上要你拍。装备巢就在下面每个武将的名字底下。", 11, DIM))
	if GameState.troop_slots() <= 0:
		_right_box.add_child(_mk_label("兵位：未解锁 —— 点亮技能树「武将带兵」，士卒就能挂到武将麾下（不占携带位）。", 11, DIM))
	else:
		_right_box.add_child(_mk_label("兵位：每将 %d 个　·　士卒可以当武将出战，也可以挂到武将麾下" % [
			GameState.troop_slots()], 12, GOOD))

	# ---- 城建（全屏） ----
	_right_box.add_child(_mk_label("", 8))
	_right_box.add_child(_mk_label("城建（挂机）", 17, ACCENT))
	if not GameState.city_unlocked():
		_right_box.add_child(_mk_label("尚未解锁　·　%s" % GameState.city_unlock_text(), 12, WARN))
		_right_box.add_child(_mk_label("克服区域 → 得城池卡（地基）→ 放建筑卡 → 建筑产钱。", 11, DIM))
	else:
		_right_box.add_child(_mk_label("建筑产出 %s / 小时" % GameState.fmt(GameState.gold_per_hour()), 13, GOOD))
		_right_box.add_child(_mk_label("离线效率 %.0f%%　·　离线上限 %.0f 小时　·　已克服 %d 处" % [
			GameState.offline_efficiency() * 100.0, GameState.offline_cap_hours(),
			GameState.cleared_count()], 12, DIM))
	var bc := Button.new()
	bc.text = "打开城建 ▶"
	bc.custom_minimum_size = Vector2(0, 40)
	bc.disabled = not GameState.city_unlocked()
	bc.pressed.connect(func(): request_city.emit())
	_right_box.add_child(bc)


## 上阵卡的一行：等级 / 被动 / 战力 / 升级 / 卸下
## 只有「武将」能练级（士兵等是素材，不显示升级按钮，避免点了没反应）。
func _mk_carry_row(id: String) -> Control:
	var c := GameData.card(id)
	var is_hero := GameState.is_hero(id)
	var lv := GameState.hero_level(id)
	var maxed := GameState.hero_lv_maxed(id)
	var cost := GameState.hero_lv_cost(id)
	var afford := GameState.gold >= float(cost)

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		_flat(PAPER_ROW, PAPER_RULE, 1, 5))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	var nm := _mk_label("%s %s" % [str(c.get("name", "?")),
		GameData.star_text(int(c.get("star", 0)))], 13, INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if is_hero:
		top.add_child(_mk_label("Lv.%d/%d" % [lv, GameState.hero_lv_max(id)], 11,
			ACCENT if not maxed else DIM))
	else:
		top.add_child(_mk_label("素材", 11, DIM))
	vb.add_child(top)

	var eff := str(c.get("effect", ""))
	if eff != "" and eff != "-":
		var el := _mk_label(eff, 11, GOOD if is_hero else DIM)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.custom_minimum_size = Vector2(330, 0)
		vb.add_child(el)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 5)
	var plb := _mk_label("战力 %s" % _pw(GameState.hero_card_power(id)), 12, INK)
	plb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(plb)
	if is_hero:
		var up := Button.new()
		if maxed:
			up.text = "已练满"
			up.disabled = true
		else:
			up.text = "升级 %d" % cost
			up.disabled = not afford
			up.pressed.connect(_on_hero_lv.bind(id))
		brow.add_child(up)
	var rb := Button.new()
	rb.text = "卸下"
	rb.pressed.connect(_on_carry.bind(id))
	brow.add_child(rb)
	vb.add_child(brow)

	# ⚠️ v1.1：装备巢 + 兵位**长在每个武将这一行里面**（每将独立，不再是全局 5 格）。
	# 士兵没有装备巢（用户明确：「士兵没有装备巢」），所以只有武才会展开。
	if is_hero:
		vb.add_child(_mk_hero_nest(id))
	return p


## ⚠️ v1.1：一个武将的**装备巢（五部位）+ 兵位**。
##   放进 _mk_carry_row 里面，让人一眼看出「这套装备是挂在这个武将身上的」——
##   这正是用户纠错的核心：装备巢不是全局的，是每个武将各自一套。
func _mk_hero_nest(who: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var used := GameState.hero_equip_of(who).size()
	var slots := GameState.equip_slots()
	box.add_child(_mk_label("　装备巢 %d / %d 部位" % [used, slots], 11,
		GOOD if used > 0 else DIM))
	if slots <= 0:
		box.add_child(_mk_label("　　未解锁 —— 点亮技能树「装备槽」", 11, WARN))
	for sub in GameState.EQUIP_SLOTS:
		box.add_child(_mk_hero_equip_row(who, str(sub)))

	# 兵位：技能树「武将带兵」点亮后才有（0 兵位时这一行整块不显示）
	if GameState.troop_cap(who) > 0:
		box.add_child(_mk_troop_row(who))
	return box


## 武将 who 的某个部位那一行：未解锁 / 空槽 / 已装。
func _mk_hero_equip_row(who: String, sub: String) -> Control:
	var unlocked := GameState.is_slot_unlocked(sub)
	var col: Color = GameState.EQUIP_SLOT_COLOR.get(sub, Color(0.62, 0.62, 0.62))

	var p := PanelContainer.new()
	if unlocked:
		p.add_theme_stylebox_override("panel", _flat(col.lerp(PAPER, 0.86), col, 1, 5))
	else:
		p.add_theme_stylebox_override("panel",
			_flat(PAPER, PAPER_RULE, 1, 5))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	p.add_child(hb)

	var nl := _mk_label("　" + sub, 12, col if unlocked else DIM)
	nl.custom_minimum_size = Vector2(52, 0)
	hb.add_child(nl)

	var lb := _mk_label("", 12, INK)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.custom_minimum_size = Vector2(140, 0)
	hb.add_child(lb)

	if not unlocked:
		lb.text = "未解锁"
		lb.add_theme_color_override("font_color", DIM)
		return p

	var id := GameState.hero_equipped_in_slot(who, sub)
	if id == "":
		lb.text = "空 · %s" % str(GameState.EQUIP_SLOT_DESC.get(sub, ""))
		lb.add_theme_color_override("font_color", DIM)
		hb.add_child(_mk_hero_equip_menu(who, sub))
	else:
		var c := GameData.card(id)
		lb.text = "%s　%s" % [str(c.get("name", "?")), str(c.get("effect", ""))]
		var rb := Button.new()
		rb.text = "卸下"
		rb.pressed.connect(_on_unequip.bind(who, id))
		hb.add_child(rb)
	return p


## 该部位可选的装备。
## ⚠️ 已经被**别的武将**穿着的那件也列出来（点了 = 直接转移过去，不是多出一件），
##    但要标注「在××身上」，否则玩家会以为凭空复制了一件。
func _mk_hero_equip_menu(who: String, sub: String) -> Control:
	var menu := MenuButton.new()
	menu.text = "＋"
	menu.custom_minimum_size = Vector2(34, 28)
	var pop := menu.get_popup()
	pop.clear()
	var any := false
	for id in GameState.owned.keys():
		var c := GameData.card(str(id))
		if str(c.get("type", "")) != "装备" or int(GameState.owned[id]) <= 0:
			continue
		if str(c.get("subtype", "")) != sub:
			continue
		any = true
		var owner := GameState.equip_owner(str(id))
		var tag := "" if (owner == "" or owner == who) else "（在%s身上）" % GameData.card_name(owner)
		pop.add_item("%s　%s%s" % [str(c.get("name", "?")), str(c.get("effect", "")), tag])
		pop.set_item_metadata(pop.item_count - 1, str(id))
	if not any:
		pop.add_item("（仓库里没有%s，去开卡包）" % sub)
		pop.set_item_disabled(0, true)
	pop.id_pressed.connect(_on_menu_pick_hero_equip.bind(who, pop))
	return menu


## ⚠️ v1.1：兵位 —— 挂上来的士卒**不占携带位**，战力照样全额计入卡组。
func _mk_troop_row(who: String) -> Control:
	var cap := GameState.troop_cap(who)
	var mine := GameState.hero_troops_of(who)

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(PAPER_ROW, PAPER_RULE, 1, 5))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var tl := _mk_label("　兵位 %d / %d　（不占携带位）" % [mine.size(), cap], 11,
		GOOD if mine.size() > 0 else DIM)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(tl)
	if mine.size() < cap:
		hb.add_child(_mk_troop_menu(who))
	vb.add_child(hb)

	for tid in mine:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lb := _mk_label("　　%s　战力 %s" % [GameData.card_name(str(tid)),
			_pw(float(GameData.card(str(tid)).get("power", 0.0)))], 12, INK)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		var rb := Button.new()
		rb.text = "撤"
		rb.pressed.connect(_on_troop_remove.bind(who, str(tid)))
		row.add_child(rb)
		vb.add_child(row)

	if mine.is_empty():
		vb.add_child(_mk_label("　　（空 —— 士卒可以当武将出战，也可以挂到这里）", 11, DIM))
	return p


## 可派到这个武将麾下的士卒。已被别的将领走的会标注「在××麾下」。
func _mk_troop_menu(who: String) -> Control:
	var menu := MenuButton.new()
	menu.text = "＋ 派兵"
	menu.custom_minimum_size = Vector2(0, 28)
	var pop := menu.get_popup()
	pop.clear()
	var any := false
	for id in GameState.owned.keys():
		var sid := str(id)
		if not GameState.is_troop(sid) or int(GameState.owned[sid]) <= 0:
			continue
		var owner := GameState.troop_owner(sid)
		if owner == who:
			continue
		any = true
		var tag := "" if owner == "" else "（在%s麾下）" % GameData.card_name(owner)
		pop.add_item("%s %s　战力 %s%s" % [GameData.card_name(sid),
			GameData.star_text(int(GameData.card(sid).get("star", 0))),
			_pw(float(GameData.card(sid).get("power", 0.0))), tag])
		pop.set_item_metadata(pop.item_count - 1, sid)
	if not any:
		pop.add_item("（仓库里没有士卒，去开卡包）")
		pop.set_item_disabled(0, true)
	pop.id_pressed.connect(_on_menu_pick_troop.bind(who, pop))
	return menu


func _mk_carry_menu() -> Control:
	var menu := MenuButton.new()
	menu.text = "＋ 上阵武将"
	menu.custom_minimum_size = Vector2(0, 34)
	var pop := menu.get_popup()
	pop.clear()
	var any := false
	for id in GameState.owned.keys():
		if not GameState.is_carryable(str(id)) or int(GameState.owned[id]) <= 0:
			continue
		if GameState.in_carry(str(id)):
			continue
		any = true
		var c := GameData.card(str(id))
		pop.add_item("%s %s　战力 %s" % [c.get("name", "?"), GameData.star_text(int(c.get("star", 0))),
			_pw(GameState.hero_card_power(str(id)))])
		pop.set_item_metadata(pop.item_count - 1, str(id))
	if not any:
		pop.add_item("（没有可上阵的卡，去抽屉开卡包）")
		pop.set_item_disabled(0, true)
	pop.id_pressed.connect(_on_menu_pick_carry.bind(pop))
	return menu


# =====================================================================
# 回调
# =====================================================================
func _on_buy(id: String) -> void:
	GameState.buy_upgrade(id)


func _on_carry(id: String) -> void:
	GameState.carry_remove(id)


func _on_hero_lv(id: String) -> void:
	GameState.buy_hero_lv(id)


## v1.1：装备是每将独立的，所以卸下必须知道「从谁身上」。
func _on_unequip(who: String, id: String) -> void:
	GameState.unequip_from(who, id)


func _on_troop_remove(who: String, id: String) -> void:
	GameState.troop_remove(who, id)


func _on_deploy(idx: int) -> void:
	deploy.emit(idx)


func _on_menu_pick_carry(pid: int, pop: PopupMenu) -> void:
	var md = pop.get_item_metadata(pid)
	if md != null:
		GameState.carry_add(str(md))


## ⚠️ bind 的参数**排在信号参数之后** —— id_pressed(id) + bind(who, pop) → (id, who, pop)。
func _on_menu_pick_hero_equip(pid: int, who: String, pop: PopupMenu) -> void:
	var md = pop.get_item_metadata(pid)
	if md != null:
		GameState.equip_to(who, str(md))


func _on_menu_pick_troop(pid: int, who: String, pop: PopupMenu) -> void:
	var md = pop.get_item_metadata(pid)
	if md != null:
		GameState.troop_put(who, str(md))


# =====================================================================
# 推荐：可挑战区域里守军最薄的那一处
# =====================================================================
func recommend_region() -> int:
	var best := -1
	var best_hp := 1e20
	for r in GameData.regions:
		var i := int(r["idx"])
		if GameState.region_status(i) != "available":
			continue
		var hp := float(r.get("total_hp", 0))
		if hp < best_hp:
			best_hp = hp
			best = i
	return best


# =====================================================================
# 小工具（与 main.gd 同款，覆盖层自带一份，避免互相依赖）
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



func _fmtv(v: float, u: Dictionary) -> String:
	var unit := str(u.get("unit", ""))
	# 「拍力」是复利倍率（×1.15/级），取整会把它显示成"1倍"，必须带小数。
	if unit == "倍":
		return "×%.2f" % v
	return "%s%s" % [GameState.fmt(v), unit]


func _pw(v: float) -> String:
	# 战力很小（★1 士兵只有 0.2），用一位小数，别被四舍五入成 0
	if absf(v - roundf(v)) < 0.05:
		return GameState.fmt(v)
	return "%.1f" % v
