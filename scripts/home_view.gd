extends Control
class_name PaanHome
const Art = preload("res://scripts/ui/print_art.gd")
const UISkin = preload("res://scripts/ui/ui_skin.gd")
const DeckView = preload("res://scripts/deck_view.gd")
const UpgradeView = preload("res://scripts/upgrade_view.gd")
## 《拍案三国》大本营 —— 全屏覆盖层。
##
## 这是「轮与轮之间」的落脚点：限时拍击 -> 金币入账 -> 升级再来一轮。
##   首页：商店 / 构筑 / 升级 / 基建四块插画入口。
##   构筑与升级在内部子页整备；商店与基建交由主界面打开对应整页。
##   战果独立保留在底栏，不随购买、换装或返回营地而丢失。
##
## 主界面是一座城的牌堆；大本营盖在牌场之上，供轮与轮之间整备。

signal deploy(idx: int)          # 出战某个区域
signal request_map()             # 打开荆州舆图
signal request_city()            # 打开全屏城建
signal request_shop()            # 打开全屏商店
signal request_journal()         # 回看军中札记
signal practice_requested(idx: int) # 练习已掌握的城池牌堆
signal closed()                  # 收起大本营

# ── 传统套色印刷纸面配色 ────────────────────────────────
# 深色主题是给屏幕的，这套是给纸的：所有文字都是「纸上的墨」。
# 底色与 ui/panel.png 的主色对齐 —— 拿不到纹理时回退成纯色也不会跳色。
const BG_DIR := "res://assets/art_v2/backgrounds/"
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
var _up_box: VBoxContainer
var _mid_box: VBoxContainer
var _right_box: VBoxContainer
var _foot: Label
var _section := "hub"
var _hub_tiles: Dictionary = {}
var _primary_action: Button
var _secondary_action: Button
var _hub_page: GridContainer
var _section_page: VBoxContainer
var _section_tools: HBoxContainer
var _section_content: VBoxContainer
var _outcome_box: HBoxContainer
var _back_button: Button
var _build_tab := "上阵"
var _camp_atlas: Texture2D
var _deck_page: Control
var _upgrade_page: Control
var _outcome_signature := ""
var _progression_panel: PanelContainer
var _progression_goal: Label
var _practice_note: Label
var _practice_button: Button
var _automation_toggle: CheckButton


func _ready() -> void:
	theme = Art.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_bg_rect("table.png"))
	_build()


## 打开：先撑满再刷内容。
## 覆盖层初始是隐藏的，全屏锚点不会自动结算 —— 复用 reveal_view 的同一套修法。
func open_home() -> void:
	_fit_to_parent()
	visible = true
	return_to_hub()
	_fit_to_parent()


func open_section(section: String) -> void:
	var aliases := {"商店": "shop", "构筑": "deck", "build": "deck", "升级": "upgrade", "基建": "base", "city": "base"}
	var key := str(aliases.get(section, section))
	if key == "shop":
		request_shop.emit()
		return
	if key == "base":
		request_city.emit()
		return
	if key not in ["deck", "upgrade"]:
		return_to_hub()
		return
	_section = key
	if is_node_ready():
		_fit_to_parent()
		visible = true
		refresh()


