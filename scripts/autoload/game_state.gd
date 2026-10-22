extends Node
## 《拍案三国》：30秒一轮，按共享拍击间隔赚取即时金币。
## 一座城一次铺出整堆卡，圆形范围轻拍；整堆清空后补牌，倒计时结束回营。
## 旧逐桌进度作为城堆内部的连续清除检查点保留，首通奖励仍只领一次。

signal changed                        # 高频：金币 / 耐力 / 血量 / 连击
signal map_changed                    # 区域状态变化（解锁 / 克服 / 新周目）
signal shop_changed                   # 持有卡 / 建筑 / 城池变化
signal message(text: String)
signal events_changed

## v1.2 正式保存成长与城建；局内桌面血量不保留。验证场景自动使用测试档。
const SAVE_ENABLED := true
const SAVE_PATH := "user://save_paan_adventure.json"
const COMBO_THRESHOLD := 20
const RANSOM := {3: 200, 4: 800, 5: 3200, 6: 12800}
const SYNC_COST := {1: 10, 2: 40, 3: 160, 4: 640, 5: 2560}
const OFFLINE_BASE_HOURS := 8.0
const OFFLINE_EFFICIENCY := 0.5
const Progression = preload("res://scripts/progression_rules.gd")
const MapEvents = preload("res://scripts/map_events.gd")
const ROUTES := ["魏线", "蜀线", "吴线", "群雄线"]

# ---------- 拍卡手感 ----------
const HEAVY_MULT := 2.5              # 重拍（拖拽划过）伤害倍率；轻拍（单击）= 1.0
const CITY_UNLOCK_AFTER := 3         # 克服该数量的非起点区域后，城池才开始发
const START_REGION := 1              # 新野：v1.0 起是真正的第一关（60 血 / 6 敌人），
									 # 但仍不计入 cleared_count()，所以不影响城建解锁节奏
const HERO_ALWAYS := "I01"           # 主角卡：不占携带位、不可卸下
const HERO_BASE_POWER := 0.3         # 主角卡自带的底子（v0.8 调参点）
									 # 判定公式里已经有 "+1.0" 的基础拍力，那才是主角自己；
									 # 卡面战力主要交给「上阵武将」，否则开局就直接碾压。

# ---------- 掉金 / 结算 ----------
const KILL_GOLD_COEF := 0.6          # 击杀掉金 = 该敌人最大血量 × 本系数 × 卡牌掉金系数
const SETTLE_GOLD_COEF := 0.5        # 结算「收成」= 本局累计伤害 × 本系数 + 底薪
const SETTLE_GOLD_BASE := 5
const CLEAR_GOLD_COEF := 0.8         # 首通奖励 = 该区域总血量 × 本系数

# ---------- 升级树（局外持久成长，金币主去处） ----------
## base  初始值 / step 每级增量 / lv 最高等级（<=0 表示无上限）/ cost 首级价 / growth 每级涨价
##
## ⚠️ v1.0 关键改动：「拍力」从**加法式**改成**复利式**。
##    加法式（base + step×lv，+10%/级，8 级封顶）的天花板是硬的 —— 战力倍率永远 ≤ ×1.8，
##    练到 200 级和练到 8 级一模一样。这会把敌人曲线的斜率钉死在 ×1.85 以内
##    （首关 30 血 / 19 关），于是"每关难度翻很多倍"在数学上根本做不到。
##    改成 kind="mult"（base × factor^lv，无上限）之后，倍率上限抬到 ×7.6，
##    而且给出的是很多**小台阶**（不再是武将星级那种 ×5 一跳）——
##    顺手治掉「一次推平 9 个区域、然后长时间卡死」的突进感。
##    v1.1：从「升级树」正式变成「技能树」—— 数值定义仍在本常量里，
##    层级与前置见下面的 SKILL_TREE。节点数值一个都没改。
const UPGRADES: Array = [
	{"id": "stamina", "name": "时长", "unit": "秒", "kind": "add", "base": Progression.ROUND_SECONDS, "step": Progression.ROUND_SECONDS_PER_LEVEL, "lv": 60,
	 "cost": 1, "growth": 1.0, "desc": "每轮基础30秒，每级延长2秒，留出更多赚钱时间"},
	{"id": "speed", "name": "拍速", "unit": "拍/秒", "kind": "mult", "base": 1.0 / Progression.SLAP_INTERVAL, "factor": 1.08,
	 "step": 0, "lv": 40, "cost": 1, "growth": 1.0, "desc": "拍击频率×1.08/级；初始轻拍0.6秒，重拍冷却为轻拍×1.8"},
	{"id": "radius", "name": "范围", "unit": "半径", "kind": "add", "base": 40, "step": 6, "lv": 20,
	 "cost": 1, "growth": 1.0, "desc": "拍卡圆圈每级扩大6；单击同时拍中圆内所有卡牌，伤害与一掌冷却共享"},
	{"id": "power", "name": "拍力", "unit": "倍", "kind": "mult", "base": 1.0, "factor": 1.12,
	 "step": 0, "lv": 0, "cost": 1, "growth": 1.0, "desc": "拍力 ×1.12/级（复利叠乘，无上限）"},
	{"id": "carry", "name": "携带位", "unit": "个", "kind": "add", "base": 3, "step": 1, "lv": 3,
	 "cost": 1, "growth": 1.0, "desc": "除主角外，能带上桌的武将数"},
	{"id": "crit", "name": "暴击", "unit": "%", "kind": "add", "base": 0, "step": 4, "lv": 8,
	 "cost": 1, "growth": 1.0, "desc": "暴击率 +4%/级（×2 伤害）"},
	{"id": "fortune", "name": "财路", "unit": "%", "kind": "add", "base": 0, "step": 20, "lv": 10,
	 "cost": 1, "growth": 1.0, "desc": "击杀掉金 +20%/级"},
	{"id": "equip", "name": "装备槽", "unit": "格", "kind": "add", "base": 0, "step": 1, "lv": 5,
	 "cost": 1, "growth": 1.0, "desc": "依次解锁 兵器/铠甲/坐骑/兵书/宝物 五个部位"},
	# v1.1 新增：士卒可以挂到武将身上（用户要求「未来点亮技能树里的武将带兵能力 可以直接把兵给武将装备」）
	{"id": "troops", "name": "武将带兵", "unit": "兵", "kind": "add", "base": 0, "step": 1, "lv": 3,
	 "cost": 1, "growth": 1.0,
	 "desc": "每个上阵武将 +1 兵位（0 → 3）；兵位上的士卒战力全额计入卡组，且不占携带位"},
]

# ---------- 技能树布局（v1.1）----------
## UPGRADES 是**数值定义**，SKILL_TREE 只加「层级」和「前置」这两层结构。
## ⚠️ 节点数值一个都没动 —— 上一轮刚调好的节拍（复利拍力 ×1.15 + 新野 60 血 + ×1.85 曲线）
##    不能再被打乱。前置也只做**浅门槛**（前置 ≥ Lv.1 即可），不做等级要求，
##    否则会把"玩家自己决定先点什么"变成"被树逼着点"。
## req 里列的是「至少点亮过一次（Lv.1）」的前置技能 id。
const SKILL_TREE: Array = [
	{"id": "stamina", "tier": 1, "req": []},
	{"id": "speed", "tier": 1, "req": []},
	{"id": "radius", "tier": 1, "req": []},
	{"id": "power",   "tier": 1, "req": []},
	{"id": "carry",   "tier": 1, "req": []},
	{"id": "crit",    "tier": 2, "req": ["power"]},
	{"id": "fortune", "tier": 2, "req": ["carry"]},
	{"id": "equip",   "tier": 2, "req": ["power"]},
	{"id": "troops",  "tier": 3, "req": ["carry", "equip"]},
]
const SKILL_TIER_NAME := {1: "一 · 立身", 2: "二 · 扬名", 3: "三 · 成军"}
const SKILL_TIERS: Array = [1, 2, 3]

# ---------- 武将升级（v0.9）：每个武将有独立等级，金币主去处之一 ----------
const HERO_LV_STEP := 0.08           # 每级 +8% 该武将自身战力
const HERO_LV_MAX := {2: 5, 3: 10, 4: 15, 5: 20, 6: 25}   # 按星级给的上限
const HERO_LV_COST := {2: 20, 3: 60, 4: 200, 5: 800, 6: 3000}   # 首级价
const HERO_LV_GROWTH := 1.35         # 每级涨价

# ---------- 装备部位（v0.9）：装备槽升级依次解锁这 5 个部位 ----------
const EQUIP_SLOTS: Array = ["兵器", "铠甲", "坐骑", "兵书", "宝物"]
const EQUIP_SLOT_COLOR := {
	"兵器": Color(0.90, 0.46, 0.42), "铠甲": Color(0.46, 0.66, 0.90),
	"坐骑": Color(0.86, 0.70, 0.36), "兵书": Color(0.52, 0.82, 0.60),
	"宝物": Color(0.78, 0.56, 0.90),
}
const EQUIP_SLOT_DESC := {
	"兵器": "主拍力", "铠甲": "主每轮时长", "坐骑": "主机动（点击/连击/金币）",
	"兵书": "主暴击与连击", "宝物": "主金币与离线收益",
}

# ---------- 旧建筑强化常量仅用于一次性返还旧档投资 ----------
const BUILDING_LV_MAX := 10
const BUILDING_LV_STEP := 0.15       # 每级 +15% 产出
const BUILDING_LV_COST := 120        # 首级价
const BUILDING_LV_GROWTH := 1.45
const BuildingTraits = preload("res://scripts/building_traits.gd")

# ---------- effect 词条（武将被动 / 装备属性 共用） ----------
const CardTraits = preload("res://scripts/build_traits.gd")
const MOD_KEYS: Array = [
	"power_pct",       # 拍力 +X%
	"power_mult",      # 拍力 ×N（多段乘区）
	"gold_pct",        # 金币 +X%
	"stamina_flat",    # 体力上限 +N
	"stamina_pct",     # 体力上限 +X%
	"crit_pct",        # 暴击 +X%
	"offline_pct",     # 离线收益 +X%
	"paian_pct",       # 终结技伤害 +X%
	"paian_mult",      # 终结技伤害 ×N
	"threshold",       # 终结技触发线 增量（负值）
	"threshold_set",   # 终结技触发线 直接设为 N（0=未设）
	"combo_gain",      # 连击 +N
	"click_pct",       # 点击伤害 / 节奏 +X%
	"pack_pct",        # 卡包价格 X%（负值）
	"all_pct",         # 全属性 +X%
	"extra_slaps",     # 每关额外 N 次点击
	"combo_shield",    # 连击保护 / 不中断（0/1）
	"relax_drag",      # 滑拍判定放宽（0/1）
	"magnet",          # 金币磁力（预留）
]

## 会被「军械坊：装备效果 +X%」放大的百分比类词条
const PCT_KEYS: Array = [
	"power_pct", "gold_pct", "stamina_pct", "crit_pct",
	"offline_pct", "paian_pct", "click_pct", "all_pct",
]

# ---------- 经济与收藏 ----------
var gold: float = 0.0
var player_lv := 1
var player_xp := 0
var skill_points := 0
var hero_xp: Dictionary = {}
var map_events: Dictionary = {}
var items: Dictionary = {}
var owned: Dictionary = {}          # card_id -> 数量（持有的一切：武将/士兵/装备/建筑/城池）
var captured: Array = []            # 囚禁中的武将 card_id（可招降）
var total_packs: int = 0

# ---------- 局外成长（升级树 / 上阵 / 装备 / 武将等级） ----------
var up: Dictionary = {}             # 升级项 id -> 等级
var carry: Array = []               # 上阵卡 id（**不含**主角卡），长度 <= carry_max()
## ⚠️ v1.1 装备巢纠错（用户：「装备巢搞错了，装备是每个武将都有」）：
##   原来是一个**全局** equipped 数组（5 格，谁都能装）。现在改成**每个武将各自一份**。
##   hero_equip[武将id] = [装备id, ...]，每将每个部位最多一件。
##   ⚠️ 一件装备卡同时只能挂在一个武将身上（靠 equip_owner() 反查，换人要摘）。
##   ⚠️ 士兵**不参与**装备（用户：「士兵没有装备巢」）；主角也不参与（固定位，保持"素"）。
var hero_equip: Dictionary = {}
## ⚠️ v1.1 兵位（用户：「未来点亮技能树里的武将带兵能力 可以直接把兵给武将装备」）：
##   hero_troops[武将id] = [士卒id, ...]。技能树「武将带兵」点亮后才有。
##   与携带位**互斥**：挂进兵位的士卒不再占携带位，战力照样全额计入。
var hero_troops: Dictionary = {}
var hero_refined: Dictionary = {}
var hero_lv: Dictionary = {}        # 武将 card_id -> 等级（v0.9）
var _eff_cache: Dictionary = {}     # effect 文本 -> 词条字典（解析缓存）
var runs: int = 0                   # 已结算局数（"第几趟"）
var run_kills: int = 0              # 本局击倒数
var run_damage: float = 0.0         # 本局累计伤害
var run_gold: float = 0.0           # 本局实际战斗获金：击倒 + 结算/首通；不包含城建与消费

# ---------- 地图 ----------
var region_state: Dictionary = {}   # idx -> "locked" | "available" | "cleared"
var cities: Dictionary = {}         # idx -> { "buildings": [building_id, ...] }
var city_lv: Dictionary = {}        # idx -> [等级, ...]（与 buildings 一一对应，v0.9）
var building_refined: Dictionary = {}  # 仓库里精制/珍藏数量；原版=owned减去这两项
var city_quality: Dictionary = {}      # 与城市建筑槽一一对应，0原版/1精制/2珍藏
var building_clocks: Dictionary = {}   # 每城10秒基础周期的剩余进度
var building_ticks: Dictionary = {}    # 每城基础周期计数；追加不推动计数
var affinity: Dictionary = {}       # 路线名 -> 该线已克服区域数
var pack_bought: Dictionary = {}    # 卡包名 -> 购买次数

# ---------- 战斗 ----------
var battle_region: int = 0
var battle: Array = []              # [{card_id, hp, hp_max, boss, nx, ny, rot}]
var battle_gen: int = 0             # 牌桌代次：每次重新铺桌 +1，UI 据此判断是否重建卡牌
var stamina: int = 0                # 旧界面入口：剩余秒数，不再按拍击扣除。
var stamina_max: int = 0            # 旧界面入口：本轮总秒数。
var round_active := false
var round_duration := 0.0
var round_seconds_left := 0.0
var round_seconds_elapsed := 0.0
var slap_cooldown_left := 0.0
var round_slaps := 0
var round_tables_flipped := 0
var round_first_clears: Array = []
var table_damage := 0.0
var _slap_batch_active := false
var _slap_batch_started := false
var _slap_batch_gen := -1
var _slap_batch_hits: Dictionary = {}
var _pending_table_clear := false
var _pile_stages_done: Dictionary = {} # 当前整堆已发过翻段金币的阶段，补堆时重置。
var _pile_stage_damage: Dictionary = {} # 分段实际伤害，用于旧档的最高进度记录。
var combo: int = 0
var in_battle: bool = false
var last_battle_report: String = ""
var last_settle: String = ""         # 最近一次结算的战报（回大本营时显示）
var end_reason: String = ""          # "" | "settled"（时间到或主动回营）；兼容旧档的cleared。
var last_outcome: Dictionary = {}   # {region, result, gold, kills, damage}；下一次有效出战才清除
var last_slap: Dictionary = {}       # {index, heavy, damage, tag} 供 UI 播特效

