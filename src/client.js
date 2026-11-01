// The playground page: pick a notebook, a compiler and a strategy, then add cells.
// The server keeps the session (the cell modules and, with hot reload, the host
// process); this script only shows it.
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
      const on = state.compiler === c && state.strategy === st;
      html += unsupported(c, st)
        ? `<button class="sq na" disabled role="radio" aria-checked="false" title="${cname}, ${sname}: not supported yet" aria-label="${cname}, ${sname}: not supported yet">n/a</button>`
        : `<button class="sq" data-mode="${c}:${st}" role="radio" aria-checked="${on}" title="${cname}, ${sname}" aria-label="${cname}, ${sname}">${on ? selectedMark : ""}</button>`;
    }
  }
  $("mode").innerHTML = html;
}

const state = {
  session: sessionStorage.getItem("cicak-session") || newId(),
  notebooks: [], notebook: null, compiler: "c", strategy: "hcr",
  added: [],   // [{cell, result}]
  log: [], busy: false,
};
sessionStorage.setItem("cicak-session", state.session);

function newId() {
  const id = (crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2) + Date.now());
  sessionStorage.setItem("cicak-session", id);
  return id;
}

function highlight(code) {
  if (window.hljs) { try { return hljs.highlight(code, { language: "nim" }).value; } catch (e) {} }
  return esc(code);
}

async function post(path, body) {
  const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  return r.json();
}

async function restart(note) {
  const old = state.session;
  state.added = [];
  state.session = newId();
  if (note) state.log.unshift({ note });
  render();
  // the old session is dropped on the server too (it would also expire on its own)
  post("/api/restart", { session: old }).catch(() => {});
}

function timingLine(res) {
  const parts = res.steps.map((s) => `${esc(s.name)} <b>${secs(s.ms)}</b>`);
  return parts.join(" · ") + ` · total <b>${secs(res.totalMs)}</b>`;
}

function render() {
  const nb = state.notebook;
  $("notebooks").innerHTML = state.notebooks.map((n) =>
    `<button data-v="${esc(n.id)}" aria-pressed="${nb && n.id === nb.id}">${esc(n.title)}</button>`).join("");
  $("about").textContent = nb ? nb.about : "";
  renderMode();
  $("strategy-hint").innerHTML = esc(hints[state.strategy]) + (state.compiler === "ic" ? " " + hcrIcNote : "");

  $("session").innerHTML = state.added.length === 0 ? `<p class="empty">No cells yet. Add one below.</p>` :
    state.added.map(({ cell, result }, i) => `
      <div class="cell done">
        <div class="head"><span class="title">${esc(cell.title)}</span><span class="label">cell ${i + 1}</span></div>
        <pre class="code"><code>${highlight(cell.code)}</code></pre>
        <pre class="out">${result.output ? esc(result.output) : "<span class=\"empty\">no output</span>"}</pre>
        <div class="timing">${timingLine(result)}</div>
      </div>`).join("");

  const addedIds = new Set(state.added.map((a) => a.cell.id));
  const next = nb ? nb.cells.filter((c) => !addedIds.has(c.id)) : [];
  $("next").innerHTML = next.length === 0 ? `<p class="empty">All cells added. Restart to try another mode.</p>` :
    next.map((c) => `
      <div class="cell next">
        <div class="head"><span class="title">${esc(c.title)}</span></div>
        <pre class="code"><code>${highlight(c.code)}</code></pre>
        <div class="row"><button class="btn primary" data-add="${esc(c.id)}" ${state.busy ? "disabled" : ""}>Add cell</button></div>
      </div>`).join("");

  $("busy").innerHTML = state.busy ? `<p class="busy">${esc(state.busy)}</p>` : "";
  for (const b of document.querySelectorAll(".controls button:not(.na), #notebooks button")) b.disabled = !!state.busy;

  $("log-list").innerHTML = state.log.map((e) => e.note ? `<li><span class="label">${esc(e.note)}</span></li>` :
    `<li class="${e.ok ? "" : "bad"}"><b>${esc(e.cell)}</b> · ${esc(e.name)} · ${secs(e.ms)} ${e.ok ? "" : "· failed"}
      <div class="cmd">$ ${esc(e.cmd)}</div>${e.log ? `<pre>${esc(e.log)}</pre>` : ""}</li>`).join("");
}

async function addCell(cellId) {
  const cell = state.notebook.cells.find((c) => c.id === cellId);
  state.busy = `${state.strategy === "hcr" ? "compiling and reloading" : "compiling and running"} “${cell.title}” with nim ${state.compiler}…`;
  render();
  try {
    const res = await post("/api/add", { session: state.session, notebook: state.notebook.id, cell: cellId,
                                          compiler: state.compiler, strategy: state.strategy });
    for (const s of (res.steps || []).slice().reverse()) state.log.unshift({ cell: cell.title, ...s });
    if (res.ok) {
      state.added.push({ cell, result: res });
    } else {
      state.log.unshift({ note: `“${cell.title}” was not added: ${res.error}` });
      $("log").open = true;
      if ((res.cells || []).length < state.added.length) state.added = [];  // the host died: the server reset the session
    }
  } catch (e) {
    state.log.unshift({ note: "request failed: " + e.message });
  }
  state.busy = false;
  render();
}

document.addEventListener("click", (ev) => {
  const b = ev.target.closest("button");
  if (!b || b.disabled) return;
  if (b.dataset.add) return addCell(b.dataset.add);
  if (b.dataset.mode) {
    const [c, st] = b.dataset.mode.split(":");
    if (c === state.compiler && st === state.strategy) return;
    state.compiler = c; state.strategy = st;
    return restart(`mode: nim ${c}, ${st === "hcr" ? "hot reload" : "re-run all"}`);
  }
  const seg = b.parentElement.id;
  if (seg === "notebooks") {
    state.notebook = state.notebooks.find((n) => n.id === b.dataset.v);
    return restart(`notebook: ${state.notebook.title}`);
  }
  if (b.id === "restart") return restart("restarted");
});

(async () => {
  const info = await (await fetch("/api/info")).json();
  $("meta").textContent = info.nim;
  state.notebooks = info.notebooks;
  state.notebook = info.notebooks[0] || null;
  await post("/api/restart", { session: state.session });  // a reload starts clean
  render();
})();
