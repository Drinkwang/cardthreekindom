extends SceneTree
## 回归：古代设定必须覆盖全部运行数据，同时保留旧卡 ID 与成长数值。

const Setting = preload("res://scripts/ancient_setting.gd")
const Book = preload("res://scripts/story_book.gd")

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cards: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json"))
	var buildings: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	var before := cards.duplicate(true)
	Setting.apply(cards, buildings)
	var forbidden := ["现实", "雷飞", "青梅竹马", "童年", "操场", "小卖部", "五毛", "五角"]
	for index in cards.size():
		var card: Dictionary = cards[index]
		var original: Dictionary = before[index]
		for field in ["id", "star", "power", "effect", "hp_coef", "gold_coef"]:
			_check(card.get(field) == original.get(field), "%s 保留 %s" % [card["id"], field])
		for field in ["name", "faction", "route", "subtype", "note"]:
			for word in forbidden:
				_check(word not in str(card.get(field, "")), "%s 的 %s 无现代文案 %s" % [card["id"], field, word])
	for building in buildings:
		_check(str(building.get("name", "")) != "小卖部", "建筑数据使用古代名称")
	for event in Book.events():
		for page in event.get("pages", []):
			_check(ResourceLoader.exists(str(page.get("scene", ""))), "%s 场景有效" % event["id"])
			_check(str(page.get("portrait", "")) not in ["G00", "G56", "I01"], "%s 使用现有古代武将头像" % event["id"])
			for word in forbidden + ["阿棠", "小野", "何婆婆", "粉笔", "校服"]:
				_check(word not in str(page), "%s 无现代剧情 %s" % [event["id"], word])
	_check(not Book.next_event({"runs": 0, "in_battle": true}, []).is_empty(), "保留序章触发兼容")
	_check(Book.journal_entries(["opening_robbery"]).size() == 1, "保留已读日记兼容")
	_check(str(Book.next_event({"runs": 1, "speed_level": 1}, ["opening_robbery"]).get("id", "")) == "first_growth", "拍速升级触发成长纪事")
	print("[ancient_setting_test] %s" % ("PASS" if failed == 0 else "FAIL %d" % failed))
	quit(0 if failed == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failed += 1
		push_error(label)
