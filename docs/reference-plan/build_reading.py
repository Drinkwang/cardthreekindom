from __future__ import annotations

import hashlib
import html
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
DOC = OUT / '拍案三国_图片基准完整策划案.md'
SOURCES = ('cards', 'regions', 'routes', 'packs', 'buildings', 'enemies')
DATA = {n: json.loads((ROOT / 'data' / (n + '.json')).read_text(encoding='utf-8')) for n in SOURCES}
CARDS = {c['id']: c for c in DATA['cards']}
BUILDINGS = {b['id']: b for b in DATA['buildings']}


def cell(value):
    return str(value if value is not None else '—').replace('|', '／').replace('\n', ' ')


def table(headers, rows):
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join(['---'] * len(headers)) + ' |'] + ['| ' + ' | '.join(cell(x) for x in row) + ' |' for row in rows])


def appendices():
    sections = ['## 附录 A｜全量卡牌目录（169 张）', '本表直接读取当前卡池，保留名称、星级、阵营和效果原文。效果原文用于核对，正式效果是否接入仍需检查；I01 的数据战力为 1.0，当前运行规则使用主角底子 0.3。建筑表中的产出来自建筑数据。']
    kinds = ['初始武将', '武将', '士兵', '装备', '城池', '建筑']
    for i, kind in enumerate(kinds, 1):
        rows = []
        entries = [c for c in DATA['cards'] if c['type'] == kind]
        for c in entries:
            value = c.get('power', '—')
            if kind == '建筑':
                value = str(BUILDINGS.get(c['id'], {}).get('prod', 0)) + ' 金币/小时'
            if kind == '城池':
                region = next((r for r in DATA['regions'] if r['city'] == c['name']), None)
                value = str(region['slots']) + ' 基础槽' if region else '—'
            rows.append([c['id'], c['name'], '★' * c['star'], c['faction'], c.get('subtype', '—'), value, c.get('effect', '—')])
        sections += [f'### A.{i} {kind} · {len(entries)} 张', table(['ID', '名称', '星级', '阵营', '子类', '数据战力/产出/槽位', '现有效果原文'], rows)]
    sections += ['## 附录 B｜区域与敌人快照（21 区域）', '以下为当前基线；江陵的三门槛取自状态代码。总生命已与各桌敌人生命之和核对，21 桌全部一致。终章目标调整见第 09.3 节，此表不提前覆盖现有数据。']
    rows = []
    for r in DATA['regions']:
        pre = '夷陵 + 公安 + 泉陵（全部）' if r['idx'] == 21 else ' / '.join(next(x['name'] for x in DATA['regions'] if x['idx'] == p) for p in r.get('unlocked_by', [])) or '开局'
        rows.append([r['idx'], r['name'], r['county'], r['route'], r['enemy_count'], format(r['total_hp'], ','), r['slots'], pre])
    sections.append(table(['区域', '城名', '郡', '路线', '敌牌', '总生命', '基础槽', '前置（普通区域满足任一）'], rows))
    for r in DATA['regions']:
        enemies = DATA['enemies'][str(r['idx'])]
        row = []
        for i, e in enumerate(enemies, 1):
            c = CARDS[e['card_id']]
            row.append([i, e['card_id'], c['name'], '★' * c['star'], format(e['hp'], ','), '关底' if e.get('boss') else '普通'])
        sections += [f"### B.{r['idx']:02d} {r['name']} · 当前敌牌明细", table(['槽位', '卡 ID', '名称', '星级', '生命', '身份'], row)]
    sections += ['## 附录 C｜九卡包数据快照与规则差异', '本表保留数据文案，和第 10.2 节的目标规则区分。当前执行按郡解锁、跨包每 10 包尝试四星，目标规则是按郡说明、每包独立周期、单独保底池。']
    rows = [[p['name'], p['scope'], p['price'], p['cards'], f"{p['min_star']}—{p['max_star']}", p['unlock'], p['pity']] for p in DATA['packs']]
    sections.append(table(['卡包', '范围', '基础价', '张数', '普通星级', '现有解锁文案', '现有保底文案'], rows))
    sections += ['### C.1 需落实的规则检查', '独立保底池须包含对应下限的候选卡；所有常规与保底候选都排除初始武将与城池；购买次数仅在购买成功后递增，折扣与 ×2.4 涨价共同反映到显示价格；新字段和旧购买计数按第 18.3 节迁移。', '### C.2 快照完整性', '卡牌 169、建筑 30、区域 21、路线 4、卡包 9，敌人表覆盖全部 21 区域；各桌生命求和等于区域总生命，敌牌数量等于区域表，所有引用卡 ID 存在。正式修改后应重新生成附录与快照。']
    return '\n\n'.join(sections) + '\n'


