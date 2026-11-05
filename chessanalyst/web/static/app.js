"use strict";

const STEP = {
  best: ["лучший", "!"], excellent: ["отличный", "!"], good: ["хороший", ""], neutral: ["нейтральный", ""],
  inaccuracy: ["неточность", "?!"], pass: ["pass", "⊘"], laxity: ["laxity", "!?"],
  mistake: ["mistake", "?"], blunder: ["blunder", "??"], forced: ["вынужденный", "□"], book: ["книга", ""],
};
const FLAG = {
  pass: "pass", neutral: "нейтральный", near_best: "практически равен лучшему", trivial: "тривиальная позиция",
  theory: "теория", book: "книга", hopeless: "безнадёжная позиция", only_move: "only move", only_light: "only move (лёгкий)", brilliant: "brilliant", underpress: "недожим",
};
const STAGE = { opening: "дебют", middlegame: "миттельшпиль", endgame: "эндшпиль" };
const CAT = { loss: "проигрыш", worse: "хуже", equal: "равно", better: "лучше", win: "выигрыш" };
const MOTIF = { mate: "мат", promotion: "превращение", fork: "вилка", pin: "связка", discovered: "вскрытое нападение",
  open_line: "открытая линия", hanging: "незащищённая фигура", material: "выигрыш материала", plan: "план" };
const REASON = { calculation: "перебор вариантов", hidden_move: "неочевидный ход", missed_defense: "пропущенная защита",
  blind_spot: "слепое пятно" };
const START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const plyText = (p) => `${Math.floor(p / 2) + 1}${p % 2 ? "..." : "."}`;
const moveText = (p) => (G.game && p < G.game.plies.length ? `${plyText(p)} ${G.game.plies[p].san}` : "после партии");
const fmtP = (x) => (x == null ? "—" : (x >= 0 ? "+" : "") + x.toFixed(2));
const fmtW = (x) => (x == null ? "—" : (100 * x).toFixed(1) + "%");

async function api(path, body) {
  const opt = body === undefined ? {} : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
  const r = await fetch(path, opt);
  const data = await r.json();
  if (!r.ok) { alert(data.error || r.statusText); throw new Error(data.error); }
  return data;
}

// --- доска: SVG с сервера, ходы кликами ---
class Board {
  constructor(el, onMove) {
    this.el = el; this.onMove = onMove; this.flip = false; this.sel = null; this.fen = START; this.extra = {};
    this.img = document.createElement("img"); this.img.alt = "доска"; el.appendChild(this.img);
    this.img.addEventListener("click", (e) => this.click(e));
    this.render();
  }
  set(fen, extra = {}) { this.fen = fen; this.extra = extra; this.sel = null; this.render(); }
  render() {
    const p = new URLSearchParams({ fen: this.fen, flip: this.flip ? "1" : "0", size: "400" });
    for (const k of ["arrows", "last", "mark"]) if (this.extra[k]) p.set(k, this.extra[k]);
    if (this.sel) p.set("sel", this.sel);
    this.img.src = "/api/board.svg?" + p;
  }
  hide(on) { this.img.style.visibility = on ? "hidden" : "visible"; }
  square(e) {
    const r = this.img.getBoundingClientRect();
    let f = Math.floor(((e.clientX - r.left) / r.width) * 8), rk = 7 - Math.floor(((e.clientY - r.top) / r.height) * 8);
    if (this.flip) { f = 7 - f; rk = 7 - rk; }
    return "abcdefgh"[f] + (rk + 1);
  }
  pieceAt(sq) {
    const rows = this.fen.split(" ")[0].split("/");
    const row = rows[8 - Number(sq[1])]; let file = 0;
    for (const ch of row) {
      if (/\d/.test(ch)) file += Number(ch);
      else { if ("abcdefgh"[file] === sq[0]) return ch; file++; }
    }
    return null;
  }
  click(e) {
    if (!this.onMove) return;
    const sq = this.square(e), turn = this.fen.split(" ")[1];
    const own = (p) => p && ((turn === "w") === (p === p.toUpperCase()));
    if (this.sel) {
      const from = this.sel; this.sel = null;
      if (sq === from) return this.render();
      if (own(this.pieceAt(sq))) { this.sel = sq; return this.render(); }
      const p = this.pieceAt(from);
      const promo = (p === "P" && sq[1] === "8") || (p === "p" && sq[1] === "1") ? "q" : "";
      this.render(); this.onMove(from + sq + promo);
    } else if (own(this.pieceAt(sq))) { this.sel = sq; this.render(); }
  }
}

// --- вкладки ---
const onTab = {};
document.querySelectorAll("#tabs button").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));
function showTab(name) {
  document.querySelectorAll("#tabs button").forEach((b) => b.classList.toggle("active", b.dataset.tab === name));
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t.id === "tab-" + name));
  onTab[name]?.();
}

