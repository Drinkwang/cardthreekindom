"""Read-only baseline/candidate economy model; does not run Godot or touch save files.

Per-target light/heavy budgets use finite dynamic programming and clipped damage.
No crit, old hero levels, equipment, complex elemental triggers, or animation timings.
Results are best-allocation bounds, not measured new-player play time.
"""
from functools import lru_cache
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
CARD = {x['id']: x for x in json.loads((ROOT/'data/cards.json').read_text(encoding='utf-8'))}
ORIGINAL = json.loads((ROOT/'data/enemies.json').read_text(encoding='utf-8'))['1']
TOTAL = sum(x['hp'] for x in ORIGINAL)


def table(total_hp, layout='original'):
    if layout == 'three':
        hp = [total_hp*3/14, total_hp*4/14, total_hp*7/14]
        coef = [1., 1., 1.]
    elif layout == 'four':
        hp = [total_hp*.12, total_hp*.16, total_hp*.28, total_hp*.44]
        coef = [1., 1., 1., 1.]
    else:
        count = int(layout.removeprefix('count')) if layout.startswith('count') else len(ORIGINAL)
        raw = ORIGINAL[:count]
        divisor = sum(x['hp'] for x in raw)
        hp = [x['hp']/divisor*total_hp for x in raw]
        coef = [1.]*len(raw)
    return tuple(hp), tuple(coef)


@lru_cache(maxsize=25000)
def battle(total_hp, damage, stamina, layout='original', first_reward=0.):
    hp, coefs = table(total_hp, layout)
    # cost -> (score, actual_damage, killed, kill_gold). Always clip to remaining HP.
    states = {(0,False): (0., 0., 0, 0.)}
    for health, coef in zip(hp, coefs):
        next_states = {}
        for (spent,had_kill), previous in states.items():
            for cost in range(stamina-spent+1):
                # All-heavy is 25% more damage per stamina; odd remainder is light.
                offered = damage*(2.5*(cost//2)+(cost%2))
                actual = min(health, offered)
                killed = int(actual >= health-1e-7)
                kill_gold = health*.12*coef*killed
                score = previous[0]+actual*.45+kill_gold+(first_reward if killed and not had_kill else 0.)
                result = (score, previous[1]+actual, previous[2]+killed, previous[3]+kill_gold)
                key=(spent+cost,had_kill or bool(killed))
                if score > next_states.get(key, (-1.,))[0]:
                    next_states[key] = result
        states = next_states
    best = max(states.items(), key=lambda s:s[1][0]+(total_hp*.2 if s[1][2]==len(hp) else 0.))
    (spent,_), (score, actual, killed, kill_gold) = best
    cleared = killed == len(hp)
    return {'actual':round(actual,4), 'kills':killed, 'clear':cleared, 'spent':spent,
            'income':round(score+(total_hp*.2 if cleared else 0.),4)}


def b(power_lv, granted):
    # Starter three unique soldiers: .2 each; protagonist fixed .3.
    if granted == 0:
        deck, passive = .9, 0.
    elif granted == 1:
        deck, passive = .3+1+.4, .50  # Lei Fei fixed two-star starter partner.
    else:
        deck, passive = .3+1+2.5+.2, .80  # Lei Fei and Zhu Ling, before final reward.
    # Mirrors original multiplier placement: passive adds to upgrade multiplier.
    return round(1+deck*(1.12**power_lv+passive), 7)


def simulate(layout='original', first_flip_reward=0., grants=False, stage_hp=None):
    stages = stage_hp or [14,28,48,82,132]
    lv = {'power':0,'stamina':0}
    gold = 0.; rows=[]; table_no=0; granted=0; bought_auto=False; first_flip=False
    for attempt in range(1,201):
        h=stages[table_no]
        damage=b(lv['power'],granted)
        active_layout = layout if table_no==0 else ('count'+str([3,3,4,5,6][table_no]) if grants else 'original')
        outcome=battle(h,damage,6+lv['stamina'],active_layout,first_flip_reward if not first_flip else 0.)
        gold += outcome['income']
        if not first_flip and outcome['kills']:
            first_flip=True
        purchases=[]
        won=outcome['clear']
        if won:
            table_no+=1
            if grants and table_no==1: granted=1
            if grants and table_no==3: granted=2
            if table_no==len(stages): gold += h*.25
        if table_no>=2 and not bought_auto and gold>=60:
            gold-=60; bought_auto=True; purchases.append('自动训练60')
        if table_no<len(stages):
            target=stages[table_no]
            while True:
                target_layout=layout if table_no==0 else ('count'+str([3,3,4,5,6][table_no]) if grants else 'original')
                current=battle(target,b(lv['power'],granted),6+lv['stamina'],target_layout)['actual']
                candidates=[]
                for key in lv:
                    cost=round(18*1.2**lv[key])
                    if cost>gold: continue
                    np=lv['power']+(key=='power'); ns=lv['stamina']+(key=='stamina')
                    future=battle(target,b(np,granted),6+ns,target_layout)
                    # Reward a new clear, otherwise improve actual damage per cost.
                    score=(future['actual']-current)/cost + (1 if future['clear'] else 0)
                    candidates.append((score,key,cost))
                if not candidates:break
                _,key,cost=max(candidates)
                gold-=cost;lv[key]+=1;purchases.append(f'{key}={lv[key]}(-{cost})')
        rows.append({'try':attempt,'table':min(table_no+int(not won),5),'hp':h,
                     'damage':round(damage,2),'stamina':6+lv['stamina'],
                     'actual':round(outcome['actual'],2),'kills':outcome['kills'],
                     'income':round(outcome['income'],2),'clear':won,
                     'gold':round(gold,2),'buy':' / '.join(purchases),'granted':granted})
        if table_no==len(stages):break
    return {'attempts':len(rows),'cleared':table_no,'levels':lv,'auto_bought':bought_auto,'rows':rows}


if __name__=='__main__':
    outputs={
        '六牌_无确定卡奖励':simulate(stage_hp=[24,42,68,102,156]),
        '首桌三牌_首次翻牌8金_无确定卡奖励':simulate('three',8,False),
        '首桌三牌_首次翻牌8金_第1与3桌确定双将':simulate('three',8,True),
    }
    import sys
    if hasattr(sys.stdout,'reconfigure'): sys.stdout.reconfigure(encoding='utf-8')
    for name, result in outputs.items():
        print(name, json.dumps({k:v for k,v in result.items() if k!='rows'},ensure_ascii=False))
        print('milestones',json.dumps([row for row in result['rows'] if row['clear'] or row['try']<=5 or '自动' in row['buy']],ensure_ascii=False))