def inline(text):
    stash = []

    def reserve(value):
        stash.append(value)
        return f'@@INLINE{len(stash) - 1}@@'

    text = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', lambda m: reserve('<figure class="reference"><a href="reference.png" target="_blank" rel="noopener"><img src="reference.png" width="1586" height="992" alt="' + html.escape(m[1], quote=True) + '"></a><figcaption>美术基准原图 · 1586 × 992 · 点击查看原尺寸</figcaption></figure>'), text)
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', lambda m: reserve('<a href="' + html.escape(m[2], quote=True) + '">' + html.escape(m[1]) + '</a>'), text)
    text = html.escape(text)
    text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
    for i, value in enumerate(stash):
        text = text.replace(f'@@INLINE{i}@@', value)
    return text


def render_md(text):
    lines = text.splitlines()
    out = []
    toc = []
    i = 0
    while i < len(lines):
        s = lines[i]
        if not s.strip():
            i += 1
            continue
        heading = re.match(r'^(#{1,3}) (.+)$', s)
        if heading:
            level, label = len(heading[1]), heading[2]
            if level == 2:
                key = 's-' + (re.match(r'\d+', label)[0] if re.match(r'\d+', label) else re.search(r'附录 ([ABC])', label)[1].lower())
                toc.append((key, label))
                out.append(f'<h2 id="{key}">{inline(label)}</h2>')
            else:
                out.append(f'<h{level}>{inline(label)}</h{level}>')
            i += 1
            continue
        if s.startswith('| '):
            rows = []
            while i < len(lines) and lines[i].startswith('| '):
                rows.append([x.strip() for x in lines[i].strip().strip('|').split('|')])
                i += 1
            body = '<div class="table-wrap"><table><thead><tr>' + ''.join('<th>' + inline(c) + '</th>' for c in rows[0]) + '</tr></thead><tbody>'
            for row in rows[2:]:
                body += '<tr>' + ''.join('<td>' + inline(c) + '</td>' for c in row) + '</tr>'
            out.append(body + '</tbody></table></div>')
            continue
        if re.match(r'^\d+\. ', s):
            items = []
            while i < len(lines) and re.match(r'^\d+\. ', lines[i]):
                items.append(re.sub(r'^\d+\. ', '', lines[i]))
                i += 1
            out.append('<ol>' + ''.join('<li>' + inline(c) + '</li>' for c in items) + '</ol>')
            continue
        if s.startswith('!['):
            out.append(inline(s))
            i += 1
            continue
        parts = []
        while i < len(lines) and lines[i].strip() and not lines[i].startswith(('#', '| ', '![')) and not re.match(r'^\d+\. ', lines[i]):
            parts.append(inline(lines[i].rstrip()) + ('<br>' if lines[i].endswith('  ') else ' '))
            i += 1
        out.append('<p>' + ''.join(parts).strip() + '</p>')
    return '\n'.join(out), toc


