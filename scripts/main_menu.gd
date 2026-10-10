extends Control
const Art = preload("res://scripts/ui/print_art.gd")
var _rules: Control
var _new_confirm: ConfirmationDialog

func _ready() -> void:
	theme = Art.theme()
	_build()

func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.background("home")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 42)
	add_child(margin)
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 48)
	margin.add_child(spread)
	var center := CenterContainer.new()
	spread.add_child(center)
	var page := PanelContainer.new()
	page.custom_minimum_size = Vector2(438, 0)
	var cover_paper := Art.panel(Art.PAPER_LIGHT, 28, Art.RULE, 1)
	cover_paper.shadow_color = Color(0.12, 0.07, 0.03, 0.3)
	cover_paper.shadow_size = 14
	cover_paper.shadow_offset = Vector2(5, 7)
	page.add_theme_stylebox_override("panel", cover_paper)
	center.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	var edition := Art.label("汉 末 风 云  ·  荆 州 八 郡", 12, Art.RED)
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(edition)
	col.add_child(Art.divider())
	var title := Art.label("拍案三国", 64)
	title.add_theme_font_override("font", Art.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Art.label("一掌聚财，再定荆州", 25, Art.INK)
	sub.add_theme_font_override("font", Art.title_font())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var memory := Art.label("限时拍击 · 金币入账 · 升级再来一轮", 14, Art.DIM)
	memory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(memory)
	var heroes := HBoxContainer.new()
	heroes.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes.add_theme_constant_override("separation", 12)
	col.add_child(heroes)
	for id in ["G28", "G26", "G27"]:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", Art.card_frame(5))
		var v := VBoxContainer.new()
		card.add_child(v)
		v.add_child(Art.image(id, Vector2(104, 92)))
		var l := Art.label(GameData.card_name(id), 14)
		l.add_theme_font_override("font", Art.title_font())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		heroes.add_child(card)
	col.add_child(Art.divider())
	var has_save := FileAccess.file_exists(GameState.save_path())
	if has_save:
		col.add_child(_button("继续征战", true, _on_start))
		var progress := Art.label("已克服 %d / %d 区域 · 金币 %s · 主角 Lv.%d" % [GameState.cleared_count(), GameState.total_field_regions(), GameState.fmt(GameState.gold), GameState.player_level()], 12, Art.DIM)
		progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(progress)
	col.add_child(_button("另启新周目" if has_save else "开始第一轮", not has_save, _ask_new))
	var row := HBoxContainer.new()
	col.add_child(row)
	for entry in [["玩法说明", _open_rules], ["退出游戏", _on_quit]]:
		var b := _button(entry[0], false, entry[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var foot := Art.label("进度自动保存  ·  离线建筑收益", 12, Art.DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)
	var art_space := VBoxContainer.new()
	art_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_space.alignment = BoxContainer.ALIGNMENT_END
	spread.add_child(art_space)
	var hero := Art.image("G27", Vector2(350, 330))
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_space.add_child(hero)
	var cycle := Art.label("巡城寻牌，单击落掌\n扩圈、提速、赚金币\n滚轮缩放，舆图引路", 23, Art.INK)
	cycle.add_theme_font_override("font", Art.title_font())
	cycle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_space.add_child(cycle)
	var caption := HBoxContainer.new()
	caption.alignment = BoxContainer.ALIGNMENT_END
	art_space.add_child(caption)
	caption.add_child(Art.stamp("拍翻天下", Vector2(56, 112)))
	var motif := Art.decorate(6)
	page.add_child(motif)
	_rules = _mk_rules()
	add_child(_rules)
	_new_confirm = ConfirmationDialog.new()
	_new_confirm.title = "另启新周目"
	_new_confirm.dialog_text = "新周目会替换当前进度。\n已有卡牌、金币、城池和成长将从头开始。"
	_new_confirm.ok_button_text = "开始新周目"
	_new_confirm.cancel_button_text = "保留进度"
	_new_confirm.confirmed.connect(_new_game)
	add_child(_new_confirm)

func _button(text: String, primary: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", 16 if primary else 14)
	if primary:
		b.add_theme_font_override("font", Art.title_font())
	if primary:
		b.add_theme_stylebox_override("normal", Art.panel(Art.RED, 12, Art.RED))
		b.add_theme_stylebox_override("hover", Art.panel(Art.RED.darkened(0.1), 12, Art.RED))
		b.add_theme_stylebox_override("pressed", Art.panel(Art.RED.darkened(0.2), 12, Art.RED))
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, Art.PAPER_LIGHT)
	b.pressed.connect(action)
	return b

func _mk_rules() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(650, 0)
	p.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 24, Art.RED))
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(Art.label("拍案须知", 28, Art.RED))
	var body := Art.label("一、巡城拍牌\n未完成的将牌分散在城内各处，彼此留出间距。每轮从30秒开始。\n鼠标小圆圈瞄准，单击立刻拍中圈内全部存活牌，共用一次0.6秒初始间隔。\n\n二、缩放与巡城\n滚轮放大、缩小镜头；鼠标靠近场地边缘时，镜头向该方向移动。\n右上角小地图显示剩余牌与当前视野，点地图可跳到城内对应位置。\n点地图标题或按M收起、展开；镜头缩放不改变实际拍击范围。\n\n三、边拍边赚钱\n有效伤害即时赚金币，翻牌与清段另有奖励。全城牌清完后才重新铺牌。\n时间到回营，金币保留；已连续清完的城池段落保存为进度。\n\n四、升级，再来一轮\n提升拍力、拍速、范围和时长。范围升级立即扩圈，一掌可以拍更多牌。\n清除新野前2段可学自动拍，前3段可扩同行位，整城完成后开放更多本领。\n\n五、城池与保存\n建筑卡组成经营连锁，3张同名同品相可合成，已装配卡受保护。\n金币、升级、卡牌和城池进度自动保存，继续游戏回到大本营。", 14)
	body.add_theme_constant_override("line_spacing", 3)
	v.add_child(body)
	v.add_child(_button("知道了，去拍牌", true, func(): _rules.visible = false))
	return layer

func _open_rules() -> void:
	_rules.visible = true

func _ask_new() -> void:
	if FileAccess.file_exists(GameState.save_path()):
		_new_confirm.popup_centered(Vector2i(430, 160))
	else:
		_new_game()

func _new_game() -> void:
	GameState.new_game()
	GameState.save_game()
	_on_start()

func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_quit() -> void:
	GameState.save_game()
	get_tree().quit()
