extends Node
## 《拍案三国》核心状态机 —— v0.8「局内刷 + 局外升级」。
##
## 局内：铺一桌 -> 用有限的耐力拍击 -> 耐力耗尽「强制结算」回大本营。
## 局外：花金币升「升级树」——耐力 / 携带位 / 拍力 / 暴击 / 财路 / 挂机效率 / 装备槽。
## 判定：卡组战力 × 耐力 >= 该区域敌人总血量 -> 克服
## 挂机落点：克服区域 -> 获城池卡(地基) -> 放建筑卡 -> 建筑产钱（城池本身不产钱）
##
## ⚠️ 局内不持久：未克服的区域每次进场都重置满血，只把金币带出去。
## ⚠️ 已克服的区域不可重刷（它是城建地基，不是刷钱场）。

signal changed                        # 高频：金币 / 耐力 / 血量 / 连击
signal map_changed                    # 区域状态变化（解锁 / 克服 / 新周目）
signal shop_changed                   # 持有卡 / 建筑 / 城池变化
signal message(text: String)

## ⚠️ v1.0：暂不落盘。开发期每次启动都是全新一周目（便于反复验证开局曲线与节拍）。
## 想恢复存档，把下面这个开关改成 true 即可 —— save_game() / load_game() 和其中
## 全部的老档校验逻辑都原样保留着，不需要重写。
## 代价：关掉之后「离线挂机结算」也随之失效（它挂在 load_game() 里），
##       目前只保留会话内的挂机产出（见 _process）。
const SAVE_ENABLED := false
const SAVE_PATH := "user://save_paan.json"
const COMBO_THRESHOLD := 20
const RANSOM := {3: 200, 4: 800, 5: 3200, 6: 12800}
const SYNC_COST := {1: 10, 2: 40, 3: 160, 4: 640, 5: 2560}
const OFFLINE_BASE_HOURS := 8.0
const OFFLINE_EFFICIENCY := 0.5
const PACK_PRICE_GROWTH := 2.4
const ROUTES := ["魏线", "蜀线", "吴线", "群雄线"]

# ---------- 拍卡手感 ----------
const HEAVY_MULT := 2.5              # 重拍（拖拽划过）伤害倍率；轻拍（单击）= 1.0
const HEAVY_STAMINA := 2             # 重拍每命中一张的耐力消耗（×2.5 伤害 → 1.25× 性价比）
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
	{"id": "stamina", "name": "耐力", "unit": "点", "kind": "add", "base": 6, "step": 1, "lv": 60,
	 "cost": 12, "growth": 1.15, "desc": "每次出战可拍击的次数（6 → 66）"},
	{"id": "power", "name": "拍力", "unit": "倍", "kind": "mult", "base": 1.0, "factor": 1.15,
	 "step": 0, "lv": 0, "cost": 18, "growth": 1.16, "desc": "拍力 ×1.15/级（复利叠乘，无上限）"},
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
	{"id": "stamina", "tier": 1, "req": []},
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
	"兵器": "主拍力", "铠甲": "主体力上限", "坐骑": "主机动（点击/连击/金币）",
	"兵书": "主暴击与连击", "宝物": "主金币与离线收益",
}

# ---------- 建筑升级（v0.9）：每座已放置建筑可强化，+产出 ----------
const BUILDING_LV_MAX := 10
const BUILDING_LV_STEP := 0.15       # 每级 +15% 产出
const BUILDING_LV_COST := 120        # 首级价
const BUILDING_LV_GROWTH := 1.45

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
var hero_lv: Dictionary = {}        # 武将 card_id -> 等级（v0.9）
var _eff_cache: Dictionary = {}     # effect 文本 -> 词条字典（解析缓存）
var runs: int = 0                   # 已结算局数（"第几趟"）
var run_kills: int = 0              # 本局击倒数
var run_damage: float = 0.0         # 本局累计伤害

# ---------- 地图 ----------
var region_state: Dictionary = {}   # idx -> "locked" | "available" | "cleared"
var cities: Dictionary = {}         # idx -> { "buildings": [building_id, ...] }
var city_lv: Dictionary = {}        # idx -> [等级, ...]（与 buildings 一一对应，v0.9）
var affinity: Dictionary = {}       # 路线名 -> 该线已克服区域数
var pack_bought: Dictionary = {}    # 卡包名 -> 购买次数