STYLE = '''
:root{--ink:#292015;--red:#9d2f25;--paper:#f8f3e7;--line:#d9cbb3;--muted:#776651;--gold:#b98d42}*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:34px}body{margin:0;background:#e8dfcc;color:var(--ink);font-family:"Microsoft YaHei","PingFang SC",sans-serif;font-size:16px;line-height:1.85}a{color:var(--red);text-underline-offset:4px}button,input{font:inherit}button,a.button{cursor:pointer;border:1px solid #bbaa8a;color:var(--ink);background:#f4ead6;border-radius:4px;padding:8px 12px;text-decoration:none;font-size:13px;line-height:1.4}button:hover,a.button:hover{border-color:var(--red);background:#eedfc2}button:focus-visible,a:focus-visible,input:focus-visible{outline:3px solid #b98d42;outline-offset:3px}aside{position:fixed;left:0;top:0;bottom:0;width:276px;background:#f1e7d1;border-right:1px solid #ccb998;display:flex;flex-direction:column;padding:28px 20px 0;z-index:5}.seal{font-family:SimSun,"Songti SC",serif;color:#f8ebd4;background:var(--red);padding:6px 12px;border:2px solid #e2c4a1;box-shadow:0 0 0 2px var(--red);font-size:26px;letter-spacing:3px;display:inline-block;line-height:1.4;transform:rotate(-1deg)}.edition{font-size:12px;color:var(--muted);margin:14px 0 18px;letter-spacing:1px}.search-label{font-size:12px;font-weight:700;display:block;margin-bottom:6px}#query{width:100%;padding:10px 12px;border:1px solid #bcab8e;border-radius:3px;background:#fff9ed;font-size:14px;color:var(--ink)}.search-controls{display:flex;gap:6px;margin-top:8px;align-items:center}.search-controls button{padding:5px 9px}#match-count{font-size:11px;color:var(--muted);min-height:24px;margin:5px 0 10px}nav{overflow:auto;flex:1;padding:0 0 24px;scrollbar-width:thin}nav a{display:block;font-size:13px;line-height:1.5;padding:7px 9px;color:var(--muted);text-decoration:none;border-left:2px solid transparent;border-radius:0 3px 3px 0}nav a:hover{background:#e9dcc2;color:var(--ink)}nav a.active{background:#e4d3b7;color:var(--red);border-left-color:var(--red);font-weight:700}.aside-foot{padding:12px 0 16px;border-top:1px solid var(--line);font-size:11px;color:var(--muted)}main{margin-left:276px;padding:44px 48px 72px;max-width:1490px}article{max-width:1060px;margin:auto;background:var(--paper);padding:52px 58px;box-shadow:0 8px 35px #39241618;border:1px solid #d4c4a8;border-top:6px solid var(--red)}.toolbar{max-width:1060px;margin:0 auto 18px;display:flex;gap:10px;align-items:center;justify-content:space-between}.toolbar .buttons{display:flex;gap:8px}.toolbar small{color:var(--muted);font-size:12px}h1,h2,h3{font-family:SimSun,"Songti SC","Noto Serif CJK SC",serif;color:var(--ink)}h1{font-size:42px;line-height:1.35;margin:0 0 20px;letter-spacing:1px}h2{font-size:28px;line-height:1.5;margin:72px 0 25px;padding:12px 0 15px;border-top:1px solid var(--line);border-bottom:2px solid var(--red);scroll-margin-top:28px}h3{font-size:21px;line-height:1.5;margin:36px 0 14px}p{margin:14px 0 20px}strong{font-weight:700;color:#762e21}ol{padding-left:26px}li{margin:10px 0;padding-left:5px}.reference{margin:30px 0 24px;border:1px solid #b6a27d;padding:7px;background:#e9dbbd;box-shadow:0 5px 15px #39241618}.reference img{display:block;width:100%;height:auto}.reference figcaption{text-align:center;font-size:12px;color:var(--muted);margin:8px 0 2px}.table-wrap{overflow:auto;margin:20px 0 28px;border:1px solid var(--line);border-radius:3px;scrollbar-width:thin}table{border-collapse:collapse;width:100%;font-size:13px;line-height:1.7;min-width:580px}th{background:#eaddc3;font-weight:700;text-align:left;color:#4b3524}td,th{padding:12px 13px;border-right:1px solid #e1d5bf;border-bottom:1px solid #e1d5bf;vertical-align:top}td:first-child,th:first-child{white-space:nowrap}td:last-child,th:last-child{border-right:0}tbody tr:nth-child(even){background:#f3ebdb}tbody tr:last-child td{border-bottom:0}#s-a~.table-wrap table{min-width:860px}mark{background:#eed174;color:#342514;padding:0 2px;border-radius:2px}mark.current{background:#b23e2d;color:#fff5dd;box-shadow:0 0 0 3px #b23e2d55}.progress{position:fixed;left:276px;right:0;top:0;height:3px;background:#d8cbb5;z-index:9}.progress span{display:block;width:0;height:100%;background:var(--red)}.metrics{display:grid;grid-template-columns:repeat(4,1fr);margin:26px 0 32px;border:1px solid var(--line);background:#efe3ce}.metrics div{padding:15px 12px;text-align:center;border-right:1px solid var(--line)}.metrics div:last-child{border:0}.metrics b{font-family:Georgia,serif;color:var(--red);font-size:28px;line-height:1.2;display:block}.metrics span{display:block;font-size:12px;color:var(--muted);margin-top:4px}.reader-note{border-left:3px solid var(--red);padding:13px 18px;background:#efe3ce;font-size:14px;line-height:1.75}.doc-footer{font-size:12px;color:var(--muted);padding-top:22px;border-top:1px solid var(--line);margin-top:60px}.mobile-nav{display:none}footer a{color:var(--muted)}
@media(min-width:1600px){main{padding-left:90px;padding-right:90px}article{padding:60px 72px}}@media(max-width:1100px){aside{width:236px;padding:24px 16px 0}main{margin-left:236px;padding:30px 24px}.progress{left:236px}article{padding:36px 30px}h1{font-size:34px}h2{font-size:25px}}@media(max-width:760px){aside{position:relative;width:100%;padding:18px;bottom:auto;border-right:0;border-bottom:1px solid var(--line)}aside nav{display:none;max-height:50vh;margin-top:12px}aside.expanded nav{display:block}.edition{margin:10px 0}.search-controls{display:inline-flex;margin-right:10px}#match-count{display:inline-block;margin-bottom:0}.aside-foot{display:none}.mobile-nav{display:inline-block;position:absolute;top:24px;right:18px}main{margin:0;padding:20px 12px}.progress{left:0}article{padding:28px 20px}h1{font-size:30px}h2{font-size:23px;margin-top:48px}h3{font-size:19px}.toolbar{align-items:flex-start;flex-direction:column;gap:10px}.metrics{grid-template-columns:repeat(2,1fr)}.metrics div{border-bottom:1px solid var(--line)}.metrics div:nth-child(2){border-right:0}body{font-size:15px}table{font-size:12px}td,th{padding:10px}}
@media print{@page{size:A4;margin:16mm 15mm}html{scroll-behavior:auto}body{background:white;color:#221c16;font-size:10pt;line-height:1.7}aside,.toolbar,.progress{display:none}main{margin:0;max-width:none;padding:0}article{max-width:none;margin:0;padding:0;border:0;box-shadow:none;background:white}h1{font-size:25pt}h2{font-size:17pt;margin-top:24pt;break-after:avoid}h3{font-size:12pt;margin-top:16pt;break-after:avoid}.reference{break-inside:avoid;padding:3pt;margin:14pt 0;box-shadow:none}.metrics{break-inside:avoid}.metrics b{font-size:18pt}.table-wrap{overflow:visible;margin:12pt 0;max-height:none;border:0}table,#s-a~.table-wrap table{min-width:0;width:100%;font-size:8pt;line-height:1.5;table-layout:auto}td,th{padding:5pt;overflow-wrap:anywhere}td:first-child,th:first-child{white-space:normal}thead{display:table-header-group}tr{break-inside:avoid}a{color:inherit;text-decoration:none}mark,mark.current{background:none;color:inherit;box-shadow:none;padding:0}.reader-note{font-size:9pt}.doc-footer{font-size:8pt}}
'''