// ===== 1. Загрузка =====
$("#pgn-file").addEventListener("change", async (e) => { const f = e.target.files[0]; if (f) $("#pgn-text").value = await f.text(); });
$("#pgn-upload").addEventListener("click", async () => {
  const r = await api("/api/games/upload", { pgn: $("#pgn-text").value, analyze: $("#load-analyze").checked,
    depth: Number($("#load-depth").value), unit: $("#load-unit").value });
  $("#pgn-text").value = ""; refreshQueue();
  if (r.ids.length === 0) alert("В тексте не найдено партий");
});
$("#cc-import").addEventListener("click", async () => {
  const r = await api("/api/chesscom", { user: $("#cc-user").value, months: $("#cc-months").value,
    time_classes: $("#cc-tc").value, results: $("#cc-results").value, skip_easy: $("#cc-easy").checked,
    limit: $("#cc-limit").value });
  alert(`Загружено партий: ${r.ids.length}`); refreshQueue();
});
let queueTimer = null;
async function refreshQueue() {
  const games = await api("/api/games");
  $("#queue tbody").innerHTML = games.map((g) => {
    const pr = g.progress;
    let st = { queued: "в очереди", analyzed: "проанализирована", classified: "разобрана" }[g.status] || g.status;
    if (pr && pr.state === "running") st = `анализ ${pr.done}/${pr.total || g.plies}`;
    if (pr && pr.state === "queued") st = "ждёт движка";
    if (pr && pr.state === "error") st = "ошибка: " + pr.error;
    return `<tr><td>${g.id}</td><td>${esc(g.white)} – ${esc(g.black)} <span class="hint">${esc(g.result)}</span></td>
      <td>${g.plies}</td><td>${esc(st)}</td><td>${g.cursor != null ? plyText(g.cursor) : "—"}</td>
      <td><button data-open="${g.id}">Открыть</button> <button data-an="${g.id}">Анализ</button></td></tr>`;
  }).join("");
  const busy = games.some((g) => g.progress && ["running", "queued"].includes(g.progress.state));
  clearTimeout(queueTimer);
  if (busy) queueTimer = setTimeout(refreshQueue, 1500);
}
$("#queue").addEventListener("click", async (e) => {
  const id = e.target.dataset.open || e.target.dataset.an;
  if (!id) return;
  if (e.target.dataset.an) {
    await api("/api/games/analyze", { ids: [Number(id)], depth: Number($("#load-depth").value), unit: $("#load-unit").value });
    refreshQueue();
  } else { await openGame(Number(id)); showTab("game"); }
});
onTab.load = refreshQueue;

// ===== 2. Партия =====
const G = { game: null, ply: 0, unit: "both", lines: null, depth: null };
const gameBoard = new Board($("#game-board"));
$("#game-flip").addEventListener("click", () => { gameBoard.flip = !gameBoard.flip; gameBoard.render(); });
$("#game-unit").addEventListener("change", (e) => { G.unit = e.target.value; renderGame(); });
document.querySelectorAll("[data-nav]").forEach((b) => b.addEventListener("click", () => {
  if (!G.game) return;
  const n = G.game.plies.length;
  G.ply = { first: 0, prev: Math.max(0, G.ply - 1), next: Math.min(n - 1, G.ply + 1), last: n - 1 }[b.dataset.nav];
  selectPly(G.ply);
}));
document.addEventListener("keydown", (e) => {
  if (!$("#tab-game").classList.contains("active") || e.target.tagName === "INPUT" || !G.game) return;
  if (e.key === "ArrowLeft") selectPly(Math.max(0, G.ply - 1));
  if (e.key === "ArrowRight") selectPly(Math.min(G.game.plies.length - 1, G.ply + 1));
});

async function openGame(id) {
  G.game = await api(`/api/games/${id}`);
  G.ply = Math.min(G.game.cursor || 0, Math.max(0, G.game.plies.length - 1));
  if (G.game.records.length) G.unit = G.game.records[0].unit;
  $("#game-unit").value = G.unit;
  renderGame(); renderIdeas();
}
onTab.game = () => { if (!G.game) $("#game-title").textContent = "Откройте партию на вкладке «Загрузка»."; };

function rec(ply) { return G.game?.records[ply]; }
function renderGame() {
  if (!G.game) return;
  const g = G.game;
  $("#game-title").innerHTML = esc(g.label) + (g.run ? ` <span class="hint">глубина ${g.run.depth}, настройки v${g.run.version}</span>` :
    ' <span class="hint">не разобрана — запустите анализ</span>');
  let html = "";
  g.plies.forEach((p, i) => {
    if (p.side === "white") html += `<span class="no">${p.move_no}.</span>`;
    else if (i === 0) html += `<span class="no">${p.move_no}.</span><span></span>`;
    const r = rec(i), cls = r ? "s-" + r.step : "";
    html += `<span class="mv ${i === G.ply ? "cur" : ""}" data-ply="${i}"><span class="${cls}">${esc(p.san)}<span class="mk">${r ? STEP[r.step][1] : ""}</span></span></span>`;
  });
  $("#game-moves").innerHTML = html;
  renderGraph(); selectPly(G.ply, true);
}
$("#game-moves").addEventListener("click", (e) => { const m = e.target.closest(".mv"); if (m) selectPly(Number(m.dataset.ply)); });