# ---------- 功能建筑累计加成 ----------
var bonus: Dictionary = {
	"combat_power_pct": 0.0, "pack_price_pct": 0.0, "offline_hours": 0.0,
	"stamina_flat": 0.0, "building_output_pct": 0.0, "equip_pct": 0.0,
	"ransom_pct": 0.0,
}

# 跨桌保留完成记号与最高伤害，敌牌剩余血量仍每次重置。
var table_wins: Dictionary = {}
var cleared_zones: Dictionary = {} # 城池 -> 已永久征服的0基分区号，允许任意顺序。
var table_best: Dictionary = {}
var first_flip_reward := false
var story_seen: Array = []
var practice_runs := 0
var practice_region := 1
var practice_table := 0
var battle_table := 0
var battle_mode := "challenge"
var automation_enabled := false
var narrative_paused := false
var _auto_clock := 0.0
var _auto_rest := 0.0
var offline_report: String = ""

var _idle_buffer: float = 0.0
var _save_timer: float = 0.0
var _manual_damage_context := false
## 构筑计数与冷却仅属于当前桌，和敌牌生命一样不跨桌或跨读档。
var build_clock: float = 0.0
var build_counts: Dictionary = {}
var build_ready_at: Dictionary = {}
var build_events: Array = []        # 最近一次行动的状态 / 伤害事件，供牌桌反馈使用
var build_effect_seq: int = 0       # UI事件批次序号：金币等其他 changed 不重复播放打击


# =====================================================================
# effect 文本 -> 规范词条（v0.9）
#   武将被动 / 装备属性 共用同一个解析器。
#   文本形如「拍力 +50%；连击不中断」「体力上限 +20%」「终结技触发线 -5」。
# =====================================================================
func empty_mods() -> Dictionary:
	var d: Dictionary = {}
	for k in MOD_KEYS:
		d[k] = 0.0
	return d


func parse_effect(text: String) -> Dictionary:
	if _eff_cache.has(text):
		var cached: Dictionary = _eff_cache[text]
		return cached
	var m := empty_mods()
	var t := text.strip_edges()
	if t != "" and t != "-":
		for raw in t.replace(";", "；").split("；"):
			_apply_segment(m, str(raw).strip_edges())
	_eff_cache[text] = m
	return m


func _apply_segment(m: Dictionary, s: String) -> void:
	if s == "":
		return
	# 无数字的特殊标记
	if s == "连击不中断" or s == "连击保护":
		m["combo_shield"] = 1.0
		return
	if s == "滑拍判定放宽":
		m["relax_drag"] = 1.0
		return
	var num := _first_number(s)
	var pct := s.contains("%")
	if s.begins_with("拍力"):
		if s.contains("×") or s.contains("*"):
			m["power_mult"] += num
		else:
			m["power_pct"] += num
	elif s.begins_with("金币"):
		m["gold_pct"] += num
	elif s.begins_with("体力上限"):
		if pct:
			m["stamina_pct"] += num
		else:
			m["stamina_flat"] += num
	elif s.begins_with("暴击"):
		m["crit_pct"] += num
	elif s.begins_with("离线收益"):
		m["offline_pct"] += num
	elif s.begins_with("终结技伤害"):
		if s.contains("×") or s.contains("*"):
			m["paian_mult"] += num
		else:
			m["paian_pct"] += num
	elif s.begins_with("终结技触发线"):
		if s.contains("降至"):
			m["threshold_set"] = num
		else:
			m["threshold"] += num
	elif s.begins_with("终结技"):
		m["paian_pct"] += num
	elif s.begins_with("连击"):
		m["combo_gain"] += num
	elif s.begins_with("点击伤害") or s.begins_with("点击节奏"):
		m["click_pct"] += num
	elif s.begins_with("卡包价格"):
		m["pack_pct"] += num
	elif s.begins_with("全属性"):
		m["all_pct"] += num
	elif s.begins_with("每关额外"):
		m["extra_slaps"] += num


func _first_number(s: String) -> float:
	## 取字符串里第一个数（支持前导负号与小数点）。
	var buf := ""
	var started := false
	var neg := false
	for i in s.length():
		var ch := s[i]
		if not started and (ch == "-" or ch == "−"):
			neg = true
			continue
		if (ch >= "0" and ch <= "9") or ch == ".":
			buf += ch
			started = true
		elif started:
			break
	if buf == "":
		return 0.0
	var v := float(buf)
	return -v if neg else v


func add_mods(a: Dictionary, b: Dictionary) -> Dictionary:
	## 词条相加（数值累加）。
	var out := empty_mods()
	for k in MOD_KEYS:
		out[k] = float(a.get(k, 0.0)) + float(b.get(k, 0.0))
	return out


# =====================================================================
# 上阵武将 / 装备 的词条汇总
# =====================================================================
func hero_mods() -> Dictionary:
	## 只汇总【上阵】武将的被动（主角卡不参与被动）。
	var m := empty_mods()
	for id in carry:
		m = add_mods(m, parse_effect(str(GameData.card(id).get("effect", ""))))
	return m


func hero_equip_mods(who: String) -> Dictionary:
	## 装备只能增加佩戴者本来具有的同名参数。
	var m := empty_mods()
	for id in hero_equip.get(who, []):
		m = add_mods(m, _matched_equipment_mods(who, str(id)))
	var amp := 1.0 + float(bonus.get("equip_pct", 0.0)) / 100.0
	for key in PCT_KEYS:
		m[key] = float(m[key]) * amp
	return m


func _matched_equipment_mods(who: String, id: String) -> Dictionary:
	var result := empty_mods()
	if not is_hero(who): return result
	var innate := parse_effect(str(GameData.card(who).get("effect", "")))
	var equipment := parse_effect(str(GameData.card(id).get("effect", "")))
	for key in MOD_KEYS:
		if not is_zero_approx(float(innate[key])):
			result[key] = float(equipment[key])
	return result


func hero_trait_params(who: String) -> Dictionary:
	var distance := float(CardTraits.GATHER_HEROES.get(who, 0.0))
	if distance <= 0.0: return {}
	for id in hero_equip_of(who):
		distance += float(CardTraits.GATHER_EQUIPMENT.get(str(id), 0.0))
	return {"gather_distance": distance, "gather_radius": CardTraits.GATHER_RADIUS}


func equipment_effect_text(who: String, id: String) -> String:
	if CardTraits.GATHER_EQUIPMENT.has(id):
		if not CardTraits.GATHER_HEROES.has(who):
			return "不契合：本将没有聚拢特性，装备不产生效果"
		return "契合：聚拢距离 +%s（与本将原有距离相加）" % fmt(float(CardTraits.GATHER_EQUIPMENT[id]))
	var equipment := parse_effect(str(GameData.card(id).get("effect", "")))
	var matched := _matched_equipment_mods(who, id)
	var names := {"power_pct": "拍力加成", "power_mult": "拍力倍率", "gold_pct": "金币加成",
		"stamina_flat": "固定时长", "stamina_pct": "时长加成", "crit_pct": "暴击率",
		"offline_pct": "离线收益", "paian_pct": "拍案加成", "paian_mult": "拍案倍率",
		"threshold": "拍案门槛", "threshold_set": "指定拍案门槛", "combo_gain": "连击积累",
		"click_pct": "点击伤害", "pack_pct": "卡包价格", "all_pct": "全属性",
		"extra_slaps": "额外时长", "combo_shield": "连击保护", "relax_drag": "滑拍判定"}
	var active: Array[String] = []
	var inactive: Array[String] = []
	for key in MOD_KEYS:
		if is_zero_approx(float(equipment[key])): continue
		var label := str(names.get(key, key))
		if is_zero_approx(float(matched[key])):
			inactive.append(label)
		else:
			var amount := float(matched[key])
			if key in PCT_KEYS: amount *= 1.0 + float(bonus.get("equip_pct", 0.0)) / 100.0
			var unit := "%" if key in PCT_KEYS else ""
			if key in ["stamina_flat", "extra_slaps"]:
				amount *= 2.0
				unit = "秒"
			if key == "combo_shield":
				active.append("连击保护（已有，不叠加）")
			else:
				active.append("%s %s%s%s" % [label, "+" if amount > 0 else "", fmt(amount), unit])
	var text := "不契合：本将没有对应特性，装备不产生效果" if active.is_empty() else "契合：" + "、".join(active)
	if not inactive.is_empty() and not active.is_empty(): text += "；不契合：" + "、".join(inactive)
	return text


func equip_mods() -> Dictionary:
	## ⚠️ v1.1：装备是**每将独立**的，所以这里要按武将汇总 —— 而且只算**上阵**的武将
	##    （与"只算上阵的卡"一致：没上阵的武将，它身上的装备也不上桌）。
	## 军械坊已在各将的契合词条中放大，不能重复乘一次。
	var m := empty_mods()
	for who in carry:
		m = add_mods(m, hero_equip_mods(str(who)))
	return m


func active_mods() -> Dictionary:
	## 武将被动 + 装备，合并后的总词条。
	return add_mods(hero_mods(), equip_mods())


func _ready() -> void:
	_check_engine()
	if not GameData.is_node_ready():
		GameData.ready.connect(_on_data_ready, CONNECT_ONE_SHOT)
	else:
		_boot()


func _check_engine() -> void:
	## 本机常见多个 Godot：/Applications/Godot.app 是 4.3，别用。
	## 用错版本会出现"看起来像业务 bug"的诡异现象，所以这里先把话说明白。
	var v: Dictionary = Engine.get_version_info()
	var major := int(v.get("major", 0))
	var minor := int(v.get("minor", 0))
	var ver := str(v.get("string", "?"))
	if major != 4 or minor < 7:
		var tip := "本项目针对 Godot 4.7.2 编写，当前引擎是 %s。" % ver
		tip += "请改用 ~/Downloads/Godot.app/Contents/MacOS/Godot 启动（/Applications/Godot.app 是 4.3）。"
		push_error(tip)
		log_msg("⚠️ %s" % tip)
	else:
		print("[GameState] 引擎版本 %s ✓" % ver)


func _on_data_ready() -> void:
	_boot()


func _boot() -> void:
	## v1.0：SAVE_ENABLED=false 时每次启动都开新周目，不去读档。
	if not SAVE_ENABLED or not load_game():
		new_game()


func _process(delta: float) -> void:
	if not narrative_paused: advance_round(delta)
	if SAVE_ENABLED:
		_save_timer += delta
		if _save_timer >= 30.0:
			_save_timer = 0.0
			save_game()


# 逐桌推进与练习共用限时轮、共享拍击间隔与即时伤害收益。
func table_count(idx: int) -> int:
	return Progression.table_count(idx)

func table_progress(idx: int) -> int:
	return (cleared_zones.get(idx, []) as Array).size()

func zone_count(idx: int) -> int:
	return table_count(idx)

func zone_cleared(idx: int, zone: int) -> bool:
	return (cleared_zones.get(idx, []) as Array).has(zone)

func zone_status(idx: int, zone: int) -> String:
	if zone < 0 or zone >= zone_count(idx) or not is_unlocked(idx): return "locked"
	return "cleared" if zone_cleared(idx, zone) else "available"

func next_zone(idx: int) -> int:
	for zone in range(zone_count(idx)):
		if not zone_cleared(idx, zone): return zone
	return -1

func zone_hp(idx: int, zone: int) -> float:
	return table_hp(idx, zone)

func zone_name(idx: int, zone: int) -> String:
	return "%s第%d区" % [GameData.region(idx).get("name", "城池"), zone + 1]

func zone_rect(idx: int, zone: int) -> Rect2:
	var rects := preload("res://scripts/city_layout.gd").zone_rects(zone_count(idx))
	return rects[zone] if zone >= 0 and zone < rects.size() else Rect2()

func battle_world_size() -> Vector2:
	return preload("res://scripts/city_layout.gd").zone_world_size(zone_count(battle_region if battle_region > 0 else START_REGION))

func get_enemy_world_center(i: int) -> Vector2:
	if i < 0 or i >= battle.size(): return Vector2.ZERO
	return Vector2(250, 250) + Vector2(float(battle[i].nx), float(battle[i].ny)) * (battle_world_size() - Vector2(500, 500))

