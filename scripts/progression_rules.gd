extends RefCounted
## 限时拍击增量节奏表。原始图鉴不动，运行数据和玩法共享这一份配置。

const VERSION := 5
const ROUND_SECONDS := 30.0
const ROUND_SECONDS_PER_LEVEL := 2.0
const SLAP_INTERVAL := 0.6
const AUTO_INTERVAL_MULT := 3.0
const FIRST_TABLES := [14.0, 28.0, 48.0, 82.0, 132.0]
const HERO_POWER := {1: 0.2, 2: 1.0, 3: 2.5, 4: 5.0, 5: 9.0, 6: 15.0}
const SOLDIER_POWER := {1: 0.2, 2: 0.5, 3: 1.1, 4: 2.0, 5: 3.4, 6: 5.5}
const REST_SECONDS := 4.0
const DAMAGE_PAY := 0.45
const KILL_PAY := 0.12
const TABLE_BONUS := 0.20
const CITY_BONUS := 0.25

static func apply(cards: Array, regions: Array) -> void:
	for c in cards:
		if str(c.get("id", "")) == "G00": c["star"] = 2 # 序章伙伴荆州壮士：薄牌接口，保留连击保护
		var star := int(c.get("star", 1))
		match str(c.get("type", "")):
			"武将": c["power"] = float(HERO_POWER.get(star, 0.2))
			"士兵": c["power"] = float(SOLDIER_POWER.get(star, 0.2))
	for r in regions:
		var idx := int(r["idx"])
		r["legacy_hp"] = float(r.get("total_hp", 0.0))
		r["total_hp"] = 132 if idx == 1 else (240 if idx == 2 else (420 if idx == 3 else int(r["total_hp"]) * 2))
		r["tables"] = table_count(idx)

static func table_count(idx: int) -> int:
	if idx == 1: return 5
	if idx <= 3: return 6
	if idx <= 8: return 8
	if idx <= 14: return 10
	return 12

static func table_hp(region: Dictionary, completed: int) -> float:
	var idx := int(region.get("idx", 1))
	var step := clampi(completed, 0, table_count(idx) - 1)
	if idx == 1: return FIRST_TABLES[step]
	var fraction := float(step + 1) / float(table_count(idx))
	return round(float(region.get("total_hp", 0)) * (0.28 + 0.72 * pow(fraction, 1.7)))

static func table_name(step: int, count: int) -> String:
	if step == count - 1: return "守桌试炼"
	return ["街角薄牌", "木凳练手", "并排成阵", "厚牌试掌"][mini(3, int(float(step) / maxf(1.0, float(count - 1)) * 4.0))]