func return_to_hub() -> void:
	_section = "hub"
	if is_node_ready():
		refresh()


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
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 22 if side in ["left", "right"] else 20)
	add_child(outer)
	var paper_frame := PanelContainer.new()
	paper_frame.add_theme_stylebox_override("panel", UISkin.panel(Art.PAPER, 12, Art.INK, 1))
	UISkin.chrome(paper_frame, "paper")
	outer.add_child(paper_frame)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	paper_frame.add_child(page)
	page.add_child(_build_top())
	page.add_child(_build_progression_strip())
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	_hub_page = GridContainer.new()
	_hub_page.name = "CampHub"
	_hub_page.columns = 2
	_hub_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hub_page.add_theme_constant_override("h_separation", 18)
	_hub_page.add_theme_constant_override("v_separation", 18)
	body.add_child(_hub_page)
	var entries := [
		["shop", "商店", "买卡包", "壹", "shop"],
		["deck", "构筑", "配将牌", "贰", "cards"],
		["upgrade", "升级", "练掌扩圈", "叁", "stamina"],
		["base", "基建", "经营城池", "肆", "city"],
	]
	for i in range(entries.size()):
		var entry: Array = entries[i]
		var tile := _build_hub_tile(str(entry[0]), str(entry[1]), str(entry[2]), str(entry[3]), str(entry[4]), i)
		_hub_tiles[str(entry[0])] = tile
		_hub_page.add_child(tile)
	_section_page = VBoxContainer.new()
	_section_page.name = "CampSection"
	_section_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_section_page.add_theme_constant_override("separation", 12)
	body.add_child(_section_page)
	_section_tools = HBoxContainer.new()
	_section_tools.add_theme_constant_override("separation", 12)
	_section_page.add_child(_section_tools)
	var sheet := PanelContainer.new()
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_theme_stylebox_override("panel", UISkin.panel(Art.PAPER, 18, Art.RULE, 1))
	UISkin.chrome(sheet, "paper")
	_section_page.add_child(sheet)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)
	_section_content = VBoxContainer.new()
	_section_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_section_content)
	_up_box = _section_content
	_mid_box = _section_content
	_right_box = _section_content
	_deck_page = DeckView.new()
	_deck_page.name = "DeckSection"
	_deck_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(_deck_page)
	_upgrade_page = UpgradeView.new()
	_upgrade_page.name = "UpgradeSection"
	_upgrade_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(_upgrade_page)
	var outcome := PanelContainer.new()
	outcome.name = "CampOutcome"
	outcome.custom_minimum_size.y = 108
	outcome.add_theme_stylebox_override("panel", UISkin.panel(Art.PAPER_LIGHT, 20, Art.GOLD, 1))
	UISkin.chrome(outcome, "footer")
	page.add_child(outcome)
	_outcome_box = HBoxContainer.new()
	_outcome_box.add_theme_constant_override("separation", 20)
	outcome.add_child(_outcome_box)
	refresh()


func _build_top() -> Control:
	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(0, 80)
	top.add_theme_stylebox_override("panel", _paper_panel())
	UISkin.chrome(top, "header")
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	top.add_child(th)
	th.add_child(Art.stamp("营", Vector2(45, 46)))
	_title = _mk_label("大本营", 42, INK)
	th.add_child(_title)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(space)
	_stats = _mk_label("", 15, INK2)
	th.add_child(_stats)
	var journal := Button.new()
	journal.name = "CampJournal"
	journal.text = "札记"
	journal.custom_minimum_size = Vector2(70, 40)
	UISkin.button(journal, false, true)
	journal.add_theme_font_size_override("font_size", 15)
	journal.tooltip_text = "回看军中札记与荆州征途。"
	journal.pressed.connect(func(): request_journal.emit())
	th.add_child(journal)
	_back_button = Button.new()
	_back_button.name = "ReturnToCamp"
	_back_button.text = "返回大本营"
	_back_button.custom_minimum_size = Vector2(138, 46)
	UISkin.button(_back_button)
	_back_button.pressed.connect(return_to_hub)
	th.add_child(_back_button)
	var bc := Button.new()
	bc.name = "ReturnToMain"
	bc.text = "← 返回主界面"
	bc.custom_minimum_size = Vector2(175, 46)
	UISkin.button(bc)
	bc.add_theme_font_size_override("font_size", 17)
	bc.pressed.connect(func(): closed.emit())
	th.add_child(bc)
	return top


func _build_progression_strip() -> Control:
	_progression_panel = PanelContainer.new()
	_progression_panel.name = "CampProgression"
	_progression_panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 8, Art.RULE, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_progression_panel.add_child(row)
	row.add_child(Art.stamp("练", Vector2(29, 34)))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 3)
	row.add_child(words)
	_progression_goal = _mk_label("", 15, INK)
	_progression_goal.name = "CampNextGoal"
	_progression_goal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(_progression_goal)
	_practice_note = _mk_label("", 12, DIM)
	_practice_note.name = "CampPracticeIncome"
	_practice_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(_practice_note)
	_practice_button = Button.new()
	_practice_button.name = "CampPractice"
	_practice_button.custom_minimum_size = Vector2(116, 38)
	_practice_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UISkin.button(_practice_button, true, true)
	_practice_button.pressed.connect(_on_practice)
	row.add_child(_practice_button)
	_automation_toggle = CheckButton.new()
	_automation_toggle.name = "CampAutomation"
	_automation_toggle.text = "自动赚钱"
	_automation_toggle.custom_minimum_size.y = 38
	_automation_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_automation_toggle.toggled.connect(_on_automation)
	row.add_child(_automation_toggle)
	return _progression_panel


