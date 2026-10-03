extends Control
## 主菜单（v1.0 新增）—— 进入「拍案三国」前的第一屏。
##
## 为什么只有「开始游戏」没有「继续游戏」：
##   v1.0 关掉了存档（GameState.SAVE_ENABLED == false），每次启动都是全新一周目，
##   所以这里不存在可续的进度档。等要发版时把那个开关翻回 true，再在这儿加一栏
##   「继续游戏」即可（读档入口已经还在）。
##
## 风格沿用 S5「90 年代怀旧印刷」：旧屋书桌做底，中间压一张摊开的纸。
## 这是拍卡游戏 —— 所以第一眼看到的应该是"桌上的一堆纸"，不是按钮阵。

const BG_DIR := "res://assets/bg/"
const UI_DIR := "res://assets/ui/"
const PANEL_MARGIN := 14.0
const BTN_MARGIN := 6.0

const PAPER := Color(0.933, 0.894, 0.796)
const PAPER_ROW := Color(0.973, 0.945, 0.874)
const PAPER_RULE := Color(0.580, 0.440, 0.240)
const ACCENT := Color(0.72, 0.28, 0.12)
const INK := Color(0.17, 0.13, 0.10)
const INK2 := Color(0.30, 0.24, 0.18)
const INK_DIM := Color(0.45, 0.39, 0.31)
const SEAL := Color(0.62, 0.17, 0.13)

var _tex_cache := {}
var _rules: Control = null


func _ready() -> void:
	_build()


# =====================================================================
# 构建
# =====================================================================
func _build() -> void:
	# ---- 底：2026 年收拾旧屋，从抽屉底翻出来的那张书桌 ----
	var bg := TextureRect.new()
	bg.texture = _tex(BG_DIR + "home.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ---- 中：一张纸 ----
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _paper_panel())
	box.custom_minimum_size = Vector2(520.0, 0.0)
	center.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(col)

	# 标题
	var title := Label.new()
	title.text = "拍案三国"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", INK)
	col.add_child(title)

	# 副标题
	var sub := Label.new()
	sub.text = "桌上的全是敌人 —— 拍翻，就归你"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", INK_DIM)
	col.add_child(sub)

	col.add_child(_gap(10))
	col.add_child(_rule())
	col.add_child(_gap(10))

	# 按钮
	col.add_child(_mk_button("开始游戏", true, _on_start))
	col.add_child(_mk_button("玩法说明", false, _open_rules))
	col.add_child(_mk_button("退出", false, _on_quit))

	col.add_child(_gap(12))
	col.add_child(_rule())

	var foot := Label.new()
	foot.text = "v1.0 开发版　·　每次启动都是全新一周目"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", INK_DIM)
	col.add_child(foot)

	# ---- 玩法说明（覆盖层，默认收起）----
	_rules = _mk_rules()
	add_child(_rules)


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, float(h))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _rule() -> Control:
	var c := ColorRect.new()
	c.color = Color(PAPER_RULE.r, PAPER_RULE.g, PAPER_RULE.b, 0.45)
	c.custom_minimum_size = Vector2(0.0, 1.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _mk_button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 44.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _btn_box(false, primary))
	b.add_theme_stylebox_override("hover", _btn_box(true, primary))
	b.add_theme_stylebox_override("pressed", _btn_box(true, primary))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", _btn_box(false, primary))
	b.add_theme_font_size_override("font_size", 19 if primary else 16)
	b.add_theme_color_override("font_color", PAPER if primary else INK)
	b.add_theme_color_override("font_hover_color", PAPER if primary else ACCENT)
	b.add_theme_color_override("font_pressed_color", PAPER if primary else ACCENT)
	b.add_theme_color_override("font_focus_color", PAPER if primary else INK)
	b.pressed.connect(cb)
	return b


## 按钮底：主按钮用「朱砂印」实色，次按钮用纸白九宫格。
func _btn_box(hover: bool, primary: bool) -> StyleBox:
	if primary:
		var sb := StyleBoxFlat.new()
		sb.bg_color = ACCENT.darkened(0.12) if hover else ACCENT
		sb.border_color = ACCENT.darkened(0.30)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		return sb
	var tex_name := "btn_hover.png" if hover else "btn_normal.png"
	var t := _paper(UI_DIR + tex_name, BTN_MARGIN)
	if t != null:
		return t
	return _flat(PAPER_ROW if not hover else PAPER, PAPER_RULE, 1, 3)


# =====================================================================
# 玩法说明
# =====================================================================
const RULES_TEXT := """一、桌上全是敌人
　　牌正面朝上、歪着散开摆在桌上。鼠标点下去就是拍它一下 —— 别客气。

二、两种拍法
　　· 单击 = 轻拍（×1.0 伤害，花 1 点耐力）
　　· 按住鼠标划过 = 重拍（×2.5 伤害，每张花 2 点耐力，一次能连拍好几张）
　　每张牌只吃一次重拍。可以从桌面空白处起手再划过去。

三、耐力耗尽 = 这一趟结束
　　耐力拍完会强制结算，回大本营。结算 = 打出的伤害 ×0.5 + 底薪。
　　没拍下来的区域下次进场满血重置，只把金币带出去。

四、拍翻整桌 = 克服这个区域
　　克服之后得一张城池卡。但城池只是块地基 —— 它本身一个子儿都不产。

五、盖建筑才产钱，而且关掉游戏也产
　　把建筑卡放到城池的槽位上，建筑才会产金币；离线也在产。
　　这是这款游戏的最终奖励：先打，再挂。

六、只有「上阵」的武将算战力
　　仓库里囤着的卡不算。上阵位一开始只有 3 个，靠升级树往上加。"""


func _mk_rules() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	layer.mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.11, 0.08, 0.05, 0.72)     # 暖墨色压暗，不是黑幕
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _paper_panel())
	box.custom_minimum_size = Vector2(640.0, 0.0)
	center.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	box.add_child(col)

	var h := Label.new()
	h.text = "玩法说明"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 26)
	h.add_theme_color_override("font_color", ACCENT)
	col.add_child(h)

	var body := Label.new()
	body.text = RULES_TEXT
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", INK2)
	body.add_theme_constant_override("line_spacing", 5)
	col.add_child(body)

	col.add_child(_gap(6))
	col.add_child(_mk_button("知道了", true, _close_rules))
	return layer


func _open_rules() -> void:
	_rules.visible = true
	# ⚠️ 隐藏中的全屏控件锚点不结算 —— 打开时必须显式给尺寸，否则覆盖层是 0 大小
	_rules.size = size


func _close_rules() -> void:
	_rules.visible = false


# =====================================================================
# 动作
# =====================================================================
func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_quit() -> void:
	get_tree().quit()


# =====================================================================
# 纸质皮肤（与大本营 / 城建 / 桌面同一套）
# =====================================================================
func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


## 纸九宫格。margin 必须等于源纹理上的真实边框宽度 ——
## ⚠️ Godot 4 的 StyleBoxTexture 没有 texture_scale，角是按源纹理 1:1 画的。
func _paper(path: String, margin: float) -> StyleBox:
	var t := _tex(path)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(margin)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


func _paper_panel() -> StyleBox:
	var sb := _paper(UI_DIR + "panel.png", PANEL_MARGIN)
	if sb != null:
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 26.0
		sb.content_margin_bottom = 24.0
		return sb
	return _flat(PAPER, PAPER_RULE, 1, 0)


func _flat(bg: Color, border: Color, w: int, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(r)
	return sb
