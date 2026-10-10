extends Node
## 《拍案三国》：30秒一轮，按共享拍击间隔赚取即时金币。
## 一座城一次铺出整堆卡，圆形范围轻拍；整堆清空后补牌，倒计时结束回营。
## 旧逐桌进度作为城堆内部的连续清除检查点保留，首通奖励仍只领一次。

signal changed                        # 高频：金币 / 耐力 / 血量 / 连击
signal map_changed                    # 区域状态变化（解锁 / 克服 / 新周目）
signal shop_changed                   # 持有卡 / 建筑 / 城池变化
signal message(text: String)

## v1.2 正式保存成长与城建；局内桌面血量不保留。验证场景自动使用测试档。
const SAVE_ENABLED := true
const SAVE_PATH := "user://save_paan.json"
const COMBO_THRESHOLD := 20
const RANSOM := {3: 200, 4: 800, 5: 3200, 6: 12800}
const SYNC_COST := {1: 10, 2: 40, 3: 160, 4: 640, 5: 2560}
const OFFLINE_BASE_HOURS := 8.0
const OFFLINE_EFFICIENCY := 0.5
const PACK_PRICE_GROWTH := 1.05
const Progression = preload("res://scripts/progression_rules.gd")
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
	{"id": "auto", "name": "自动拍", "unit": "已解锁", "kind": "add", "base": 0, "step": 1, "lv": 1,
	 "cost": 60, "growth": 1.0, "desc": "按拍速自动轻拍，间隔为手拍3倍、伤害25%；在限时轮内练已清除的城池卡段"},
	{"id": "auto_next", "name": "自动下一趟", "unit": "已解锁", "kind": "add", "base": 0, "step": 1, "lv": 1,
	 "cost": 120, "growth": 1.0, "desc": "练习结束休息4秒再铺原城牌堆；持续挂机及离线练习，不替你推进主线"},
	{"id": "auto_power", "name": "自动助力", "unit": "%", "kind": "add", "base": 25, "step": 5, "lv": 3,
	 "cost": 180, "growth": 2.0, "desc": "自动拍伤害25%→40%；手拍仍是冲关主力"},
	{"id": "stamina", "name": "时长", "unit": "秒", "kind": "add", "base": Progression.ROUND_SECONDS, "step": Progression.ROUND_SECONDS_PER_LEVEL, "lv": 60,
	 "cost": 18, "growth": 1.20, "desc": "每轮基础30秒，每级延长2秒，留出更多赚钱时间"},
	{"id": "speed", "name": "拍速", "unit": "拍/秒", "kind": "mult", "base": 1.0 / Progression.SLAP_INTERVAL, "factor": 1.08,
	 "step": 0, "lv": 40, "cost": 24, "growth": 1.25, "desc": "拍击频率×1.08/级；初始轻拍0.6秒，重拍冷却为轻拍×1.8"},
	{"id": "radius", "name": "范围", "unit": "半径", "kind": "add", "base": 34, "step": 6, "lv": 20,
	 "cost": 24, "growth": 1.22, "desc": "拍卡圆圈每级扩大6；单击同时拍中圆内所有卡牌，伤害与一掌冷却共享"},
	{"id": "power", "name": "拍力", "unit": "倍", "kind": "mult", "base": 1.0, "factor": 1.12,
	 "step": 0, "lv": 0, "cost": 18, "growth": 1.20, "desc": "拍力 ×1.12/级（复利叠乘，无上限）"},
	{"id": "carry", "name": "携带位", "unit": "个", "kind": "add", "base": 3, "step": 1, "lv": 3,
	 "cost": 300, "growth": 2.00, "desc": "除主角外，能带上桌的武将数"},
	{"id": "crit", "name": "暴击", "unit": "%", "kind": "add", "base": 0, "step": 4, "lv": 8,
	 "cost": 60, "growth": 1.40, "desc": "暴击率 +4%/级（×2 伤害）"},
	{"id": "fortune", "name": "财路", "unit": "%", "kind": "add", "base": 0, "step": 20, "lv": 10,
	 "cost": 40, "growth": 1.35, "desc": "击杀掉金 +20%/级"},
	{"id": "idle", "name": "挂机效率", "unit": "%", "kind": "add", "base": 0, "step": 5, "lv": 10,
	 "cost": 80, "growth": 1.40, "desc": "离线产出效率 +5%/级，离线上限 +1h/级"},
	{"id": "equip", "name": "装备槽", "unit": "格", "kind": "add", "base": 0, "step": 1, "lv": 5,
	 "cost": 150, "growth": 1.60, "desc": "依次解锁 兵器/铠甲/坐骑/兵书/宝物 五个部位"},
	# v1.1 新增：士卒可以挂到武将身上（用户要求「未来点亮技能树里的武将带兵能力 可以直接把兵给武将装备」）
	{"id": "troops", "name": "武将带兵", "unit": "兵", "kind": "add", "base": 0, "step": 1, "lv": 3,
	 "cost": 600, "growth": 2.00,
	 "desc": "每个上阵武将 +1 兵位（0 → 3）；兵位上的士卒战力全额计入卡组，且不占携带位"},
]

