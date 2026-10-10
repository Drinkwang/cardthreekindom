"use strict";

const CARDS = [
  {id:"guanyu", name:"关羽", text:"每轮额外再拍1次；追加也能附加攻击。"},
  {id:"guanyinping", name:"关银屏", text:"每次拍击附加1倍拍击基准的火焰。"},
  {id:"zhangfei", name:"张飞", text:"所有即时特殊攻击伤害×2。"},
  {id:"zhouyu", name:"周瑜", text:"所有火焰伤害×2。"},
  {id:"zhuling", name:"朱灵", text:"每次拍击附加1倍拍击基准的雷击。"},
  {id:"wenpin", name:"文聘", text:"所有雷击伤害×2。"}
];

function computeBuild(base, mode, selection) {
  const team = new Set(selection);
  const benchmark = Number(base) * Number(mode);
  const hits = team.has("guanyu") ? 2 : 1;
  const specialMult = team.has("zhangfei") ? 2 : 1;
  const fireMult = team.has("zhouyu") ? 2 : 1;
  const thunderMult = team.has("wenpin") ? 2 : 1;
  const physical = benchmark;
  const fire = team.has("guanyinping") ? benchmark * specialMult * fireMult : 0;
  const thunder = team.has("zhuling") ? benchmark * specialMult * thunderMult : 0;
  return {benchmark,hits,specialMult,fireMult,thunderMult,physical,fire,thunder,
    physicalTotal:physical*hits,fireTotal:fire*hits,thunderTotal:thunder*hits,
    total:hits*(physical+fire+thunder),stamina:Number(mode)===2.5?2:1};
}

if (typeof module !== "undefined" && module.exports) module.exports = {computeBuild};

if (typeof document !== "undefined") {
  const selected = new Set(["guanyu","guanyinping","zhangfei"]);
  const byId = id => document.getElementById(id);
  const fmt = number => new Intl.NumberFormat("zh-CN",{maximumFractionDigits:2}).format(number);
  let animationTimer = null;

  for (const card of CARDS) {
    const button = document.createElement("button");
    button.className = "hero";
    button.dataset.id = card.id;
    button.innerHTML = `<strong>${card.name}</strong><span>${card.text}</span>`;
    button.addEventListener("click",()=>{
      if(selected.has(card.id)) selected.delete(card.id); else selected.add(card.id);
      render();
    });
    byId("heroes").append(button);
  }

  function stopAnimation() {
    if(animationTimer!==null) clearTimeout(animationTimer);
    animationTimer=null;
    byId("play").disabled=false;
  }

  function render() {
    stopAnimation();
    const base=Math.max(1,Math.min(1000000,Number(byId("base").value)||1));
    const result=computeBuild(base,byId("mode").value,selected);
    document.querySelectorAll(".hero").forEach(button=>button.setAttribute("aria-pressed",String(selected.has(button.dataset.id))));
    byId("selection-note").textContent=`已上阵 ${selected.size} / 6 · 同名只上一张。`;
    const hasFire=result.fire>0,hasThunder=result.thunder>0;
    byId("result-title").textContent=hasFire&&hasThunder?"双属性拍击":hasFire?"炎掌组合":hasThunder?"雷击组合":"普通拍击组合";
    const rules=[`${result.hits}道拍击`];
    if(hasFire)rules.push(`每道附火${fmt(result.fire)}`);
    if(hasThunder)rules.push(`每道附雷${fmt(result.thunder)}`);
    rules.push(`整轮${result.stamina}耐力`);
    byId("rule-line").textContent=rules.join(" · ");
    byId("packets").replaceChildren();
    for(let i=0;i<result.hits;i++){
      const packet=document.createElement("article");packet.className="packet";
      const parts=[`<span>普通<strong>${fmt(result.physical)}</strong></span>`];
      if(hasFire)parts.push(`<span class="fire">＋火焰<strong>${fmt(result.fire)}</strong></span>`);
      if(hasThunder)parts.push(`<span class="thunder">＋雷击<strong>${fmt(result.thunder)}</strong></span>`);
      packet.innerHTML=`<h3>第${i+1}道拍击<em>${i===0?"基础拍击":"关羽追加 · 不再追加"}</em></h3><div class="damage-parts">${parts.join("")}</div>`;
      byId("packets").append(packet);
    }
    byId("physical-total").textContent=fmt(result.physicalTotal);
    byId("fire-total").textContent=fmt(result.fireTotal);
    byId("thunder-total").textContent=fmt(result.thunderTotal);
    byId("total").textContent=fmt(result.total);
    byId("formula").textContent=`${result.hits}道 ×（${fmt(result.physical)}普通＋${fmt(result.fire)}火焰＋${fmt(result.thunder)}雷击）＝${fmt(result.total)}`;
    const warnings=[];
    if(selected.has("zhangfei")&&!hasFire&&!hasThunder)warnings.push("张飞尚无特殊攻击来源，可加入关银屏或朱灵。");
    if(selected.has("zhouyu")&&!hasFire)warnings.push("周瑜尚无火焰来源。");
    if(selected.has("wenpin")&&!hasThunder)warnings.push("文聘尚无雷击来源。");
    byId("warnings").textContent=warnings.join(" ");
  }

  byId("base").addEventListener("input",render);
  byId("mode").addEventListener("change",render);
  byId("reset").addEventListener("click",()=>{
    selected.clear();["guanyu","guanyinping","zhangfei"].forEach(id=>selected.add(id));
    byId("base").value=100;byId("mode").value="1";render();
  });
  byId("play").addEventListener("click",()=>{
    stopAnimation();byId("play").disabled=true;
    const packets=Array.from(document.querySelectorAll(".packet"));
    let index=0;
    const show=()=>{
      packets.forEach(packet=>packet.classList.remove("active"));
      if(index<packets.length){packets[index++].classList.add("active");animationTimer=setTimeout(show,240);}
      else{animationTimer=null;byId("play").disabled=false;}
    };
    show();
  });
  render();
}
