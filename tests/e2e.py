"""End-to-end check of a running playground: python3 tests/e2e.py [base-url]

Adds the "Hot reloading basics" cells in every compiler/strategy combination and
checks what ran. Hot reloading with `nim ic` does not link on Nim 2.4 (cicak
experiments/hcr-ic), so the server refuses it: the check is that it says so.
With --strict (and the server started with CICAK_TRY_HCR_IC=1) it is tried
like the other modes.
"""
import json, sys, time, urllib.request

args = [a for a in sys.argv[1:] if not a.startswith("--")]
BASE = (args[0] if args else "http://localhost:8000").rstrip("/")
STRICT = "--strict" in sys.argv
NB = "01-hot-reload"


def call(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        raw = r.read().decode()
    return json.loads(raw) if path.startswith("/api") else raw


def steps(res):
    return " · ".join(f"{s['name']} {s['ms']:.0f} ms" for s in res["steps"])


failures = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    return cond


assert call("/health") == "ok"
info = call("/api/info")
print(info["nim"])
assert any(nb["id"] == NB for nb in info["notebooks"]), "notebook missing"

for compiler in ["c", "ic"]:
    for strategy in ["hcr", "rerun"]:
        session = f"e2e-{compiler}-{strategy}-{int(time.time())}"
        if compiler == "ic" and strategy == "hcr" and not STRICT:
            print(f"\nnim {compiler}, {strategy} (unsupported)")
            res = call("/api/add", {"session": session, "notebook": NB, "cell": f"{NB}/1",
                                    "compiler": compiler, "strategy": strategy})
            if not check(not res["ok"] and "nim ic" in res["error"] and not res["steps"],
                         f"refused at once: {res['error']}"):
                failures.append(f"nim {compiler} {strategy} refusal")
            call("/api/restart", {"session": session})
            continue
        print(f"\nnim {compiler}, {strategy}")
        good = True
        outputs = []
        for i in range(1, 5):
            res = call("/api/add", {"session": session, "notebook": NB, "cell": f"{NB}/{i}",
                                    "compiler": compiler, "strategy": strategy})
            good &= check(res["ok"], f"cell {i}: {steps(res)} = {res['totalMs']:.0f} ms {res['error']}")
            if not res["ok"]:
                for s in res["steps"]:
                    if not s["ok"]:
                        print("       " + s["log"].replace("\n", "\n       ")[-1500:])
                break
            outputs.append(res["output"])
        if good:
            last = outputs[-1]
            good &= check("y is still 42" in last, "the last cell sees x and y")
            if strategy == "hcr":
                good &= check("x = 41" not in last, "hot reload runs only the new cell")
            else:
                good &= check(last.startswith("x = 41"), "re-run runs every cell again")
        call("/api/restart", {"session": session})
        if not good:
            failures.append(f"nim {compiler} {strategy}")

print("\ncompile errors are reported and the cell is not added")
session = f"e2e-err-{int(time.time())}"
res = call("/api/add", {"session": session, "notebook": NB, "cell": f"{NB}/4", "compiler": "c", "strategy": "rerun"})
if not (check(not res["ok"], "not added") and check("undeclared identifier" in res["steps"][-1]["log"], "the log has the error")):
    failures.append("compile error")
res = call("/api/add", {"session": session, "notebook": NB, "cell": f"{NB}/1", "compiler": "c", "strategy": "rerun"})
if not check(res["ok"] and res["index"] == 1, "the next cell is cell 1"):
    failures.append("after an error")

print("\n" + ("all good" if not failures else "failed: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
