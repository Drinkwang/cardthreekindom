extends Control
class_name PaanStoryView
## 可跳过的荆州纪事，以及已读剧情日记。打开期间拦截拍卡输入。
const Art = preload("res://scripts/ui/print_art.gd")
const Book = preload("res://scripts/story_book.gd")

signal event_finished(id: String, skipped: bool)
signal closed()

var _event: Dictionary = {}
var _page_index := 0
var _replay := false
var _journal_mode := false
var _seen_ids: Array = []
var _entries: Array = []
var _heading: Label
var _subtitle: Label
var _body: Label
var _caption: Label
var _speaker: Label
var _portrait: TextureRect
var _scene: TextureRect
var _page_count: Label
var _next: Button
var _skip: Button
var _diary_button: Button
var _story_row: HBoxContainer
var _journal_list: VBoxContainer
var _journal_scroll: ScrollContainer
var _scene_panel: PanelContainer
var _outer: MarginContainer


func _ready() -> void:
	theme = Art.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = not _event.is_empty() or _journal_mode
	resized.connect(_fit)
	_fit()
	if not _event.is_empty():
		if _journal_mode:
			_build_journal_list()
		_render_page()


func open_event(event: Dictionary, replay: bool = false) -> void:
	if event.is_empty():
		return
	_event = event.duplicate(true)
	_page_index = 0
	_replay = replay
	_journal_mode = false
	visible = true
	if is_node_ready():
		_render_page()
		_fit()
		_next.grab_focus()


func open_journal(seen_ids: Array) -> void:
	_seen_ids = seen_ids.duplicate()
	_entries = Book.journal_entries(_seen_ids)
	_journal_mode = true
	_replay = true
	_page_index = 0
	_event = _entries[0].duplicate(true) if not _entries.is_empty() else {}
	visible = true
	if is_node_ready():
		_build_journal_list()
		_render_page()
		_fit()


func is_open() -> bool:
	return visible


func current_event_id() -> String:
	return str(_event.get("id", ""))