JS = '''
const sections=[...document.querySelectorAll('article h2')],links=[...document.querySelectorAll('nav a')],content=document.querySelector('article');
function setActive(id){links.forEach(a=>a.classList.toggle('active',a.hash==='#'+id))}
const observer=new IntersectionObserver(items=>{const visible=items.filter(x=>x.isIntersecting).sort((a,b)=>a.boundingClientRect.top-b.boundingClientRect.top);if(visible.length)setActive(visible[0].target.id)},{rootMargin:'-4% 0px -65% 0px',threshold:0});sections.forEach(x=>observer.observe(x));
document.querySelector('#print').addEventListener('click',()=>window.print());
document.querySelector('.mobile-nav').addEventListener('click',e=>{const open=document.querySelector('aside').classList.toggle('expanded');e.currentTarget.setAttribute('aria-expanded',String(open))});links.forEach(a=>a.addEventListener('click',()=>{document.querySelector('aside').classList.remove('expanded');document.querySelector('.mobile-nav').setAttribute('aria-expanded','false');setActive(a.hash.slice(1))}));
function progress(){const h=document.documentElement,space=h.scrollHeight-h.clientHeight;document.querySelector('.progress span').style.width=(space?100*h.scrollTop/space:0)+'%'}window.addEventListener('scroll',progress,{passive:true});window.addEventListener('resize',progress);progress();
let marks=[],selected=-1,timer;
function clearMarks(){content.querySelectorAll('mark').forEach(m=>m.replaceWith(document.createTextNode(m.textContent)));content.normalize();marks=[];selected=-1;document.querySelector('#match-count').textContent='';}
function search(){clearMarks();const term=document.querySelector('#query').value.trim().toLocaleLowerCase();if(!term)return;const walker=document.createTreeWalker(content,NodeFilter.SHOW_TEXT,{acceptNode:n=>n.parentElement.closest('script,style,button,mark')?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT}),nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);let total=0;for(const node of nodes){const raw=node.textContent,low=raw.toLocaleLowerCase();let pos=0,index,hits=[];while((index=low.indexOf(term,pos))!==-1){total++;if(marks.length<200){const m=document.createElement('mark');m.textContent=raw.slice(index,index+term.length);hits.push({at:index,node:m});marks.push(m);}pos=index+term.length;}if(hits.length){const frag=document.createDocumentFragment();let from=0;for(const hit of hits){frag.append(document.createTextNode(raw.slice(from,hit.at)),hit.node);from=hit.at+term.length;}frag.append(document.createTextNode(raw.slice(from)));node.replaceWith(frag);}}document.querySelector('#match-count').textContent=total?'找到 '+total+' 处'+(total>200?'，显示前200处':''):'没有找到匹配内容';if(marks.length)jump(1);}
function jump(delta){if(!marks.length)return;if(selected>=0)marks[selected].classList.remove('current');selected=(selected+delta+marks.length)%marks.length;marks[selected].classList.add('current');marks[selected].scrollIntoView({behavior:'smooth',block:'center'});}
document.querySelector('#query').addEventListener('input',()=>{clearTimeout(timer);timer=setTimeout(search,180)});document.querySelector('#query').addEventListener('keydown',e=>{if(e.key==='Enter'){clearTimeout(timer);if(!marks.length)search();else jump(e.shiftKey?-1:1);e.preventDefault();}if(e.key==='Escape'){document.querySelector('#query').value='';clearMarks();}});document.querySelector('#prev').addEventListener('click',()=>jump(-1));document.querySelector('#next').addEventListener('click',()=>jump(1));document.querySelector('#clear').addEventListener('click',()=>{document.querySelector('#query').value='';clearMarks();});
'''