func zone_details(idx: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for zone in range(zone_count(idx)):
		result.append({"zone": zone, "name": zone_name(idx, zone), "rect": zone_rect(idx, zone),
			"hp": zone_hp(idx, zone), "cards": _table_health_values(idx, zone).size(),
			"cleared": zone_cleared(idx, zone), "status": zone_status(idx, zone),
			"difficulty": maxi(1, ceili(float(zone + 1) / zone_count(idx) * 5.0))})
	return result

func table_hp(idx: int, completed: int = -1) -> float:
	return Progression.table_hp(GameData.region(idx), maxi(0, next_zone(idx)) if completed < 0 else completed)

func table_best_value(idx: int, step: int) -> float:
	return float(table_best.get("%d:%d" % [idx, step], 0.0))

func _update_table_best() -> void:
	for step in _pile_stage_damage:
		var key := "%d:%d" % [battle_region, int(step)]
		table_best[key] = maxf(float(table_best.get(key, 0.0)), float(_pile_stage_damage[step]))

func round_duration_value() -> float:
	# 保留stamina存档键；原体力词条按每点2秒延长，百分比继续放大时长。
	var seconds := upgrade_value("stamina")
	var mods := active_mods()
	seconds += (float(bonus["stamina_flat"]) + float(mods["stamina_flat"]) + float(mods["extra_slaps"])) * Progression.ROUND_SECONDS_PER_LEVEL
	seconds *= 1.0 + float(mods["stamina_pct"]) / 100.0
	if bond_tier("魏线") >= 2: seconds *= 1.1
	return maxf(Progression.ROUND_SECONDS, seconds)

func slap_interval(heavy: bool = false) -> float:
	return maxf(0.025, 1.0 / maxf(1.0, upgrade_value("speed"))) * (1.8 if heavy else 1.0)

func slap_radius() -> float:
	return upgrade_value("radius")

func pile_remaining() -> int:
	var remaining := 0
	for e in battle:
		if float(e["hp"]) > 0.0: remaining += 1
	return remaining

func pile_card_count() -> int:
	return battle.size()

func pile_health() -> float:
	var hp := 0.0
	for e in battle: hp += maxf(0.0, float(e["hp"]))
	return hp

func pile_max_health() -> float:
	var hp := 0.0
	for e in battle: hp += float(e["hp_max"])
	return hp

func auto_interval() -> float:
	return slap_interval() * Progression.AUTO_INTERVAL_MULT

func round_gold_per_second() -> float:
	return run_gold / maxf(1.0, round_seconds_elapsed)

func begin_slap_batch() -> bool:
	# 圆内所有目标共享一掌与一次冷却；代次保护防止命中刚补出的新堆。
	end_slap_batch()
	if not round_active or not in_battle or narrative_paused or round_seconds_left <= 0.0 or slap_cooldown_left > 0.000001:
		return false
	_slap_batch_active = true
	_slap_batch_gen = battle_gen
	return true

func end_slap_batch() -> void:
	var was_active := _slap_batch_active
	_slap_batch_active = false
	_slap_batch_started = false
	_slap_batch_gen = -1
	_slap_batch_hits = {}
	var replenish := _pending_table_clear
	_pending_table_clear = false
	if was_active and in_battle and round_active: _update_pile_checkpoints()
	if replenish and in_battle and round_active: _clear_region()

func advance_round(delta: float) -> void:
	if narrative_paused or delta <= 0.0: return
	if in_battle and round_active:
		if battle_mode == "visit":
			slap_cooldown_left = maxf(0.0, slap_cooldown_left - delta)
			return
		if MapEvents.advance(self, minf(delta, round_seconds_left)):
			events_changed.emit()
	var remaining := delta
	while remaining > 0.000001 and in_battle and round_active and not narrative_paused:
		var slice := minf(remaining, round_seconds_left)
		slice = minf(slice, _next_build_event_time())
		if slice > 0.0:
			slap_cooldown_left = maxf(0.0, slap_cooldown_left - slice)
			round_seconds_elapsed += slice
			round_seconds_left = maxf(0.0, round_seconds_left - slice)
			stamina = int(ceil(round_seconds_left))
			remaining -= slice
			_tick_build_effects(slice, true)
		if not in_battle: break
		if round_seconds_left <= 0.000001:
			round_seconds_left = 0.0
			settle_run("time_up")
		elif slice <= 0.0:
			break

func _start_table(idx: int) -> bool:
	battle_region = idx
	_reset_build_traits()
	_refresh_enemies()
	round_duration = round_duration_value()
	round_seconds_left = round_duration
	round_seconds_elapsed = 0.0
	round_active = true
	slap_cooldown_left = 0.0
	round_slaps = 0
	round_tables_flipped = 0
	round_first_clears = []
	table_damage = 0.0
	end_slap_batch()
	stamina_max = int(ceil(round_duration))
	stamina = stamina_max
	combo = 0
	run_kills = 0
	run_damage = 0.0
	run_gold = 0.0
	end_reason = ""
	last_outcome = {}
	in_battle = true
	last_slap = {}
	MapEvents.ensure_region(self, idx)
	events_changed.emit()
	last_battle_report = "%s · 巡城处理宝箱与任务" % GameData.region(idx).get("name", "") if battle_mode == "visit" else "%s · 未征服分区%d张　每轮%d秒 · 间隔%.2f秒 · 轻拍%.1f · 总厚度%s" % [
		GameData.region(idx).get("name", ""), battle.size(), stamina, slap_interval(), click_damage(), fmt(pile_max_health())]
	changed.emit()
	return battle_mode == "visit" or not battle.is_empty()

func _grant_table_reward(idx: int, step: int) -> void:
	if idx != 1: return
	if table_progress(idx) == 1:
		for id in ["B06", "B08"]:
			_building_stock_change(id, 0, 1)
	var gift := "G00" if step == 0 else ("G04" if step == 2 else ("G05" if step == 4 else ""))
	if gift != "":
		owned[gift] = int(owned.get(gift, 0)) + 1
		_auto_carry()
		log_msg("获得将牌「%s」，构筑能让下一掌不一样。" % GameData.card_name(gift))


func practice_unlocked() -> bool:
	return false

func _practice_target(idx: int) -> int:
	if table_progress(idx) > 0: return idx
	for r in GameData.regions:
		if table_progress(int(r["idx"])) > 0: return int(r["idx"])
	return 0

func start_practice(_idx: int = 1) -> bool:
	return false # 已征服分区不再刷新，挂机只通过建筑。

func auto_unlocked() -> bool:
	return false

func auto_ratio() -> float:
	return 0.0

func set_automation(enabled: bool) -> bool:
	stop_automation(false)
	return not enabled

func stop_automation(announce: bool = true) -> void:
	automation_enabled = false
	_auto_clock = 0.0
	_auto_rest = 0.0
	if announce:
		save_game()
		changed.emit()

func _finish_automation_run() -> void:
	stop_automation(false)

func advance_automation(_delta: float) -> void:
	stop_automation(false)

func practice_rate() -> float:
	return 0.0 # 旧API保留给历史界面，建筑之外不再产生挂机工资。

func progression_hint() -> String:
	var idx := battle_region if battle_region > 0 and not _is_cleared(battle_region) else 0
	if idx == 0:
		for r in GameData.regions:
			if is_unlocked(int(r["idx"])) and not _is_cleared(int(r["idx"])):
				idx = int(r["idx"])
				break
	if idx == 0: return "荆州全境已征服 · 经营建筑，整理收藏"
	var done := table_progress(idx)
	var zone := next_zone(idx)
	var goal := "%s 已征服%d/%d区 · 推荐第%d区厚度%s" % [GameData.region(idx).get("name", ""), done, table_count(idx), zone + 1, fmt(table_hp(idx, zone))]
	var best := table_best_value(idx, zone)
	if best > 0.0: goal += " · 最好%.0f%%" % minf(100.0, best / table_hp(idx, zone) * 100.0)
	var cost := mini(upgrade_cost("radius"), mini(upgrade_cost("power"), mini(upgrade_cost("stamina"), upgrade_cost("speed"))))
	goal += " · " + ("可升级拍力、拍速、范围或时长" if gold >= cost else "再积累%s金币可练一笔" % fmt(cost - gold))
	return goal

func progression_star_cap() -> int:
	if cleared_count() >= 10: return 6
	if cleared_count() >= 4: return 5
	return 4 if _is_cleared(1) else 3

func story_context() -> Dictionary:
	var cleared := []
	var total := 0
	for r in GameData.regions:
		var idx := int(r["idx"])
		if _is_cleared(idx): cleared.append(idx)
		total += table_progress(idx)
	return {"runs": runs, "cleared_count": cleared_count(), "cleared_regions": cleared,
		"first_clear": _is_cleared(1), "power_level": upgrade_level("power"), "stamina_level": upgrade_level("stamina"), "speed_level": upgrade_level("speed"), "auto_unlocked": auto_unlocked(),
		"idle_runs": practice_runs, "practice_runs": practice_runs, "training": battle_mode == "practice",
		"in_battle": in_battle, "last_result": end_reason, "field_clear": _is_cleared(21),
		"table_wins": total, "total_tables": total}

func mark_story_seen(id: String) -> void:
	if not story_seen.has(id): story_seen.append(id)
	save_game()

func hero_stock(id: String, quality: int = 0) -> int:
	var total := maxi(0, int(owned.get(id, 0)))
	var qualities: Array = hero_refined.get(id, [0, 0])
	var rare := mini(total, maxi(0, int(qualities[1]))) if qualities.size() > 1 else 0
	var fine := mini(total - rare, maxi(0, int(qualities[0]))) if qualities.size() > 0 else 0
	return [total - fine - rare, fine, rare][clampi(quality, 0, 2)]

func hero_quality(id: String) -> int:
	if hero_stock(id, 2) > 0: return 2
	return 1 if hero_stock(id, 1) > 0 else 0

func hero_quality_name(id: String) -> String:
	return ["原版", "精制", "珍藏"][hero_quality(id)]

func _hero_free_stock(id: String, quality: int) -> int:
	var protected := in_carry(id) or not hero_equip_of(id).is_empty() or not hero_troops_of(id).is_empty()
	return maxi(0, hero_stock(id, quality) - (1 if protected and hero_quality(id) == quality else 0))

func hero_fusion_stock(id: String) -> int:
	return _hero_free_stock(id, 1) if _hero_free_stock(id, 1) >= 3 else _hero_free_stock(id, 0)

func can_fuse_hero(id: String) -> bool:
	return is_hero(id) and (_hero_free_stock(id, 0) >= 3 or _hero_free_stock(id, 1) >= 3)

func fuse_hero(id: String) -> bool:
	if in_battle: return false
	if not can_fuse_hero(id): return false
	var quality := 1 if _hero_free_stock(id, 1) >= 3 else 0
	var fine := hero_stock(id, 1)
	var rare := hero_stock(id, 2)
	owned[id] = int(owned[id]) - 2
	hero_refined[id] = [fine + (1 if quality == 0 else -3), rare + (1 if quality == 1 else 0)]
	log_msg("同名合成「%s」：3%s→1%s；星级与触发规则保留。" % [GameData.card_name(id), ["原版", "精制"][quality], ["精制", "珍藏"][quality]])
	save_game()
	shop_changed.emit()
	changed.emit()
	return true

func _load_progression_state(d: Dictionary) -> void:
	table_wins = {}
	cleared_zones = {}
	var zone_data: Dictionary = d.get("cleared_zones", {}) if d.get("cleared_zones", {}) is Dictionary else {}
	for r in GameData.regions:
		var idx := int(r["idx"])
		var zones: Array[int] = []
		var stored: Variant = zone_data.get(str(idx), [])
		if stored is Array:
			for value in stored:
				var zone := int(value)
				if zone >= 0 and zone < zone_count(idx) and not zones.has(zone): zones.append(zone)
		zones.sort()
		cleared_zones[idx] = zones
		table_wins[idx] = zones.size()
		if zones.size() == zone_count(idx): region_state[idx] = "cleared"
	table_best = {}
	for key in d.get("table_best", {}):
		var bits := str(key).split(":")
		if bits.size() == 2 and not GameData.region(int(bits[0])).is_empty():
			table_best[str(key)] = maxf(0.0, float(d["table_best"][key]))
	story_seen = []
	for id in d.get("story_seen", []):
		if id is String and not story_seen.has(id): story_seen.append(id)
	first_flip_reward = bool(d.get("first_flip_reward", runs > 0))
	practice_runs = maxi(0, int(d.get("practice_runs", 0)))
	practice_region = _practice_target(int(d.get("practice_region", 1)))
	if practice_region == 0: practice_region = 1
	practice_table = clampi(int(d.get("practice_table", 0)), 0, maxi(0, table_progress(practice_region) - 1))
	automation_enabled = false
	narrative_paused = false
	hero_refined = {}
	for id in d.get("hero_refined", {}):
		if is_hero(str(id)) and d["hero_refined"][id] is Array:
			hero_refined[str(id)] = d["hero_refined"][id]



# =====================================================================
# 新周目
# =====================================================================
func new_game() -> void:
	gold = 0.0
	player_lv = 1
	player_xp = 0
	skill_points = 0
	hero_xp = {}
	map_events = {}
	items = {}
	_manual_damage_context = false
	owned = {"I01": 1}
	captured = []
	region_state = {}
	for r in GameData.regions:
		region_state[int(r["idx"])] = "locked"
	cities = {}
	city_lv = {}
	building_refined = {}
	city_quality = {}
	building_clocks = {}
	building_ticks = {}
	_idle_buffer = 0.0
	affinity = {}
	for rt in ROUTES:
		affinity[rt] = 0
	pack_bought = {}
	total_packs = 0
	in_battle = false
	round_active = false
	round_duration = 0.0
	round_seconds_left = 0.0
	round_seconds_elapsed = 0.0
	slap_cooldown_left = 0.0
	round_slaps = 0
	round_tables_flipped = 0
	round_first_clears = []
	table_damage = 0.0
	_pile_stages_done = {}
	_pile_stage_damage = {}
	end_slap_batch()
	battle = []
	end_reason = ""
	_reset_build_traits()
	last_outcome = {}
	_reset_bonus()

	# 局外成长全部归零：升级树 0 级、只带 3 个、没有装备槽、武将 0 级。
	up = {}
	for u in UPGRADES:
		up[str(u["id"])] = 0
	carry = []
	hero_equip = {}          # v1.1：装备巢改成每将独立（原全局 equipped 数组已废）
	hero_troops = {}         # v1.1：兵位（技能树「武将带兵」点亮后才有）
	hero_lv = {}
	hero_refined = {}
	table_wins = {}
	cleared_zones = {}
	table_best = {}
	first_flip_reward = false
	story_seen = []
	practice_runs = 0
	practice_region = 1
	practice_table = 0
	battle_table = 0
	battle_mode = "challenge"
	automation_enabled = false
	narrative_paused = false
	_auto_clock = 0.0
	_auto_rest = 0.0
	runs = 0
	run_kills = 0
	run_damage = 0.0
	run_gold = 0.0
	last_settle = ""

	# v1.0：新野不再是"零敌人的序章"—— 它是要真打的第一个区域（60 血 / 6 个敌人，约 7~10 趟）。
	# 所以这里只标成「可挑战」，不再直接算已克服。
	# ⚠️ 新野仍然**不计入 cleared_count()**（城建解锁依旧要求"再克服 3 处"），
	#    这样"挂机是后面才拿到的奖励、不是开场背景板"这条设计没有被破坏。
	region_state[START_REGION] = "available"
	_grant_affinity(START_REGION)

	log_msg("孤身来到新野，拍翻敌牌后再招募同行。")

	# 直接铺第一桌，玩家一进来就有一桌卡等着拍
	ensure_table()
	save_game()
	map_changed.emit()
	shop_changed.emit()
	changed.emit()


func hard_reset() -> void:
	new_game()
	log_msg("已重开新周目。")


# =====================================================================
# 路线 / 亲和 / 羁绊
# =====================================================================
func route_unit_count(rt: String) -> int:
	# 羁绊看的是「上阵」的卡，不是仓库里堆的卡 —— 带谁上场才是流派选择
	var n := 0
	if str(GameData.card(HERO_ALWAYS).get("route", "")) == rt:
		n += 1
	for id in carry:
		if str(GameData.card(id).get("route", "")) == rt:
			n += 1
	return n


func affinity_tier(rt: String) -> int:
	var v := int(affinity.get(rt, 0))
	if v >= 7: return 3
	if v >= 5: return 2
	if v >= 3: return 1
	return 0


func bond_tier(rt: String) -> int:
	var n := route_unit_count(rt)
	if n >= 6: return 2
	if n >= 3: return 1
	return 0


func affinity_unlock_text(rt: String) -> String:
	var t := affinity_tier(rt)
	if t >= 3: return "亲和 7 已达成 · 专属建筑已解锁"
	if t == 2: return "亲和 5 · 基建位按已征服区数开放"
	if t == 1: return "亲和 3：招降 -15%"
	return "亲和 0"


# =====================================================================
# 升级树（局外持久成长）—— 金币的主去处
# =====================================================================
func up_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if str(u["id"]) == id:
			return u
	return {}


func upgrade_level(id: String) -> int:
	return int(up.get(id, 0))


## 升级树的取值公式，两种形态：
##   kind="add"   → base + step × lv      （加法式，线性；必须设 lv 上限）
##   kind="mult"  → base × factor ^ lv    （复利式，无上限；用来撑起陡峭的敌人曲线）
func _up_formula(u: Dictionary, lv: int) -> float:
	var base := float(u.get("base", 0.0))
	if str(u.get("kind", "add")) == "mult":
		return base * pow(float(u.get("factor", 1.0)), float(lv))
	return base + float(u.get("step", 0.0)) * float(lv)


func _up_cap(u: Dictionary) -> int:
	## <=0 表示无上限（只有复利式才允许）。
	return int(u.get("lv", 0))


func upgrade_value(id: String) -> float:
	var u := up_def(id)
	if u.is_empty():
		return 0.0
	return _up_formula(u, upgrade_level(id))


func upgrade_next_value(id: String) -> float:
	## 下一级会变成多少 —— 加法式是 +step，复利式是 ×factor，两者不能混用。
	var u := up_def(id)
	if u.is_empty():
		return 0.0
	return _up_formula(u, upgrade_level(id) + 1)


func upgrade_preview(id: String) -> Dictionary:
	# 同步只读预览：用战斗实际公式计算，包含装备、武将和建筑修饰。
	if id not in ["power", "speed", "stamina", "radius"]: return {}
	var current := _upgrade_snapshot()
	var existed := up.has(id)
	var level := upgrade_level(id)
	var maxed := upgrade_maxed(id)
	if not maxed: up[id] = level + 1
	var next := _upgrade_snapshot()
	if existed: up[id] = level
	else: up.erase(id)
	return {"current": current, "next": next, "level": level, "maxed": maxed}


func _upgrade_snapshot() -> Dictionary:
	var interval := slap_interval()
	var duration := round_duration_value()
	return {"damage": click_damage(), "interval": interval, "frequency": 1.0 / interval,
		"duration": duration, "slaps": ceili(duration / interval - 0.000001), "radius": slap_radius()}


func upgrade_max_value(id: String) -> float:
	## 无上限的升级树返回"当前值"（界面不显示满级值）。
	var u := up_def(id)
	if u.is_empty():
		return 0.0
	var cap := _up_cap(u)
	if cap <= 0:
		return _up_formula(u, upgrade_level(id))
	return _up_formula(u, cap)


func upgrade_maxed(id: String) -> bool:
	var u := up_def(id)
	if u.is_empty():
		return true
	var cap := _up_cap(u)
	if cap <= 0:
		return false                       # 无上限：永远不满级
	return upgrade_level(id) >= cap


func upgrade_cost(id: String) -> int:
	return 0 if up_def(id).is_empty() or upgrade_maxed(id) else 1

func buy_upgrade(id: String) -> bool:
	if in_battle or up_def(id).is_empty() or not skill_req_met(id) or upgrade_maxed(id): return false
	var cost := upgrade_cost(id)
	if skill_points < cost: return false
	skill_points -= cost
	up[id] = upgrade_level(id) + 1
	save_game()
	shop_changed.emit()
	changed.emit()
	return true


# =====================================================================
# 技能树（v1.1）—— 层级 + 前置（数值仍在 UPGRADES）
# =====================================================================
func skill_node(id: String) -> Dictionary:
	for n in SKILL_TREE:
		if str(n["id"]) == id:
			return n
	return {}


func skill_tier(id: String) -> int:
	return int(skill_node(id).get("tier", 1))


func skill_reqs(id: String) -> Array:
	return skill_node(id).get("req", [])


func skill_req_met(id: String) -> bool:
	if id in ["auto", "auto_next", "auto_power", "idle"]: return false
	for req in skill_reqs(id):
		if upgrade_level(str(req)) < 1: return false
	if id == "carry" and table_progress(1) < 3: return false
	if id in ["equip", "troops"] and not _is_cleared(1): return false
	return true


func skill_req_text(id: String) -> String:
	if id in ["auto", "auto_next", "auto_power", "idle"]: return ""
	var miss := []
	for req in skill_reqs(id):
		if upgrade_level(str(req)) < 1: miss.append(str(up_def(str(req)).get("name", req)))
	if id in ["equip", "troops"] and not _is_cleared(1): miss.append("征服新野全城")
	if id == "carry" and table_progress(1) < 3: miss.append("征服新野任意3区")
	return "需先：" + " · ".join(miss) if not miss.is_empty() else ""


func skills_of_tier(t: int) -> Array:
	var out := []
	for n in SKILL_TREE:
		if int(n.get("tier", 0)) == t:
			out.append(str(n["id"]))
	return out


func skill_tier_progress(t: int) -> int:
	## 这一层点亮了几个（供界面显示 N/M）。
	var n := 0
	for id in skills_of_tier(t):
		if upgrade_level(str(id)) >= 1:
			n += 1
	return n


func total_upgrade_levels() -> int:
	var n := 0
	for k in up.keys():
		n += int(up[k])
	return n


func player_level() -> int:
	return player_lv

func player_xp_required() -> int:
	return 20 + 10 * (player_lv - 1)

func gain_player_xp(amount: int) -> void:
	if amount <= 0: return
	player_xp += amount
	var leveled := false
	while player_xp >= player_xp_required():
		player_xp -= player_xp_required()
		player_lv += 1
		skill_points += 1
		leveled = true
	if leveled: save_game()
	changed.emit()

func hero_xp_of(id: String) -> int:
	return int(hero_xp.get(id, 0)) if is_hero(id) else 0

func hero_xp_required(id: String) -> int:
	return 10 + 5 * (hero_level(id) - 1) if is_hero(id) and not hero_lv_maxed(id) else 0

func gain_hero_xp(id: String, amount: int) -> void:
	if amount <= 0 or not is_hero(id) or int(owned.get(id, 0)) <= 0 or hero_lv_maxed(id): return
	hero_xp[id] = hero_xp_of(id) + amount
	while not hero_lv_maxed(id) and hero_xp_of(id) >= hero_xp_required(id):
		hero_xp[id] = hero_xp_of(id) - hero_xp_required(id)
		hero_lv[id] = hero_level(id) + 1
	if hero_lv_maxed(id): hero_xp[id] = 0

func _award_slap_growth() -> void:
	if int(build_counts.get("growth_slap", -1)) == round_slaps: return
	build_counts["growth_slap"] = round_slaps
	for id in carry:
		if is_hero(str(id)):
			gain_hero_xp(str(id), 1)
	gain_player_xp(1)


# =====================================================================
# 上阵（携带位）—— 只有上桌的卡才算战力
# =====================================================================
func carry_max() -> int:
	return int(upgrade_value("carry"))


func is_carryable(id: String) -> bool:
	if id == HERO_ALWAYS:
		return false
	var c := GameData.card(id)
	if c.is_empty():
		return false
	if not (str(c.get("type", "")) in ["武将", "士兵"]):
		return false
	return float(c.get("power", 0.0)) > 0.0


func in_carry(id: String) -> bool:
	return carry.has(id)


func carry_add(id: String) -> bool:
	if in_battle: return false
	if not is_carryable(id):
		return false
	if in_carry(id):
		return false
	if in_troops(id):
		log_msg("%s 正在「%s」麾下带兵 —— 先从那卸下，才能上阵。" % [
			GameData.card_name(id), GameData.card_name(troop_owner(id))])
		return false
	if int(owned.get(id, 0)) <= 0:
		log_msg("没有这张卡。")
		return false
	if carry.size() >= carry_max():
		log_msg("携带位已满（%d 个）—— 去大本营升级「携带位」。" % carry_max())
		return false
	carry.append(id)
	_after_carry_change()
	return true


func carry_remove(id: String) -> bool:
	if in_battle: return false
	if not carry.has(id):
		return false
	carry.erase(id)
	_after_carry_change()
	return true


## v1.0：底部上阵条「拖到第 index 个槽位」用。
## 与 carry_add() 的差别只在**落点**：这里会把 id 插到第 index 位（后面的往后挪），
## 而不是一律追加到末尾 —— 否则玩家把牌拖到第 3 个空格、却出现在第 1 个空格，
## 会觉得"拖拽没生效"。已在阵中的牌会被移到该位（等于重排）。
## 槽位已满且这张牌不在阵中时拒绝（不会静默顶掉别人）。
func carry_put(id: String, index: int) -> bool:
	if in_battle: return false
	if not is_carryable(id):
		return false
	if in_troops(id) and not in_carry(id):
		log_msg("%s 正在「%s」麾下带兵 —— 先从那卸下，才能上阵。" % [
			GameData.card_name(id), GameData.card_name(troop_owner(id))])
		return false
	if int(owned.get(id, 0)) <= 0:
		log_msg("没有这张卡。")
		return false
	var already := in_carry(id)
	if already:
		carry.erase(id)
	elif carry.size() >= carry_max():
		log_msg("携带位已满（%d 个）—— 去大本营升级「携带位」。" % carry_max())
		return false
	var i := clampi(index, 0, carry.size())
	carry.insert(i, id)
	_after_carry_change()
	return true


func carry_toggle(id: String) -> bool:
	if in_carry(id):
		carry_remove(id)
		return false
	return carry_add(id)


func carry_auto() -> void:
	if in_battle: return
	# 按有效战力从高到低自动填满携带位（新手上手用）
	carry.clear()
	var pool := []
	for id in owned.keys():
		if is_carryable(str(id)) and int(owned.get(id, 0)) > 0:
			pool.append(str(id))
	pool.sort_custom(func(a: String, b: String) -> bool:
		return hero_card_power(a) > hero_card_power(b))
	for id in pool:
		if carry.size() >= carry_max():
			break
		carry.append(str(id))
	_after_carry_change()


func _auto_carry() -> void:
	carry_auto()


func _after_carry_change() -> void:
	save_game()
	shop_changed.emit()
	changed.emit()


# =====================================================================
# 武将升级（v0.9）—— 每个武将有独立等级，越练越强
# =====================================================================
func is_hero(id: String) -> bool:
	return str(GameData.card(id).get("type", "")) == "武将"


func hero_level(id: String) -> int:
	return clampi(int(hero_lv.get(id, 1)), 1, 20) if is_hero(id) else 0

func hero_lv_max(id: String) -> int:
	return 20 if is_hero(id) else 0

func hero_lv_maxed(id: String) -> bool:
	return hero_level(id) >= hero_lv_max(id)


func hero_lv_cost(_id: String) -> int:
	return 0


func hero_lv_mult(id: String) -> float:
	return 1.0 + 0.08 * max(0, hero_level(id) - 1)

func hero_card_power(id: String) -> float:
	return float(GameData.card(id).get("power", 0.0)) * hero_lv_mult(id) * [1.0, 1.35, 1.8][hero_quality(id)]

func buy_hero_lv(_id: String) -> bool:
	return false # 武将只通过出战经验升级。

func equip_slots() -> int:
	## 已解锁的部位数（0~5），全局共享的解锁进度。
	return int(upgrade_value("equip"))


func unlocked_slots() -> Array:
	## 已解锁的部位名列表（按 EQUIP_SLOTS 顺序取前 N 个）。
	var out := []
	for i in range(mini(equip_slots(), EQUIP_SLOTS.size())):
		out.append(EQUIP_SLOTS[i])
	return out


func is_slot_unlocked(subtype: String) -> bool:
	var idx := EQUIP_SLOTS.find(subtype)
	return idx >= 0 and idx < equip_slots()


func equip_slot_of(id: String) -> String:
	return str(GameData.card(id).get("subtype", ""))


func has_equip_nest(id: String) -> bool:
	## 谁能有装备巢：**只有武将**（用户明确：士兵没有装备巢）。
	return is_hero(id)


func hero_equip_of(who: String) -> Array:
	## 某个武将身上的装备 id 列表（返回**副本**，外部改不动内部数组）。
	var out: Array = []
	for id in hero_equip.get(who, []):
		out.append(str(id))
	return out


func hero_equip_free(who: String) -> int:
	## 该将还空几格。已装数天然 <= 解锁数（同部位会互相换掉），所以直接相减即可。
	return equip_slots() - hero_equip_of(who).size()


func equip_owner(id: String) -> String:
	## 这件装备挂在谁身上（没有则 ""）。一件装备同一时间只能挂一个武将。
	for who in hero_equip.keys():
		if (hero_equip[who] as Array).has(id):
			return str(who)
	return ""


func in_equipped(id: String) -> bool:
	## 这件装备是否挂在**任何**武将身上。
	return equip_owner(id) != ""


func hero_equipped_in_slot(who: String, subtype: String) -> String:
	## 该将的该部位当前装的是哪件（没有则 ""）。
	for id in hero_equip.get(who, []):
		if equip_slot_of(str(id)) == subtype:
			return str(id)
	return ""


func is_equippable(id: String) -> bool:
	## 是装备卡，且它的部位已解锁。
	var c := GameData.card(id)
	if c.is_empty() or str(c.get("type", "")) != "装备":
		return false
	return is_slot_unlocked(str(c.get("subtype", "")))


func equip_to(who: String, id: String) -> bool:
	if in_battle: return false
	## 把装备 id 挂到武将 who 身上。
	if not is_hero(who):
		log_msg("「%s」没有装备巢 —— 只有武将能带装备。" % GameData.card_name(who))
		return false
	var c := GameData.card(id)
	if c.is_empty() or str(c.get("type", "")) != "装备":
		return false
	var sub := str(c.get("subtype", ""))
	if not is_slot_unlocked(sub):
		log_msg("「%s」部位尚未解锁 —— 去大本营点亮技能树「装备槽」。" % sub)
		return false
	if int(owned.get(id, 0)) <= 0:
		log_msg("没有这张装备。")
		return false
	if int(owned.get(who, 0)) <= 0:
		log_msg("「%s」不在手上。" % GameData.card_name(who))
		return false
	# 一件装备只能挂一个武将：先把它从原来那位身上摘下来
	var prev := equip_owner(id)
	if prev != "" and prev != who:
		(hero_equip[prev] as Array).erase(id)
	# 同部位只留一件：换掉旧的
	var old := hero_equipped_in_slot(who, sub)
	if old != "" and old != id:
		(hero_equip[who] as Array).erase(old)
	var mine: Array = hero_equip.get(who, [])
	if mine.has(id):
		return false
	mine.append(id)
	hero_equip[who] = mine
	var from := "" if prev == "" or prev == who else "（从「%s」转来）" % GameData.card_name(prev)
	log_msg("「%s」装上【%s】%s%s（%s）" % [
		GameData.card_name(who), sub, GameData.card_name(id), from, str(c.get("effect", ""))])
	save_game()
	shop_changed.emit()
	changed.emit()
	return true


func unequip_from(who: String, id: String) -> bool:
	if in_battle: return false
	## 从武将 who 身上摘下装备 id。
	var mine: Array = hero_equip.get(who, [])
	if not mine.has(id):
		return false
	mine.erase(id)
	hero_equip[who] = mine
	log_msg("「%s」卸下 %s。" % [GameData.card_name(who), GameData.card_name(id)])
	save_game()
	shop_changed.emit()
	changed.emit()
	return true


func unequip_card(id: String) -> bool:
	## 通用卸下：不关心挂在哪，直接找主人摘掉（界面按"装备"维度操作时用）。
	var who := equip_owner(id)
	if who == "":
		return false
	return unequip_from(who, id)


func equip_toggle_for(who: String, id: String) -> bool:
	## 某将身上的某件装备「点了就切」。返回**切换后的状态**（true = 现在装上了）。
	if equip_owner(id) == who:
		unequip_from(who, id)
		return false
	return equip_to(who, id)


# =====================================================================
# 兵位（v1.1）—— 技能树「武将带兵」点亮后，士卒可以挂到武将麾下
#   用户：「士兵没有装备巢，但是可以当武将出战，**未来点亮技能树里的武将带兵能力
#          可以直接把兵给武将装备**」。
#   设计：兵位 = 该武将**额外**的、只收「士卒」的格子；挂进去的士卒**不再占携带位**，
#        战力照样全额计入卡组（= 变相扩容携带位，但要先花金币点亮技能）。
#        士兵仍然可以单独上阵（当武将使），两条路都通。
# =====================================================================
func troop_slots() -> int:
	## 每个武将能带几个兵（技能树「武将带兵」0→3）。
	return int(upgrade_value("troops"))


func troop_cap(who: String) -> int:
	if not is_hero(who):
		return 0
	return troop_slots()


func is_troop(id: String) -> bool:
	return str(GameData.card(id).get("type", "")) == "士兵"


func hero_troops_of(who: String) -> Array:
	## 该将麾下的士卒 id 列表（**副本**）。
	var out: Array = []
	for id in hero_troops.get(who, []):
		out.append(str(id))
	return out


func troop_owner(id: String) -> String:
	## 这个士卒在谁麾下（没有则 ""）。一个兵同时只听一个将。
	for who in hero_troops.keys():
		if (hero_troops[who] as Array).has(id):
			return str(who)
	return ""


func in_troops(id: String) -> bool:
	return troop_owner(id) != ""


func troop_put(who: String, id: String) -> bool:
	if in_battle: return false
	## 把士卒挂到武将 who 麾下。
	if not is_hero(who):
		log_msg("「%s」不是武将，带不了兵。" % GameData.card_name(who))
		return false
	if troop_slots() <= 0:
		log_msg("还不会带兵 —— 去大本营点亮技能树「武将带兵」。")
		return false
	if not is_troop(id):
		log_msg("兵位上只能放士卒（「%s」不是士卒）。" % GameData.card_name(id))
		return false
	if int(owned.get(id, 0)) <= 0:
		log_msg("没有这个士卒。")
		return false
	var prev := troop_owner(id)
	if prev == who:
		return false
	if prev != "":
		log_msg("「%s」已在「%s」麾下 —— 先从那卸下。" % [GameData.card_name(id), GameData.card_name(prev)])
		return false
	var mine: Array = hero_troops.get(who, [])
	if mine.size() >= troop_cap(who):
		log_msg("「%s」的兵位满了（%d 个）—— 升级技能树「武将带兵」。" % [GameData.card_name(who), troop_cap(who)])
		return false
	mine.append(id)
	hero_troops[who] = mine
	# 与携带位互斥：挂进兵位就不再占携带位（否则同一张牌算两遍战力）
	if in_carry(id):
		carry.erase(id)
	log_msg("「%s」麾下添了 %s（战力 %s，不占携带位）" % [
		GameData.card_name(who), GameData.card_name(id),
		fmt(float(GameData.card(id).get("power", 0.0)))])
	_after_carry_change()
	return true


func troop_remove(who: String, id: String) -> bool:
	if in_battle: return false
	var mine: Array = hero_troops.get(who, [])
	if not mine.has(id):
		return false
	mine.erase(id)
	hero_troops[who] = mine
	log_msg("「%s」麾下撤走 %s。" % [GameData.card_name(who), GameData.card_name(id)])
	_after_carry_change()
	return true


func troop_power() -> float:
	## 麾下士卒贡献的战力 —— **只算上阵的武将**（没上阵的将，它的装备和兵都不上桌）。
	var total := 0.0
	for who in carry:
		for tid in hero_troops.get(str(who), []):
			total += float(GameData.card(str(tid)).get("power", 0.0))
	return total


func _purge_attachments(id: String) -> void:
	## 某张卡被消耗光（owned 归零）后，把它身上的关联一起清掉 ——
	## 否则重开到同一 id 时会"继承"旧装备/旧兵，看起来像幽灵数据。
	if int(owned.get(id, 0)) > 0:
		return
	hero_equip.erase(id)
	hero_troops.erase(id)
	for who in hero_equip.keys():
		var a: Array = hero_equip[who]
		a.erase(id)
		hero_equip[who] = a
	for who in hero_troops.keys():
		var t: Array = hero_troops[who]
		t.erase(id)
		hero_troops[who] = t


# =====================================================================
# 卡组战力（只算上阵的）
# =====================================================================
func hero_power() -> float:
	# 主角卡不读 cards.json 的 power —— 那会和公式里的基础拍力 +1.0 重复计算，
	# 结果就是"开局 6 点耐力两巴掌清掉第一桌"。主角的成长交给「拍力」升级树。
	return HERO_BASE_POWER


func carry_power() -> float:
	var total := 0.0
	for id in carry:
		total += hero_card_power(id)      # 卡面战力 × 武将等级倍率
	# v1.1：挂在上阵武将麾下的士卒，战力也全额计入（并且它们不占携带位）
	return total + troop_power()


func base_power() -> float:
	return hero_power() + carry_power()


func equip_bonus() -> float:
	## 装备提供的「拍力%」（含军械坊放大），供界面显示。
	return float(equip_mods()["power_pct"]) / 100.0


func power_multiplier() -> float:
	var mods := active_mods()
	var m := 1.0
	# 升级树「拍力」：v1.0 起是复利（×1.15/级，无上限）→ 走乘区，不能当百分点加。
	# 保留加法分支是为了万一回滚 kind="add" 时不会静默算错。
	var pu := up_def("power")
	if str(pu.get("kind", "add")) == "mult":
		m *= upgrade_value("power")
	else:
		m += upgrade_value("power") / 100.0
	if bond_tier("魏线") >= 1: m += 0.10
	if bond_tier("魏线") >= 2: m += 0.15
	m += float(bonus["combat_power_pct"]) / 100.0  # 功能建筑
	m += float(mods["power_pct"]) / 100.0          # 武将被动 + 装备（拍力%）
	m += float(mods["all_pct"]) / 100.0            # 全属性 +X%
	if float(mods["power_mult"]) > 0.0:
		m *= float(mods["power_mult"])             # 拍力 ×N（如关羽 ×2.5）
	return m


func deck_power() -> float:
	return base_power() * power_multiplier()


func click_damage() -> float:
	var d := 1.0 + deck_power()
	var mods := active_mods()
	d *= 1.0 + float(mods["click_pct"]) / 100.0    # 点击伤害 +X%
	return d


func slaps_needed(idx: int) -> int:
	# 按当前轻拍伤害估算：还差几下才能把这一桌清空
	var dmg := click_damage()
	if dmg <= 0.0:
		return 999
	return int(ceil(table_hp(idx) / dmg))


func combo_gain() -> int:
	var n := 1 + (3 if bond_tier("吴线") >= 1 else 0)
	n += int(active_mods()["combo_gain"])
	return n


func combo_threshold() -> int:
	## 终结技（拍案）触发线；某些武将/装备会把线压低（更好触发）。
	var mods := active_mods()
	var set := int(mods["threshold_set"])
	if set > 0:
		return maxi(2, set)
	return maxi(2, COMBO_THRESHOLD + int(mods["threshold"]))


func combo_shield() -> bool:
	return float(active_mods()["combo_shield"]) > 0.0


func paian_mult() -> float:
	var m := 7.0 if bond_tier("吴线") >= 2 else 5.0
	var mods := active_mods()
	m *= 1.0 + float(mods["paian_pct"]) / 100.0
	if float(mods["paian_mult"]) > 0.0:
		m *= float(mods["paian_mult"])
	return m


func crit_chance() -> float:
	var p := upgrade_value("crit") / 100.0
	if bond_tier("蜀线") >= 1:
		p += 0.10
	p += float(active_mods()["crit_pct"]) / 100.0
	return minf(p, 0.9)


func crit_mult() -> float:
	return 4.0 if bond_tier("蜀线") >= 2 else 2.0


func fortune_mult() -> float:
	return 1.0 + upgrade_value("fortune") / 100.0 + float(active_mods()["gold_pct"]) / 100.0


func stamina_max_value() -> int:
	return int(ceil(round_duration_value()))


# =====================================================================
# 地图
# =====================================================================
func _is_cleared(idx: int) -> bool:
	return region_state.get(idx, "locked") == "cleared"


func is_unlocked(idx: int) -> bool:
	if idx == 1:
		return true
	if idx == 21:
		# 江陵是汇合点：需先克服夷陵 + 公安 + 泉陵
		return _is_cleared(9) and _is_cleared(12) and _is_cleared(20)
	var r := GameData.region(idx)
	for p in r.get("unlocked_by", []):
		if _is_cleared(int(p)):
			return true
	return false


func region_status(idx: int) -> String:
	if _is_cleared(idx):
		return "cleared"
	if is_unlocked(idx):
		return "available"
	return "locked"


func region_route(idx: int) -> String:
	return GameData.region(idx).get("route", "通用")


func _grant_affinity(idx: int) -> void:
	var rt := region_route(idx)
	if rt in ROUTES:
		affinity[rt] = int(affinity.get(rt, 0)) + 1


func _city_card_id(idx: int) -> String:
	var city_name: String = GameData.region(idx).get("city", "")
	for c in GameData.cards:
		if c.get("type", "") == "城池" and c.get("name", "") == city_name:
			return str(c.get("id", ""))
	return ""


# ---- 城池压后登场：先拍几桌纯拍卡，过一段才解锁"挂机那条线" ----
func total_field_regions() -> int:
	var n := 0
	for r in GameData.regions:
		if int(r["idx"]) != START_REGION:
			n += 1
	return n


func cleared_count() -> int:
	var n := 0
	for r in GameData.regions:
		var i := int(r["idx"])
		if i != START_REGION and _is_cleared(i):
			n += 1
	return n


func city_unlocked() -> bool:
	for region in GameData.regions:
		if table_progress(int(region["idx"])) > 0: return true
	return false

func city_unlock_text() -> String:
	return "已解锁 · 每征服一区开放1槽" if city_unlocked() else "征服任意一个分区后开放基建"

func _backfill_cities() -> Array:
	# 城池一旦解锁，把此前已克服区域的城池卡补齐发放（幂等）
	var got := []
	if not city_unlocked():
		return got
	for r in GameData.regions:
		var i := int(r["idx"])
		if table_progress(i) > 0: _ensure_building_arrays(i)
		# v1.0：新野也会被克服，它的城池卡 C01 同样要补发（否则一旦错过就永久拿不到）。
		if not _is_cleared(i):
			continue
		var cid := _city_card_id(i)
		if cid != "" and int(owned.get(cid, 0)) <= 0:
			owned[cid] = 1
			got.append(str(r.get("name", "?")))
	return got


func _grant_city(idx: int) -> void:
	if not city_unlocked():
		return
	var cid := _city_card_id(idx)
	if cid == "":
		return
	if int(owned.get(cid, 0)) <= 0:
		owned[cid] = 1


# =====================================================================
# 铺桌：把卡牌摆到桌面上（归一化坐标 + 旋转角），等玩家来拍
# =====================================================================
func ensure_table() -> bool:
	# 桌上没有牌时，自动把第一个"已解锁且未克服"的区域铺上来
	if in_battle and battle.size() > 0:
		return true
	var best := -1
	for r in GameData.regions:
		var i := int(r["idx"])
		# v1.0：不再跳过新野 —— 它现在是第一关，开局就该把它的桌铺上来。
		if is_unlocked(i) and not _is_cleared(i):
			best = i
			break
	if best < 0:
		return false
	return start_battle(best)


func table_all_cleared() -> bool:
	return in_battle and battle.size() > 0 and _all_cleared()


# =====================================================================
# 战斗
# =====================================================================
func start_battle(idx: int) -> bool:
	if not is_unlocked(idx) or _is_cleared(idx) or GameData.region(idx).is_empty() or next_zone(idx) < 0: return false
	if in_battle: settle_run("returned")
	stop_automation(false)
	battle_mode = "challenge"
	battle_table = next_zone(idx)
	return _start_table(idx)


func start_event_visit(idx: int) -> bool:
	if not is_unlocked(idx) or not _is_cleared(idx): return false
	if in_battle: settle_run("returned")
	battle_mode = "visit"
	battle_table = 0
	return _start_table(idx)


func map_event_entries(region: int = 0) -> Array[Dictionary]:
	var idx := battle_region if region <= 0 else region
	if not in_battle or idx <= 0 or idx != battle_region: return []
	if MapEvents.ensure_region(self, idx): save_game()
	return MapEvents.entries(self, idx)


func consume_event_slap() -> bool:
	if not in_battle or not round_active or narrative_paused or slap_cooldown_left > 0.000001: return false
	slap_cooldown_left = slap_interval()
	round_slaps += 1
	return true


func interact_map_event(id: String, point: Vector2) -> Dictionary:
	if not in_battle or not round_active or narrative_paused: return {"handled": false}
	MapEvents.ensure_region(self, battle_region)
	var event: Dictionary = map_events.get(id, {})
	if int(event.get("region", 0)) != battle_region: return {"handled": false}
	var before := gold
	var result := MapEvents.interact(self, id, point)
	if bool(result.get("changed", false)):
		run_gold += maxf(0.0, gold - before)
		save_game()
		shop_changed.emit()
		events_changed.emit()
	changed.emit()
	return result


func _refresh_enemies() -> void:
	battle = []
	_pile_stages_done = {}
	_pile_stage_damage = {}
	if battle_mode == "visit":
		battle_gen += 1
		return
	var raw: Array = GameData.enemies_by_region.get(battle_region, [])
	# 每段是固定地理分区；只铺仍未征服的区，顺序互不依赖。
	for step in range(zone_count(battle_region)):
		if zone_cleared(battle_region, step): continue
		var health := _table_health_values(battle_region, step)
		_pile_stage_damage[step] = 0.0
		for i in range(health.size()):
			var e: Dictionary = raw[i]
			var hp := float(health[i])
			battle.append({"card_id": e["card_id"], "hp": hp, "hp_max": hp, "stage": step,
				"boss": bool(e["boss"]) and step == table_count(battle_region) - 1,
				"nx": 0.5, "ny": 0.5, "rot": 0.0,
				"thunder": 0, "mark_remaining": 0.0,
				"burn_remaining": 0.0, "burn_dps": 0.0, "burn_tick": 0.0,
				"kill_rewarded": false})
	_layout_table()
	battle_gen += 1

func _table_health_values(idx: int, step: int) -> Array:
	var raw: Array = GameData.enemies_by_region.get(idx, [])
	var take := raw.size()
	if idx == 1: take = mini([3, 3, 4, 5, 6][clampi(step, 0, 4)], take)
	var total := 0.0
	for i in range(take): total += float(raw[i]["hp"])
	var hp_total := table_hp(idx, step)
	var health: Array = []
	for i in range(take):
		health.append([3.0, 4.0, 7.0][i] if idx == 1 and step == 0 else hp_total * float(raw[i]["hp"]) / maxf(1.0, total))
	return health


func _layout_table() -> void:
	var layout = preload("res://scripts/city_layout.gd")
	for zone in range(zone_count(battle_region)):
		var indices: Array[int] = []
		for i in range(battle.size()):
			if int(battle[i]["stage"]) == zone: indices.append(i)
		var positions: Array[Dictionary] = layout.zone_positions(indices.size(), battle_region, zone, zone_count(battle_region))
		for n in range(indices.size()):
			battle[indices[n]]["nx"] = positions[n].nx
			battle[indices[n]]["ny"] = positions[n].ny
			battle[indices[n]]["rot"] = positions[n].rot


func attack(i: int, heavy: bool = false, automatic: bool = false) -> bool:
	## 一次圆形轻拍的多个目标共享冷却；旧重拍接口保留供构筑兼容。
	if automatic or not in_battle or not round_active or narrative_paused or round_seconds_left <= 0.0 or i < 0 or i >= battle.size():
		return false
	if battle[i]["hp"] <= 0.0:
		return false
	var batch := _slap_batch_active and not automatic
	if batch and (_slap_batch_gen != battle_gen or _slap_batch_hits.has(i)):
		return false
	if not (batch and _slap_batch_started):
		if slap_cooldown_left > 0.000001: return false
		slap_cooldown_left = slap_interval(heavy)
		round_slaps += 1
		if batch: _slap_batch_started = true
	if batch: _slap_batch_hits[i] = true
	var gold_before := run_gold
	var kills_before := run_kills
	var action_gen := battle_gen

	var base := click_damage() * (auto_ratio() if automatic else 1.0)
	if not automatic: _auto_clock = 0.0
	var dmg := base
	if heavy:
		dmg *= HEAVY_MULT
	if float(battle[i].get("mark_remaining", 0.0)) > 0.0:
		dmg *= 1.2
	var tag := ""
	combo += combo_gain() * (2 if heavy else 1)
	if combo >= combo_threshold():
		# 「连击保护 / 不中断」：拍案后连击不清零，只扣掉触发线
		if combo_shield():
			combo = maxi(0, combo - combo_threshold())
		else:
			combo = 0
		dmg *= paian_mult()
		tag = "拍案！"
	elif randf() < crit_chance():
		dmg *= crit_mult()
		tag = "暴击！"

	build_events = []
	var chain := {}
	_manual_damage_context = true
	var lightning := 0.0
	if heavy and carry.has("G05") and _build_ready("G05"):
		var marks := mini(2, int(battle[i].get("thunder", 0)))
		if marks > 0:
			battle[i]["thunder"] = int(battle[i].get("thunder", 0)) - marks
			lightning = float(marks) * 1.5 * base
			build_ready_at["G05"] = build_clock + 6.0
			chain["G05"] = true
	var actual := _build_damage(i, dmg, chain, base, "重拍" if heavy else "轻拍")
	if lightning > 0.0:
		actual += _build_damage(i, lightning, chain, base, "雷爆")
		if tag == "":
			tag = "雷爆！"
	_after_build_base(i, heavy, base)
	_manual_damage_context = false
	build_effect_seq += 1
	last_slap = {"index": i, "heavy": heavy, "damage": actual, "tag": tag,
		"effects": build_events.duplicate(true), "source": "base", "effect_seq": build_effect_seq,
		"gold_gain": run_gold - gold_before, "battle_gen": action_gen, "automatic": automatic}
	if tag != "":
		log_msg("%s%s　造成 %.0f 伤害" % ["重拍·" if heavy else "轻拍·", tag, dmg])

	if run_kills > kills_before: _award_slap_growth()
	_finish_build_action()
	return true


func _reset_build_traits() -> void:
	build_clock = 0.0
	build_counts = {}
	build_ready_at = {}
	build_events = []


func apply_slap_displacement(center: Vector2, hit_indices: Array) -> Array:
	# 主界面在整掌命中完成、end_slap_batch前调用；多目标不能重复拉动。
	var moved: Array = []
	if not in_battle or not round_active or not _slap_batch_active or not _slap_batch_started:
		return moved
	if bool(last_slap.get("automatic", false)) or int(build_counts.get("gather_slap", -1)) == round_slaps:
		return moved
	build_counts["gather_slap"] = round_slaps
	var distance := 0.0
	for who in carry:
		distance += float(hero_trait_params(str(who)).get("gather_distance", 0.0))
	if distance <= 0.0: return moved
	var anchor := -1
	var nearest := INF
	for raw_index in hit_indices:
		var index := int(raw_index)
		if not _slap_batch_hits.has(index) or index < 0 or index >= battle.size(): continue
		var gap := get_enemy_world_center(index).distance_squared_to(center)
		if gap < nearest:
			anchor = index
			nearest = gap
	if anchor < 0: return moved
	var stage := int(battle[anchor].get("stage", 0))
	if zone_cleared(battle_region, stage): return moved
	var bounds := zone_rect(battle_region, stage).grow(-80.0)
	var target := center.clamp(bounds.position, bounds.end)
	var area := battle_world_size() - Vector2(500, 500)
	for index in range(battle.size()):
		if not _build_alive(index) or int(battle[index].get("stage", 0)) != stage: continue
		var before := get_enemy_world_center(index)
		if before.distance_to(center) > CardTraits.GATHER_RADIUS: continue
		var after := before.move_toward(target, distance).clamp(bounds.position, bounds.end)
		if before.is_equal_approx(after): continue
		battle[index]["nx"] = (after.x - 250.0) / area.x
		battle[index]["ny"] = (after.y - 250.0) / area.y
		moved.append({"index": index, "from": before, "to": after, "kind": "聚拢"})
	if not moved.is_empty():
		last_slap["displacements"] = moved
		changed.emit()
	return moved


func _build_ready(id: String) -> bool:
	return build_clock >= float(build_ready_at.get(id, 0.0))


func _build_alive(i: int) -> bool:
	return i >= 0 and i < battle.size() and float(battle[i]["hp"]) > 0.0


func _build_thickest() -> int:
	var pick := -1
	var hp := -1.0
	for i in range(battle.size()):
		if float(battle[i]["hp"]) > hp and _build_alive(i):
			pick = i
			hp = float(battle[i]["hp"])
	return pick


func _build_weakest_normal(exclude: int = -1) -> int:
	var pick := -1
	var hp := INF
	for i in range(battle.size()):
		if i == exclude or not _build_alive(i) or bool(battle[i].get("boss", false)):
			continue
		if float(battle[i]["hp"]) < hp:
			pick = i
			hp = float(battle[i]["hp"])
	return pick


func _build_damage(i: int, damage: float, chain: Dictionary, base: float, kind: String) -> float:
	if not _build_alive(i) or damage <= 0.0:
		return 0.0
	var actual := minf(float(battle[i]["hp"]), damage)
	battle[i]["hp"] = maxf(0.0, float(battle[i]["hp"]) - actual)
	run_damage += actual
	table_damage += actual
	var stage := int(battle[i].get("stage", battle_table))
	_pile_stage_damage[stage] = float(_pile_stage_damage.get(stage, 0.0)) + actual
	build_events.append({"index": i, "damage": actual, "tag": kind, "kind": kind})
	if not _build_alive(i) and not bool(battle[i].get("kill_rewarded", false)):
		battle[i]["kill_rewarded"] = true
		_on_enemy_killed(i)
		if float(battle[i].get("mark_remaining", 0.0)) > 0.0 \
			and carry.has("G24") and _build_ready("G24") and not chain.has("G24"):
			var next := _build_weakest_normal(i)
			if next >= 0:
				chain["G24"] = true
				build_ready_at["G24"] = build_clock + 6.0
				_build_damage(next, base, chain, base, "白羽追击")
	return actual


func _after_build_base(i: int, heavy: bool, base: float) -> void:
	# 只有基础拍击进入计数。派生伤害、燃烧与追击不触发这些发动机。
	if carry.has("G30") and heavy and _build_alive(i) and _build_ready("G30"):
		battle[i]["burn_remaining"] = 6.0
		battle[i]["burn_dps"] = base * 0.3
		battle[i]["burn_tick"] = 0.0
		battle[i]["burn_base"] = base
		build_ready_at["G30"] = build_clock + 4.0
		build_events.append({"index": i, "damage": 0.0, "tag": "点火", "kind": "点火"})
	if carry.has("G04"):
		build_counts["G04"] = int(build_counts.get("G04", 0)) + 1
		if int(build_counts["G04"]) % 3 == 0:
			var target := _build_thickest()
			if target >= 0:
				battle[target]["thunder"] = mini(3, int(battle[target].get("thunder", 0)) + 1)
				build_events.append({"index": target, "damage": 0.0, "tag": "雷印", "kind": "雷印"})
	if carry.has("G20") and not heavy:
		build_counts["G20"] = int(build_counts.get("G20", 0)) + 1
		if int(build_counts["G20"]) % 3 == 0:
			var target := _build_thickest()
			if target >= 0:
				battle[target]["mark_remaining"] = 6.0
				build_events.append({"index": target, "damage": 0.0, "tag": "标记", "kind": "标记"})
	if carry.has("G40"):
		build_counts["G40"] = int(build_counts.get("G40", 0)) + 1
		if int(build_counts["G40"]) % 4 == 0:
			_build_spread_fire()


func _build_spread_fire() -> void:
	var source := -1
	var remaining := 0.0
	for i in range(battle.size()):
		if _build_alive(i) and float(battle[i].get("burn_remaining", 0.0)) > remaining:
			source = i
			remaining = float(battle[i]["burn_remaining"])
	if source < 0:
		return
	var target := -1
	var hp := -1.0
	for i in range(battle.size()):
		if _build_alive(i) and float(battle[i].get("burn_remaining", 0.0)) <= 0.0 \
			and float(battle[i]["hp"]) > hp:
			target = i
			hp = float(battle[i]["hp"])
	if target < 0:
		return
	for field in ["burn_remaining", "burn_dps", "burn_tick", "burn_base"]:
		battle[target][field] = battle[source].get(field, 0.0)
	build_events.append({"index": target, "damage": 0.0, "tag": "借风", "kind": "借风"})


func _tick_build_effects(delta: float, elapsed_slice: bool = false) -> void:
	if not in_battle or not round_active or narrative_paused or (round_seconds_left <= 0.0 and not elapsed_slice) or delta <= 0.0:
		return
	var gold_before := run_gold
	var action_gen := battle_gen
	build_clock += delta
	build_events = []
	var status_changed := false
	var chain := {}
	for i in range(battle.size()):
		if not _build_alive(i):
			continue
		var mark := float(battle[i].get("mark_remaining", 0.0))
		if mark > 0.0:
			battle[i]["mark_remaining"] = maxf(0.0, mark - delta)
			status_changed = status_changed or mark <= delta
		var burn := float(battle[i].get("burn_remaining", 0.0))
		if burn <= 0.0:
			continue
		var elapsed := minf(delta, burn)
		battle[i]["burn_remaining"] = maxf(0.0, burn - elapsed)
		var accumulator := float(battle[i].get("burn_tick", 0.0)) + elapsed
		var ticks := int(floor(accumulator + 0.000001))
		battle[i]["burn_tick"] = accumulator - float(ticks)
		status_changed = status_changed or burn <= delta
		if ticks > 0:
			_build_damage(i, float(ticks) * float(battle[i].get("burn_dps", 0.0)), chain,
				float(battle[i].get("burn_base", click_damage())), "燃烧")
	if not build_events.is_empty():
		var event: Dictionary = build_events[0]
		build_effect_seq += 1
		last_slap = {"index": int(event["index"]), "heavy": false, "damage": float(event["damage"]),
			"tag": "燃烧", "source": "dot", "effects": build_events.duplicate(true), "effect_seq": build_effect_seq,
			"gold_gain": run_gold - gold_before, "battle_gen": action_gen}
		_finish_build_action()
	elif status_changed:
		changed.emit()

func _next_build_event_time() -> float:
	# 元素伤害及标记到期也作为时间边界，避免大delta使自动拍的目标选择滞后。
	var next := INF
	for i in range(battle.size()):
		if not _build_alive(i): continue
		var mark := float(battle[i].get("mark_remaining", 0.0))
		if mark > 0.0: next = minf(next, mark)
		var burn := float(battle[i].get("burn_remaining", 0.0))
		if burn > 0.0:
			var tick := float(battle[i].get("burn_tick", 0.0))
			next = minf(next, minf(burn, maxf(0.000001, 1.0 - tick)))
	return next


func _finish_build_action() -> void:
	if not in_battle:
		return
	if not _slap_batch_active: _update_pile_checkpoints()
	if _all_cleared():
		if _slap_batch_active:
			_pending_table_clear = true
			changed.emit()
		else:
			_clear_region()
	else:
		changed.emit()


func _all_cleared() -> bool:
	for e in battle:
		if e["hp"] > 0.0:
			return false
	return true


func _on_enemy_killed(i: int) -> void:
	run_kills += 1
	if MapEvents.on_enemy_killed(self, str(battle[i]["card_id"])): events_changed.emit()
	if not _manual_damage_context: return
	var reward := float(battle[i]["hp_max"]) * (Progression.DAMAGE_PAY + Progression.KILL_PAY) * fortune_mult()
	gold += reward
	run_gold += reward
	if not first_flip_reward:
		first_flip_reward = true
		gold += 8.0
		run_gold += 8.0


func _stage_cleared(step: int) -> bool:
	var found := false
	for e in battle:
		if int(e.get("stage", battle_table)) != step: continue
		found = true
		if float(e["hp"]) > 0.0: return false
	return found


func _update_pile_checkpoints() -> void:
	if not in_battle or battle.is_empty(): return
	var idx := battle_region
	var changed_progress := false
	# 任一区独立永久征服；不要求相邻编号先完成，也不再重铺已征服区。
	for step in _pile_stage_damage:
		if zone_cleared(idx, int(step)) or _pile_stages_done.has(step) or not _stage_cleared(int(step)): continue
		_pile_stages_done[step] = true
		var zones: Array = cleared_zones.get(idx, [])
		zones.append(int(step))
		zones.sort()
		cleared_zones[idx] = zones
		table_wins[idx] = zones.size()
		changed_progress = true
		round_tables_flipped += 1
		_grant_table_reward(idx, int(step))
	_update_table_best()
	if changed_progress and table_progress(idx) == zone_count(idx) and not _is_cleared(idx):
		region_state[idx] = "cleared"
		round_first_clears.append(idx)
		_grant_affinity(idx)
		for e in GameData.enemies_by_region.get(idx, []):
			var c := GameData.card(str(e["card_id"]))
			if str(c.get("type", "")) == "武将" and bool(c.get("capturable", false)):
				if not captured.has(e["card_id"]): captured.append(e["card_id"])
		_backfill_cities()
	if changed_progress:
		_recompute_bonus()
		save_game()
		map_changed.emit()
		shop_changed.emit()


func _clear_region() -> void:
	if not in_battle or not round_active or battle.is_empty() or not _all_cleared(): return
	_update_pile_checkpoints()
	settle_run("city_cleared")


func settle_run(reason: String = "returned") -> void:
	if not in_battle: return
	if MapEvents.finish_round(self): events_changed.emit()
	# 到期/主动回营也兑现已拍翻的当前桌，不能因鼠标尚未抬起丢掉完成记号。
	end_slap_batch()
	_update_table_best()
	if round_seconds_elapsed > 0.0 or run_damage > 0.0:
		runs += 1
		if battle_mode == "practice": practice_runs += 1
	in_battle = false
	round_active = false
	round_seconds_left = 0.0
	slap_cooldown_left = 0.0
	stamina = 0
	end_slap_batch()
	end_reason = "settled"
	_reset_build_traits()
	_record_outcome("settled")
	last_outcome["reason"] = reason
	battle = []
	battle_gen += 1
	combo = 0
	last_settle = "%s · %s　%.1f秒拍%d次 · 翻%d张 / 清%d段 · 本轮获得%s金币。" % [
		GameData.region(battle_region).get("name", ""), "本轮时间到" if reason == "time_up" else "本轮回营",
		round_seconds_elapsed, round_slaps, run_kills, round_tables_flipped, fmt(run_gold)]
	last_battle_report = last_settle
	_finish_automation_run()
	log_msg(last_settle)
	save_game()
	map_changed.emit()
	shop_changed.emit()
	changed.emit()


func _record_outcome(result: String) -> void:
	last_outcome = {"region": battle_region, "result": result, "gold": run_gold,
		"kills": run_kills, "damage": run_damage, "table": battle_table + 1, "tables": table_count(battle_region),
		"mode": battle_mode, "hp": pile_max_health(), "best": table_best_value(battle_region, battle_table),
		"pile_cards": pile_card_count(), "pile_remaining": pile_remaining(),
		"city_clear": battle_region in round_first_clears, "first_clears": round_first_clears.duplicate(),
		"seconds": round_seconds_elapsed, "duration": round_duration, "slaps": round_slaps,
		"tables_flipped": round_tables_flipped, "gold_per_second": round_gold_per_second()}


func retreat() -> void:
	## 玩家主动回营：保留所有即时收入与成长。
	if in_battle:
		settle_run()


func leave_battle() -> void:
	if in_battle: settle_run("returned")


# =====================================================================
# 卡包（按区域/郡解锁）
# =====================================================================
func county_cleared(county: String) -> bool:
	for r in GameData.regions:
		if r.get("county", "") == county and _is_cleared(int(r["idx"])):
			return true
	return false


func pack_unlocked(i: int) -> bool:
	if i < 0 or i >= GameData.packs.size():
		return false
	var scope: String = GameData.packs[i].get("scope", "")
	var county := scope.split(" · ")[0]
	if county == "全境":
		return true
	if i == 1: return _is_cleared(5)
	return county_cleared(county)


func pack_price(i: int) -> int:
	if i < 0 or i >= GameData.packs.size(): return 0
	var p: Dictionary = GameData.packs[i]
	var off := clampf(float(bonus["pack_price_pct"]) + float(active_mods()["pack_pct"]), -50.0, 75.0)
	var price := Progression.STARTER_PACK_PRICE if i == 0 else int(p.get("price", 100))
	return maxi(1, int(round(float(price) * (1.0 - off / 100.0))))


func buy_pack(i: int) -> Array:
	if in_battle:
		log_msg("请先结束本轮，再到卡铺开包。")
		return []
	if i < 0 or i >= GameData.packs.size(): return []
	if not pack_unlocked(i):
		log_msg("「%s」未解锁：需先克服该郡的任一区域。" % GameData.packs[i].get("name", "?"))
		return []
	var price := pack_price(i)
	if gold < float(price):
		log_msg("金币不足（需要 %d，现有 %d）" % [price, int(gold)])
		return []
	gold -= float(price)
	var drawn := _draw_pack_cards(i, int(GameData.packs[i].get("cards", 5)))
	# 各包独立累计，每10包保证当前牌池至少一张三星牌。
	total_packs += 1
	if (int(pack_bought.get(GameData.packs[i].get("name", ""), 0)) + 1) % Progression.PACK_PITY_COUNT == 0:
		var hi := _draw_high_star(i, mini(Progression.PACK_PITY_STAR, progression_star_cap()))
		if hi != "":
			drawn[drawn.size() - 1] = hi
	for id in drawn:
		owned[id] = int(owned.get(id, 0)) + 1
	var nm: String = GameData.packs[i].get("name", "?")
	pack_bought[nm] = int(pack_bought.get(nm, 0)) + 1
	log_msg("开「%s」：%s" % [nm, _names(drawn)])
	_recompute_bonus()
	save_game()
	shop_changed.emit()
	changed.emit()
	return drawn


func _pack_pool(i: int) -> Array:
	var p: Dictionary = GameData.packs[i]
	var faction: String = p.get("faction", "全势力")
	var max_star := mini(int(p.get("max_star", 3)), progression_star_cap())
	var pool := []
	for c in GameData.cards:
		var t: String = c.get("type", "")
		if not (t in ["士兵", "武将", "装备", "建筑"]):
			continue
		var st := int(c.get("star", 0))
		if st < 1 or st > max_star:
			continue
		var f: String = c.get("faction", "")
		if not ("全势力" in faction) and f != faction and f != "通用":
			continue
		pool.append(c)
	if pool.is_empty():
		for c in GameData.cards:
			if c.get("type", "") == "士兵":
				pool.append(c)
	return pool


func _weighted_pick(pool: Array) -> Dictionary:
	var weights := []
	var sum := 0.0
	for c in pool:
		var w := float(max(1, 7 - int(c.get("star", 1))))
		weights.append(w)
		sum += w
	var roll := randf() * sum
	var acc := 0.0
	for k in range(pool.size()):
		acc += weights[k]
		if roll <= acc:
			var hit: Dictionary = pool[k]
			return hit
	var last: Dictionary = pool[pool.size() - 1]
	return last


func _draw_pack_cards(i: int, count: int) -> Array:
	var pool := _pack_pool(i)
	var out := []
	for k in range(count):
		out.append(str(_weighted_pick(pool).get("id", "S01")))
	return out


func _draw_high_star(i: int, min_star: int) -> String:
	var hi := []
	for c in _pack_pool(i):
		if int(c.get("star", 0)) >= min_star:
			hi.append(c)
	if hi.is_empty():
		return ""
	return str(_weighted_pick(hi).get("id", ""))


# =====================================================================
# 招降
# =====================================================================
func ransom_cost(card_id: String) -> int:
	var c := GameData.card(card_id)
	var star := int(c.get("star", 3))
	var base := float(RANSOM.get(star, 200))
	var disc: float = bonus["ransom_pct"]
	if affinity_tier(c.get("route", "")) >= 1:
		disc += 15.0
	return max(1, int(round(base * (1.0 - disc / 100.0))))


func ransom(card_id: String) -> bool:
	if in_battle: return false
	if not captured.has(card_id):
		return false
	var cost := ransom_cost(card_id)
	if gold < float(cost):
		log_msg("金币不足（招降需要 %d）" % cost)
		return false
	gold -= float(cost)
	captured.erase(card_id)
	owned[card_id] = int(owned.get(card_id, 0)) + 1
	log_msg("招降 %s（-%d 金币）" % [GameData.card_name(card_id), cost])
	_recompute_bonus()
	save_game()
	shop_changed.emit()
	changed.emit()
	return true


# =====================================================================
# 合成：3 张同星 + 金币 -> 随机高一星
# =====================================================================
func _star_candidates(star: int) -> Array:
	var out := []
	for id in owned.keys():
		var c := GameData.card(str(id))
		if c.get("type", "") not in ["士兵", "装备"] or int(c.get("star", 0)) != star: continue
		var held := 1 if in_carry(str(id)) or in_equipped(str(id)) or in_troops(str(id)) else 0
		for k in range(maxi(0, int(owned[id]) - held)): out.append(id)
	return out


func synth_cost(star: int) -> int:
	return int(SYNC_COST.get(star, 160))


func synthesize(star: int) -> String:
	if in_battle: return ""
	if star >= progression_star_cap():
		log_msg("当前进度最高开放★%d；武将请用同名合成。" % progression_star_cap())
		return ""
	if star >= 6:
		log_msg("已是最高星级，无法再合成。")
		return ""
	var cands := _star_candidates(star)
	if cands.size() < 3:
		log_msg("★%d 的卡不足 3 张。" % star)
		return ""
	var cost := int(SYNC_COST.get(star, 160))
	if gold < float(cost):
		log_msg("金币不足（合成需要 %d）" % cost)
		return ""
	gold -= float(cost)
	for k in range(3):
		var id: String = cands[k]
		owned[id] = int(owned[id]) - 1
		if int(owned[id]) <= 0:
			owned.erase(id)
			_purge_attachments(id)   # v1.1：卡被吃光 → 身上的装备/兵一并清掉（别留幽灵关联）
	var pool := []
	for c in GameData.cards:
		if int(c.get("star", 0)) == star + 1 and c.get("type", "") in ["士兵", "装备"]:
			pool.append(c)
	var got: String = str(_weighted_pick(pool).get("id", "S01"))
	owned[got] = int(owned.get(got, 0)) + 1
	log_msg("合成：3 张 ★%d -> %s" % [star, GameData.card_name(got)])
	_recompute_bonus()
	save_game()
	shop_changed.emit()
	changed.emit()
	return got


# =====================================================================
# 城建：城池 = 地基（槽位），建筑 = 产钱实体
# =====================================================================
func city_slots(idx: int) -> int:
	return table_progress(idx)

func city_buildings(idx: int) -> Array:
	return cities[idx].get("buildings", []) if cities.has(idx) else []

func city_used_slots(idx: int) -> int:
	var used := 0
	for id in city_buildings(idx):
		if str(id) != "":
			used += 1
	return used

func city_levels(idx: int) -> Array:
	return city_lv.get(idx, [])

func _building_at(idx: int, slot: int) -> String:
	var arr := city_buildings(idx)
	return str(arr[slot]) if slot >= 0 and slot < arr.size() else ""

func building_quality(idx: int, slot: int) -> int:
	var qualities: Array = city_quality.get(idx, [])
	return clampi(int(qualities[slot]), 0, 2) if slot >= 0 and slot < qualities.size() else 0

func building_stock(id: String, quality: int = 0) -> int:
	if GameData.building(id).is_empty() or quality < 0 or quality > 2:
		return 0
	var total := maxi(0, int(owned.get(id, 0)))
	var refined: Array = building_refined.get(id, [0, 0])
	var rare := mini(total, maxi(0, int(refined[1]))) if refined.size() > 1 else 0
	var fine := mini(total - rare, maxi(0, int(refined[0]))) if refined.size() > 0 else 0
	return [total - fine - rare, fine, rare][quality]

func _building_stock_change(id: String, quality: int, amount: int) -> void:
	var fine := building_stock(id, 1)
	var rare := building_stock(id, 2)
	owned[id] = maxi(0, int(owned.get(id, 0)) + amount)
	if quality == 1:
		fine += amount
	elif quality == 2:
		rare += amount
	if int(owned[id]) == 0:
		owned.erase(id)
		building_refined.erase(id)
	else:
		building_refined[id] = [maxi(0, fine), maxi(0, rare)]

func _ensure_building_arrays(idx: int) -> void:
	if not cities.has(idx):
		cities[idx] = {"buildings": []}
	if not city_quality.has(idx):
		city_quality[idx] = []
	if not city_lv.has(idx):
		city_lv[idx] = []
	for arr in [city_quality[idx], city_lv[idx]]:
		while arr.size() < city_buildings(idx).size():
			arr.append(0)
		while arr.size() > city_buildings(idx).size():
			arr.pop_back()

func city_combo(idx: int) -> Dictionary:
	var result := BuildingTraits.evaluate(city_buildings(idx), city_quality.get(idx, []))
	result["hourly"] = 0.0
	return result

func advance_buildings(_seconds: float, _efficiency: float = 1.0) -> float:
	return 0.0

func _building_loadout_changed(idx: int) -> void:
	# 改阵重开周期，不能把快到期的产出搬到另一城反复领取。
	building_clocks[idx] = 0.0
	building_ticks[idx] = 0
	_recompute_bonus()
	save_game()
	shop_changed.emit()
	changed.emit()

func building_lv(_idx: int, _slot: int) -> int:
	return 0 # 保留旧调用入口；建筑成长已经改为品相合成。

func building_lv_maxed(_idx: int, _slot: int) -> bool:
	return true

func building_lv_cost(_idx: int, _slot: int) -> int:
	return 0

func upgrade_building(_idx: int, _slot: int) -> bool:
	log_msg("建筑不再金币练级：仓库3张同名同品相合成，原技能和星级保留。")
	return false

func building_output(idx: int, slot: int) -> float:
	return float(GameData.building(_building_at(idx, slot)).get("prod", 0.0)) * BuildingTraits.quality_mult(building_quality(idx, slot))

func place_building(idx: int, building_id: String, quality: int = -1, target_slot: int = -1) -> bool:
	if in_battle or city_slots(idx) <= 0 or GameData.building(building_id).is_empty():
		return false
	if city_buildings(idx).has(building_id):
		log_msg("同城同名建筑只装配1张；重复卡可同名合成。")
		return false
	if quality == -1:
		for candidate in [2, 1, 0]:
			if building_stock(building_id, candidate) > 0:
				quality = candidate
				break
	if building_stock(building_id, quality) <= 0 or city_used_slots(idx) >= city_slots(idx):
		return false
	_ensure_building_arrays(idx)
	var buildings := city_buildings(idx)
	if target_slot < 0:
		target_slot = buildings.find("")
		if target_slot < 0: target_slot = buildings.size()
	if target_slot >= city_slots(idx) or (target_slot < buildings.size() and str(buildings[target_slot]) != ""):
		return false
	while buildings.size() <= target_slot:
		buildings.append("")
	_ensure_building_arrays(idx)
	buildings[target_slot] = building_id
	city_quality[idx][target_slot] = quality
	_building_stock_change(building_id, quality, -1)
	log_msg("装配%s·%s：%s" % [GameData.card_name(building_id), BuildingTraits.quality_name(quality), GameData.building(building_id).get("effect", "")])
	_building_loadout_changed(idx)
	return true

func remove_building(idx: int, slot_index: int) -> bool:
	if in_battle: return false
	var id := _building_at(idx, slot_index)
	if id == "":
		return false
	_ensure_building_arrays(idx)
	_building_stock_change(id, building_quality(idx, slot_index), 1)
	city_buildings(idx)[slot_index] = ""
	city_quality[idx][slot_index] = 0
	while not city_buildings(idx).is_empty() and str(city_buildings(idx).back()) == "":
		city_buildings(idx).pop_back()
	_ensure_building_arrays(idx)
	log_msg("卸下%s，原品相建筑卡已返还仓库。" % GameData.card_name(id))
	_building_loadout_changed(idx)
	return true

func move_building_slot(idx: int, from: int, to: int) -> bool:
	if in_battle: return false
	if _building_at(idx, from) == "" or to < 0 or to >= city_slots(idx):
		return false
	while city_buildings(idx).size() <= to:
		city_buildings(idx).append("")
	_ensure_building_arrays(idx)
	var id := _building_at(idx, from)
	var quality := building_quality(idx, from)
	city_buildings(idx)[from] = _building_at(idx, to)
	city_quality[idx][from] = building_quality(idx, to)
	city_buildings(idx)[to] = id
	city_quality[idx][to] = quality
	_building_loadout_changed(idx)
	return true

func gold_per_hour() -> float:
	return 0.0

func building_star_pool(star: int) -> Array:
	var out := []
	for id in owned.keys():
		if int(GameData.building(str(id)).get("star", 0)) == star:
			for i in range(int(owned[id])):
				out.append(str(id))
	return out

func synth_building_cost(_star: int) -> int:
	return 0

func fuse_building(id: String, quality: int = 0) -> String:
	if in_battle: return ""
	if quality < 0 or quality >= 2 or building_stock(id, quality) < 3:
		log_msg("合成需要仓库3张同名、同品相建筑；已装配卡受保护。")
		return ""
	_building_stock_change(id, quality, -3)
	_building_stock_change(id, quality + 1, 1)
	log_msg("同名合成：%s·%s×3 → %s×1（星级、触发条件不变）" % [GameData.card_name(id), BuildingTraits.quality_name(quality), BuildingTraits.quality_name(quality + 1)])
	save_game()
	shop_changed.emit()
	changed.emit()
	return id

func synth_buildings(star: int) -> String:
	# 旧调用兼容，但不再混合不同名字或随机升星。
	for building in GameData.buildings:
		if int(building["star"]) == star:
			for quality in [0, 1]:
				if building_stock(str(building["id"]), quality) >= 3:
					return fuse_building(str(building["id"]), quality)
	return ""

func _load_building_state(data: Dictionary) -> void:
	building_refined = {}
	for id in data.get("building_refined", {}):
		var value: Variant = data["building_refined"][id]
		if not GameData.building(str(id)).is_empty() and value is Array and value.size() == 2:
			building_refined[str(id)] = [maxi(0, int(value[0])), maxi(0, int(value[1]))]
	city_quality = {}
	building_clocks = {}
	building_ticks = {}
	for idx in cities.keys():
		var stored_quality: Variant = data.get("city_quality", {}).get(str(idx), [])
		city_quality[idx] = stored_quality.duplicate() if stored_quality is Array else []
		_ensure_building_arrays(int(idx))
		building_clocks[idx] = 0.0
		building_ticks[idx] = 0
		var seen := {}
		for slot in range(city_buildings(int(idx)).size()):
			var id := _building_at(int(idx), slot)
			city_quality[idx][slot] = clampi(int(city_quality[idx][slot]), 0, 2)
			city_lv[idx][slot] = 0
			if id == "": continue
			if GameData.building(id).is_empty():
				city_buildings(int(idx))[slot] = ""
				city_quality[idx][slot] = 0
			elif slot >= city_slots(int(idx)) or seen.has(id):
				_building_stock_change(id, building_quality(int(idx), slot), 1)
				city_buildings(int(idx))[slot] = ""
				city_quality[idx][slot] = 0
			else:
				seen[id] = true
		while not city_buildings(int(idx)).is_empty() and str(city_buildings(int(idx)).back()) == "":
			city_buildings(int(idx)).pop_back()
		_ensure_building_arrays(int(idx))

func offline_efficiency() -> float:
	return 0.0

func offline_cap_hours() -> float:
	return 0.0

func _reset_bonus() -> void:
	for k in bonus.keys():
		bonus[k] = 0.0


func _recompute_bonus() -> void:
	_reset_bonus()
	var strongest := {}
	for idx in cities.keys():
		for slot in range(city_buildings(int(idx)).size()):
			var building := GameData.building(_building_at(int(idx), slot))
			var effect: String = building.get("effect_type", "none")
			if bonus.has(effect):
				var amount := float(building.get("effect_value", 0.0)) * BuildingTraits.quality_mult(building_quality(int(idx), slot))
				if bool(building.get("unique", false)):
					var id := str(building["id"])
					strongest[id] = {"type": effect, "value": maxf(amount, float(strongest.get(id, {}).get("value", 0.0)))}
				else:
					bonus[effect] = float(bonus[effect]) + amount
	for entry in strongest.values():
		bonus[entry["type"]] += float(entry["value"])


# =====================================================================
# 存档
# =====================================================================
func save_game() -> void:
	if not SAVE_ENABLED:
		return                            # v1.0：开发期不落盘
	var data := {
		"gold": gold, "owned": owned, "captured": captured,
		"zone_system_version": 2, "cleared_zones": cleared_zones,
		"player_lv": player_lv, "player_xp": player_xp, "skill_points": skill_points,
		"hero_xp": hero_xp, "map_events": map_events, "items": items,
		"progression_version": Progression.VERSION, "table_wins": table_wins, "table_best": table_best,
		"first_flip_reward": first_flip_reward, "story_seen": story_seen,
		"hero_refined": hero_refined, "practice_runs": practice_runs, "practice_region": practice_region,
		"practice_table": practice_table, "automation_enabled": automation_enabled,
		"region_state": region_state, "cities": cities, "city_lv": city_lv,
		"building_system_version": 2, "building_refined": building_refined, "city_quality": city_quality,
		"building_clocks": building_clocks, "building_ticks": building_ticks,
		"affinity": affinity,
		"pack_bought": pack_bought, "total_packs": total_packs,
		"up": up, "carry": carry,
		"hero_equip": hero_equip, "hero_troops": hero_troops, "hero_lv": hero_lv,
		"runs": runs,
		"last_outcome": last_outcome, "battle_region": battle_region, "last_settle": last_settle,
		"last_save": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not SAVE_ENABLED:
		return false                      # v1.0：开发期不读档
	if not FileAccess.file_exists(save_path()):
		return false
	var f := FileAccess.open(save_path(), FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return false
	if int(d.get("zone_system_version", 0)) != 2:
		return false

	gold = float(d.get("gold", 0.0))
	player_lv = maxi(1, int(d.get("player_lv", 1)))
	player_xp = maxi(0, int(d.get("player_xp", 0)))
	skill_points = maxi(0, int(d.get("skill_points", 0)))
	hero_xp = d.get("hero_xp", {})
	map_events = d.get("map_events", {})
	items = d.get("items", {})
	offline_report = ""
	owned = d.get("owned", {})
	captured = d.get("captured", [])
	pack_bought = d.get("pack_bought", {})
	total_packs = int(d.get("total_packs", 0))
	runs = int(d.get("runs", 0))

	# 升级树：先铺默认 0 级，再覆盖存档里的值（老存档缺项也能兼容）
	up = {}
	for u in UPGRADES:
		up[str(u["id"])] = 0
	for k in d.get("up", {}).keys():
		if up.has(str(k)):
			up[str(k)] = int(d["up"][k])

	carry = []
	for id in d.get("carry", []):
		if int(owned.get(str(id), 0)) > 0 and is_carryable(str(id)):
			carry.append(str(id))

	# 装备巢（v1.1）：每将独立。逐条校验 —— 武将在手 / 装备在手 / 部位已解锁 /
	# 同部位不重复 / 一件装备只挂一个武将（先到先得）。
	# ⚠️ 老存档的全局 "equipped" 列表**不迁移**（v1.0 起 SAVE_ENABLED=false，本来就没有老档；
	#    真要恢复存档时再补一个「把全局装备分给第一个上阵武将」的迁移即可）。
	hero_equip = {}
	var used_equip := {}
	var raw_equip: Dictionary = d.get("hero_equip", {})
	for who in raw_equip.keys():
		var hid := str(who)
		if int(owned.get(hid, 0)) <= 0 or not is_hero(hid):
			continue
		var seen_slot := {}
		var keep: Array = []
		for id in raw_equip[who]:
			var eid := str(id)
			if int(owned.get(eid, 0)) <= 0 or used_equip.has(eid):
				continue
			var c := GameData.card(eid)
			if c.is_empty() or str(c.get("type", "")) != "装备":
				continue
			var sub := str(c.get("subtype", ""))
			if not is_slot_unlocked(sub) or seen_slot.has(sub):
				continue
			seen_slot[sub] = true
			used_equip[eid] = true
			keep.append(eid)
		if not keep.is_empty():
			hero_equip[hid] = keep

	# 兵位（v1.1）：士卒在手 / 该将有兵位 / 一个兵只在一个将麾下。
	hero_troops = {}
	var used_troop := {}
	var raw_troops: Dictionary = d.get("hero_troops", {})
	for who in raw_troops.keys():
		var hid2 := str(who)
		if int(owned.get(hid2, 0)) <= 0 or not is_hero(hid2):
			continue
		var keep2: Array = []
		for id in raw_troops[who]:
			var tid := str(id)
			if int(owned.get(tid, 0)) <= 0 or used_troop.has(tid) or not is_troop(tid):
				continue
			if keep2.size() >= troop_cap(hid2):
				break
			used_troop[tid] = true
			keep2.append(tid)
		if not keep2.is_empty():
			hero_troops[hid2] = keep2
	# 兵位与携带位互斥（存档里可能同时有）
	for who in hero_troops.keys():
		for tid in hero_troops[who]:
			if carry.has(str(tid)):
				carry.erase(str(tid))

	# 武将等级：只保留还有这张武将的
	hero_lv = {}
	for k in d.get("hero_lv", {}).keys():
		var hid := str(k)
		if int(owned.get(hid, 0)) > 0 and is_hero(hid):
			hero_lv[hid] = clampi(int(d["hero_lv"][k]), 1, hero_lv_max(hid))

	affinity = {}
	for rt in ROUTES:
		affinity[rt] = 0
	for k in d.get("affinity", {}).keys():
		affinity[k] = int(d["affinity"][k])

	region_state = {}
	for k in d.get("region_state", {}).keys():
		region_state[int(k)] = d["region_state"][k]

	cities = {}
	for k in d.get("cities", {}).keys():
		cities[int(k)] = d["cities"][k]

	# 建筑等级：与 buildings 对齐（老存档没有则全 0）
	city_lv = {}
	for k in d.get("city_lv", {}).keys():
		city_lv[int(k)] = d["city_lv"][k]
	for k in cities.keys():
		var n := (cities[k].get("buildings", []) as Array).size()
		if not city_lv.has(k):
			city_lv[k] = []
		var lv: Array = city_lv[k]
		while lv.size() < n:
			lv.append(0)
		while lv.size() > n:
			lv.remove_at(lv.size() - 1)

	_load_progression_state(d)
	_load_building_state(d)
	_backfill_cities()
	_recompute_bonus()

	# 局内血量不持久；有效战果停在整备界面，重进游戏不能自动把战果覆盖掉。
	in_battle = false
	round_active = false
	round_duration = 0.0
	round_seconds_left = 0.0
	round_seconds_elapsed = 0.0
	slap_cooldown_left = 0.0
	round_slaps = 0
	round_tables_flipped = 0
	round_first_clears = []
	table_damage = 0.0
	_pile_stages_done = {}
	_pile_stage_damage = {}
	end_slap_batch()
	battle = []
	_reset_build_traits()
	battle_gen += 1
	combo = 0
	run_kills = 0
	run_damage = 0.0
	run_gold = 0.0
	last_slap = {}
	end_reason = ""
	last_outcome = _validated_outcome(d.get("last_outcome", {}))
	last_settle = str(d.get("last_settle", ""))
	if not last_outcome.is_empty():
		battle_region = int(last_outcome["region"])
		battle_mode = str(last_outcome["mode"])
		battle_table = int(last_outcome["table"]) - 1
		end_reason = str(last_outcome["result"])
		stamina_max = stamina_max_value()
		stamina = 0
		run_kills = int(last_outcome["kills"])
		run_damage = float(last_outcome["damage"])
		run_gold = float(last_outcome["gold"])
		round_duration = float(last_outcome.get("duration", round_duration_value()))
		round_seconds_elapsed = float(last_outcome.get("seconds", 0.0))
		round_slaps = int(last_outcome.get("slaps", 0))
		round_tables_flipped = int(last_outcome.get("tables_flipped", 0))
		round_first_clears = last_outcome.get("first_clears", []).duplicate()
		last_battle_report = last_settle
	else:
		# 旧档没有战果，继续原有自动铺首个可挑战区域的行为。
		if not automation_enabled: ensure_table()
	_auto_rest = Progression.REST_SECONDS
	save_game()
	return true


func _validated_outcome(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	var region_value: Variant = raw.get("region", 0)
	if not (region_value is int or region_value is float): return {}
	var idx := int(_outcome_number(raw, "region"))
	if float(idx) != float(region_value): return {}
	if GameData.region(idx).is_empty() or not is_unlocked(idx): return {}
	var result := str(raw.get("result", ""))
	if result not in ["cleared", "settled"]: return {}
	var step := clampi(int(raw.get("table", 1)), 1, table_count(idx))
	var mode := "practice" if str(raw.get("mode", "challenge")) == "practice" else "challenge"
	if result == "cleared" and mode == "challenge" and not _is_cleared(idx) and table_progress(idx) < step: return {}
	var first_clears: Array = []
	if raw.get("first_clears", []) is Array:
		for value in raw.get("first_clears", []):
			if (value is int or value is float) and _is_cleared(int(value)) and not first_clears.has(int(value)):
				first_clears.append(int(value))
	var city_cards := 0
	var city_hp := 0.0
	for stage in range(table_count(idx)):
		city_cards += _table_health_values(idx, stage).size()
		city_hp += table_hp(idx, stage)
	var pile_cards := clampi(int(_outcome_number(raw, "pile_cards")), 0, city_cards)
	var hp := clampf(_outcome_number(raw, "hp"), 0.0, city_hp) if raw.has("pile_cards") else table_hp(idx, step - 1)
	return {"region": idx, "result": result, "gold": _outcome_number(raw, "gold"),
		"kills": int(_outcome_number(raw, "kills")), "damage": _outcome_number(raw, "damage"),
		"table": step, "tables": table_count(idx), "mode": mode, "hp": hp,
		"pile_cards": pile_cards, "pile_remaining": clampi(int(_outcome_number(raw, "pile_remaining")), 0, pile_cards),
		"best": table_best_value(idx, step - 1), "city_clear": bool(raw.get("city_clear", false)) and _is_cleared(idx) and mode == "challenge",
		"reason": str(raw.get("reason", "returned")), "seconds": _outcome_number(raw, "seconds"),
		"duration": maxf(Progression.ROUND_SECONDS, _outcome_number(raw, "duration")),
		"slaps": int(_outcome_number(raw, "slaps")), "tables_flipped": int(_outcome_number(raw, "tables_flipped")),
		"first_clears": first_clears, "gold_per_second": _outcome_number(raw, "gold_per_second")}


func _outcome_number(raw: Dictionary, key: String) -> float:
	var value: Variant = raw.get(key, 0)
	if value is int or value is float:
		return maxf(0.0, float(value))
	return 0.0


# =====================================================================
# 工具
# =====================================================================
func log_msg(t: String) -> void:
	message.emit(t)


func _join(arr: Array) -> String:
	var s := ""
	for k in range(arr.size()):
		if k > 0:
			s += "、"
		s += str(arr[k])
	return s


func _names(ids: Array) -> String:
	var out := []
	for id in ids:
		out.append(GameData.card_name(id))
	return _join(out)


func fmt(n: float) -> String:
	var v := int(round(n))
	if v >= 100000000:
		return "%.2f亿" % (v / 100000000.0)
	if v >= 10000:
		return "%.2f万" % (v / 10000.0)
	return str(v)


## 测试与截图自动隔离，任何验证场景都不会覆盖玩家的正式存档。
func save_path() -> String:
	var test := OS.get_cmdline_user_args().has("--test-profile")
	for arg in OS.get_cmdline_args():
		if arg.ends_with("ZoneConquestTest.tscn") or arg.ends_with("ManualCampaignTest.tscn") or arg.ends_with("ManualCombatUITest.tscn") or arg.ends_with("HeroEquipmentTraitsTest.tscn") or arg.ends_with("RestFlowTest.tscn") or arg.ends_with("RevealAnimationTest.tscn") or arg.ends_with("UIInteractionTest.tscn"):
			test = true
		if arg.ends_with("UpgradeArtTest.tscn") or arg.ends_with("CityPileTest.tscn") or arg.ends_with("CityExplorationTest.tscn"):
			test = true
		if arg.ends_with("SelfTest.tscn") or arg.ends_with("IncrementalTest.tscn") or arg.ends_with("Screenshot.tscn") or arg.ends_with("PrintTest.tscn") or arg.ends_with("OutcomeTest.tscn") or arg.ends_with("HubTest.tscn") or arg.ends_with("BuildTraitsTest.tscn") or arg.ends_with("ArtV5Test.tscn") or arg.ends_with("BuildingComboTest.tscn") or arg.ends_with("BuildingDragTest.tscn"):
			test = true
	return "user://save_paan_test.json" if test else SAVE_PATH


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