func _refresh_progression() -> void:
	if _progression_panel == null:
		return
	_progression_panel.visible = _section not in ["deck", "upgrade"]
	_progression_goal.text = GameState.progression_hint()
	_progression_goal.tooltip_text = _progression_goal.text
	var unlocked := GameState.practice_unlocked()
	var idx := GameState.practice_region if GameState.practice_region > 0 else 1
	var name := str(GameData.region(idx).get("name", "新野"))
	_practice_button.text = "再拍" + name
	_practice_button.disabled = not unlocked or GameState.in_battle
	_practice_button.tooltip_text = "再拍一轮已掌握的城池牌堆，首次奖励只领取一次。" if unlocked else "先清完新野牌堆第 1 段，开放反复赚钱。"
	_automation_toggle.disabled = not GameState.auto_unlocked()
	_automation_toggle.set_pressed_no_signal(GameState.automation_enabled)
	_automation_toggle.tooltip_text = "自动拍击已掌握的城池牌堆，赚取金币供下一次升级。" if GameState.auto_unlocked() else "清完新野牌堆第 2 段，在升级页学会自动拍。"
	if unlocked and GameState.auto_unlocked():
		_practice_note.text = "自动基础 ≥ %s 金币 / 分（联动另计）　·　%s" % [_pw(GameState.practice_rate()), "自动赚钱中，随时可停" if GameState.automation_enabled else "自动拍只练已掌握牌堆"]
	elif unlocked:
		_practice_note.text = "每轮 %.0f 秒 · %.2f 拍 / 秒 · 第 2 段后可学自动拍" % [GameState.round_duration_value(), 1.0 / GameState.slap_interval()]
	else:
		_practice_note.text = "每轮 %.0f 秒 · 单击圆圈内卡牌赚钱 · 清堆后自动补牌" % GameState.round_duration_value()
	_practice_note.tooltip_text = _practice_note.text


# =====================================================================
# 刷新
# =====================================================================
func refresh() -> void:
	if _hub_page == null:
		return
	_title.text = {"hub": "大本营", "deck": "构筑 · 将牌册", "upgrade": "升级 · 练掌堂"}.get(_section, "大本营")
	_stats.text = "金币 %s　·　每轮 %.0f 秒\n拍力 %s　·　范围 %s　·　%.2f 拍 / 秒" % [GameState.fmt(GameState.gold), GameState.round_duration_value(), _pw(GameState.click_damage()), _pw(GameState.slap_radius()), 1.0 / GameState.slap_interval()]
	_hub_page.visible = _section == "hub"
	_section_page.visible = false
	_deck_page.visible = _section == "deck"
	_upgrade_page.visible = _section == "upgrade"
	_back_button.visible = _section != "hub"
	_refresh_progression()
	for key in _hub_tiles:
		var tile := _hub_tiles[key] as Button
		var status := tile.get_meta("status_label") as Label
		match str(key):
			"shop": status.text = "补充你的三国牌"
			"deck": status.text = "已上阵 %d / %d" % [GameState.carry.size(), GameState.carry_max()]
			"upgrade": status.text = "拍力 · 拍速 · 范围 · 时长"
			"base": status.text = "%s / 小时" % GameState.fmt(GameState.gold_per_hour()) if GameState.city_unlocked() else GameState.city_unlock_text()
	_clear(_section_tools)
	if _section == "upgrade":
		_upgrade_page.refresh()
	elif _section == "deck":
		_deck_page.refresh()
	var outcome_signature := str(GameState.last_outcome) + str(GameState.in_battle) + str(GameState.battle_region) + str(GameState.up)
	if outcome_signature != _outcome_signature or _outcome_box.get_child_count() == 0:
		_outcome_signature = outcome_signature
		_fill_outcome()
	elif GameState.in_battle and _foot != null:
		_foot.text = _active_round_note()
	if _secondary_action != null:
		_secondary_action.visible = _section != "upgrade"