# ---------- 战斗 ----------
var battle_region: int = 0
var battle: Array = []              # [{card_id, hp, hp_max, boss, nx, ny, rot}]
var battle_gen: int = 0             # 牌桌代次：每次重新铺桌 +1，UI 据此判断是否重建卡牌
var stamina: int = 0
var stamina_max: int = 0
var combo: int = 0
var in_battle: bool = false
var last_battle_report: String = ""
var last_settle: String = ""         # 最近一次结算的战报（回大本营时显示）
var end_reason: String = ""          # "" | "cleared"（拍翻整桌）| "settled"（耐力耗尽）
var last_slap: Dictionary = {}       # {index, heavy, damage, tag} 供 UI 播特效

# ---------- 功能建筑累计加成 ----------
var bonus: Dictionary = {
	"combat_power_pct": 0.0, "pack_price_pct": 0.0, "offline_hours": 0.0,
	"stamina_flat": 0.0, "building_output_pct": 0.0, "equip_pct": 0.0,
	"ransom_pct": 0.0,
}

var offline_report: String = ""

var _idle_buffer: float = 0.0
var _save_timer: float = 0.0


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
	var rate := gold_per_hour()
	if rate > 0.0:
		_idle_buffer += rate * delta / 3600.0
		if _idle_buffer >= 1.0:
			var add := int(_idle_buffer)
			_idle_buffer -= float(add)
			gold += float(add)
			changed.emit()
	if SAVE_ENABLED:                     # v1.0：开发期不自动落盘
		_save_timer += delta
		if _save_timer >= 30.0:
			_save_timer = 0.0
			save_game()


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
	affinity = {}
	for rt in ROUTES:
		affinity[rt] = 0
	pack_bought = {}
	total_packs = 0
	in_battle = false
	battle = []
	end_reason = ""
	_reset_bonus()

	# 局外成长全部归零：升级树 0 级、只带 3 个、没有装备槽、武将 0 级。
	up = {}
	for u in UPGRADES:
		up[str(u["id"])] = 0
	carry = []
	hero_equip = {}          # v1.1：装备巢改成每将独立（原全局 equipped 数组已废）
	hero_troops = {}         # v1.1：兵位（技能树「武将带兵」点亮后才有）
	hero_lv = {}
	runs = 0
	run_kills = 0
	run_damage = 0.0
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
	log_msg("开局：主角卡「新野之主」 + 一包卡（%s）。上阵 %d 张、耐力 %d —— 打不死几个是正常的，反复刷钱升级。" % [
		_names(starter), carry.size(), stamina_max_value()])

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
	## 所有前置都至少点亮过一次（Lv.1）。
	for r in skill_reqs(id):
		if upgrade_level(str(r)) < 1:
			return false
	return true


func skill_req_text(id: String) -> String:
	## 还没满足的前置，拼成一句人话；都满足了返回 ""。
	var miss := []
	for r in skill_reqs(id):
		if upgrade_level(str(r)) < 1:
			miss.append(str(up_def(str(r)).get("name", r)))
	if miss.is_empty():
		return ""
	return "需先点亮：" + "·".join(miss)


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


func hero_level(id: String) -> int:
	return int(hero_lv.get(id, 0))


func hero_lv_max(id: String) -> int:
	var st := int(GameData.card(id).get("star", 1))
	return int(HERO_LV_MAX.get(st, 5))


func hero_lv_maxed(id: String) -> bool:
	return hero_level(id) >= hero_lv_max(id)


func hero_lv_cost(id: String) -> int:
	var st := int(GameData.card(id).get("star", 1))
	var base := int(HERO_LV_COST.get(st, 20))
	return int(round(float(base) * pow(HERO_LV_GROWTH, float(hero_level(id)))))


func hero_lv_mult(id: String) -> float:
	return 1.0 + float(hero_level(id)) * HERO_LV_STEP


func hero_card_power(id: String) -> float:
	## 某个武将的"自身战力" = 卡面基础战力 × 等级倍率。
	return float(GameData.card(id).get("power", 0.0)) * hero_lv_mult(id)