# ---------- 技能树布局（v1.1）----------
## UPGRADES 是**数值定义**，SKILL_TREE 只加「层级」和「前置」这两层结构。
## ⚠️ 节点数值一个都没动 —— 上一轮刚调好的节拍（复利拍力 ×1.15 + 新野 60 血 + ×1.85 曲线）
##    不能再被打乱。前置也只做**浅门槛**（前置 ≥ Lv.1 即可），不做等级要求，
##    否则会把"玩家自己决定先点什么"变成"被树逼着点"。
## req 里列的是「至少点亮过一次（Lv.1）」的前置技能 id。
const SKILL_TREE: Array = [
	{"id": "auto", "tier": 2, "req": ["power"]},
	{"id": "auto_next", "tier": 3, "req": ["auto"]},
	{"id": "auto_power", "tier": 3, "req": ["auto_next"]},
	{"id": "stamina", "tier": 1, "req": []},
	{"id": "speed", "tier": 1, "req": []},
	{"id": "radius", "tier": 1, "req": []},
	{"id": "power",   "tier": 1, "req": []},
	{"id": "carry",   "tier": 1, "req": []},
	{"id": "crit",    "tier": 2, "req": ["power"]},
	{"id": "fortune", "tier": 2, "req": ["carry"]},
	{"id": "equip",   "tier": 2, "req": ["power"]},
	{"id": "idle",    "tier": 3, "req": ["fortune"]},
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
	## 某个武将身上所有装备提供的词条。
	var m := empty_mods()
	for id in hero_equip.get(who, []):
		m = add_mods(m, parse_effect(str(GameData.card(str(id)).get("effect", ""))))
	return m


func equip_mods() -> Dictionary:
	## ⚠️ v1.1：装备是**每将独立**的，所以这里要按武将汇总 —— 而且只算**上阵**的武将
	##    （与"只算上阵的卡"一致：没上阵的武将，它身上的装备也不上桌）。
	## 再用功能建筑「军械坊」放大百分比类词条。
	var m := empty_mods()
	for who in carry:
		m = add_mods(m, hero_equip_mods(str(who)))
	var amp: float = 1.0 + float(bonus.get("equip_pct", 0.0)) / 100.0
	if not is_equal_approx(amp, 1.0):
		for k in PCT_KEYS:
			m[k] = float(m[k]) * amp
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
	if not narrative_paused:
		advance_round(delta)
	var income := advance_buildings(delta)
	if income > 0.0:
		gold += income
		changed.emit()
	if SAVE_ENABLED:
		_save_timer += delta
		if _save_timer >= 30.0:
			_save_timer = 0.0
			save_game()


# 逐桌推进与练习共用限时轮、共享拍击间隔与即时伤害收益。
func table_count(idx: int) -> int:
	return Progression.table_count(idx)

func table_progress(idx: int) -> int:
	return table_count(idx) if _is_cleared(idx) else clampi(int(table_wins.get(idx, 0)), 0, table_count(idx))

func table_hp(idx: int, completed: int = -1) -> float:
	return Progression.table_hp(GameData.region(idx), table_progress(idx) if completed < 0 else completed)

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
	# 自动轮按实际出手事件切分时间：大delta与正常帧具有相同动作、冷却及结算规则。
	if narrative_paused or delta <= 0.0: return
	var remaining := delta
	while remaining > 0.000001 and not narrative_paused:
		if not in_battle:
			if not automation_enabled or not auto_unlocked() or upgrade_level("auto_next") < 1: break
			var rest := minf(remaining, maxf(0.0, _auto_rest))
			_auto_rest -= rest
			remaining -= rest
			if _auto_rest > 0.000001: break
			if not start_practice(practice_region):
				stop_automation(false)
				break
		var automated := automation_enabled and auto_unlocked() and battle_mode == "practice"
		var slice := minf(remaining, round_seconds_left)
		if automated: slice = minf(slice, maxf(0.0, auto_interval() - _auto_clock))
		slice = minf(slice, _next_build_event_time())
		if slice > 0.0:
			slap_cooldown_left = maxf(0.0, slap_cooldown_left - slice)
			if automated: _auto_clock += slice
			round_seconds_elapsed += slice
			round_seconds_left = maxf(0.0, round_seconds_left - slice)
			stamina = int(ceil(round_seconds_left))
			remaining -= slice
			# 先同步计时再派发伤害事件；0秒边界仍结算刚过去的有效时间片。
			_tick_build_effects(slice, true)
		if round_seconds_left <= 0.000001:
			round_seconds_left = 0.0
			settle_run("time_up")
			continue
		if automated and _auto_clock + 0.000001 >= auto_interval():
			_auto_clock = maxf(0.0, _auto_clock - auto_interval())
			var target := -1
			var low := INF
			for i in range(battle.size()):
				if _build_alive(i) and float(battle[i]["hp"]) < low:
					low = float(battle[i]["hp"])
					target = i
			if target >= 0: attack(target, false, true)
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
	last_battle_report = "%s · %s整堆%d张　每轮%d秒 · 间隔%.2f秒 · 轻拍%.1f · 总厚度%s" % [
		GameData.region(idx).get("name", ""), "练习" if battle_mode == "practice" else "挑战",
		battle.size(), stamina, slap_interval(), click_damage(), fmt(pile_max_health())]
	changed.emit()
	return not battle.is_empty()

func _grant_table_reward(idx: int, step: int) -> void:
	if idx != 1: return
	var gift := "G00" if step == 0 else ("G04" if step == 2 else ("G05" if step == 4 else ""))
	if gift != "":
		owned[gift] = int(owned.get(gift, 0)) + 1
		_auto_carry()
		log_msg("获得将牌「%s」，构筑能让下一掌不一样。" % GameData.card_name(gift))
	if step == 4:
		for id in ["B06", "B08"]: owned[id] = int(owned.get(id, 0)) + 1
		# 初次建城直接接上可理解的两卡组合，不要求先抽到产出来源。
		place_building(1, "B06", 0, 0)
		place_building(1, "B08", 0, 1)
		log_msg("新野基建开放：农田→水井，每10秒6金币。去基建接上更多组合。")

func practice_unlocked() -> bool:
	for r in GameData.regions:
		if table_progress(int(r["idx"])) > 0: return true
	return false

func _practice_target(idx: int) -> int:
	if table_progress(idx) > 0: return idx
	for r in GameData.regions:
		if table_progress(int(r["idx"])) > 0: return int(r["idx"])
	return 0

func start_practice(idx: int = 1) -> bool:
	var target := _practice_target(idx)
	if target == 0: return false
	if in_battle: settle_run("returned")
	practice_region = target
	practice_table = clampi(table_progress(target) - 1, 0, table_count(target) - 1)
	battle_mode = "practice"
	battle_table = practice_table
	_auto_clock = 0.0
	_auto_rest = 0.0
	return _start_table(target)

func auto_unlocked() -> bool:
	return upgrade_level("auto") > 0

func auto_ratio() -> float:
	return clampf(upgrade_value("auto_power") / 100.0, 0.25, 0.40)

func set_automation(enabled: bool) -> bool:
	if enabled and (not auto_unlocked() or not practice_unlocked()): return false
	automation_enabled = enabled
	_auto_clock = 0.0
	_auto_rest = 0.0
	if enabled and (not in_battle or battle_mode != "practice"):
		if in_battle: settle_run() # 已拍伤害有结算，不丢弃手动这一趟。
		automation_enabled = true
		start_practice(practice_region)
	save_game()
	changed.emit()
	return true

func stop_automation(announce: bool = true) -> void:
	automation_enabled = false
	_auto_clock = 0.0
	_auto_rest = 0.0
	if announce:
		save_game()
		changed.emit()

func _finish_automation_run() -> void:
	if not automation_enabled or battle_mode != "practice": return
	if upgrade_level("auto_next") > 0:
		_auto_rest = Progression.REST_SECONDS
	else:
		automation_enabled = false
		log_msg("自动练完这一趟。完成新野后可解锁持续练习。")

func advance_automation(delta: float) -> void:
	if automation_enabled: advance_round(delta)

func practice_rate() -> float:
	# 保守离线工资：使用同轮时长、拍速、自动伤害与休息；不预支暴击或构筑伤害。
	var idx := _practice_target(practice_region)
	if idx == 0 or not auto_unlocked(): return 0.0
	var duration := round_duration_value()
	var actions := maxi(0, int(floor((duration - 0.000001) / auto_interval())))
	var full: Array = []
	var stages: Array = []
	for step in range(table_progress(idx)):
		for hp in _table_health_values(idx, step):
			full.append(hp)
			stages.append(step)
	if full.is_empty(): return 0.0
	var health := full.duplicate()
	var paid: Dictionary = {}
	var damage := click_damage() * auto_ratio()
	var payout := 0.0
	for ignored in range(actions):
		var pick := -1
		var low := INF
		for i in range(health.size()):
			if float(health[i]) > 0.0 and float(health[i]) < low:
				pick = i
				low = float(health[i])
		if pick < 0: break
		var actual := minf(damage, float(health[pick]))
		health[pick] = float(health[pick]) - actual
		payout += actual * Progression.DAMAGE_PAY
		if float(health[pick]) <= 0.0: payout += float(full[pick]) * Progression.KILL_PAY
		var stage := int(stages[pick])
		if not paid.has(stage):
			var stage_done := true
			for i in range(health.size()):
				if int(stages[i]) == stage and float(health[i]) > 0.0:
					stage_done = false
					break
			if stage_done:
				paid[stage] = true
				payout += table_hp(idx, stage) * Progression.TABLE_BONUS
		var complete := true
		for hp in health:
			if float(hp) > 0.0:
				complete = false
				break
		if complete:
			health = full.duplicate()
			paid = {}
	return payout * fortune_mult() * 60.0 / (duration + Progression.REST_SECONDS)

func progression_hint() -> String:
	var idx := battle_region if battle_region > 0 and not _is_cleared(battle_region) else 0
	if idx == 0:
		for r in GameData.regions:
			if is_unlocked(int(r["idx"])) and not _is_cleared(int(r["idx"])):
				idx = int(r["idx"])
				break
	if idx == 0: return "荆州全境完成 · 回旧城牌堆验证新组合"
	var done := table_progress(idx)
	var goal := "%s 卡堆已清%d/%d段 · 当前段厚度%s" % [GameData.region(idx).get("name", ""), done, table_count(idx), fmt(table_hp(idx, done))]
	var best := table_best_value(idx, done)
	if best > 0.0: goal += " · 最好%.0f%%" % minf(100.0, best / table_hp(idx, done) * 100.0)
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
	for r in GameData.regions:
		var idx := int(r["idx"])
		table_wins[idx] = table_count(idx) if _is_cleared(idx) else clampi(int(d.get("table_wins", {}).get(str(idx), 0)), 0, table_count(idx) - 1)
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
	automation_enabled = bool(d.get("automation_enabled", false)) and auto_unlocked() and practice_unlocked() and upgrade_level("auto_next") > 0
	narrative_paused = false
	hero_refined = {}
	for id in d.get("hero_refined", {}):
		if is_hero(str(id)) and d["hero_refined"][id] is Array:
			hero_refined[str(id)] = d["hero_refined"][id]
	if int(d.get("progression_version", 0)) < 4:
		# 已完成城池直接视为所有桌已完；旧将牌升级投资一次返还，收藏不删。
		var refund := 0.0
		for id in d.get("hero_lv", {}):
			if not is_hero(str(id)) or int(owned.get(str(id), 0)) <= 0: continue
			var star := 4 if str(id) == "G00" else int(GameData.card(str(id)).get("star", 2))
			var old_level := clampi(int(d["hero_lv"][id]), 0, int(HERO_LV_MAX.get(star, 5)))
			for level in range(old_level):
				refund += round(float(HERO_LV_COST.get(star, 20)) * pow(HERO_LV_GROWTH, level))
		gold += refund
		if runs > 0 and not story_seen.has("opening_robbery"): story_seen.append("opening_robbery")
		if refund > 0.0: offline_report = "武将改同名合成，已返还旧培养%s金币。" % fmt(refund)
	hero_lv = {}


# =====================================================================
# 新周目
# =====================================================================
func new_game() -> void:
	gold = 0.0
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

	# 开局：1 张主角卡 + 1 个卡包（5 张）。此时没有任何城池 —— 挂机是后面才解锁的事。
	var starter := _draw_starter(5)
	for id in starter:
		owned[id] = int(owned.get(id, 0)) + 1
	_auto_carry()
	log_msg("开局：主角卡「%s」 + 一包卡（%s）。上阵 %d 张，每轮 %d 秒；圆圈拍卡即时赚金，升级拍力、拍速、范围和时长。" % [
		GameData.card_name(HERO_ALWAYS), _names(starter), carry.size(), stamina_max_value()])

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
	if t == 2: return "亲和 5：槽位 +1"
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
	var u := up_def(id)
	if u.is_empty():
		return 0
	return int(round(float(u["cost"]) * pow(float(u["growth"]), float(upgrade_level(id)))))


func buy_upgrade(id: String) -> bool:
	var u := up_def(id)
	if u.is_empty():
		return false
	# v1.1：技能树前置门禁（浅门槛 —— 前置 ≥ Lv.1 即可）
	if not skill_req_met(id):
		log_msg("「%s」还点不了 —— %s" % [u.get("name", "?"), skill_req_text(id)])
		return false
	if upgrade_maxed(id):
		log_msg("「%s」已满级。" % u.get("name", "?"))
		return false
	var cost := upgrade_cost(id)
	if gold < float(cost):
		log_msg("金币不足（%s 升级需要 %d，现有 %d）" % [u.get("name", "?"), cost, int(gold)])
		return false
	gold -= float(cost)
	var lv := upgrade_level(id) + 1
	up[id] = lv
	log_msg("点亮「%s」→ Lv.%d　现在 %s%s（-%d 金币）" % [
		u.get("name", "?"), lv, fmt(upgrade_value(id)), str(u.get("unit", "")), cost])
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
	for req in skill_reqs(id):
		if upgrade_level(str(req)) < 1: return false
	if id == "auto" and table_progress(1) < 2: return false
	if id in ["auto_next", "auto_power", "idle"] and not _is_cleared(1): return false
	if id == "carry" and table_progress(1) < 3: return false
	if id in ["equip", "troops"] and not _is_cleared(1): return false
	return true


func skill_req_text(id: String) -> String:
	var miss := []
	for req in skill_reqs(id):
		if upgrade_level(str(req)) < 1: miss.append(str(up_def(str(req)).get("name", req)))
	if id == "auto" and table_progress(1) < 2: miss.append("清除新野卡堆前2段")
	if id in ["auto_next", "auto_power", "idle", "equip", "troops"] and not _is_cleared(1): miss.append("拍空新野整堆")
	if id == "carry" and table_progress(1) < 3: miss.append("清除新野卡堆前3段")
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
	# 1 级起步，每 3 个升级点算 1 级（纯展示）
	return 1 + int(total_upgrade_levels() / 3)


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


func hero_level(_id: String) -> int:
	return 0 # 独立经验等级已退役。旧投资迁移时返还。


func hero_lv_max(_id: String) -> int:
	return 0


func hero_lv_maxed(id: String) -> bool:
	return hero_level(id) >= hero_lv_max(id)


func hero_lv_cost(_id: String) -> int:
	return 0


func hero_lv_mult(id: String) -> float:
	return [1.0, 1.35, 1.8][hero_quality(id)]


func hero_card_power(id: String) -> float:
	## 某个武将的"自身战力" = 卡面基础战力 × 等级倍率。
	return float(GameData.card(id).get("power", 0.0)) * hero_lv_mult(id)


func buy_hero_lv(_id: String) -> bool:
	log_msg("武将不设等级，请用仓库的同名3张合成。")
	return false


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
	return _is_cleared(START_REGION)


func city_unlock_text() -> String:
	return "已解锁" if city_unlocked() else "拍空新野整堆开放基建 · %d/5段" % table_progress(1)


func _backfill_cities() -> Array:
	# 城池一旦解锁，把此前已克服区域的城池卡补齐发放（幂等）
	var got := []
	if not city_unlocked():
		return got
	for r in GameData.regions:
		var i := int(r["idx"])
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
	if not is_unlocked(idx) or GameData.region(idx).is_empty(): return false
	if in_battle: settle_run("returned")
	stop_automation(false)
	battle_mode = "challenge"
	battle_table = mini(table_count(idx) - 1, table_progress(idx))
	return _start_table(idx)


func _refresh_enemies() -> void:
	battle = []
	_pile_stages_done = {}
	_pile_stage_damage = {}
	var raw: Array = GameData.enemies_by_region.get(battle_region, [])
	var first := 0 if battle_mode == "practice" or _is_cleared(battle_region) else battle_table
	# 自动练习只练已完成部分；手动挑战把所有剩余阶段一起铺入同一个城堆。
	var limit := table_progress(battle_region) if battle_mode == "practice" else table_count(battle_region)
	for step in range(first, limit):
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
	var positions := preload("res://scripts/city_layout.gd").positions(battle.size(), battle_region)
	for i in range(battle.size()):
		battle[i]["nx"] = positions[i].nx
		battle[i]["ny"] = positions[i].ny
		battle[i]["rot"] = positions[i].rot


func attack(i: int, heavy: bool = false, automatic: bool = false) -> bool:
	## 一次圆形轻拍的多个目标共享冷却；旧重拍接口保留供构筑兼容。
	if not in_battle or not round_active or narrative_paused or round_seconds_left <= 0.0 or i < 0 or i >= battle.size():
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
	build_effect_seq += 1
	last_slap = {"index": i, "heavy": heavy, "damage": actual, "tag": tag,
		"effects": build_events.duplicate(true), "source": "base", "effect_seq": build_effect_seq,
		"gold_gain": run_gold - gold_before, "battle_gen": action_gen}
	if tag != "":
		log_msg("%s%s　造成 %.0f 伤害" % ["重拍·" if heavy else "轻拍·", tag, dmg])

	_finish_build_action()
	return true


func _reset_build_traits() -> void:
	build_clock = 0.0
	build_counts = {}
	build_ready_at = {}
	build_events = []


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
	var payout := actual * Progression.DAMAGE_PAY * fortune_mult()
	gold += payout
	run_gold += payout
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
	var reward := float(battle[i]["hp_max"]) * Progression.KILL_PAY * fortune_mult()
	gold += reward
	run_gold += reward
	run_kills += 1
	if not first_flip_reward:
		first_flip_reward = true
		gold += 8.0
		run_gold += 8.0
		log_msg("第一张翻牌！一次性收获8金币，下一趟可以买助力。")


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
	var reward := 0.0
	var changed_progress := false
	# 每个段只在本次铺堆第一次清完时发金币；先拍厚段也不会提前推进连续检查点。
	for step in _pile_stage_damage:
		if _pile_stages_done.has(step) or not _stage_cleared(int(step)): continue
		_pile_stages_done[step] = true
		reward += table_hp(idx, int(step)) * Progression.TABLE_BONUS * fortune_mult()
		round_tables_flipped += 1
	_update_table_best()
	if battle_mode != "practice" and not _is_cleared(idx):
		var next := table_progress(idx)
		while next < table_count(idx) and _stage_cleared(next):
			table_wins[idx] = next + 1
			changed_progress = true
			if next == table_count(idx) - 1:
				region_state[idx] = "cleared"
				round_first_clears.append(idx)
				reward += table_hp(idx, next) * Progression.CITY_BONUS * fortune_mult()
				_grant_affinity(idx)
				for e in battle:
					var c := GameData.card(str(e["card_id"]))
					if str(c.get("type", "")) == "武将" and bool(c.get("capturable", false)):
						if not captured.has(e["card_id"]): captured.append(e["card_id"])
				_backfill_cities()
				log_msg("%s整堆已空！城池首通，剩余时间继续赚金。" % GameData.region(idx).get("name", ""))
			_grant_table_reward(idx, next)
			next += 1
	if reward > 0.0:
		gold += reward
		run_gold += reward
		if not last_slap.is_empty(): last_slap["gold_gain"] = float(last_slap.get("gold_gain", 0.0)) + reward
	if changed_progress:
		_recompute_bonus()
		save_game()
		map_changed.emit()
		shop_changed.emit()


func _clear_region() -> void:
	if not in_battle or not round_active or battle.is_empty() or not _all_cleared(): return
	_update_pile_checkpoints()
	var idx := battle_region
	# 全堆清空才补整堆。段内清完不换牌，也不重置镜头或当前圆形拍击。
	battle_table = 0 if battle_mode == "practice" or _is_cleared(idx) else mini(table_count(idx) - 1, table_progress(idx))
	table_damage = 0.0
	_reset_build_traits()
	_refresh_enemies()
	last_battle_report = "%s · 整堆拍空，重新铺%d张；剩余%.1f秒，继续赚金！" % [GameData.region(idx).get("name", ""), battle.size(), round_seconds_left]
	save_game()
	map_changed.emit()
	shop_changed.emit()
	changed.emit()


func settle_run(reason: String = "returned") -> void:
	if not in_battle: return
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
	last_settle = "%s · %s　%.1f秒拍%d次 · 翻%d张 / 清%d段 · 收获%s金币。升级拍力、拍速、范围和时长，再开一轮。" % [
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
	var n := int(pack_bought.get(p.get("name", ""), 0))
	var off := clampf(float(bonus["pack_price_pct"]) + float(active_mods()["pack_pct"]), -50.0, 75.0)
	return maxi(1, int(round(float(p.get("price", 100)) * minf(1.5, 1.0 + 0.05 * n) * (1.0 - off / 100.0))))


func buy_pack(i: int) -> Array:
	if not pack_unlocked(i):
		log_msg("「%s」未解锁：需先克服该郡的任一区域。" % GameData.packs[i].get("name", "?"))
		return []
	var price := pack_price(i)
	if gold < float(price):
		log_msg("金币不足（需要 %d，现有 %d）" % [price, int(gold)])
		return []
	gold -= float(price)
	var drawn := _draw_pack_cards(i, int(GameData.packs[i].get("cards", 5)))
	# 保底：每 10 包必出 1 张 ★★★★ 及以上
	total_packs += 1
	if (int(pack_bought.get(GameData.packs[i].get("name", ""), 0)) + 1) % 10 == 0:
		var hi := _draw_high_star(i, mini(3, progression_star_cap()))
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


func _draw_starter(count: int) -> Array:
	# 固定三种薄牌，避免抽到重复后开局强度与教程失配。
	var pool := []
	for c in GameData.cards:
		if str(c.get("type", "")) == "士兵" and int(c.get("star", 0)) == 1: pool.append(str(c["id"]))
	var out := []
	for i in range(count): out.append(pool[i % mini(3, pool.size())])
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
	var legacy := int(GameData.region(idx).get("slots", 1))
	if affinity_tier(region_route(idx)) >= 2:
		legacy += 1
	return maxi(6, legacy)

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
	result["hourly"] = float(result["hourly"]) * _building_global_mult()
	return result

func _building_global_mult() -> float:
	var mult := 1.0 + float(bonus["building_output_pct"]) / 100.0
	if bond_tier("群雄线") >= 2:
		mult += 0.10
	if bond_tier("群雄线") >= 1:
		mult += 0.20
	return mult

func advance_buildings(seconds: float, efficiency: float = 1.0) -> float:
	if seconds <= 0 or not city_unlocked():
		return 0.0
	var income := 0.0
	for raw_idx in cities.keys():
		var idx := int(raw_idx)
		if not _is_cleared(idx):
			continue
		var summary := city_combo(idx)
		if float(summary["normal"]) <= 0:
			continue
		var elapsed := float(building_clocks.get(idx, 0.0)) + seconds
		var cycles := int(floor((elapsed + 0.0000001) / BuildingTraits.CYCLE))
		building_clocks[idx] = maxf(0.0, elapsed - cycles * BuildingTraits.CYCLE)
		if cycles > 0:
			var before := int(building_ticks.get(idx, 0))
			income += BuildingTraits.payout(summary, before, cycles)
			building_ticks[idx] = (before + cycles) % 60
	return income * _building_global_mult() * clampf(efficiency, 0, 1)

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
	if not city_unlocked() or not _is_cleared(idx) or GameData.building(building_id).is_empty():
		return false
	if city_buildings(idx).has(building_id):
		log_msg("同城同名建筑只装配1张；重复卡可同名合成。")
		return false
	if quality == -1:
		for q in [2, 1, 0]:
			if building_stock(building_id, q) > 0:
				quality = q
				break
	if building_stock(building_id, quality) <= 0 or city_used_slots(idx) >= city_slots(idx):
		return false
	_ensure_building_arrays(idx)
	var arr := city_buildings(idx)
	if target_slot < 0:
		target_slot = arr.find("")
		if target_slot < 0:
			target_slot = arr.size()
	if target_slot >= city_slots(idx) or (target_slot < arr.size() and str(arr[target_slot]) != ""):
		return false
	while arr.size() <= target_slot:
		arr.append("")
	_ensure_building_arrays(idx)
	arr[target_slot] = building_id
	city_quality[idx][target_slot] = quality
	_building_stock_change(building_id, quality, -1)
	log_msg("装配%s·%s：%s" % [GameData.card_name(building_id), BuildingTraits.quality_name(quality), GameData.building(building_id).get("effect", "")])
	_building_loadout_changed(idx)
	return true

func remove_building(idx: int, slot_index: int) -> bool:
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
	var total := 0.0
	for idx in cities.keys():
		if _is_cleared(int(idx)):
			total += float(city_combo(int(idx))["hourly"])
	return total

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
		building_clocks[idx] = clampf(float(data.get("building_clocks", {}).get(str(idx), 0)), 0, 9.999999)
		building_ticks[idx] = maxi(0, int(data.get("building_ticks", {}).get(str(idx), 0))) % 60
		var seen := {}
		for slot in range(city_buildings(int(idx)).size()):
			var id := _building_at(int(idx), slot)
			city_quality[idx][slot] = clampi(int(city_quality[idx][slot]), 0, 2)
			var old_level := clampi(int(city_lv[idx][slot]), 0, BUILDING_LV_MAX)
			if int(data.get("building_system_version", 0)) < 2 and old_level > 0 and not GameData.building(id).is_empty():
				var star := int(GameData.building(id).get("star", 1))
				for level in range(old_level):
					gold += int(round(BUILDING_LV_COST * pow(1.6, maxi(0, star - 1)) * pow(BUILDING_LV_GROWTH, level)))
			city_lv[idx][slot] = 0
			if id == "":
				continue
			if GameData.building(id).is_empty():
				city_buildings(int(idx))[slot] = ""
			elif seen.has(id):
				_building_stock_change(id, building_quality(int(idx), slot), 1)
				city_buildings(int(idx))[slot] = ""
				city_quality[idx][slot] = 0
			else:
				seen[id] = true
		while not city_buildings(int(idx)).is_empty() and str(city_buildings(int(idx)).back()) == "":
			city_buildings(int(idx)).pop_back()
		_ensure_building_arrays(int(idx))


func offline_efficiency() -> float:
	# 离线结算效率：基础 50%，「挂机效率」升级每级 +5%，装备/武将「离线收益」再叠加，封顶 100%
	var e: float = OFFLINE_EFFICIENCY + upgrade_value("idle") / 100.0
	e *= 1.0 + float(active_mods()["offline_pct"]) / 100.0
	return minf(1.0, e)


func offline_cap_hours() -> float:
	var h: float = OFFLINE_BASE_HOURS + float(bonus["offline_hours"]) \
		+ float(upgrade_level("idle"))          # 挂机效率：每级 +1h 离线上限
	if bond_tier("群雄线") >= 2:
		h *= 1.5
	return minf(h, 24.0)


func _reset_bonus() -> void:
	for k in bonus.keys():
		bonus[k] = 0.0


func _recompute_bonus() -> void:
	_reset_bonus()
	var strongest := {}
	for idx in cities.keys():
		for slot in range(city_buildings(int(idx)).size()):
			var b := _building_at(int(idx), slot)
			var bd := GameData.building(b)
			var t: String = bd.get("effect_type", "none")
			if bonus.has(t):
				var amount := float(bd.get("effect_value", 0.0)) * BuildingTraits.quality_mult(building_quality(int(idx), slot))
				if bool(bd.get("unique", false)):
					strongest[b] = {"type": t, "value": maxf(amount, float(strongest.get(b, {}).get("value", 0.0)))}
				else:
					bonus[t] = float(bonus[t]) + amount
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

	gold = float(d.get("gold", 0.0))
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
			hero_lv[hid] = mini(int(d["hero_lv"][k]), hero_lv_max(hid))

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
	if int(d.get("progression_version", 0)) < 4 and _is_cleared(1) and city_used_slots(1) == 0:
		for id in ["B06", "B08"]:
			owned[id] = int(owned.get(id, 0)) + 1
		place_building(1, "B06", 0, 0)
		place_building(1, "B08", 0, 1)
	_recompute_bonus()

	# 离线复用在线周期及追加计数，入账后立即保存，不能重复领取。
	var elapsed := float(Time.get_unix_time_from_system()) - float(d.get("last_save", 0))
	if elapsed > 0.0 and gold_per_hour() > 0.0:
		var eff := offline_efficiency()
		var hours: float = minf(elapsed / 3600.0, offline_cap_hours())
		var gain := advance_buildings(hours * 3600.0, eff)
		gold += gain
		offline_report = "离线 %.1f 小时，建筑产出 %d 金币（效率 %.0f%%）" % [
			hours, int(gain), eff * 100.0]

	if automation_enabled and upgrade_level("auto_next") > 0 and elapsed > 0.0:
		var trained := minf(elapsed, offline_cap_hours() * 3600.0)
		var gain := practice_rate() / 60.0 * trained * offline_efficiency()
		gold += gain
		practice_runs += int(trained / (round_duration_value() + Progression.REST_SECONDS))
		offline_report += "  练习积累%s金币（估算收益，离线效率%.0f%%）" % [fmt(gain), offline_efficiency() * 100.0]
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
		if arg.ends_with("UpgradeArtTest.tscn") or arg.ends_with("CityPileTest.tscn") or arg.ends_with("CityExplorationTest.tscn"):
			test = true
		if arg.ends_with("SelfTest.tscn") or arg.ends_with("IncrementalTest.tscn") or arg.ends_with("Screenshot.tscn") or arg.ends_with("PrintTest.tscn") or arg.ends_with("OutcomeTest.tscn") or arg.ends_with("HubTest.tscn") or arg.ends_with("BuildTraitsTest.tscn") or arg.ends_with("ArtV5Test.tscn") or arg.ends_with("BuildingComboTest.tscn") or arg.ends_with("BuildingDragTest.tscn"):
			test = true
	return "user://save_paan_test.json" if test else SAVE_PATH


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