func _build_hub_tile(key: String, title: String, subtitle: String, _mark: String, icon: String, index: int) -> Button:
	var compact := get_viewport_rect().size.y <= 740.0
	var tile := Button.new()
	tile.name = "Camp" + key.capitalize()
	tile.custom_minimum_size = Vector2(420, 160 if compact else 185)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.clip_contents = true
	tile.tooltip_text = "进入" + title
	tile.set_meta("section", key)
	for state in ["normal", "hover", "pressed", "focus"]:
		var shade := Art.PAPER_LIGHT.darkened(0.025 if state == "pressed" else 0.0)
		tile.add_theme_stylebox_override(state, UISkin.panel(shade, 12, Art.RED, 2 if state in ["hover", "focus"] else 1))
	var scene := TextureRect.new()
	scene.texture = _camp_texture(index)
	scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.offset_left = 7
	scene.offset_right = -7
	scene.offset_top = 7
	scene.offset_bottom = -7
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(scene)
	if scene.texture == null:
		scene.texture = Art.nav_icon(icon)
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		scene.anchor_left = 0.44
	var wash := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.27, 0.40, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color("f9edcf"), Color(0.976, 0.929, 0.812, 0.92), Color(0.976, 0.929, 0.812, 0.67), Color(0.976, 0.929, 0.812, 0.0), Color(0.976, 0.929, 0.812, 0.0)])
	var wash_texture := GradientTexture2D.new()
	wash_texture.gradient = gradient
	wash_texture.fill_from = Vector2(0, 0)
	wash_texture.fill_to = Vector2(1, 0)
	wash.texture = wash_texture
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.offset_left = 7
	wash.offset_right = -7
	wash.offset_top = 7
	wash.offset_bottom = -7
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(wash)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14 if compact else 18)
	margin.add_theme_constant_override("margin_bottom", 14 if compact else 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.custom_minimum_size.x = 176
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 6 if compact else 9)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 11)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _mk_label(title, 52 if compact else 64, Art.RED)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(name_label)
	words.add_child(heading)
	var caption := _mk_label(subtitle, 19 if compact else 22, INK2)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(caption)
	var status := _mk_label("", 13, DIM)
	status.custom_minimum_size.x = 176
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(status)
	tile.set_meta("status_label", status)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(space)
	tile.pressed.connect(open_section.bind(key))
	return tile


func _camp_texture(index: int) -> Texture2D:
	var path := "res://assets/art_v4/camp_atlas.png"
	if _camp_atlas == null and ResourceLoader.exists(path):
		_camp_atlas = load(path) as Texture2D
	if _camp_atlas == null:
		return null
	var cell := _camp_atlas.get_size() / Vector2(2, 2)
	var portrait := AtlasTexture.new()
	portrait.atlas = _camp_atlas
	portrait.region = Rect2(Vector2(index % 2, index / 2) * cell + Vector2(2, 2), cell - Vector2(4, 4))
	portrait.filter_clip = true
	return portrait


func _build_deck_tabs() -> void:
	for tab in ["上阵", "装备", "兵种"]:
		var button := Button.new()
		button.text = str(tab)
		button.custom_minimum_size = Vector2(140, 44)
		button.toggle_mode = true
		button.button_pressed = _build_tab == tab
		button.set_meta("deck_tab", tab)
		if _build_tab == tab:
			button.add_theme_stylebox_override("normal", Art.panel(Art.PAPER_LIGHT, 12, Art.RED, 2))
			button.add_theme_stylebox_override("pressed", Art.panel(Art.PAPER_LIGHT, 12, Art.RED, 2))
			button.add_theme_color_override("font_color", Art.RED)
		button.pressed.connect(func():
			_build_tab = str(tab)
			refresh())
		_section_tools.add_child(button)
	var note := _mk_label("上阵后才计入战力；装备与士卒各归一将。", 13, DIM)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_tools.add_child(note)