func buy_hero_lv(id: String) -> bool:
	if not is_hero(id):
		log_msg("「%s」不是可练级的武将（士兵/装备等做素材用）。" % GameData.card_name(id))
		return false
	if int(owned.get(id, 0)) <= 0:
		return false
	if hero_lv_maxed(id):
		log_msg("「%s」已练到顶（Lv.%d）。" % [GameData.card_name(id), hero_lv_max(id)])
		return false
	var cost := hero_lv_cost(id)
	if gold < float(cost):
		log_msg("金币不足（「%s」升到 Lv.%d 需要 %d，现有 %d）" % [
			GameData.card_name(id), hero_level(id) + 1, cost, int(gold)])
		return false
	gold -= float(cost)
	var lv := hero_level(id) + 1
	hero_lv[id] = lv
	log_msg("武将「%s」→ Lv.%d　自身战力 %s → %s（-%d 金币）" % [
		GameData.card_name(id), lv,
		fmt(float(GameData.card(id).get("power", 0.0))), fmt(hero_card_power(id)), cost])
	save_game()
	shop_changed.emit()
	changed.emit()
	return true


# =====================================================================
# 装备巢 —— ⚠️ v1.1：**每个武将各自一个**（原来是全局共用 5 格，用户纠错）
#   用户原话：「装备巢搞错了，装备是每个武将都有」「士兵没有装备巢」。
#   部位仍靠技能树「装备槽」全局解锁（0→5），**每将按同一份解锁进度**各开自己的格子。
#   规则：① 只有「武将」有装备巢（士兵/装备/城池/建筑都没有；主角 I01 也没有）
#         ② 一个部位一件，换部位 = 自动换
#         ③ 一件装备**同时只能挂在一个武将身上**（挂给别人 = 自动从旧人身上摘）
#         ④ 只有**上阵**的武将，它身上的装备才计入战力（见 equip_mods()）
# =====================================================================
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
	return int(ceil(float(GameData.region(idx).get("total_hp", 0)) / dmg))


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
	var s := int(upgrade_value("stamina"))
	s += int(bonus["stamina_flat"])                 # 演武场：耐力上限 +5
	var mods := active_mods()
	s += int(mods["stamina_flat"])                  # 装备/武将 体力上限 +N
	s += int(mods["extra_slaps"])                   # 每关额外 N 次点击
	s += int(round(float(s) * float(mods["stamina_pct"]) / 100.0))
	if bond_tier("魏线") >= 2:
		s += int(round(float(s) * 0.10))
	return maxi(1, s)


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
	return cleared_count() >= CITY_UNLOCK_AFTER


func city_unlock_text() -> String:
	if city_unlocked():
		return "已解锁"
	return "再克服 %d 处即解锁城建挂机" % (CITY_UNLOCK_AFTER - cleared_count())


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
	if not is_unlocked(idx):
		log_msg("「%s」尚未解锁。" % GameData.region(idx).get("name", "?"))
		return false
	if _is_cleared(idx):
		log_msg("「%s」已克服，敌人不会再刷新。" % GameData.region(idx).get("name", "?"))
		return false
	battle_region = idx
	_refresh_enemies()            # 未克服的区域：每次进场都满血重来（局内不持久）
	var r := GameData.region(idx)
	stamina_max = stamina_max_value()
	stamina = stamina_max
	combo = 0
	run_kills = 0
	run_damage = 0.0
	end_reason = ""
	in_battle = true
	last_battle_report = "第 %d 趟「%s」：%d 张牌　耐力 %d　轻拍 %.1f / 重拍 %.1f　约需 %d 拍" % [
		runs + 1, r.get("name", "?"), battle.size(), stamina,
		click_damage(), click_damage() * HEAVY_MULT, slaps_needed(idx)]
	log_msg(last_battle_report)
	changed.emit()
	return true


func _refresh_enemies() -> void:
	battle = []
	for e in GameData.enemies_by_region.get(battle_region, []):
		var hp := float(e["hp"])
		battle.append({
			"card_id": e["card_id"], "hp": hp, "hp_max": hp,
			"boss": bool(e["boss"]),
			"nx": 0.5, "ny": 0.5, "rot": 0.0,
		})
	_layout_table()
	battle_gen += 1