def build():
    base = DOC.read_text(encoding='utf-8').split('\n## 附录 A｜', 1)[0].rstrip()
    full = base + '\n\n' + appendices()
    DOC.write_text(full, encoding='utf-8')
    rendered, toc = render_md(full)
    divider = rendered.index('<h2 id="s-01">')
    cover, body = rendered[:divider], rendered[divider:]
    metrics = '<div class="metrics"><div><b>169</b><span>卡牌条目</span></div><div><b>21</b><span>荆州区域</span></div><div><b>4</b><span>路线倾向</span></div><div><b>24</b><span>正文篇章 + 全量附录</span></div></div>'
    cover = cover.replace('<figure class="reference">', metrics + '<figure class="reference">', 1)
    nav = ''.join(f'<a href="#{key}">{html.escape(label)}</a>' for key, label in toc)
    download = html.escape(DOC.name, quote=True)
    page = '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="拍案三国图片基准完整策划案：玩法、养成、经济、全页面设计、怀旧印刷美术规范及完整卡池区域附录。"><title>拍案三国 · 图片基准完整策划案</title><style>' + STYLE + '</style></head><body><div class="progress" aria-hidden="true"><span></span></div><aside><div><a class="seal" href="#top" style="text-decoration:none">拍案三国</a><button class="mobile-nav" type="button" aria-expanded="false" aria-controls="contents">目录</button><div class="edition">图片基准 · v1.3 设计稿 · 2026.10.04</div><label for="query" class="search-label">搜索规则、章节或卡名</label><input id="query" type="search" placeholder="例如：关羽、保底、上阵" autocomplete="off"><div class="search-controls"><button id="prev" type="button" aria-label="上一处匹配">↑</button><button id="next" type="button" aria-label="下一处匹配">↓</button><button id="clear" type="button">清除</button></div><div id="match-count" role="status" aria-live="polite"></div></div><nav id="contents" aria-label="策划案章节">' + nav + '</nav><div class="aside-foot">24 篇正文 · 3 份全量附录<br>设计状态与当前工程基线已区分</div></aside><main id="top"><div class="toolbar"><small>完整游戏策划 / 怀旧印刷视觉规范</small><div class="buttons"><a class="button" href="' + download + '" download>下载可编辑正文</a><button id="print" type="button">打印 / 保存 PDF</button></div></div><article>' + cover + '<div class="reader-note"><strong>阅读提示</strong> · 第 01—14 节为玩法与页面，第 15—17 节为美术与声音，第 18—23 节为实施与验收；附录收录全部卡牌、各桌敌人和卡包基线。本次交付为设计稿，目标版功能尚未据此开发。</div>' + body + '<footer class="doc-footer">《拍案三国》图片基准完整策划案 · 2026-10-04<br><a href="project-snapshot.json" download>下载本次项目数据快照</a> · <a href="reference.png" target="_blank" rel="noopener">查看美术基准原图</a> · <a href="#top">回到开头</a></footer></article></main><script>' + JS + '</script></body></html>'
    (OUT / 'index.html').write_text(page, encoding='utf-8')
    snapshots = {n + '.json': {'sha256': hashlib.sha256((ROOT / 'data' / (n + '.json')).read_bytes()).hexdigest()} for n in SOURCES}
    snapshot = {'date': '2026-10-04', 'status': '当前工程基线，目标设计尚未实施', 'counts': {n: len(d) for n, d in DATA.items()}, 'reference': {'file': 'reference.png', 'size': [1586, 992], 'sha256': hashlib.sha256((OUT / 'reference.png').read_bytes()).hexdigest()}, 'sources': snapshots, 'data': DATA}
    (OUT / 'project-snapshot.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding='utf-8')
    assert len(CARDS) == 169 and len(toc) == 27
    for r in DATA['regions']:
        enemies = DATA['enemies'][str(r['idx'])]
        assert len(enemies) == r['enemy_count']
        assert sum(e['hp'] for e in enemies) == r['total_hp']
        assert all(e['card_id'] in CARDS for e in enemies)
    print(json.dumps({'chapters': len(toc), 'characters': len(full), 'html_bytes': len(page.encode('utf-8')), 'cards': len(CARDS), 'regions': len(DATA['regions']), 'files': [DOC.name, 'index.html', 'reference.png', 'project-snapshot.json']}, ensure_ascii=False))


if __name__ == '__main__':
    build()
