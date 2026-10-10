"""Build the design catalogue only; never modifies runtime card data."""
import json
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SOURCES = ["wei-proposals.json", "shu-proposals.json", "wu-proposals.json", "root-proposals.json"]
units = []
for source in SOURCES:
    units.extend(json.loads((HERE / source).read_text(encoding="utf-8-sig")))
by_id = {unit["id"]: unit for unit in units}
assert len(by_id) == len(units) == 83, "Duplicate or missing proposal"

def amend(card_id, **fields):
    by_id[card_id].update(fields)

amend("S09", role="首拍刀锋接口", skill_name="弩矢先发",
      effect="每次行动首拍附加0.25P刀锋。",
      rules="只在行动第一道完整拍击生成0.25P刀锋，不随追加拍击重复。与同段其他刀锋来源系数相加后再计算倍率；独立上阵或挂任意武将均作用全队。同种只能有一支有效出战编队，其余是仓库合成材料。",
      combo_ids=["G10", "G26", "G27"],
      combo_reason="弩手提供较大的首拍刀锋，徐晃加强重拍刀锋，张飞放大即时特殊，赵云还可复制同段合并刀锋。多段队更适合每拍生效的益州刀手，两种兵有不同取舍。",
      tags=["刀锋", "首拍", "低星接口"])
amend("S06", role="易伤刀锋接口", skill_name="山刀趁隙",
      effect="每拍对易伤目标，附加0.22P刀锋。",
      rules="每道完整或加权拍击生成伤害前检查目标是否有至少1层易伤；成立则按本段P生成0.22P刀锋，包括追加。首拍前施加的易伤可立即满足。独立上阵或挂任意武将全队生效，同种只有一支有效编队。没有易伤来源时技能休眠。",
      combo_ids=["G18", "G48", "G26"],
      combo_reason="糜芳先挂易伤，山越部曲用兵位提供刀源，魏延在刀属性层加强，张飞再乘即时特殊层。它的条件刀系数高于无条件益州刀手，需要为易伤入口留位置。",
      tags=["刀锋", "易伤条件", "低星接口", "追加继承"])
amend("G12", rules="斩杀条件在每道直接拍击开始时，按该段主目标生命比例记录；+100%加入该段刀属性增幅层，与徐晃等同层相加。追加各自重新检查自己的主目标；范围复制只取源头已经算好的最终值，不按副目标血线重算斩杀。翻牌奖励每牌一次，不按溢出伤害发奖。")
amend("G11", combo_ids=["G06", "G30", "G19"],
      combo_reason="李典确保破甲，韩玄提供即时火并每三行动点燃；满宠让已有燃烧对破甲目标翻倍，廖化将燃烧再接为每拍刀锋。程普只扩散即时火，不传播燃烧。")
amend("G27", combo_ids=["G28", "G26", "S10"],
      combo_reason="关羽让赵云生成两道完整刀锋，张飞先放大源伤害再穿透；益州刀手每拍的小刀锋也进入同一个穿透包。若改用关平补刀，还须配置糜芳等易伤来源。")
amend("S18", combo_ids=["G30", "G19", "G11"],
      combo_reason="韩玄每三行动点燃，满宠同次行动开始先施破甲，燃烧即可翻倍；廖化与五溪蛮兵从仍在燃烧的下一拍/下一行动获得刀锋和首拍普通增幅。另加李典或枪兵可更早铺甲，但不是满宠发动的必需条件。")
amend("S13", combo_ids=["G06", "S02", "G14"],
      combo_reason="李典首拍前加破甲，南阳枪兵首拍后再加一层，数次行动即可到3层；魏武卒与许褚在普通增幅层相加。文聘可替代部分叠甲，但必须另有朱灵等雷源。")
amend("S16", combo_ids=["G42", "G52", "S07"],
      combo_reason="周泰与虎士加强普通部分，江东水卒明确提供轻拍风源，吕蒙才能把普通增幅接给风包。周泰的有限回收可能暂时退出低耐力条件，下一行动重新判断。")
amend("S01", combo_ids=["G08", "G22", "G18"],
      combo_reason="多一点耐力可多推进一次于禁、赵累的行动计数；糜芳先挂易伤，让赵累的每四行动补给有明确条件。乡勇不免费触发技能，只增加可付费行动次数。")