func _layout_table() -> void:
	# 把敌人摆成"随手甩在桌上的"样子：抖动的网格 + 随机旋转。
	# 抖动幅度按格子剩余空间给 —— 桌上只有两三张时，牌会摊得更开，别挤在中线一条。
	var n := battle.size()
	if n <= 0:
		return
	var aspect := 2.05
	var cols := maxi(1, int(ceil(sqrt(float(n) * aspect))))
	var rows := maxi(1, int(ceil(float(n) / float(cols))))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(battle_region) * 7919 + n * 104729
	var step_x := 0.88 / float(cols)
	var step_y := 0.88 / float(rows)
	for i in range(n):
		var col := i % cols
		var row := int(floor(float(i) / float(cols)))
		var base_x := 0.06 + step_x * (float(col) + 0.5)
		var base_y := 0.06 + step_y * (float(row) + 0.5)
		var jx := step_x * 0.34
		var jy := step_y * 0.34
		if rows <= 1:
			jy = 0.32        # 只有一行时纵向摊开，别全挤在中线一条上
		battle[i]["nx"] = clampf(base_x + rng.randf_range(-jx, jx), 0.03, 0.97)
		battle[i]["ny"] = clampf(base_y + rng.randf_range(-jy, jy), 0.04, 0.96)
		battle[i]["rot"] = rng.randf_range(-0.20, 0.20)   # 弧度，约 ±11.5°


func attack(i: int, heavy: bool = false) -> bool:
	## 拍击。heavy=false 是单击轻拍（×1.0，1 耐力），heavy=true 是拖拽划过（×2.5，2 耐力）。
	## 返回是否真的打中（供 UI 决定要不要播打击特效）。
	if not in_battle or i < 0 or i >= battle.size():
		return false
	if stamina <= 0 or battle[i]["hp"] <= 0.0:
		return false

	var dmg := click_damage()
	if heavy:
		dmg *= HEAVY_MULT
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

	battle[i]["hp"] -= dmg
	run_damage += dmg
	stamina -= (HEAVY_STAMINA if heavy else 1)
	last_slap = {"index": i, "heavy": heavy, "damage": dmg, "tag": tag}
	if tag != "":
		log_msg("%s%s　造成 %.0f 伤害" % ["重拍·" if heavy else "轻拍·", tag, dmg])

	if battle[i]["hp"] <= 0.0:
		_on_enemy_killed(i)

	if _all_cleared():
		_clear_region()
	elif stamina <= 0:
		settle_run()        # 耐力耗尽 -> 强制结算回大本营（不再原地重来）
	else:
		changed.emit()
	return true


func _all_cleared() -> bool:
	for e in battle:
		if e["hp"] > 0.0:
			return false
	return true


func _on_enemy_killed(i: int) -> void:
	var c := GameData.card(battle[i]["card_id"])
	var raw = c.get("gold_coef")
	var coef: float = 0.3 if raw == null else float(raw)
	if coef <= 0.0:
		coef = 0.3
	var reward: float = maxf(1.0, float(battle[i]["hp_max"]) * KILL_GOLD_COEF * coef * fortune_mult())
	gold += reward
	run_kills += 1


