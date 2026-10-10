extends RefCounted
## 建筑构筑的结构化规则源。覆盖导出数据，不手改上游生成的 JSON。
const CYCLE := 10.0
const QUALITY_NAMES := ["原版", "精制", "珍藏"]
const QUALITY_MULT := [1.0, 1.35, 1.8]
const RULES := {
	"B01": {"tag": "农产", "base": 1.0, "text": "每10秒产出1金币"},
	"B02": {"tag": "民生", "base": 1.0, "text": "每10秒产出1金币"},
	"B03": {"all_pct": 0.10, "text": "同城基础产出+10%"},
	"B04": {"extra_pct": 0.25, "text": "同城追加结算收益+25%"},
	"B05": {"tag": "商贸", "base": 3.0, "text": "每10秒产出3金币"},
	"B06": {"tag": "农产", "base": 4.0, "text": "每10秒产出4金币"},
	"B07": {"period": 5, "repeat": 0.5, "target": "全部", "text": "每5次基础产出，追加结算50%"},
	"B08": {"flat": 2.0, "target": "农产", "text": "同城每张农产卡，每次产出+2金币"},
	"B09": {"tag": "工坊", "base": 8.0, "text": "每10秒产出8金币"},
	"B10": {"tag_pct": 0.25, "target": "工坊", "text": "同城工坊基础产出+25%"},
	"B11": {"period": 3, "repeat": 1.0, "target": "农产", "text": "每3次农产基础产出，追加结算1次"},
	"B12": {"extra_pct": 1.0, "text": "同城追加结算收益+100%（单独为×2）"},
	"B13": {"period": 5, "repeat": 1.0, "target": "全部", "text": "每5次基础产出，追加结算1次"},
	"B14": {"tag": "水运", "base": 16.0, "text": "每10秒产出16金币"},
	"B15": {"diverse_pct": 0.05, "text": "每种不同产出类型，基础产出+5%"},
	"B16": {"tag_pct": 0.50, "target": "商贸", "text": "同城商贸基础产出+50%"},
	"B17": {"all_pct": 0.30, "text": "同城基础产出+30%"},
	"B18": {"period": 4, "repeat": 0.5, "target": "全部", "text": "每4次基础产出，追加结算50%"},
	"B19": {"tag": "水运", "base": 32.0, "text": "每10秒产出32金币"},
	"B20": {"tag": "工坊", "base": 32.0, "text": "每10秒产出32金币"},
	"B21": {"tag": "民生", "base": 64.0, "text": "每10秒产出64金币"},
	"B22": {"tag": "民生", "base": 64.0, "period": 3, "repeat": 0.5, "target": "全部", "min_types": 3, "text": "每10秒产64金币；3种产出类型时，每3次追加50%"},
}

static func quality_mult(quality: int) -> float:
	return float(QUALITY_MULT[clampi(quality, 0, 2)])

static func quality_name(quality: int) -> String:
	return str(QUALITY_NAMES[clampi(quality, 0, 2)])

static func apply(buildings: Array, cards: Array) -> void:
	for building in buildings:
		var id := str(building.get("id", ""))
		if RULES.has(id):
			var rule: Dictionary = RULES[id]
			building["effect"] = str(rule["text"])
			building["prod"] = float(rule.get("base", 0.0)) * 360.0
			building["combo_rule"] = rule
		for card in cards:
			if str(card.get("id", "")) == id:
				card["effect"] = building["effect"]
				break

static func evaluate(ids: Array, qualities: Array) -> Dictionary:
	var sources := []
	var types := {}
	var flat := {}
	var tag_pct := {}
	var all_pct := 0.0
	var extra_pct := 0.0
	var repeats := []
	var unique := {}
	for slot in range(ids.size()):
		var id := str(ids[slot])
		if id == "" or unique.has(id):
			continue
		unique[id] = true
		var rule: Dictionary = RULES.get(id, {})
		var scale := quality_mult(int(qualities[slot]) if slot < qualities.size() else 0)
		var tag := str(rule.get("tag", ""))
		if float(rule.get("base", 0)) > 0:
			sources.append({"id": id, "tag": tag, "base": float(rule["base"]) * scale, "slot": slot})
			types[tag] = true
		var target := str(rule.get("target", "全部"))
		flat[target] = float(flat.get(target, 0.0)) + float(rule.get("flat", 0.0)) * scale
		tag_pct[target] = float(tag_pct.get(target, 0.0)) + float(rule.get("tag_pct", 0.0)) * scale
		all_pct += float(rule.get("all_pct", 0.0)) * scale
		extra_pct += float(rule.get("extra_pct", 0.0)) * scale
		if rule.has("period"):
			repeats.append({"id": id, "period": int(rule["period"]), "repeat": float(rule["repeat"]) * scale, "target": target, "min_types": int(rule.get("min_types", 0))})
	# 品相强化数值，不改变追加次数/周期。
	unique.clear()
	for slot in range(ids.size()):
		var id := str(ids[slot])
		if unique.has(id):
			continue
		unique[id] = true
		var rule: Dictionary = RULES.get(id, {})
		all_pct += float(rule.get("diverse_pct", 0.0)) * types.size() * quality_mult(int(qualities[slot]) if slot < qualities.size() else 0)
	var normal := 0.0
	for source in sources:
		var tag := str(source["tag"])
		source["value"] = (float(source["base"]) + float(flat.get(tag, 0.0))) * (1.0 + all_pct + float(tag_pct.get(tag, 0.0)))
		normal += float(source["value"])
	var average := normal
	for repeat in repeats:
		var subtotal := 0.0
		for source in sources:
			if str(repeat["target"]) in ["全部", str(source["tag"])]:
				subtotal += float(source["value"])
		repeat["active"] = types.size() >= int(repeat["min_types"]) and subtotal > 0.0
		repeat["value"] = subtotal * float(repeat["repeat"]) * (1.0 + extra_pct) if repeat["active"] else 0.0
		average += float(repeat["value"]) / int(repeat["period"])
	return {"sources": sources, "types": types.keys(), "normal": normal, "repeats": repeats, "extra_pct": extra_pct, "average": average, "hourly": average * 360.0}

static func payout(summary: Dictionary, before: int, cycles: int) -> float:
	var total := float(summary["normal"]) * cycles
	for repeat in summary["repeats"]:
		var period := int(repeat["period"])
		var triggers := int(floor(float(before + cycles) / period)) - int(floor(float(before) / period))
		total += triggers * float(repeat["value"])
	return total