func _fill_deck_section() -> void:
	_clear(_right_box)
	var total := "携带 %d / %d　·　装备部位 %d / 5　·　每将兵位 %d" % [GameState.carry.size(), GameState.carry_max(), GameState.equip_slots(), GameState.troop_slots()]
	_right_box.add_child(_mk_label(total, 16, INK2))
	if _build_tab == "上阵":
		var hero := GameData.card(GameState.HERO_ALWAYS)
		_right_box.add_child(_mk_label("%s · 主角常驻，不占携带位　·　战力 %s" % [hero.get("name", "?"), _pw(GameState.hero_power())], 15, INK))
		_right_box.add_child(_mk_carry_menu())
		var carry_grid := GridContainer.new()
		carry_grid.columns = 2
		carry_grid.add_theme_constant_override("h_separation", 14)
		carry_grid.add_theme_constant_override("v_separation", 14)
		_right_box.add_child(carry_grid)
		for id in GameState.carry:
			var card := _mk_carry_row(str(id), false)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			carry_grid.add_child(card)
		if GameState.carry.is_empty():
			_right_box.add_child(_mk_label("还没有上阵将牌。点击上方‘上阵武将’，挑一张已拥有的卡。", 14, DIM))
		return
	var equipment := _build_tab == "装备"
	if equipment and GameState.equip_slots() <= 0:
		_right_box.add_child(_mk_label("尚未解锁装备部位：在升级页点亮‘装备槽’。", 15, WARN))
	elif not equipment and GameState.troop_slots() <= 0:
		_right_box.add_child(_mk_label("尚未解锁兵位：在升级页点亮‘武将带兵’。", 15, WARN))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_right_box.add_child(grid)
	var hero_count := 0
	for id in GameState.carry:
		var who := str(id)
		if not GameState.is_hero(who):
			continue
		hero_count += 1
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 12, Art.RULE, 1))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		card.add_child(column)
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 12)
		heading.add_child(Art.image(who, Vector2(64, 64)))
		heading.add_child(_mk_label(GameData.card_name(who), 23, INK))
		column.add_child(heading)
		if equipment:
			column.add_child(_mk_hero_nest(who, true, false))
		else:
			column.add_child(_mk_troop_row(who))
		grid.add_child(card)
	if hero_count == 0:
		_right_box.add_child(_mk_label("先在‘上阵’页带上一位武将，再为他配装备、派士卒。", 14, DIM))


func _fill_outcome() -> void:
	_clear(_outcome_box)
	_primary_action = null
	_secondary_action = null
	var result: Dictionary = {}
	var outcome: Variant = GameState.get("last_outcome")
	if outcome is Dictionary:
		result = outcome
	var idx := int(result.get("region", 0))
	var valid := idx > 0 and not GameData.region(idx).is_empty() and str(result.get("result", "")) in ["cleared", "settled"]
	var headline := "整备好，开始一轮"
	var detail := ""
	var mark := "拍"
	var primary_text := "开始拍击"
	var primary := Callable()
	var secondary_text := "去升级"
	var secondary: Callable = func(): open_section("upgrade")
	if GameState.in_battle:
		var region := GameData.region(GameState.battle_region)
		headline = "%s · 本轮进行中" % region.get("name", "城池牌堆")
		detail = _active_round_note()
		primary_text = "继续拍击"
		primary = func(): closed.emit()
	elif valid:
		var region := GameData.region(idx)
		mark = "财"
		headline = "%s · 本轮赚得 %s 金币" % [region.get("name", "?"), GameState.fmt(float(result.get("gold", 0.0)))]
		detail = "%d 次拍击　·　拍翻 %d 张　·　已清 %d 段　·　升级范围，一掌拍更多" % [int(result.get("slaps", 0)), int(result.get("kills", 0)), int(result.get("tables_flipped", 0))]
		primary_text = "再来一轮"
		if GameState.region_status(idx) == "cleared":
			primary = func(): practice_requested.emit(idx)
		else:
			primary = _on_deploy.bind(idx)
	else:
		idx = recommend_region()
		if idx <= 0:
			idx = GameState.practice_region if GameState.practice_region > 0 else 1
		var region := GameData.region(idx)
		headline = "%s · 每轮 %.0f 秒" % [region.get("name", "?"), GameState.round_duration_value()]
		detail = "%.2f 拍 / 秒　·　预计可拍约 %d 次　·　单击圈内卡牌，清堆自动补牌" % [1.0 / GameState.slap_interval(), ceili(GameState.round_duration_value() / GameState.slap_interval())]
		if GameState.region_status(idx) == "cleared":
			primary = func(): practice_requested.emit(idx)
		else:
			primary = _on_deploy.bind(idx)
	_outcome_box.add_child(Art.stamp(mark, Vector2(45, 54)))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 5)
	words.add_child(_mk_label(headline, 32, INK))
	_foot = _mk_label(detail, 14, INK2)
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_foot.custom_minimum_size.x = 300
	words.add_child(_foot)
	_outcome_box.add_child(words)
	_primary_action = Button.new()
	_primary_action.name = "OutcomePrimaryAction"
	_primary_action.text = primary_text
	_primary_action.custom_minimum_size = Vector2(154, 52)
	_primary_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_primary(_primary_action)
	if primary.is_valid():
		_primary_action.pressed.connect(primary)
	_outcome_box.add_child(_primary_action)
	if secondary.is_valid():
		_secondary_action = Button.new()
		_secondary_action.name = "OutcomeSecondaryAction"
		_secondary_action.text = secondary_text
		_secondary_action.custom_minimum_size = Vector2(128, 52)
		_secondary_action.add_theme_font_override("font", Art.title_font())
		_secondary_action.add_theme_font_size_override("font_size", 22)
		_secondary_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UISkin.button(_secondary_action)
		_secondary_action.pressed.connect(secondary)
		_outcome_box.add_child(_secondary_action)


