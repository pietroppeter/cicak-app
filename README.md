# cicak-app 🦎

A playground for [cicak](https://github.com/pietroppeter/cicak), the Nim REPL: add
predefined cells to a live Nim process and see what runs and how long it takes.
Built with [Mummy](https://github.com/guzba/mummy), deployed with [Disco](https://disco.cloud),
in cicak's green theme. Planned home: <https://cicak.pietroppeter.xyz>.

Visitors never type code. They pick a **notebook** (a file in [`notebooks/`](notebooks)),
then add its cells one at a time, choosing:

- the **compiler**: `nim c`, or `nim ic` (incremental compilation)
- how cells **run**: *hot reload* (one host process stays alive; a new cell is compiled
  with `--hotcodereloading:on` and loaded with `performCodeReload()`, so only its
  top-level code runs) or *re-run all* (the program importing every cell is compiled
  and run from scratch, as INim does)

Each added cell shows its output and the time of each step (compile, reload or run).
The **log** lists every command with its duration and output. **Restart** starts over;
changing notebook, compiler or strategy restarts too.

This is the mechanism of cicak's
[hot code reloading proof of concept](https://pietroppeter.github.io/cicak/blog/2026-10-31-hcr-poc.html),
made interactive. Next steps are in [PLAN.md](PLAN.md).

## How it works

Each cell becomes a module `cell_<k>.nim` that imports every earlier cell, and
`cells.nim` imports them all. With hot reload, `host.nim` imports `cells` and waits on
stdin; the server regenerates `cells.nim`, recompiles (to `host.next`: the running
executable can't be overwritten, the cell libraries are what matter) and sends
`reload`. With re-run, `prog.nim` imports `cells` and is compiled and run each time.

| Route | What |
|---|---|
| `GET /` | the page |
| `GET /api/info` | Nim version, notebooks and their cells |
| `POST /api/add` | `{session, cell, compiler: "c"\|"ic", strategy: "hcr"\|"rerun"}`: output, steps with timings |
| `POST /api/restart` | `{session}` |
| `GET /health` | `ok` |

Sessions live on the server (a directory per session under `WORK_DIR`, plus the host
process). One build or run happens at a time; at most 6 sessions, idle ones end after
20 minutes.

## Notebooks

One `.nim` file per notebook, in jupytext's percent format:

```nim
# Title of the notebook
# More comment lines before the first cell are its description.

# %% title of a cell
var x* = 41
echo "x = ", x

# %% another cell
echo x + 1
```

Every cell imports the cells added before it, so symbols later cells use need `*`.
Each cell imports the standard modules it uses.

## Run locally

Needs Nim 2.4 built from source (see [cicak's setup](https://github.com/pietroppeter/cicak#setup)):
hot code reloading crashes at startup on Nim 2.2, and `nim ic` needs `nifler`. On 2.2,
*re-run all* with `nim c` works.

```sh
./deps.sh                                  # clones the pinned dependencies into deps/
nim c -d:release -o:cicak_app src/cicak_app.nim
./cicak_app                                # http://localhost:8000
python3 tests/e2e.py                       # adds cells in every mode against it
```

Or with Docker (the first build compiles Nim, a few minutes):

```sh
docker build -t cicak-app . && docker run --rm -p 8000:8000 cicak-app
```

Environment: `PORT` (8000), `WORK_DIR` (session files), `NOTEBOOKS_DIR` (next to the
binary), `RTL_DIR` (where `libnimrtl.so` and `libnimhcr.so` are; built on first use if missing),
`NIM` (the compiler).

## Deploy

`Dockerfile` + `disco.json`, as in [disco-nim-mummy](https://github.com/pietroppeter/disco-nim-mummy):
the `web` service on port 8000 with a `/health` check. No volume: sessions are
throwaway. The image keeps Nim and gcc, since cells are compiled at run time.

## CI

`e2e` builds Nim 2.4 from source (cached), builds the app and runs `tests/e2e.py`:
the "Hot reloading basics" notebook in all four modes. Hot reload with `nim ic` has
never been tried, so it is reported but doesn't fail CI yet. `docker` builds the image
and runs the same test against the container.