function whiteValue(r, unit) {
  const v = unit === "pawns" ? r.ep_pawns : r.ep_wdl;
  if (r.side === "white") return v;
  return unit === "pawns" ? -v : 1 - v;
}
function renderGraph() {
  const recs = G.game.records, el = $("#game-graph");
  if (!recs.length) { el.innerHTML = ""; return; }
  const W = 400, H = 120, n = recs.length, x = (i) => (n === 1 ? W / 2 : (i / (n - 1)) * W);
  const yW = (v) => H - v * H, yP = (v) => H / 2 - (Math.max(-6, Math.min(6, v)) / 6) * (H / 2);
  const path = (f) => recs.map((r, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${f(r).toFixed(1)}`).join("");
  let svg = `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><rect width="${W}" height="${H}" fill="var(--bg)"/>
    <line x1="0" x2="${W}" y1="${H / 2}" y2="${H / 2}" stroke="var(--line)"/>`;
  if (G.unit !== "pawns") svg += `<path d="${path((r) => yW(whiteValue(r, "wdl")))}" fill="none" stroke="var(--accent)" stroke-width="2"/>`;
  if (G.unit !== "wdl") svg += `<path d="${path((r) => yP(whiteValue(r, "pawns")))}" fill="none" stroke="var(--muted)" stroke-width="1.5" ${G.unit === "both" ? 'stroke-dasharray="4 3"' : ""}/>`;
  recs.forEach((r, i) => {
    if (["mistake", "blunder", "laxity"].includes(r.step) || r.flags.includes("pass")) {
      const y = G.unit === "pawns" ? yP(whiteValue(r, "pawns")) : yW(whiteValue(r, "wdl"));
      svg += `<circle cx="${x(i)}" cy="${y}" r="3" fill="var(--${r.flags.includes("pass") && !["mistake", "blunder"].includes(r.step) ? "pass" : r.step === "laxity" ? "lax" : r.step})"/>`;
    }
  });
  svg += `<line id="graph-cur" x1="${x(G.ply)}" x2="${x(G.ply)}" y1="0" y2="${H}" stroke="var(--ink)" stroke-opacity=".5"/></svg>`;
  el.innerHTML = svg;
  el.firstChild.addEventListener("click", (e) => {
    const r = e.currentTarget.getBoundingClientRect();
    selectPly(Math.round(((e.clientX - r.left) / r.width) * (n - 1)));
  });
}

async function selectPly(ply, noFetch) {
  G.ply = ply;
  const g = G.game, p = g.plies[ply], r = rec(ply);
  if (!p) return;
  document.querySelectorAll("#game-moves .mv").forEach((m) => m.classList.toggle("cur", Number(m.dataset.ply) === ply));
  const cur = $("#graph-cur");
  if (cur && g.records.length > 1) { const x = (ply / (g.records.length - 1)) * 400; cur.setAttribute("x1", x); cur.setAttribute("x2", x); }
  const arrows = [p.uci + ":blue"];
  if (r && r.best_moves.length && r.best_moves[0].uci !== p.uci) arrows.push(r.best_moves[0].uci + ":green");
  gameBoard.flip = gameBoard.flip; gameBoard.set(p.fen_before, { arrows: arrows.join(",") });
  $("#move-detail").innerHTML = r ? detailHtml(p, r) : `<b>${plyText(ply)} ${esc(p.san)}</b><p class="hint">Ход ещё не разобран.</p>`;
  $("#cont-result").innerHTML = "";
  api(`/api/games/${g.id}/cursor`, { ply });
  if (!noFetch || G.lines === null) loadLines(p.fen_before, g.run?.depth);
}

function valuesHtml(r) {
  const rows = [];
  if (G.unit !== "wdl") rows.push(["пешки", `E0 ${fmtP(r.e0_pawns)} · E1 ${fmtP(r.e1_pawns)} · Ep ${fmtP(r.ep_pawns)} · G ${fmtP(r.g_pawns)} · D ${fmtP(r.d_pawns)} · L ${r.l_pawns.toFixed(2)}`]);
  if (G.unit !== "pawns") rows.push(["WDL", `E0 ${fmtW(r.e0_wdl)} · E1 ${fmtW(r.e1_wdl)} · Ep ${fmtW(r.ep_wdl)} · G ${fmtW(r.g_wdl)} · D ${fmtW(r.d_wdl)} · L ${fmtW(r.l_wdl)}`]);
  return rows.map(([k, v]) => `<b>${k}</b><span>${v}</span>`).join("");
}
function detailHtml(p, r) {
  const tags = [r.subtype, ...r.flags].filter(Boolean).map((f) => `<span class="tag">${esc(FLAG[f] || f)}</span>`).join("");
  const units = Object.keys(r.unit_steps || {}).length > 1 && new Set(Object.values(r.unit_steps)).size > 1
    ? `<span class="hint">(${Object.entries(r.unit_steps).map(([u, s]) => `${u}: ${STEP[s][0]}`).join(", ")})</span>` : "";
  const mv = (list) => list.map((b) => `${esc(b.san)} <span class="hint">${esc(b.eval)} ${b.type}${b.subtypes.length ? "(" + b.subtypes.join(",") + ")" : ""}${b.only_move ? " only move" : ""}${b.brilliant ? " brilliant" : ""}</span>`).join("; ") || "—";
  const idea = G.game.ideas.find((i) => i.punish_ply === r.ply);
  return `<div class="row"><b>${plyText(r.ply)} ${esc(p.san)}</b> <span class="s-${r.step}"><b>${STEP[r.step][0]}${STEP[r.step][1]}</b></span> ${units} ${tags}</div>
    <div class="kv">
      <b>тип</b><span>${r.move_type}${r.type_subtypes.length ? " (" + r.type_subtypes.join(", ") + ")" : ""}</span>
      <b>стадия</b><span>${STAGE[r.stage]}</span>
      <b>категория</b><span>${CAT[r.cat_e1]} → ${CAT[r.cat_ep]} <span class="hint">по ${r.decided_by}</span></span>
      ${valuesHtml(r)}
      <b>лучшие</b><span>${mv(r.best_moves)}</span>
      <b>≈ лучшему</b><span>${mv(r.near_best_moves)}</span>
      ${idea ? `<b>идея</b><span>${esc(idea.chunk)} — начало перед ${moveText(idea.start_ply)}, пропуск ${idea.miss_ply != null ? moveText(idea.miss_ply) : "—"}, дистанция ${idea.distance ?? "—"} <a href="#" data-idea="${idea.id}">цепочка →</a></span>` : ""}
    </div>`;
}
$("#move-detail").addEventListener("click", (e) => {
  const id = e.target.dataset.idea; if (!id) return;
  e.preventDefault(); showTab("ideas"); selectIdea(Number(id));
});

async function loadLines(fen, depth, multipv) {
  G.lines = null;
  $("#pos-lines tbody").innerHTML = `<tr><td colspan="4" class="hint">считаю…</td></tr>`;
  const body = { fen }; if (depth) body.depth = depth; if (multipv) body.multipv = multipv;
  const r = await api("/api/position", body);
  G.lines = r.lines; G.depth = r.depth;
  $("#pos-depth").textContent = `глубина ${r.depth}, линий ${r.lines.length}`;
  $("#pos-lines tbody").innerHTML = r.lines.map((l) => `<tr><td><b>${esc(l.pv[0])}</b></td><td>${esc(l.eval)}</td><td>${fmtW(l.wdl)}</td><td class="hint">${esc(l.pv.join(" "))}</td></tr>`).join("");
}
$("#pos-deepen").addEventListener("click", () => {
  const p = G.game?.plies[G.ply]; if (!p) return;
  loadLines(p.fen_before, (G.depth || 18) + 4, 8);
});
$("#cont-send").addEventListener("click", async () => {
  const p = G.game?.plies[G.ply]; if (!p) return;
  const r = await api("/api/continuation", { fen: p.fen_before, move: p.uci, line: $("#cont-line").value,
    source: "game", ref: `${G.game.id}:${G.ply}` });
  $("#cont-result").innerHTML = contHtml(r);
});
function contHtml(r) {
  if (r.diverge_kind === "match") return `<p class="ok">Совпало с главным вариантом: ${esc(r.engine_line.join(" "))}</p>`;
  const who = r.diverge_side === "opponent" ? "ответ соперника" : "свой ход";
  return `<p><span class="bad">Расхождение на ${r.diverge_index + 1}-м полуходе (${who})</span>: у тебя ${esc(r.user_move)}, движок — <b>${esc(r.engine_move)}</b> (${esc(r.kind_label)}).<br>
    <span class="hint">Главный вариант: ${esc(r.engine_line.join(" "))}</span></p>`;
}
$("#lib-save").addEventListener("click", async () => {
  if (!G.game) return;
  await api("/api/library", { game_id: G.game.id, ply: G.ply, title: $("#lib-title").value || `${G.game.label}, ${plyText(G.ply)}` });
  $("#lib-title").value = ""; alert("Сохранено в библиотеку");
});
$("#play-here").addEventListener("click", () => {
  const p = G.game?.plies[G.ply]; if (!p) return;
  $("#play-fen").value = p.fen_before; showTab("play");
});

// ===== 3. Идеи =====
let curIdea = null;
function renderIdeas() {
  const ideas = G.game?.ideas || [];
  $("#idea-list").innerHTML = ideas.length ? ideas.map((i) => {
    const p = G.game.plies[i.punish_ply];
    const head = i.kind === "pass" ? `pass ${plyText(i.punish_ply)} ${esc(p?.san)} (${i.owner})` : `${plyText(i.punish_ply)} ${esc(p?.san)} — ошибка ${i.victim === "white" ? "белых" : "чёрных"}`;
    return `<div class="idea ${curIdea === i.id ? "cur" : ""}" data-id="${i.id}"><b>${head}</b><br>${esc(i.chunk)}<br>
      <span class="hint">${MOTIF[i.signature.motif] || i.signature.motif}${i.distance != null ? `, дистанция ${i.distance}` : ""}</span></div>`;
  }).join("") : '<p class="hint">Нет цепочек: партия не разобрана или без ошибок.</p>';
  $("#idea-chain").innerHTML = "";
}
$("#idea-list").addEventListener("click", (e) => { const d = e.target.closest(".idea"); if (d) selectIdea(Number(d.dataset.id)); });
function fenAt(ply) { const g = G.game; return ply < g.plies.length ? g.plies[ply].fen_before : g.final_fen; }
function selectIdea(id, revealed) {
  curIdea = id; renderIdeasHighlight();
  const i = G.game.ideas.find((x) => x.id === id); if (!i) return;
  const exercise = $("#idea-exercise").checked && !revealed;
  const cells = i.chain.map((c) => ({ ply: c.ply, fen: fenAt(c.ply), arrows: `${c.attacker}${c.target}:red`,
    cls: (c.present ? "" : "absent ") + (exercise ? "" : c.ply === i.start_ply ? "start" : ""),
    label: `${c.ply < G.game.plies.length ? plyText(c.ply) + " " + G.game.plies[c.ply].san : "после партии"}${exercise ? "" : c.ply === i.start_ply ? " · начало идеи" : c.present ? "" : " · идеи ещё нет"}` }));
  if (!exercise && i.miss_ply != null && i.miss_ply < G.game.plies.length) {
    const r = rec(i.miss_ply), p = G.game.plies[i.miss_ply];
    const best = r?.best_moves[0]?.uci;
    cells.push({ ply: i.miss_ply, fen: p.fen_before, arrows: `${p.uci}:red${best ? "," + best + ":green" : ""}`, cls: "miss",
      label: `${plyText(i.miss_ply)} ${p.san} · пропуск${best ? " (надо " + r.best_moves[0].san + ")" : ""}` });
  }
  if (i.kind === "punishment" && i.miss_ply !== i.punish_ply && !exercise) {
    const p = G.game.plies[i.punish_ply];
    cells.push({ ply: i.punish_ply, fen: p.fen_before, arrows: `${p.uci}:red`, cls: "punish", label: `${plyText(i.punish_ply)} ${p.san} · наказание` });
  }
  cells.sort((a, b) => a.ply - b.ply || (a.cls === "punish") - (b.cls === "punish"));
  $("#idea-chain").innerHTML = `<p><b>${esc(i.chunk)}</b> — ${MOTIF[i.signature.motif] || i.signature.motif}, ключевой ход ${esc(i.signature.key)}.
    ${exercise ? '<br><span class="hint">Кликни позицию, где, по-твоему, идея появилась.</span>' :
      `<br>Начало: перед ${moveText(i.start_ply)}; пропуск: ${i.miss_ply != null ? moveText(i.miss_ply) : "—"}; дистанция: ${i.distance ?? "—"} полуход(а). Ходы владельца, строившие идею: ${i.builder_plies.map(moveText).join(", ") || "—"}`}</p>
    <div class="chain">${cells.map((c) => `<div class="cell ${c.cls}" data-ply="${c.ply}"><img src="/api/board.svg?${new URLSearchParams({ fen: c.fen, arrows: c.arrows, size: 190 })}"><div>${esc(c.label)}</div></div>`).join("")}</div>
    <div id="guess-result"></div>`;
}
function renderIdeasHighlight() { document.querySelectorAll(".idea").forEach((d) => d.classList.toggle("cur", Number(d.dataset.id) === curIdea)); }
$("#idea-chain").addEventListener("click", async (e) => {
  const cell = e.target.closest(".cell"); if (!cell) return;
  if ($("#idea-exercise").checked && curIdea) {
    const r = await api(`/api/ideas/${curIdea}/guess`, { ply: Number(cell.dataset.ply) });
    selectIdea(curIdea, true);
    $("#guess-result").innerHTML = r.correct ? '<p class="ok">Верно: начало идеи найдено (+2)</p>' : `<p class="bad">Начало идеи — ${plyText(r.start_ply)}</p>`;
  } else { showTab("game"); selectPly(Math.min(Number(cell.dataset.ply), G.game.plies.length - 1)); }
});
$("#idea-exercise").addEventListener("change", () => curIdea && selectIdea(curIdea));
onTab.ideas = () => { if (!G.game) $("#idea-list").innerHTML = '<p class="hint">Откройте партию.</p>'; };

// ===== 4. Игра =====
let play = null;
const playBoard = new Board($("#play-board"), (uci) => playMove(uci));
$("#play-start").addEventListener("click", async () => {
  play = await api("/api/play", { fen: $("#play-fen").value || START, source: G.game ? `game:${G.game.id}:${G.ply}` : null });
  playBoard.flip = play.human === "black"; renderPlay();
});
$("#play-send").addEventListener("click", () => playMove($("#play-move").value));
async function playMove(mv) {
  if (!play || !mv) return;
  const r = await api(`/api/play/${play.id}/move`, { move: mv });
  play = r.session; $("#play-move").value = ""; renderPlay();
}
function renderPlay() {
  const last = play.moves.length ? play.moves[play.moves.length - 1].uci : "";
  playBoard.set(play.fen, { last });
  $("#play-status").innerHTML = play.status === "active" ? `Ты играешь ${play.human === "white" ? "белыми" : "чёрными"}.` : `<b>Партия окончена: ${esc(play.status.split(":")[1])}</b>`;
  $("#play-moves").innerHTML = play.moves.map((m, i) => {
    const lab = m.by === "human" ? `<span class="s-${m.step}">${esc(m.san)}<span class="mk">${STEP[m.step][1]}</span></span> <span class="hint">${STEP[m.step][0]}${m.step !== "best" && m.best.length ? ", лучше " + esc(m.best[0]) : ""}</span>`
      : `${esc(m.san)} ${m.deviated ? '<span class="tag">уход с линии</span>' : ""}`;
    return `<span class="no">${i + 1}</span><span class="mv" style="grid-column: span 2">${lab}</span>`;
  }).join("");
}
$("#play-cont-send").addEventListener("click", async () => {
  if (!play?.fen_after_human) return;
  const r = await api("/api/continuation", { fen: play.fen_after_human, line: $("#play-cont").value, source: "play", ref: String(play.id) });
  $("#play-cont-result").innerHTML = contHtml(r);
});

// ===== 5. Задачи и проба =====
const PZ = { cur: null, done: [], t0: 0, timer: null, failed: false, probe: null, queue: [], diff: null };
const pzBoard = new Board($("#pz-board"), (uci) => pzMove(uci));
function scale(el, n, key) {
  el.innerHTML = `<span class="scale">${Array.from({ length: n }, (_, i) => `<button data-v="${i + 1}">${i + 1}</button>`).join("")}</span>`;
  el.onclick = (e) => { const v = e.target.dataset.v; if (!v) return; PZ[key] = Number(v);
    el.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b.dataset.v === v)); };
}
async function loadThemes() {
  const t = await api("/api/themes");
  $("#pz-theme").innerHTML = '<option value="">любая тема</option>' + t.themes.map(([n, c]) => `<option value="${esc(n)}">${esc(n)} (${c})</option>`).join("");
  $("#pz-reasons").innerHTML = Object.entries(t.reasons).map(([k, v]) => `<label><input type="checkbox" value="${k}"> ${esc(v)}</label><br>`).join("");
  $("#pz-count").textContent = `задач в базе: ${t.count}`;
  $("#pref-rating").value = t.rating;
}
onTab.puzzles = loadThemes;
function startPuzzle(p) {
  PZ.cur = p; PZ.done = []; PZ.failed = false; PZ.diff = null;
  pzBoard.flip = p.fen.split(" ")[1] === "b";
  pzBoard.set(p.fen, { last: p.opponent_move });
  $("#pz-info").textContent = `${PZ.probe ? "Проба · " : ""}Рейтинг ${p.rating} · ${p.themes.slice(0, 4).join(", ")} · соперник сыграл ${p.opponent_san}`;
  $("#pz-msg").textContent = "Твой ход"; $("#pz-reflect").classList.add("hidden");
  PZ.t0 = performance.now(); clearInterval(PZ.timer);
  PZ.timer = setInterval(() => { $("#pz-timer").textContent = ((performance.now() - PZ.t0) / 1000).toFixed(1) + " с"; }, 100);
}
$("#pz-next").addEventListener("click", async () => {
  PZ.probe = null;
  const q = new URLSearchParams({ theme: $("#pz-theme").value, min: $("#pz-min").value, max: $("#pz-max").value });
  startPuzzle(await api("/api/puzzle?" + q));
});
async function pzMove(uci) {
  if (!PZ.cur || !$("#pz-reflect").classList.contains("hidden")) return;
  const r = await api("/api/puzzle/move", { id: PZ.cur.id, done: PZ.done, move: uci });
  if (!r.correct) { PZ.failed = true; $("#pz-msg").innerHTML = `<span class="bad">Нет. Решение: ${esc(r.expected)}</span>`; return endPuzzle(); }
  PZ.done.push(uci); if (r.reply) PZ.done.push(r.reply);
  pzBoard.set(r.fen, { last: r.reply || uci });
  if (r.done) { $("#pz-msg").innerHTML = '<span class="ok">Решено</span>'; endPuzzle(); }
}
function endPuzzle() {
  clearInterval(PZ.timer); PZ.seconds = (performance.now() - PZ.t0) / 1000;
  $("#pz-reflect").classList.remove("hidden"); scale($("#pz-diff"), 5, "diff");
  $("#pz-reasons").querySelectorAll("input").forEach((i) => (i.checked = false));
}
$("#pz-reflect-send").addEventListener("click", async () => {
  const reasons = [...$("#pz-reasons").querySelectorAll("input:checked")].map((i) => i.value);
  await api("/api/puzzle/attempt", { id: PZ.cur.id, seconds: PZ.seconds, solved: !PZ.failed, difficulty: PZ.diff, reasons,
    probe_id: PZ.probe?.probe_id || null });
  $("#pz-reflect").classList.add("hidden");
  if (PZ.probe) {
    if (PZ.queue.length) startPuzzle(PZ.queue.shift());
    else { $("#probe-final").classList.remove("hidden"); scale($("#probe-ease"), 5, "ease"); scale($("#probe-interest"), 5, "interest"); }
  }
});
$("#probe-start").addEventListener("click", async () => {
  PZ.probe = await api("/api/probe", {}); PZ.queue = PZ.probe.puzzles.slice(1);
  $("#probe-result").innerHTML = ""; startPuzzle(PZ.probe.puzzles[0]);
});
$("#probe-finish").addEventListener("click", async () => {
  if (!PZ.ease || !PZ.interest) return alert("Оцени лёгкость и желание играть");
  const r = await api(`/api/probe/${PZ.probe.probe_id}/finish`, { ease: PZ.ease, interest: PZ.interest });
  $("#probe-final").classList.add("hidden"); PZ.probe = null;
  $("#probe-result").innerHTML = `<p><b>${esc(r.verdict)}</b></p>` + (r.mode === "compared"
    ? `<p class="hint">Время (норм.): ${r.mean_norm.toFixed(2)} при средней ${r.average_norm.toFixed(2)} — ${r.slower_than_average ? "медленнее" : "быстрее"} обычного.
       Корреляция времени и лёгкости: ${r.time_ease_correlation == null ? "—" : r.time_ease_correlation.toFixed(2)}. Время суток: ${r.hour}:00.</p>`
    : `<p class="hint">${esc(r.note)}</p>`);
});
$("#pref-save").addEventListener("click", () => api("/api/prefs", { player_rating: Number($("#pref-rating").value) }));
$("#pzi-go").addEventListener("click", async () => {
  const r = await api("/api/puzzles/import", { path: $("#pzi-path").value, themes: $("#pzi-themes").value,
    min: $("#pzi-min").value, max: $("#pzi-max").value, limit: $("#pzi-limit").value });
  alert(`Импортировано: ${r.imported}`); loadThemes();
});

// ===== 6. Библиотека =====
let libItem = null, quizQ = null;
const libBoard = new Board($("#lib-board"));
const quizBoard = new Board($("#quiz-board"));
async function loadLibrary() {
  const items = await api("/api/library");
  $("#lib-list").innerHTML = items.length ? `<table><tr><th>Идея</th><th>Стадия</th><th>Повторений</th><th>Лучший результат</th><th>Место</th></tr>${items.map((i) =>
    `<tr><td>${esc(i.title)}<br><span class="hint">${esc(i.chunk || "")}</span></td><td>${STAGE[i.stage] || "—"}</td><td>${i.reviews}</td><td>${Math.round(i.best_score * 100)}%</td><td>${esc(i.locus || "")}</td></tr>`).join("")}</table>`
    : '<p class="hint">Пока пусто: сохраняйте идеи со вкладки «Партия».</p>';
  renderMastery((await api("/api/stats")).mastery);
}
onTab.library = loadLibrary;
$("#lib-next").addEventListener("click", async () => {
  libItem = await api("/api/library/next");
  if (!libItem) return alert("Библиотека пуста");
  libBoard.flip = libItem.fen.split(" ")[1] === "b"; libBoard.set(libItem.fen); libBoard.hide(false);
  $("#lib-task").innerHTML = `<p><b>${esc(libItem.title)}</b> — воспроизведи ключевую линию (${libItem.key_line.length} полуходов)${$("#lib-memory").checked ? " и позицию" : ""}.</p>`;
  $("#lib-result").innerHTML = ""; $("#lib-line").value = ""; $("#lib-recall").value = "";
  if ($("#lib-memory").checked) setTimeout(() => libBoard.hide(true), Number($("#lib-seconds").value) * 1000);
});
$("#lib-check").addEventListener("click", async () => {
  if (!libItem) return;
  const r = await api(`/api/library/${libItem.id}/review`, { line: $("#lib-line").value, recall: $("#lib-recall").value || null });
  libBoard.hide(false);
  $("#lib-result").innerHTML = `<p>Линия: <b class="${r.line_score === 1 ? "ok" : "bad"}">${Math.round(r.line_score * 100)}%</b> (верно ${r.matched}) — ${esc(r.key_san.join(" "))}
    ${r.recall_score != null ? `<br>Позиция по памяти: <b>${Math.round(r.recall_score * 100)}%</b>` : ""}</p>`;
  loadLibrary();
});
$("#libn-add").addEventListener("click", async () => {
  await api("/api/library", { title: $("#libn-title").value, fen: $("#libn-fen").value, key_line: $("#libn-line").value, locus: $("#libn-locus").value });
  ["#libn-title", "#libn-fen", "#libn-line", "#libn-locus"].forEach((s) => ($(s).value = "")); loadLibrary();
});
$("#quiz-next").addEventListener("click", async () => {
  quizQ = await api("/api/quiz");
  if (!quizQ) { $("#quiz-q").textContent = "Новых позиций нет — разберите ещё партии."; return; }
  quizBoard.flip = quizQ.side === "black"; quizBoard.set(quizQ.fen, { arrows: quizQ.uci + ":blue" });
  $("#quiz-q").innerHTML = `<p>Сыгран ход <b>${esc(quizQ.san)}</b>. Какая это ступень?</p>`;
  $("#quiz-buttons").innerHTML = Object.entries(STEP).filter(([k]) => k !== "forced").map(([k, [n]]) => `<button data-step="${k}" class="s-${k}">${n}</button>`).join("");
  $("#quiz-result").innerHTML = "";
});
$("#quiz-buttons").addEventListener("click", async (e) => {
  const step = e.target.dataset.step; if (!step || !quizQ) return;
  const r = await api("/api/quiz", { game_id: quizQ.game_id, ply: quizQ.ply, settings_version: quizQ.settings_version, answer: step });
  $("#quiz-result").innerHTML = r.correct ? '<p class="ok">Верно (+1)</p>' : `<p class="bad">Это ${STEP[r.truth][0]}. Лучшие: ${esc(r.best.join(", "))}</p>`;
  $("#quiz-buttons").innerHTML = ""; quizQ = null; renderMastery(r.mastery);
});
function renderMastery(m) {
  $("#mastery").innerHTML = `<tr><th>Ступень</th><th>Верно</th><th>Попыток</th><th>Освоено</th></tr>` + Object.entries(m).map(([k, v]) =>
    `<tr><td class="s-${k}">${STEP[k][0]}</td><td>${v.correct}/${v.required}</td><td>${v.attempts}</td><td>${v.mastered ? "✔" : ""}</td></tr>`).join("");
}

// ===== 7. Статистика =====
onTab.stats = async () => {
  const s = await api("/api/stats"), g = s.games;
  const stages = Object.entries(g.by_stage).map(([k, v]) => `<tr><td>${STAGE[k]}</td><td>${v.moves}</td><td>${v.errors}</td>
    <td>${(100 * v.frequency).toFixed(1)}%</td><td>${v.mean_loss_pawns.toFixed(2)}</td><td>${fmtW(v.mean_loss_wdl)}</td></tr>`).join("");
  const steps = Object.entries(STEP).map(([k, [n]]) => `<tr><td class="s-${k}">${n}</td><td>${g.steps[k] || 0}</td></tr>`).join("");
  const motifs = Object.entries(g.idea_motifs).map(([k, v]) => `${MOTIF[k] || k}: ${v}`).join(", ") || "—";
  const dist = Object.entries(g.idea_distances).map(([k, v]) => `${k}: ${v}`).join(", ") || "—";
  const cont = g.continuations.map((c) => `${c.diverge_side === "opponent" ? "ответ соперника" : c.diverge_side === "self" ? "свой ход" : "совпало"} / ${c.diverge_kind}: ${c.n}`).join("; ") || "—";
  const themes = s.puzzles.themes.slice(0, 15).map((t) => `<tr><td>${esc(t.theme)}</td><td>${t.attempts}</td><td>${(100 * t.fail_rate).toFixed(0)}%</td>
    <td>${t.difficulty == null ? "—" : t.difficulty.toFixed(1)}</td><td>${t.normalized.toFixed(2)}</td><td>${Object.entries(t.reasons).map(([r, n]) => (REASON[r] || r) + ": " + n).join(", ")}</td></tr>`).join("");
  const plan = s.puzzles.plan.map((p) => `<li><b>${esc(p.theme)}</b>: ${esc(p.advice)}</li>`).join("") || "<li class='hint'>мало данных</li>";
  const probes = s.probes.map((p) => `<tr><td>${esc(p.started_at)}</td><td>${p.hour}:00</td><td>${p.mean_norm == null ? "—" : p.mean_norm.toFixed(2)}</td><td>${p.ease}</td><td>${p.interest}</td></tr>`).join("");
  $("#stats").innerHTML = `<p>Очки за процесс: <b>${s.points}</b>${g.player ? ` · игрок: ${esc(g.player)}` : " · ходы обеих сторон"} · ходов: ${g.moves} · pass-флагов: ${g.pass_flags}</p>
    <div class="cols"><div class="grow"><h3>Стадии (ошибки = laxity, mistake, blunder)</h3>
      <table><tr><th>Стадия</th><th>Ходов</th><th>Ошибок</th><th>Частота</th><th>Ср. потеря, пешки</th><th>Ср. потеря, WDL</th></tr>${stages}</table>
      <h3>Ступени</h3><table>${steps}</table></div>
    <div class="grow"><h3>Идеи</h3><p>Мотивы: ${motifs}<br>Дистанции (полуходов): ${dist}</p>
      <h3>«Покажи своё продолжение»: что пропускаешь</h3><p>${esc(cont)}</p>
      <h3>Карта трудностей задач</h3><table><tr><th>Тема</th><th>Попыток</th><th>Провалы</th><th>Сложность</th><th>Время (норм.)</th><th>Причины</th></tr>${themes}</table>
      <h3>План</h3><ul>${plan}</ul>
      <h3>Пробы</h3><table><tr><th>Когда</th><th>Час</th><th>Время (норм.)</th><th>Лёгкость</th><th>Желание</th></tr>${probes}</table></div></div>`;
};

// ===== День =====
onTab.day = async () => {
  const d = await api("/api/day");
  const acts = Object.entries(d.today).map(([k, v]) => `${k}: ${v.count}`).join(", ") || "пока ничего";
  $("#day-summary").innerHTML = `<p>${esc(d.day)} · очков сегодня: <b>${d.today_points}</b> · всего: ${d.total_points}<br><span class="hint">${esc(acts)}</span></p>
    ${d.story ? `<p>Находка дня: <b>${esc(d.story.finding)}</b></p>` : ""}
    ${d.suggestion ? `<p class="hint">Кандидат: ${esc(d.suggestion.chunk)} (дистанция ${d.suggestion.distance})</p>` : ""}`;
  if (d.suggestion && !$("#day-finding").value) $("#day-finding").placeholder = d.suggestion.chunk;
  $("#day-save").onclick = async () => {
    const text = $("#day-finding").value || d.suggestion?.chunk; if (!text) return;
    await api("/api/day", { finding: text, game_id: d.suggestion?.game_id, idea_id: d.suggestion?.id });
    $("#day-finding").value = ""; onTab.day();
  };
};

refreshQueue();