func close_story() -> void:
	if not visible:
		return
	if not _replay and not _event.is_empty():
		_finish(true)
	else:
		visible = false
		closed.emit()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.10, 0.07, 0.04, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_outer = MarginContainer.new()
	_outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_outer)
	var sheet := PanelContainer.new()
	sheet.name = "StoryPaper"
	sheet.add_theme_stylebox_override("panel", Art.panel(Art.PAPER, 22, Art.RED, 2))
	_outer.add_child(sheet)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	sheet.add_child(page)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	page.add_child(header)
	header.add_child(Art.stamp("记", Vector2(60, 64)))
	var headings := VBoxContainer.new()
	headings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(headings)
	_heading = Art.label("荆州纪事", 30, Art.INK)
	_heading.name = "StoryHeading"
	_heading.add_theme_font_override("font", Art.title_font())
	headings.add_child(_heading)
	_subtitle = Art.label("一页一段，慢慢再来。", 13, Art.DIM)
	headings.add_child(_subtitle)
	_diary_button = _button("返回游戏", false, close_story)
	header.add_child(_diary_button)
	page.add_child(Art.divider())
	_story_row = HBoxContainer.new()
	_story_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story_row.add_theme_constant_override("separation", 22)
	page.add_child(_story_row)
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.custom_minimum_size.x = 220
	_journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_story_row.add_child(_journal_scroll)
	_journal_list = VBoxContainer.new()
	_journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_list.add_theme_constant_override("separation", 10)
	_journal_scroll.add_child(_journal_list)
	_scene_panel = PanelContainer.new()
	_scene_panel.custom_minimum_size.x = 355
	_scene_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_panel.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 9, Art.RULE, 1))
	_story_row.add_child(_scene_panel)
	_scene = TextureRect.new()
	_scene.name = "StoryIllustration"
	_scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_panel.add_child(_scene)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 15)
	_story_row.add_child(text_column)
	var speaker_row := HBoxContainer.new()
	speaker_row.add_theme_constant_override("separation", 15)
	text_column.add_child(speaker_row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(86, 96)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speaker_row.add_child(_portrait)
	_speaker = Art.label("", 24, Art.RED)
	_speaker.add_theme_font_override("font", Art.title_font())
	_speaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speaker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speaker_row.add_child(_speaker)
	var text_scroll := ScrollContainer.new()
	text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	text_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_column.add_child(text_scroll)
	_body = Art.label("", 19, Art.INK)
	_body.name = "StoryBody"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("line_spacing", 9)
	text_scroll.add_child(_body)
	_caption = Art.label("", 14, Art.DIM)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(_caption)
	page.add_child(Art.divider())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	page.add_child(actions)
	_page_count = Art.label("", 14, Art.DIM)
	_page_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(_page_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_skip = _button("跳过剧情 · 日记可重看", false, func(): _finish(true))
	_skip.name = "StorySkip"
	actions.add_child(_skip)
	_next = _button("下一页", true, _next_page)
	_next.name = "StoryNext"
	_next.custom_minimum_size.x = 170
	actions.add_child(_next)


func _fit() -> void:
	if not is_node_ready():
		return
	var compact := get_viewport_rect().size.x < 1000
	for side in ["left", "right", "top", "bottom"]:
		_outer.add_theme_constant_override("margin_" + side, 24 if compact else 46)
	_scene_panel.visible = not compact and not _journal_mode
	_scene_panel.custom_minimum_size.x = clampf(get_viewport_rect().size.x * 0.31, 280, 430)
	_journal_scroll.visible = _journal_mode
	_body.add_theme_font_size_override("font_size", 17 if compact else 19)
	_heading.add_theme_font_size_override("font_size", 25 if compact else 30)


func _render_page() -> void:
	if not is_node_ready():
		return
	_journal_scroll.visible = _journal_mode
	_skip.visible = not _journal_mode and not _replay
	_diary_button.visible = _journal_mode or _replay
	if _event.is_empty():
		_heading.text = "荆州纪事"
		_subtitle.text = "到达的故事和跳过的故事，都留在这里。"
		_speaker.text = "还没有写下的第一页"
		_body.text = "先去新野练拍。积攒军资、修习掌法，新的见闻会记在这里。"
		_caption.text = "日记不会提前透露尚未发生的故事。"
		_portrait.visible = false
		_next.visible = false
		_page_count.text = ""
		return
	var pages: Array = _event.get("pages", [])
	if pages.is_empty():
		return
	_page_index = clampi(_page_index, 0, pages.size() - 1)
	var entry: Dictionary = pages[_page_index]
	_heading.text = ("荆州纪事 · " if _journal_mode else "") + str(_event.get("title", ""))
	_subtitle.text = str(_event.get("chapter", "")) + (" · 重看旧事" if _replay else " · 一次成长，记一小段")
	_speaker.text = str(entry.get("speaker", ""))
	_body.text = str(entry.get("text", ""))
	_caption.text = str(entry.get("caption", ""))
	var portrait_id := str(entry.get("portrait", ""))
	_portrait.visible = not portrait_id.is_empty()
	_portrait.texture = Art.portrait_icon_texture(portrait_id) if not portrait_id.is_empty() else null
	var path := str(entry.get("scene", ""))
	_scene.texture = load(path) as Texture2D if ResourceLoader.exists(path) else Art.paper_background()
	_page_count.text = "%d / %d 页" % [_page_index + 1, pages.size()]
	_next.visible = true
	_next.text = "再读一遍" if _journal_mode and _page_index == pages.size() - 1 else ("返回游戏" if _page_index == pages.size() - 1 else "下一页")
	_fit()


func _build_journal_list() -> void:
	for child in _journal_list.get_children():
		_journal_list.remove_child(child)
		child.queue_free()
	for entry in _entries:
		var selected: Dictionary = entry
		var label := str(entry.get("chapter", "")) + "\n" + str(entry.get("title", ""))
		var button := _button(label, false, func():
			_event = selected.duplicate(true)
			_page_index = 0
			_render_page())
		button.custom_minimum_size.y = 64
		_journal_list.add_child(button)


func _next_page() -> void:
	if _event.is_empty():
		return
	var pages: Array = _event.get("pages", [])
	if _page_index < pages.size() - 1:
		_page_index += 1
		_render_page()
	elif _journal_mode:
		_page_index = 0
		_render_page()
	else:
		_finish(false)


func _finish(skipped: bool) -> void:
	if not visible:
		return
	var id := current_event_id()
	visible = false
	if not _replay and not id.is_empty():
		event_finished.emit(id, skipped)
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_story()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_next_page()
		get_viewport().set_input_as_handled()


func _button(text: String, primary: bool, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 16)
	if primary:
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, Art.panel(Art.RED.darkened(0.10 if state == "pressed" else 0.0), 12, Art.RED, 1))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Art.PAPER_LIGHT)
	button.pressed.connect(action)
	return button