amend("G55", rules="先完成行动前状态刷新、施加与转换，再以首拍主目标快照统计排除本卡后的实际直接属性来源种类；轻重、血线、易伤、燃烧等条件都先判断。只数实际可生成的火雷风刀，不数纯倍率、复制或DOT；为0或1种时，本行动各完整/加权拍击附0.15P刀锋。结果锁定整次行动，后段条件改变不回算；自身刀锋不反向取消条件，也不计入下一行动的原始来源。原有刀为唯一属性时与其相加。")
amend("N01", rules="关银屏尚不在现有卡池，N01为策划临时ID，实施时登记正式ID。每段生成一份0.6P火源，追加先按权重确定本段P；自动拍先对行动基准施加挂机系数。火伤不自动形成燃烧，需配王甫或韩玄等明确点燃技能。")
amend("G30", rules="每道拍击生成0.35P火源，同类相加后形成直接火包，追加按段权重继承。每第3次有效行动仅首拍在火伤实际命中且目标存活后挂1层燃烧：每秒0.1P，持续3秒，P取该首拍快照；张飞、吕蒙及其他仅即时属性增幅不计入DOT。全队燃烧共享3层上限，第4层替换剩余时间最短的一层。追加不增加行动计数，DOT不触发拍击词条、扩散和追击。")
amend("G20", rules="普通增幅层首拍+25%，完整追加合计+50%，不是1.25×1.25。基础+25%也适用于甘宁等普通衍生伤害；追加专属+25%只适用于完整/加权追加拍击段，不适用于甘宁。先按段权重确定P；不增加火雷风刀、燃烧、收益和拍击次数。")
amend("G14", rules="手动重拍行动的普通伤害+100%，与其他普通百分比同层相加，不再独立乘2。包含本行动首拍、追加及甘宁普通衍生伤害；不改变即时属性、复制或燃烧。轻拍及目前规划的自动轻拍不满足重拍条件。")
amend("G32", rules="自动轻拍行动的普通伤害+35%，包括首拍、追加和甘宁普通衍生包；同普通增幅层相加。不改变手动伤害、自动频率、即时属性或建筑收益。尚未解锁自动拍时技能休眠，界面须说明。")
amend("G49", rules="行动开始安排最多2个不同存活普通副目标，按剩余生命从低到高选择，排除主目标与首领；主目标全部拍击段结束后各结算0.5P普通伤害。沿用本行动输入倍率、暴击和挂机系数；接受全普通增幅、轻重/自动/耐力条件增幅，并按副目标自身血线、易伤、破甲、燃烧判断普通条件。不接受仅首拍、仅追加、青州兵后续拍击段的限定加成。不属于完整拍击，不生成附属属性、不转换为火风、不触发任何拍击或状态词条。关羽不复制这次行动级安排；预定目标提前死亡则取消，无副目标不回流主目标。")
amend("G42", effect="普通伤害+25%；每累计拍翻3张敌牌，回收1点耐力。")
amend("G47", rules="每道直接拍击开始按该段主目标生命比例判断；不低于70%时，普通增幅层+100%，同层相加。即时属性不直接吃本词条，吕蒙可另作转换。追加重新检查自己的目标；甘宁普通副包按各副目标命中前生命判定。此血线增幅本身不排除首领，甘宁选目标仍须遵守只能选普通副牌的限制。只按真实伤害发工资，不按理论溢出发奖。")
amend("G16", rules="首领指本桌BOSS标记，不是血最多的普通牌；每拍1P刀锋始终有效，追加继承。对首领的普通增幅+100%进入普通层，与许褚等相加；不直接增加属性层，不自带破甲，额外配置李典等可增强普通攻坚部分。")
amend("G01", rules="普通与风包分别计算，追加继承风源。先以行动基准A乘段权重确定本段P，再附0.35P风；权重0.5的追加对应本段P=0.5A，风源为0.175A。不额外创造拍击、范围或行动。")
amend("G08", rules="有效行动含自动轻拍，每桌从0计；追加不算新行动。第3、6、9次等行动开始安排一段权重0.4的完整拍击，本段P=0.4A，可生成普通、即时属性并施命中状态。行动开始只规划一次，不递归生成其他追加；与关羽、张辽等贡献的段相加，换桌重置计数。")
amend("G13", rules="行动开始增加两段，权重各0.5，本段P=0.5A，随后生成完整普通与即时属性，可施命中状态，不递归追加。追加优先选首拍之外两张不同存活普通牌；无合适普通牌回存活原目标，仅剩首领则打首领，原目标已翻则按最低生命选存活目标。与其他追加贡献相加；首拍加本卡两段总权重2，不代表每段都用完整A。")
amend("G28", rules="行动开始贡献一段权重1的完整追加，本段P=A；轻拍、重拍和自动轻拍均生效。整次行动只扣原操作一次耐力，追加不扣、不算新行动，不再触发行动级追加生成器。原目标存活继续打同牌，已翻则按统一规则重选。追加继承每拍来源与增幅，不再次发动首拍/每行动一次的技能。")
amend("S21", rules="只作用完整/加权追加拍击段，不产生追加，首拍不生效。普通增幅层+50%，另按本段P生成0.3P刀锋；权重0.5时本段P=0.5A，刀锋为0.15A，权重0.4时为0.12A。与其他刀源合并后计算倍率，不按兵张数叠加。")
amend("G49", effect="每次行动，另追击2张普通牌，各造成行动基准A的50%普通伤害。")
by_id["G49"]["rules"] = by_id["G49"]["rules"].replace("各结算0.5P普通伤害", "各结算0.5A普通伤害；A为本行动首拍基准，不读取最后追加段的P")
amend("G52", effect="火、雷、风、刀锋即时伤害+100%；普通增伤同时等值强化这四种属性。")
by_id["G52"]["rules"] = by_id["G52"]["rules"].replace("百分比总和B", "百分比总和U").replace("100%+B", "100%+U").replace("B仅包含", "U仅包含")