func _clear_region() -> void:
	var idx := battle_region
	region_state[idx] = "cleared"
	in_battle = false
	end_reason = "cleared"
	combo = 0
	runs += 1
	var r := GameData.region(idx)

	# 首通奖励：按区域总血量折算
	var clear_gold := int(float(r.get("total_hp", 0)) * CLEAR_GOLD_COEF * fortune_mult())
	gold += float(clear_gold)

	# 战利品：★★★ 及以上武将进入囚禁（可招降）
	var jailed := []
	for e in battle:
		var c := GameData.card(e["card_id"])
		if str(c.get("type", "")) == "武将" and bool(c.get("capturable", false)):
			captured.append(e["card_id"])
			jailed.append(str(c.get("name", "?")))

	_grant_affinity(idx)
	var had_city := city_unlocked()
	var got_cities := _backfill_cities()
	_recompute_bonus()

	var newly := []
	for n in r.get("unlocks", []):
		var rr := GameData.region(int(n))
		if rr.get("name", "") != "":
			newly.append(rr["name"])

	last_battle_report = "拍翻整桌！「%s」已克服　首通 %d 金币" % [r.get("name", "?"), clear_gold]
	if not got_cities.is_empty():
		last_battle_report += "　获得城池卡：" + _join(got_cities)
	if not had_city:
		last_battle_report += "　（再克服 %d 处解锁城建挂机）" % (CITY_UNLOCK_AFTER - cleared_count())
	elif city_slots(idx) > 0:
		last_battle_report += "　建筑槽位 %d" % city_slots(idx)
	if not newly.is_empty():
		last_battle_report += "　新解锁：" + _join(newly)
	if not jailed.is_empty():
		last_battle_report += "　囚禁：" + _join(jailed)
	log_msg(last_battle_report)
	save_game()
	map_changed.emit()
	shop_changed.emit()
	changed.emit()


func settle_run() -> void:
	## 耐力耗尽 -> 强制结算：本局战果折算成金币带走，桌子收掉，回大本营整备。
	## 未克服的区域下次进场依旧满血 —— 局内进度不持久，只有金币带得出去。
	if not in_battle:
		return
	var idx := battle_region
	var r := GameData.region(idx)
	var stipend := int(run_damage * SETTLE_GOLD_COEF) + SETTLE_GOLD_BASE
	gold += float(stipend)
	runs += 1
	var k := run_kills
	var d := run_damage
	in_battle = false
	end_reason = "settled"
	battle = []
	battle_gen += 1
	combo = 0
	last_settle = "第 %d 趟 · 「%s」　击倒 %d 张 · 打出 %s 伤害 → 收成 %d 金币。回大本营整备。" % [
		runs, r.get("name", "?"), k, fmt(d), stipend]
	last_battle_report = last_settle
	log_msg(last_settle)
	save_game()
	map_changed.emit()
	shop_changed.emit()
	changed.emit()


func retreat() -> void:
	## 玩家主动撤退：与耐力耗尽同样结算，已打出的战果不浪费。
	if in_battle:
		settle_run()


func leave_battle() -> void:
	in_battle = false
	battle = []
	battle_gen += 1
	changed.emit()


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
	return county_cleared(county)


func pack_price(i: int) -> int:
	var p: Dictionary = GameData.packs[i]
	var base := int(p.get("price", 100))
	var n := int(pack_bought.get(p.get("name", ""), 0))
	var price := base * pow(PACK_PRICE_GROWTH, n)
	var off: float = bonus["pack_price_pct"] + float(active_mods()["pack_pct"])
	return max(1, int(round(price * (1.0 - off / 100.0))))


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
	if total_packs % 10 == 0:
		var hi := _draw_high_star(i, 4)
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
	var max_star := int(p.get("max_star", 3))
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
	# 开局包刻意只给 ★1 士兵。
	# 理由：开局必须"一局打死几个、反复重开刷钱"，所以初始战力要可预测地低；
	# 运气好抽到一张 ★3 武将（战力 5.0）会让第一桌直接被两巴掌扇穿，节奏就没了。
	var pool := []
	for c in GameData.cards:
		if str(c.get("type", "")) == "士兵" and int(c.get("star", 0)) == 1:
			pool.append(c)
	if pool.is_empty():
		return _draw_pack_cards(0, count)
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
		var c := GameData.card(id)
		if c.get("type", "") in ["初始武将", "城池"]:
			continue
		if int(c.get("star", 0)) != star:
			continue
		for k in range(int(owned[id])):
			out.append(id)
	return out


func synth_cost(star: int) -> int:
	return int(SYNC_COST.get(star, 160))


func synthesize(star: int) -> String:
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
		if int(c.get("star", 0)) == star + 1 and c.get("type", "") in ["士兵", "武将", "装备", "建筑"]:
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
	var s := int(GameData.region(idx).get("slots", 1))
	if affinity_tier(region_route(idx)) >= 2:
		s += 1
	return s


func city_buildings(idx: int) -> Array:
	if not cities.has(idx):
		return []
	return cities[idx].get("buildings", [])


