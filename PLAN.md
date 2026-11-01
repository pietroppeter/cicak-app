# Plan

Where the playground is going. Ideas move to cicak's BACKLOG.md when they are about
the REPL itself rather than this app.

## Now (this scaffold)

- Notebooks of predefined cells, added one at a time.
- `nim c` / `nim ic`, hot reload / re-run all, restart, per-step timings, a log.
- Docker image with Nim 2.4 from source, Disco config, CI running every mode.

## Next

1. **Deploy** at cicak.pietroppeter.xyz (Disco project `cicak`, from this repo).
2. **Find out what hot reload + `nim ic` does** (cicak backlog: "HCR together with IC").
   CI reports it; the page shows the error if it fails.
3. **Timings at a glance**: a small summary per session (first compile, mean per
   cell) and a way to compare modes side by side, e.g. run a whole notebook in all
   four modes and show a table. That is the data for the dev log.
4. **Stream output** over a WebSocket (as the counter does), so long compiles show
   progress and output appears as it is printed.
5. **More notebooks** for the experiments to come: redefining a symbol
   (`import cell_K except x`), changing a type (where HCR has to restart), showing
   values (`>>> x`), a slow cell (does re-run pay for it every time?).
6. **Use cicak's engine** once it exists: the app becomes a front end to the JSON-RPC
   server (research post, "Library and service architecture") instead of driving
   `nim` itself.

## Later: typing your own code

The point of a REPL playground, and the risky part: it means running anyone's code on
the server. Before that it needs at least a sandbox per session (no network, read-only
file system apart from the session directory, CPU/memory/time limits, e.g. nsjail or
bubblewrap, or a separate Disco service), rate limits, and probably a sign-in or an
access token. Until then the cells come only from `notebooks/`.

## Open questions

- Should a session survive a page reload? Now a reload starts clean.
- One build at a time is fine for a demo. If several people use it at once, a queue
  with a visible position would be better than waiting silently.