# Normalize terminology and the final one-active-squad rule in published records.
replace_terms = {"刀刃": "刀锋", "刀伤": "刀锋伤害", "開始": "开始", "行动开_始": "行动开始"}
replace_soldiers = {
    "重复兵仍各贡献基础战力": "重复兵留在仓库作为合成材料，不额外出战",
    "重复只贡献战力": "重复兵留在仓库作为合成材料，不额外出战",
    "多张仅贡献战力": "重复兵留在仓库作为合成材料，不额外出战",
    "多张仅战力": "重复兵留在仓库作为合成材料，不额外出战",
    "多张只战力": "重复兵留在仓库作为合成材料，不额外出战",
    "仅贡献战力": "重复兵留在仓库作为合成材料，不额外出战",
    "重复只贡献战力。": "重复兵仅作合成材料。",
}
for unit in units:
    for field in ("role", "skill_name", "effect", "rules", "combo_reason", "tags"):
        if isinstance(unit[field], list):
            unit[field] = [s.replace("刀刃", "刀锋") for s in unit[field]]
        else:
            value = unit[field]
            for old, new in replace_terms.items():
                value = value.replace(old, new)
            value = value.replace("伤害害", "伤害")
            if unit["type"] == "士兵":
                for old, new in replace_soldiers.items():
                    value = value.replace(old, new)
            unit[field] = value
    if unit["type"] == "士兵":
        unit["rules"] += " 全队同名仅允许一支有效编队出战；兵位转移移动原编队，仓库重复兵不计战力、词条或兵种。"
    unit["scope"] = "拟新增" if unit["id"] == "N01" else "现有"
    if unit["type"] == "武将":
        unit["power"] = {2: 1, 3: 2.5, 4: 5, 5: 9, 6: 15}[unit["star"]]
    elif unit["type"] == "士兵":
        unit["power"] = {1: 0.2, 2: 0.6, 3: 1.2, 4: 2.4}[unit["star"]]
    else:
        unit["power"] = 1

native = json.loads((ROOT / "data/cards.json").read_text(encoding="utf-8-sig"))
native_combat = {c["id"]: c for c in native if c["type"] in ("武将", "士兵", "初始武将")}
assert len(native_combat) == 82
assert set(by_id) == set(native_combat) | {"N01"}
for card_id, card in native_combat.items():
    for field in ("name", "type", "star", "faction"):
        assert by_id[card_id][field] == card[field], (card_id, field)