func city_levels(idx: int) -> Array:
	## 与 city_buildings 一一对应的等级数组（v0.9）。
	if not city_lv.has(idx):
		return []
	return city_lv[idx]


func _building_at(idx: int, slot: int) -> String:
	var arr := city_buildings(idx)
	if slot < 0 or slot >= arr.size():
		return ""
	return str(arr[slot])


func building_lv(idx: int, slot: int) -> int:
	var lv := city_levels(idx)
	if slot < 0 or slot >= lv.size():
		return 0
	return int(lv[slot])


func building_lv_maxed(idx: int, slot: int) -> bool:
	return building_lv(idx, slot) >= BUILDING_LV_MAX


func building_lv_cost(idx: int, slot: int) -> int:
	var b := _building_at(idx, slot)
	if b == "" or building_lv_maxed(idx, slot):
		return 0
	var st := int(GameData.building(b).get("star", 1))
	var base := float(BUILDING_LV_COST) * pow(1.6, float(maxi(0, st - 1)))
	return int(round(base * pow(BUILDING_LV_GROWTH, float(building_lv(idx, slot)))))


func building_output(idx: int, slot: int) -> float:
	## 单座建筑的当前产出（含自身等级）。
	var b := _building_at(idx, slot)
	if b == "":
		return 0.0
	var prod := float(GameData.building(b).get("prod", 0))
	return prod * (1.0 + float(building_lv(idx, slot)) * BUILDING_LV_STEP)


func upgrade_building(idx: int, slot: int) -> bool:
	if not city_unlocked() or not _is_cleared(idx):
		return false
	if building_lv_maxed(idx, slot):
		log_msg("这栋已强化到顶（Lv.%d）。" % BUILDING_LV_MAX)
		return false
	var cost := building_lv_cost(idx, slot)
	if gold < float(cost):
		log_msg("金币不足（强化需要 %d，现有 %d）" % [cost, int(gold)])
		return false
	gold -= float(cost)
	var lv := building_lv(idx, slot) + 1
	if not city_lv.has(idx):
		city_lv[idx] = []
	var arr: Array = city_lv[idx]
	while arr.size() < city_buildings(idx).size():
		arr.append(0)
	arr[slot] = lv
	log_msg("强化「%s」→ Lv.%d　产出 %s /小时（-%d 金币）" % [
		GameData.building(_building_at(idx, slot)).get("name", "?"), lv,
		fmt(building_output(idx, slot)), cost])
	save_game()
	shop_changed.emit()
	changed.emit()
	return true


func place_building(idx: int, building_id: String) -> void:
	if not city_unlocked():
		log_msg("城建尚未解锁：%s。" % city_unlock_text())
		return
	if not _is_cleared(idx):
		log_msg("该城池尚未克服。")
		return
	if int(owned.get(building_id, 0)) <= 0:
		log_msg("没有这张建筑卡。")
		return
	if city_buildings(idx).size() >= city_slots(idx):
		log_msg("「%s」的槽位已满。" % GameData.region(idx).get("name", "?"))
		return
	if not cities.has(idx):
		cities[idx] = {"buildings": []}
	cities[idx]["buildings"].append(building_id)
	if not city_lv.has(idx):
		city_lv[idx] = []
	var lvl: Array = city_lv[idx]
	lvl.append(0)
	owned[building_id] = int(owned[building_id]) - 1
	log_msg("在「%s」放置 %s（%s）" % [
		GameData.region(idx).get("name", "?"), GameData.building(building_id).get("name", "?"),
		GameData.building(building_id).get("effect", "")])
	_recompute_bonus()
	save_game()
	shop_changed.emit()
	changed.emit()


func remove_building(idx: int, slot_index: int) -> void:
	var arr := city_buildings(idx)
	if slot_index < 0 or slot_index >= arr.size():
		return
	var b: String = arr[slot_index]
	arr.remove_at(slot_index)
	if city_lv.has(idx):
		var lv: Array = city_lv[idx]
		if slot_index < lv.size():
			lv.remove_at(slot_index)
	owned[b] = int(owned.get(b, 0)) + 1
	_recompute_bonus()
	log_msg("拆除 %s，卡已回收（强化等级作废）。" % GameData.building(b).get("name", "?"))
	save_game()
	shop_changed.emit()
	changed.emit()