func _active_round_note() -> String:
	return "剩余 %.1f 秒　·　已赚 %s 金币　·　已拍 %d 次　·　继续本轮拍击" % [GameState.round_seconds_left, GameState.fmt(GameState.run_gold), GameState.round_slaps]


func _fill_upgrades() -> void:
	_clear(_up_box)
	_up_box.add_child(_section_heading("壹", "练拍手册", "技能成长"))
	_up_box.add_child(_mk_label("拍力翻厚牌，拍速多连拍，范围让圆圈变大、一次拍更多卡，时长增加本轮赚钱时间。", 12, DIM))
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

	var nm := _mk_label(str(u["name"]), 16, DIM if locked else INK)
	nm.custom_minimum_size = Vector2(72, 0)
	hb.add_child(nm)

	var lvl := _mk_label("Lv.%d" % lv, 11, DIM)
	if id in ["auto", "auto_next"]:
		lvl.text = "已学会" if lv > 0 else "未学会"
	lvl.custom_minimum_size = Vector2(40, 0)
	hb.add_child(lvl)

	var vt := "%s → %s" % [_fmtv(cur, u), "满" if maxed else _fmtv(nxt, u)]
	if id == "auto":
		vt = "自动拍击已开放" if lv > 0 else "解锁自动拍 · 从手动拍力的 25% 起步"
	elif id == "auto_next":
		vt = "自动再开一轮已开放" if lv > 0 else "解锁自动下一轮 · 休息后继续赚钱"
	var val := _mk_label(vt, 14, DIM if (maxed or locked) else (GOOD if afford else WARN))

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)

	var b := Button.new()
	b.set_meta("upgrade_id", id)
	if maxed:
		b.text = "已学会" if id in ["auto", "auto_next"] else "已满级"
		b.disabled = true
	elif locked:
		b.text = "未解锁"
		b.disabled = true
	else:
		b.text = "%s %d" % ["解锁" if id in ["auto", "auto_next"] else "升级", cost]
		b.disabled = not afford
		b.pressed.connect(_on_buy.bind(id))
	hb.add_child(b)

	wrap.add_child(p)
	wrap.add_child(val)
	var description := _mk_label("　" + str(u["desc"]), 11, DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wrap.add_child(description)
	if locked:
		wrap.add_child(_mk_label("　※ " + GameState.skill_req_text(id), 11, WARN))
	return wrap


func _fill_mid() -> void:
	_clear(_mid_box)
	_mid_box.add_child(_section_heading("贰", "下一座城的牌堆", "出征"))

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
	var available_slaps := ceili(GameState.round_duration_value() / GameState.slap_interval())
	var cap := dmg * float(available_slaps)
	var need := GameState.slaps_needed(idx)

	_mid_box.add_child(_mk_label("下一城（推荐 · 牌堆最薄的一处）", 11, DIM))
	var p := PanelContainer.new()
	var sb := Art.panel(Art.PAPER_LIGHT, 10, Art.RULE, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 3)
	p.add_child(pv)
	var city_title := HBoxContainer.new()
	city_title.add_theme_constant_override("separation", 10)
	city_title.add_child(Art.stamp(Art.faction_label(route), Vector2(34, 34), accent))
	city_title.add_child(_mk_label("%02d  %s" % [idx, r.get("name", "?")], 25, INK))
	pv.add_child(city_title)
	pv.add_child(Art.image(Art.city_id(idx), Vector2(0, 150)))
	pv.add_child(_mk_label("%s　·　%s　·　%s" % [route, r.get("county", ""), r.get("difficulty", "")], 12,
		DIM))
	pv.add_child(_mk_label("守军 %d 张　·　总血量 %s" % [int(r.get("enemy_count", 0)), GameState.fmt(total_hp)],
		13, INK))
	pv.add_child(_mk_label("拍力 %s / 拍　·　每轮约 %d 拍 → 预计伤害 %s" % [
		_pw(dmg), available_slaps, GameState.fmt(cap)], 13, INK))
	var verdict := "拍力参考约 %d 拍清堆，扩大范围可同时命中更多卡" % need
	var vcol := GOOD
	if need > available_slaps:
		verdict = "拍力参考约 %d 拍清堆；先赚金币，提升拍力、拍速与范围" % need
		vcol = WARN
	pv.add_child(_mk_label(verdict, 14, vcol))
	if GameState.city_unlocked():
		pv.add_child(_mk_label("克服后：得城池卡「%s」· 建筑槽位 %d" % [
			r.get("city", ""), GameState.city_slots(idx)], 12, GOOD))
	_mid_box.add_child(p)

	_mid_box.add_child(_mk_label("", 6))
	var bd := Button.new()
	bd.text = "出  战  ▶"
	bd.custom_minimum_size = Vector2(0, 52)
	_style_primary(bd)
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
	_right_box.add_child(_section_heading("叁", "我的将牌", "上阵与整备"))
	_right_box.add_child(_mk_label("上阵的牌计入战力与被动。", 12, DIM))
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
	_right_box.add_child(_mk_label("装备来自卡包，直接挂到各武将名下。", 12, DIM))
	if GameState.troop_slots() <= 0:
		_right_box.add_child(_mk_label("兵位：未解锁 —— 点亮技能树「武将带兵」，士卒就能挂到武将麾下（不占携带位）。", 11, DIM))
	else:
		_right_box.add_child(_mk_label("兵位：每将 %d 个　·　士卒可以当武将出战，也可以挂到武将麾下" % [
			GameState.troop_slots()], 12, GOOD))

	# ---- 城建（全屏） ----
	_right_box.add_child(_mk_label("", 8))
	_right_box.add_child(_section_heading("肆", "城中生计", "建筑收益"))
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


## 上阵卡的一行：品质 / 被动 / 战力 / 同名合成 / 卸下。
func _mk_carry_row(id: String, include_nest: bool = true) -> Control:
	var c := GameData.card(id)
	var is_hero := GameState.is_hero(id)

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		_flat(PAPER_ROW, PAPER_RULE, 1, 5))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.add_child(Art.image(id, Vector2(64, 64)))
	var nm := _mk_label("%s %s" % [str(c.get("name", "?")),
		GameData.star_text(int(c.get("star", 0)))], 13, INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if is_hero:
		top.add_child(_mk_label(GameState.hero_quality_name(id), 11, ACCENT))
	else:
		top.add_child(_mk_label("素材", 11, DIM))
	vb.add_child(top)

	var eff := GameData.effect_text(c)
	if eff != "" and eff != "-":
		var el := _mk_label(eff, 11, GOOD if is_hero else DIM)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.custom_minimum_size = Vector2(288, 0)
		vb.add_child(el)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 5)
	var plb := _mk_label("战力 %s" % _pw(GameState.hero_card_power(id)), 12, INK)
	plb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(plb)
	if is_hero:
		var up := Button.new()
		up.text = "同名合成 %d / 3" % GameState.hero_fusion_stock(id)
		up.disabled = not GameState.can_fuse_hero(id)
		up.tooltip_text = "同名同品质 3 张 → 1 张更高品质；上阵和附着中的卡受到保护。"
		up.pressed.connect(_on_hero_fuse.bind(id))
		brow.add_child(up)
	var rb := Button.new()
	rb.text = "卸下"
	rb.pressed.connect(_on_carry.bind(id))
	brow.add_child(rb)
	vb.add_child(brow)

	# ⚠️ v1.1：装备巢 + 兵位**长在每个武将这一行里面**（每将独立，不再是全局 5 格）。
	# 士兵没有装备巢（用户明确：「士兵没有装备巢」），所以只有武才会展开。
	if is_hero and include_nest:
		vb.add_child(_mk_hero_nest(id))
	return p