for unit in units:
    for field in ("role", "skill_name", "effect", "rules", "combo_reason", "tags"):
        assert unit[field], (unit["id"], field)
    assert 2 <= len(unit["combo_ids"]) <= 3
    assert len(set(unit["combo_ids"])) == len(unit["combo_ids"])
    assert all(c in by_id and c != unit["id"] for c in unit["combo_ids"])

type_order = {"初始武将": 0, "武将": 1, "士兵": 2}
units.sort(key=lambda u: (type_order[u["type"]], u["star"], u["id"]))
catalog = {
    "version": "v2.2", "date": "2026-10-06", "status": "目标策划稿，未接入游戏",
    "counts": {"heroes": 57, "soldiers": 24, "protagonists": 1, "new_units": 1},
    "rarity_counts": {
        "heroes": dict(sorted(Counter(c["star"] for c in units if c["type"] == "武将" and c["scope"] == "现有").items())),
        "soldiers": dict(sorted(Counter(c["star"] for c in units if c["type"] == "士兵").items())),
    },
    "units": units,
}
(HERE / "all-units.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(HERE / "catalog-data.js").write_text("window.PAAN_ROSTER = " + json.dumps(catalog, ensure_ascii=False, indent=2) + ";\n", encoding="utf-8")

body = (HERE / "方案正文.md").read_text(encoding="utf-8")
sections = [body, "\n## 14. 全卡效果总册\n\n以下覆盖全部现有武将与士兵；主角和拟新增关银屏另列。每条的P均采用该拍击段基准，具体行动/首拍限制优先于‘每拍’通则。搭配是可拆分的建议，不是隐藏套装；需要火、易伤或破甲的条件已写明。\n"]
groups = [
    ("14.1 常驻主角", [c for c in units if c["type"] == "初始武将"]),
]
for star in range(1, 7):
    group = [c for c in units if c["type"] == "武将" and c["star"] == star and c["scope"] == "现有"]
    if group:
        groups.append((f"14.2.{star} 现有★{star}武将（{len(group)}名）", group))
groups.append(("14.3 拟新增武将：关银屏", [by_id["N01"]]))
for star in range(1, 5):
    group = [c for c in units if c["type"] == "士兵" and c["star"] == star]
    groups.append((f"14.4.{star} ★{star}士兵（{len(group)}种）", group))
for heading, group in groups:
    sections.append(f"\n### {heading}\n")
    for unit in group:
        label = f"{unit['name']} · ★{unit['star']} · {unit['faction']} · {unit['id']}"
        companions = "、".join(f"{by_id[c]['name']}（{c}）" for c in unit["combo_ids"])
        sections.append(f"\n#### {label}\n\n**定位：**{unit['role']}　**技能：**{unit['skill_name']}　**原版基础战力：**{unit['power']:g}\n\n**卡面效果：**{unit['effect']}\n\n**判定与叠加：**{unit['rules']}\n\n**建议搭配：**{companions}。{unit['combo_reason']}\n")
sections.append("\n## 15. 交付核对与策划边界\n\n本册以当前工程 `data/cards.json` 的卡名、ID、阵营和星级为核对基准，覆盖57名现有武将、24种士兵及1张主角卡，共82条现有战斗单位；另列1名拟新增★4关银屏，共83条设计记录。未改变现有卡池数据。每条均填写定位、技能、效果、判定、搭配和机制标签，搭配引用已校验存在。\n\n高星与低星的关系以本册的星级预算、规则层与组合样例为准；全部系数是起测值，需要按第13节试玩与仿真调参。范围上限、回收上限与挂机系数同时生效，不能挑其中一个算收益。旧版12将演示保留为历史草案；本册中关银屏为0.6P火源、朱灵为0.35P雷源，覆盖旧稿的1P示例系数。\n\n阅读页与JSON用于策划检索、对照和后续数据录入；它们没有替换游戏的独立武将练级、现有六将联动与原数值。实施应先改上游卡池生成器，再生成游戏数据，并完成存档迁移。\n")
final_path = HERE / "拍案三国_全武将与士兵星级效果构筑策划案.md"
final_path.write_text("\n".join(sections), encoding="utf-8")
print(json.dumps({"validated_existing": len(native_combat), "designed_records": len(units), "rarity_counts": catalog["rarity_counts"], "document": str(final_path)}, ensure_ascii=False))