func gold_per_hour() -> float:
	var total := 0.0
	for idx in cities.keys():
		var arr := city_buildings(int(idx))
		for k in range(arr.size()):
			total += building_output(int(idx), k)
	if total <= 0.0:
		return 0.0
	var mult: float = 1.0 + float(bonus["building_output_pct"]) / 100.0
	if bond_tier("群雄线") >= 2:
		mult += 0.10
	if bond_tier("群雄线") >= 1:
		mult += 0.20
	return total * mult


# =====================================================================
# 建筑合成（v0.9）：3 张同星建筑 + 金币 -> 1 张高一星建筑
# =====================================================================
func building_star_pool(star: int) -> Array:
	var out := []
	for id in owned.keys():
		var c := GameData.card(id)
		if c.is_empty() or str(c.get("type", "")) != "建筑":
			continue
		if int(c.get("star", 0)) != star:
			continue
		for k in range(int(owned[id])):
			out.append(str(id))
	return out


func synth_building_cost(star: int) -> int:
	return int(round(float(SYNC_COST.get(star, 160)) * 1.5))


func synth_buildings(star: int) -> String:
	## 只吃建筑卡：3 张同星建筑 -> 1 张高一星建筑。
	if star >= 6:
		log_msg("★6 已是最高的建筑。")
		return ""
	var cands := building_star_pool(star)
	if cands.size() < 3:
		log_msg("★%d 建筑不足 3 张（现有 %d）。" % [star, cands.size()])
		return ""
	var cost := synth_building_cost(star)
	if gold < float(cost):
		log_msg("金币不足（建筑合成需要 %d）" % cost)
		return ""
	gold -= float(cost)
	for k in range(3):
		var id: String = cands[k]
		owned[id] = int(owned[id]) - 1
		if int(owned[id]) <= 0:
			owned.erase(id)
	var pool := []
	for c in GameData.buildings:
		if int(c.get("star", 0)) == star + 1:
			pool.append(str(c.get("id", "")))
	var got := "B01"
	if not pool.is_empty():
		got = str(pool[randi() % pool.size()])
	owned[got] = int(owned.get(got, 0)) + 1
	log_msg("建筑合成：3 张 ★%d -> %s ★%d" % [star, GameData.card_name(got), star + 1])
	_recompute_bonus()
	save_game()
	shop_changed.emit()
	changed.emit()
	return got


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
	for idx in cities.keys():
		for b in cities[idx].get("buildings", []):
			var bd := GameData.building(b)
			var t: String = bd.get("effect_type", "none")
			if bonus.has(t):
				bonus[t] = float(bonus[t]) + float(bd.get("effect_value", 0.0))


# =====================================================================
# 存档
# =====================================================================
func save_game() -> void:
	if not SAVE_ENABLED:
		return                            # v1.0：开发期不落盘
	var data := {
		"gold": gold, "owned": owned, "captured": captured,
		"region_state": region_state, "cities": cities, "city_lv": city_lv,
		"affinity": affinity,
		"pack_bought": pack_bought, "total_packs": total_packs,
		"up": up, "carry": carry,
		"hero_equip": hero_equip, "hero_troops": hero_troops, "hero_lv": hero_lv,
		"runs": runs,
		"last_save": int(Time.get_unix_time_from_system()),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not SAVE_ENABLED:
		return false                      # v1.0：开发期不读档
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
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

	_recompute_bonus()

	# 离线结算
	var elapsed := float(Time.get_unix_time_from_system()) - float(d.get("last_save", 0))
	if elapsed > 60.0 and gold_per_hour() > 0.0:
		var eff := offline_efficiency()
		var hours: float = minf(elapsed / 3600.0, offline_cap_hours())
		var gain := gold_per_hour() * hours * eff
		gold += gain
		offline_report = "离线 %.1f 小时，建筑产出 %d 金币（效率 %.0f%%）" % [
			hours, int(gain), eff * 100.0]

	# 回到游戏就有一桌牌等着拍
	ensure_table()
	return true


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