## ⚠️ v1.1：一个武将的**装备巢（五部位）+ 兵位**。
##   放进 _mk_carry_row 里面，让人一眼看出「这套装备是挂在这个武将身上的」——
##   这正是用户纠错的核心：装备巢不是全局的，是每个武将各自一套。
func _mk_hero_nest(who: String, show_equipment: bool = true, show_troops: bool = true) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	if show_equipment:
		var used := GameState.hero_equip_of(who).size()
		var slots := GameState.equip_slots()
		box.add_child(_mk_label("　装备巢 %d / %d 部位" % [used, slots], 11,
			GOOD if used > 0 else DIM))
		if slots <= 0:
			box.add_child(_mk_label("　　未解锁 —— 点亮技能树「装备槽」", 11, WARN))
		for sub in GameState.EQUIP_SLOTS:
			box.add_child(_mk_hero_equip_row(who, str(sub)))

	# 兵位：技能树「武将带兵」点亮后才有（0 兵位时这一行整块不显示）
	if show_troops and GameState.troop_cap(who) > 0:
		box.add_child(_mk_troop_row(who))
	return box


## 武将 who 的某个部位那一行：未解锁 / 空槽 / 已装。
func _mk_hero_equip_row(who: String, sub: String) -> Control:
	var unlocked := GameState.is_slot_unlocked(sub)
	var col: Color = {"兵器": Art.RED, "铠甲": Art.ROUTES["魏线"],
		"坐骑": Art.GOLD, "兵书": Art.ROUTES["吴线"], "宝物": Art.RARITY[4]}.get(sub, Art.DIM)

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
	lb.custom_minimum_size = Vector2(110, 0)
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
		hb.add_child(Art.image(id, Vector2(28, 28)))
		var c := GameData.card(id)
		lb.text = "%s　%s" % [str(c.get("name", "?")), GameData.effect_text(c)]
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
		pop.add_icon_item(Art.texture(str(id)), "%s　%s%s" % [str(c.get("name", "?")), GameData.effect_text(c), tag])
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
		row.add_child(Art.image(str(tid), Vector2(28, 28)))
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
		pop.add_icon_item(Art.texture(sid), "%s %s　战力 %s%s" % [GameData.card_name(sid),
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
		pop.add_icon_item(Art.texture(str(id)), "%s %s　战力 %s" % [c.get("name", "?"), GameData.star_text(int(c.get("star", 0))),
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


func _on_hero_fuse(id: String) -> void:
	GameState.fuse_hero(id)


func _on_practice() -> void:
	var idx := GameState.practice_region if GameState.practice_region > 0 else 1
	practice_requested.emit(idx)


func _on_automation(enabled: bool) -> void:
	GameState.set_automation(enabled)
	_refresh_progression()


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
	l.add_theme_font_size_override("font_size", maxi(12, size) if size > 4 else size)
	l.add_theme_color_override("font_color", color)
	if size >= 17:
		l.add_theme_font_override("font", Art.title_font())
	if text.length() > 26 and size <= 14:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 180
	return l


func _section_heading(mark: String, title: String, note: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.add_child(Art.stamp(mark, Vector2(34, 36)))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(_mk_label(title, 22, INK))
	titles.add_child(_mk_label(note, 12, DIM))
	row.add_child(titles)
	return row


func _style_primary(button: Button) -> void:
	button.add_theme_font_override("font", Art.title_font())
	button.add_theme_font_size_override("font_size", 26)
	UISkin.button(button, true)


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
func _paper(_path: String, _margin: float, _scale: float = 1.0) -> StyleBox:
	return Art.panel(Art.PAPER, 8)


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
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = Art.background(name.get_basename())
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg



func _fmtv(v: float, u: Dictionary) -> String:
	var unit := str(u.get("unit", ""))
	# 「拍力」是复利倍率（×1.15/级），取整会把它显示成"1倍"，必须带小数。
	if unit == "倍":
		return "×%.2f" % v
	if unit == "拍/秒":
		return "%.2f 拍/秒" % v
	return "%s%s" % [GameState.fmt(v), unit]


func _pw(v: float) -> String:
	# 战力很小（★1 士兵只有 0.2），用一位小数，别被四舍五入成 0
	if absf(v - roundf(v)) < 0.05:
		return GameState.fmt(v)
	return "%.1f" % v
