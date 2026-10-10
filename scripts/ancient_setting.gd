extends RefCounted
## 三国设定覆盖层。保留生成数据的 ID 与数值，使旧存档、掉落与合成继续有效。
## 名称、阵营与背景由这里集中修正；data/*.json 仍由上游工具生成。

const CARD_TEXT := {
	"I01": {"name": "新野校尉", "subtype": "主角卡", "faction": "新野", "route": "起点",
		"note": "驻守新野的校尉；练拍、经营军营，从一张薄牌积攒军资"},
	"G00": {"name": "荆州壮士", "subtype": "地方武将", "faction": "荆州", "route": "通用",
		"note": "新野练拍营的壮士；擅长护住连拍节奏"},
	"G56": {"name": "荆州游侠", "subtype": "地方武将", "faction": "荆州", "route": "通用",
		"note": "行走荆州的游侠；擅长借掌风翻动厚牌"},
	"B05": {"name": "杂货铺", "note": "往来商旅采买纸牌与日常货物，收入用于营地经营"},
	"B10": {"note": "军营练兵之所，也供将士练习拍牌"},
}

const PORTRAIT_ALIASES := {"I01": "G23", "G00": "G20", "G56": "G27"}


static func apply(cards: Array, buildings: Array) -> void:
	for card in cards:
		var id := str(card.get("id", ""))
		if CARD_TEXT.has(id):
			var override: Dictionary = CARD_TEXT[id]
			for field in override:
				card[field] = override[field]
	for building in buildings:
		if str(building.get("id", "")) == "B05":
			building["name"] = "杂货铺"
