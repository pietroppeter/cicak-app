// The playground page: one tab per notebook, each with its own session and mode.
// Add the next cell, or restart. The server keeps each session (the cell modules
// and, with hot reload, the host process); this script only shows them.
"use strict";
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const secs = (ms) => (ms >= 1000 ? (ms / 1000).toFixed(2) + " s" : ms.toFixed(ms < 10 ? 1 : 0) + " ms");

const hints = {
  hcr: "One host process stays alive. A new cell is compiled with --hotcodereloading:on and loaded with performCodeReload(): only its top-level code runs.",
  rerun: "The program importing every cell so far is compiled and run from scratch, as INim does: every cell runs again.",
};

const compilers = [["c", "nim c"], ["ic", "nim ic"]];
const strategies = [["rerun", "re-run all"], ["hcr", "hot reload"]];
const selectedMark = "🦎";
// hot reload with nim ic does not link on Nim 2.4 (cicak experiments/hcr-ic)
const unsupported = (compiler, strategy) => compiler === "ic" && strategy === "hcr";
const hcrIcNote = `Hot reload with nim ic is not available: Nim 2.4's incremental backend does not support hot code reloading (<a href="https://github.com/pietroppeter/cicak/tree/main/experiments/hcr-ic">why</a>).`;

function renderMode() {
  let html = `<span></span>` + strategies.map(([, name]) => `<span class="col">${name}</span>`).join("");
  for (const [c, cname] of compilers) {
    html += `<span class="row">${cname}</span>`;
    for (const [st, sname] of strategies) {
      const on = tab().compiler === c && tab().strategy === st;
      html += unsupported(c, st)
        ? `<button class="sq na" disabled role="radio" aria-checked="false" title="${cname}, ${sname}: not supported yet" aria-label="${cname}, ${sname}: not supported yet">n/a</button>`
        : `<button class="sq" data-mode="${c}:${st}" role="radio" aria-checked="${on}" title="${cname}, ${sname}" aria-label="${cname}, ${sname}">${on ? selectedMark : ""}</button>`;
    }
  }
  $("mode").innerHTML = html;
}

const state = {
  base: newId(),     // a page load starts clean: fresh server sessions
  notebooks: [], current: null,
  tabs: {},          // notebook id -> {session, compiler, strategy, added: [{cell, result}]}
  log: [], busy: false,
};

function newId() {
  return crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2) + Date.now();
}

function tab(id = state.current) {
  if (!state.tabs[id]) state.tabs[id] = { session: `${state.base}-${id}-0`, compiler: "c", strategy: "hcr", added: [], n: 0 };
  return state.tabs[id];
}
const notebook = (id = state.current) => state.notebooks.find((n) => n.id === id);

function highlight(code) {
  if (window.hljs) { try { return hljs.highlight(code, { language: "nim" }).value; } catch (e) {} }
  return esc(code);
}

async function post(path, body) {
  const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  return r.json();
}

function restart(note) {
  const t = tab();
  const old = t.session;
  t.added = [];
  t.session = `${state.base}-${state.current}-${++t.n}`;
  if (note) state.log.unshift({ note: `${notebook().title}: ${note}` });
  render();
  // the old session is dropped on the server too (it would also expire on its own)
  post("/api/restart", { session: old }).catch(() => {});
}

function timingLine(res) {
  const parts = res.steps.map((s) => `<span class="step">${esc(s.name)} <b>${secs(s.ms)}</b></span>`);
  return parts.join(" · ") + ` · <span class="step">total <b>${secs(res.totalMs)}</b></span>`;
}

