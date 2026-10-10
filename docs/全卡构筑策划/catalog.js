"use strict";
(() => {
  const roster = window.PAAN_ROSTER;
  const grid = document.getElementById("card-grid");
  const detail = document.getElementById("detail-panel");
  if (!roster || !Array.isArray(roster.units)) {
    grid.innerHTML = '<div class="no-results"><h3>名册数据尚未就绪</h3><p>请将 catalog-data.js 与本页保存在同一目录，再重新打开。</p></div>';
    document.getElementById("result-count").textContent = "未加载名册";
    document.getElementById("prev-page").disabled = true;
    document.getElementById("next-page").disabled = true;
    return;
  }
  const units = roster.units;
  const byId = new Map(units.map(unit => [unit.id, unit]));
  const PER_PAGE = 12;
  const state = { query: "", type: "all", star: "all", range: "all", page: 0, selectedId: null };
  const search = document.getElementById("card-search");
  const starSelect = document.getElementById("star-filter");
  const count = document.getElementById("result-count");
  const pageInfo = document.getElementById("page-info");
  const prev = document.getElementById("prev-page");
  const next = document.getElementById("next-page");
  const escape = value => String(value ?? "").replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
  const normalize = value => String(value ?? "").normalize("NFKC").toLocaleLowerCase("zh-CN").trim();
  const starText = unit => "★".repeat(Math.max(1, Math.min(6, Number(unit.star) || 1)));
  const typeText = unit => unit.id === "I01" ? "常驻主角" : unit.type;
  const indexes = new Map(units.map(unit => [unit.id, normalize([unit.id, unit.name, unit.type, unit.faction, unit.role, unit.skill_name, unit.effect, unit.rules, unit.combo_reason, ...(unit.tags || []), ...(unit.combo_ids || []).map(id => byId.get(id)?.name || id)].join(" "))]));
  if (roster.status) document.getElementById("plan-status").textContent = roster.status;
  document.getElementById("edition").textContent = [roster.version, roster.date].filter(Boolean).join(" · ");
  const counts = roster.counts || {};
  document.getElementById("roster-counts").textContent = (counts.heroes ?? units.filter(unit => unit.type === "武将" && unit.id !== "N01").length) + "名现有武将 · " + (counts.soldiers ?? units.filter(unit => unit.type === "士兵").length) + "种士兵 · 新增关银屏 · 常驻主角";
  function filteredUnits() {
    const terms = normalize(state.query).split(/\s+/).filter(Boolean);
    return units.filter(unit => {
      if (state.type !== "all" && unit.type !== state.type) return false;
      if (state.star !== "all" && Number(unit.star) !== Number(state.star)) return false;
      if (state.range === "low" && Number(unit.star) > 3) return false;
      if (state.range === "high" && Number(unit.star) < 5) return false;
      return terms.every(term => indexes.get(unit.id).includes(term));
    }).sort((a, b) => {
      if (terms.length) {
        const directA = terms.every(term => normalize(a.name + " " + a.id).includes(term));
        const directB = terms.every(term => normalize(b.name + " " + b.id).includes(term));
        if (directA !== directB) return directA ? -1 : 1;
      }
      if (a.id === "I01" || b.id === "I01") return a.id === "I01" ? -1 : 1;
      return Number(a.star) - Number(b.star) || a.id.localeCompare(b.id);
    });
  }
  function jumpChip(id, showMeta = true) {
    const unit = byId.get(id);
    if (!unit) return '<span class="tag">' + escape(id) + '（设计待登记）</span>';
    return '<button type="button" class="card-jump" data-jump="' + escape(id) + '">' + escape(unit.name) + (showMeta ? '<span>★' + Number(unit.star) + '</span>' : "") + "</button>";
  }
  function renderDetail(unit, moveFocus = false) {
    if (!unit) return;
    state.selectedId = unit.id;
    const newNote = unit.id === "N01" ? "关银屏为新增设计，N01是策划临时ID。" : unit.id === "I01" ? "主角常驻不占携带位，不合成；其★2是原数据标记。" : unit.type === "士兵" ? "同种士兵全队仅1支有效编队，重复卡用于合成。单独上阵或挂在武将下均按词条范围生效。" : "同名同品相3合1，星级与技能身份不变；品相只增强基础战力。";
    detail.innerHTML = '<div class="detail-topline"><span class="faction-stamp faction-' + escape(unit.faction) + '">' + escape(String(unit.faction || "").slice(0, 1)) + '</span><span>' + escape(unit.faction) + " · " + escape(typeText(unit)) + " · " + escape(unit.id) + '</span>' + (unit.id === "N01" ? '<span class="badge">新增设计</span>' : "") + '</div><div class="detail-title"><h2 tabindex="-1" id="detail-name">' + escape(unit.name) + '</h2><span class="detail-stars" aria-label="' + Number(unit.star) + '星">' + starText(unit) + '</span></div><p class="detail-role">' + escape(unit.role) + '</p><div class="card-effect"><h3 class="skill-name">' + escape(unit.skill_name) + '</h3><p class="effect-text">' + escape(unit.effect) + '</p></div><section class="detail-section"><h3>怎么触发 · 怎么结算</h3><p>' + escape(unit.rules) + '</p></section><section class="detail-section"><h3>可以这样接招</h3><div class="combo-chips">' + (unit.combo_ids || []).map(id => jumpChip(id)).join("") + '</div><p>' + escape(unit.combo_reason) + '</p></section><div class="tag-list" aria-label="机制标签">' + (unit.tags || []).map(tag => '<span class="tag">' + escape(tag) + '</span>').join("") + '</div><p class="detail-note">' + escape(newNote) + ' 上述搭配为思路示例，可以自由替换。</p>';
    detail.scrollTop = 0;
    detail.querySelectorAll("[data-jump]").forEach(button => button.addEventListener("click", () => selectById(button.dataset.jump, true)));
    grid.querySelectorAll("[data-select]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.select === unit.id)));
    if (moveFocus) {
      document.getElementById("detail-name").focus({ preventScroll: true });
      if (window.matchMedia("(max-width:760px)").matches) detail.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion:reduce)").matches ? "auto" : "smooth", block: "start" });
    }
    const url = new URL(window.location.href);
    url.hash = "card=" + encodeURIComponent(unit.id);
    try { history.replaceState(null, "", url.href); } catch (_) { /* File hosts can refuse history updates; reading still works. */ }
  }
  function syncFilters() {
    search.value = state.query;
    starSelect.value = state.star;
    document.querySelectorAll("[data-type]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.type === state.type)));
    document.querySelectorAll("[data-range]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.range === state.range)));
    document.getElementById("clear-search").disabled = !state.query;
  }
  function render() {
    const filtered = filteredUnits();
    const pages = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
    state.page = Math.min(Math.max(0, state.page), pages - 1);
    const pageUnits = filtered.slice(state.page * PER_PAGE, (state.page + 1) * PER_PAGE);
    count.textContent = "筛得 " + filtered.length + " / " + units.length + " 张";
    pageInfo.textContent = "第 " + (state.page + 1) + " / " + pages + " 页";
    prev.disabled = state.page === 0;
    next.disabled = state.page >= pages - 1;
    syncFilters();
    if (!filtered.length) {
      grid.innerHTML = '<div class="no-results"><h3>这一页暂时没有卡。</h3><p>试试减少筛选条件，或搜索“火”“追加”“易伤”。</p><button class="quiet-button reset-button" id="reset-filters" type="button">重置全部筛选</button></div>';
      document.getElementById("reset-filters").addEventListener("click", () => { resetFilters(); render(); });
      return;
    }
    grid.innerHTML = pageUnits.map(unit => '<button type="button" class="unit-card" data-select="' + escape(unit.id) + '" aria-pressed="' + String(unit.id === state.selectedId) + '" aria-label="' + escape(unit.name + "，" + unit.star + "星，" + typeText(unit) + "，" + unit.role) + '"><span class="unit-card-top"><span class="faction-stamp faction-' + escape(unit.faction) + '" aria-hidden="true">' + escape(String(unit.faction || "").slice(0, 1)) + '</span><span class="unit-card-name">' + escape(unit.name) + '</span></span><span class="card-mini-meta"><span class="stars" aria-label="' + Number(unit.star) + '星">' + starText(unit) + '</span><span>' + escape(typeText(unit)) + '</span>' + (unit.id === "N01" ? '<span class="badge">新</span>' : "") + '</span><span class="unit-card-role">' + escape(unit.role) + '</span></button>').join("");
    grid.scrollTop = 0;
    grid.querySelectorAll("[data-select]").forEach(button => button.addEventListener("click", () => renderDetail(byId.get(button.dataset.select), true)));
    if (!state.selectedId || !filtered.some(unit => unit.id === state.selectedId)) renderDetail(pageUnits[0]);
  }
  function resetFilters() { state.query = ""; state.type = "all"; state.star = "all"; state.range = "all"; state.page = 0; }
  function selectById(id, moveFocus = false) {
    const unit = byId.get(id);
    if (!unit) return;
    resetFilters();
    const all = filteredUnits();
    state.page = Math.floor(all.findIndex(item => item.id === id) / PER_PAGE);
    state.selectedId = id;
    render();
    renderDetail(unit, moveFocus);
  }
  search.addEventListener("input", () => { state.query = search.value; state.page = 0; render(); });
  document.getElementById("clear-search").addEventListener("click", () => { state.query = ""; state.page = 0; render(); search.focus(); });
  starSelect.addEventListener("change", () => { state.star = starSelect.value; state.range = "all"; state.page = 0; render(); });
  document.querySelectorAll("[data-type]").forEach(button => button.addEventListener("click", () => { state.type = button.dataset.type; state.page = 0; render(); }));
  function toggleRange(range) { state.range = state.range === range ? "all" : range; state.star = "all"; state.page = 0; render(); }
  document.querySelectorAll("[data-range]").forEach(button => button.addEventListener("click", () => toggleRange(button.dataset.range)));
  prev.addEventListener("click", () => { state.page--; render(); });
  next.addEventListener("click", () => { state.page++; render(); });
  document.addEventListener("keydown", event => {
    const isTyping = event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement || event.target instanceof HTMLSelectElement || event.target.isContentEditable;
    if (event.altKey && !event.ctrlKey && !event.metaKey && (event.key === "1" || event.key === "2")) { event.preventDefault(); toggleRange(event.key === "1" ? "low" : "high"); return; }
    if (!isTyping && event.key === "/" && !event.altKey && !event.ctrlKey && !event.metaKey) { event.preventDefault(); search.focus(); }
    if (event.key === "Escape" && event.target === search && state.query) { state.query = ""; state.page = 0; render(); }
  });
  const examples = [
    { title: "首拍点火，后拍出刀", chain: "火源 → 点燃 → 燃烧条件刀锋", ids: ["G17", "G21", "G19", "G28"], text: "傅士仁把普通伤害切出火；王甫点燃后，关羽的追加立刻接通廖化烧刀。也可替换火源与追加来源。" },
    { title: "先开易伤，再放大刀", chain: "首拍前易伤 → 条件刀源 → 特殊倍率", ids: ["G18", "G23", "G26", "S23"], text: "糜芳负责启动，关平负责产刀，张飞负责放大；白毦兵维持易伤。低星接口和高星倍率各有职责。" },
    { title: "一掌重拍，普通与刀并进", chain: "先手破甲 → 普通重拍 → 刀属性重拍", ids: ["G06", "G14", "G10", "S17"], text: "李典先挂破甲，许褚强化普通部分，徐晃强化重拍刀锋；藤甲兵帮助打出更多有限重拍。" },
    { title: "三段风掌，拆开整张桌", chain: "每拍风源 → 风后易伤 → 多段分桌", ids: ["G02", "G01", "G13", "G45"], text: "蔡瑁提供风，张允让命中接易伤，张辽把追加分到不同敌牌；黄祖可补风扩散，范围遵守统一上限。" }
  ];
  document.getElementById("combo-examples").innerHTML = examples.map(example => '<article class="combo-example"><h3>' + escape(example.title) + '</h3><p class="example-chain">' + escape(example.chain) + '</p><div class="combo-chips">' + example.ids.map(id => jumpChip(id, false)).join("") + '</div><p>' + escape(example.text) + '</p></article>').join("");
  document.querySelectorAll("#combo-examples [data-jump]").forEach(button => button.addEventListener("click", () => selectById(button.dataset.jump, true)));
  const initialId = (() => { try { return decodeURIComponent(window.location.hash.replace(/^#card=/, "")); } catch (_) { return ""; } })();
  if (byId.has(initialId)) selectById(initialId); else { state.selectedId = byId.has("G17") ? "G17" : units[0]?.id; render(); renderDetail(byId.get(state.selectedId)); }
  window.addEventListener("hashchange", () => {
    const id = (() => { try { return decodeURIComponent(window.location.hash.replace(/^#card=/, "")); } catch (_) { return ""; } })();
    if (byId.has(id) && id !== state.selectedId) selectById(id);
  });
})();
