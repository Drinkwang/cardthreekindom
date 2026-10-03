extends Node
## 只读数据层：加载 tools/export_game_data.py 从设计稿导出的 JSON。
## 想改数值 → 改 tools/gen_cards.py → 重跑两个脚本 → 游戏自动同步。

var cards: Array = []
var card_by_id: Dictionary = {}
var regions: Array = []
var region_by_idx: Dictionary = {}
var enemies_by_region: Dictionary = {}
var routes: Array = []
var route_by_name: Dictionary = {}
var packs: Array = []
var buildings: Array = []
var building_by_id: Dictionary = {}


func _ready() -> void:
	cards = _load_array("cards")
	regions = _load_array("regions")
	routes = _load_array("routes")
	packs = _load_array("packs")
	buildings = _load_array("buildings")
	enemies_by_region = _load_dict("enemies")

	for c in cards:
		card_by_id[c["id"]] = c
	for r in regions:
		region_by_idx[int(r["idx"])] = r
	for rt in routes:
		route_by_name[rt["name"]] = rt
	for b in buildings:
		building_by_id[b["id"]] = b

	# JSON 的键是字符串，转成 int 方便按区域号取
	var fixed := {}
	for k in enemies_by_region.keys():
		fixed[int(k)] = enemies_by_region[k]
	enemies_by_region = fixed

	print("[GameData] 卡牌 %d / 区域 %d / 路线 %d / 卡包 %d / 建筑 %d"
		% [cards.size(), regions.size(), routes.size(), packs.size(), buildings.size()])


func _load_array(name: String) -> Array:
	var v = _load(name)
	return v if v is Array else []


func _load_dict(name: String) -> Dictionary:
	var v = _load(name)
	return v if v is Dictionary else {}


func _load(name: String):
	var path := "res://data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("数据文件缺失: %s（先跑 tools/export_game_data.py）" % path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("JSON 解析失败: %s" % path)
	return parsed


func card(id: String) -> Dictionary:
	var c: Dictionary = card_by_id.get(id, {})
	return c


func card_name(id: String) -> String:
	var c: Dictionary = card_by_id.get(id, {})
	return c.get("name", id)


func region(idx: int) -> Dictionary:
	var r: Dictionary = region_by_idx.get(idx, {})
	return r


func route(route_name: String) -> Dictionary:
	var r: Dictionary = route_by_name.get(route_name, {})
	return r


func building(id: String) -> Dictionary:
	var b: Dictionary = building_by_id.get(id, {})
	return b


func star_text(n: int) -> String:
	return "★".repeat(max(0, n))