function render() {
  const nb = notebook(), t = tab();
  $("notebooks").innerHTML = state.notebooks.map((n) => {
    const k = tab(n.id).added.length;
    return `<button role="tab" data-tab="${esc(n.id)}" aria-selected="${n.id === state.current}">${esc(n.title)}${k ? ` <span class="count">${k}</span>` : ""}</button>`;
  }).join("");
  $("about").textContent = nb ? nb.about : "";
  renderMode();
  $("strategy-hint").innerHTML = esc(hints[t.strategy]) + (t.compiler === "ic" ? " " + hcrIcNote : "");

  $("session").innerHTML = t.added.map(({ cell, result }, i) => `
      <div class="cell done">
        <div class="head"><span class="title">${esc(cell.title)}</span><span class="label">cell ${i + 1}</span></div>
        <pre class="code"><code>${highlight(cell.code)}</code></pre>
        <pre class="out">${result.output ? esc(result.output) : "<span class=\"empty\">no output</span>"}</pre>
        <div class="timing">${timingLine(result)}</div>
      </div>`).join("");

  // only the next cell can be added: each cell imports the ones before it
  const rest = nb ? nb.cells.slice(t.added.length) : [];
  const restartBtn = `<button class="btn" id="restart" ${t.added.length ? "" : "disabled"}>Restart</button>`;
  $("next").innerHTML = rest.length === 0
    ? `<div class="row"><p class="empty">All cells added.</p>${restartBtn}</div>`
    : `<div class="cell next">
        <div class="head"><span class="title">${esc(rest[0].title)}</span><span class="label">next: cell ${t.added.length + 1}</span></div>
        <pre class="code"><code>${highlight(rest[0].code)}</code></pre>
        <div class="row"><button class="btn primary" data-add="${esc(rest[0].id)}">Add cell</button>${restartBtn}</div>
      </div>` + (rest.length > 1 ? `<p class="later">then: ${rest.slice(1).map((c) => esc(c.title)).join(" · ")}</p>` : "");

  $("busy").innerHTML = state.busy ? `<p class="busy">${esc(state.busy)}</p>` : "";
  for (const b of document.querySelectorAll("main button:not(.na)")) b.disabled = !!state.busy || (b.id === "restart" && !t.added.length);

  $("log-list").innerHTML = state.log.map((e) => e.note ? `<li><span class="label">${esc(e.note)}</span></li>` :
    `<li class="${e.ok ? "" : "bad"}"><b>${esc(e.cell)}</b> · ${esc(e.name)} · ${secs(e.ms)} ${e.ok ? "" : "· failed"}
      <div class="cmd">$ ${esc(e.cmd)}</div>${e.log ? `<pre>${esc(e.log)}</pre>` : ""}</li>`).join("");
}

async function addCell(cellId) {
  const nbId = state.current, t = tab(), nb = notebook();
  const cell = nb.cells.find((c) => c.id === cellId);
  state.busy = `${t.strategy === "hcr" ? "compiling and reloading" : "compiling and running"} “${cell.title}” with nim ${t.compiler}…`;
  render();
  let ok = false;
  try {
    const res = await post("/api/add", { session: t.session, notebook: nbId, cell: cellId,
                                          compiler: t.compiler, strategy: t.strategy });
    for (const s of (res.steps || []).slice().reverse()) state.log.unshift({ cell: cell.title, ...s });
    if (res.ok && (res.cells || []).length === t.added.length + 1) {
      t.added.push({ cell, result: res });
      ok = true;
    } else if (res.ok) {
      // the server ended this session meanwhile (idle, or too many sessions)
      state.log.unshift({ note: `${nb.title}: the server had ended this session; restarted` });
      t.added = [];
      post("/api/restart", { session: t.session }).catch(() => {});
    } else {
      state.log.unshift({ note: `“${cell.title}” was not added: ${res.error}` });
      if ((res.cells || []).length < t.added.length) t.added = [];  // the host died: the server reset the session
    }
  } catch (e) {
    state.log.unshift({ note: "request failed: " + e.message });
  }
  state.busy = false;
  render();
  if (ok) {
    document.querySelector("#session .cell:last-child").scrollIntoView({ behavior: "smooth", block: "start" });
  } else {
    $("log").open = true;
    $("log").scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

document.addEventListener("click", (ev) => {
  const b = ev.target.closest("button");
  if (!b || b.disabled) return;
  if (b.dataset.add) return addCell(b.dataset.add);
  if (b.dataset.tab) { state.current = b.dataset.tab; return render(); }
  if (b.dataset.mode) {
    const t = tab();
    const [c, st] = b.dataset.mode.split(":");
    if (c === t.compiler && st === t.strategy) return;
    const k = t.added.length;
    if (k && !confirm(`Changing mode restarts “${notebook().title}”: its ${k} cell${k > 1 ? "s" : ""} will be cleared.`)) return;
    t.compiler = c; t.strategy = st;
    return restart(`mode: nim ${c}, ${st === "hcr" ? "hot reload" : "re-run all"}`);
  }
  if (b.id === "restart") return restart("restarted");
});

(async () => {
  const info = await (await fetch("/api/info")).json();
  $("meta").textContent = info.nim;
  state.notebooks = info.notebooks;
  state.current = info.notebooks[0] ? info.notebooks[0].id : null;
  render();
})();
