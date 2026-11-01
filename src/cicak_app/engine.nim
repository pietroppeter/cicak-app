## The engine behind the playground: a session adds predefined cells, one
## module per cell, and runs them in one of two ways:
##
## - `hcr` (hot code reloading): a long-running host process imports `cells`,
##   a module that imports every cell so far. Adding a cell regenerates
##   `cells.nim`, recompiles with `--hotcodereloading:on` and asks the host to
##   `performCodeReload()`. Only the new cell's top-level code runs.
## - `rerun`: the program importing all cells is recompiled and run from
##   scratch, as INim does. Every cell's top-level code runs again.
##
## Either way the compiler is `nim c` or `nim ic` (incremental compilation).
## Every command is recorded as a `Step` with its duration and output, which the
## page shows as the log.
##
## The cells come from `notebooks/` and are never typed by visitors, so the
## playground runs only code that is in the repository.

import std/[os, osproc, streams, strutils, strtabs, times, monotimes, tables, locks, json]

type
  Compiler* = enum ccC = "c", ccIc = "ic"
  Strategy* = enum stHcr = "hcr", stRerun = "rerun"
  Step* = object
    name*, cmd*, log*: string
    ms*: float
    ok*: bool
  AddResult* = object
    ok*: bool
    index*: int        ## 1-based position of the new cell, 0 if it was not added
    output*: string    ## what the program printed for this step
    error*: string
    steps*: seq[Step]
    totalMs*: float
  Session* {.acyclic.} = ref object
    id*: string
    dir: string
    notebook*: string
    compiler*: Compiler
    strategy*: Strategy
    cells*: seq[string]   ## ids of the added cells
    host: Process         ## hcr only
    lastUsed: MonoTime

const
  Marker = "\x1fcicak:"   # host -> server: "\x1fcicak:ready" / "\x1fcicak:done"
  NimFlags = "--hints:off --warnings:off"
  HostSource = """
import std/hotcodereloading
import cells

setStdIoUnbuffered()
stdout.write "$1ready\n"
stdout.flushFile
var line: string
while stdin.readLine(line):
  if line == "reload":
    performCodeReload()
    stdout.write "$1done\n"
    stdout.flushFile
""" % Marker
  ProgSource = "import cells\n"
  MaxSessions = 6
  IdleTimeout = initDuration(minutes = 20)
  CompileTimeoutS = 180
  RunTimeoutS = 20
  MaxLog = 20_000

var
  workDir* = getEnv("WORK_DIR", getTempDir() / "cicak-app")
  nimExe* = getEnv("NIM", "nim")
  lock: Lock            ## one build or run at a time, server-wide
  sessions: Table[string, Session]

initLock(lock)

proc nimLib(): string =
  getEnv("NIM_LIB", findExe(nimExe).parentDir.parentDir / "lib")

proc rtlDir(): string = getEnv("RTL_DIR", workDir / "rtl")

proc elapsedMs(t0: MonoTime): float = (getMonoTime() - t0).inMicroseconds.float / 1000

proc clip(s: string): string =
  if s.len <= MaxLog: s else: s[0 ..< MaxLog] & "\n… (" & $(s.len - MaxLog) & " more bytes)"

proc run(name, cmd, dir: string, timeoutS: int, env: StringTableRef = nil): Step =
  ## Runs a shell command in `dir` with a time limit and records it.
  let t0 = getMonoTime()
  let full = "timeout " & $timeoutS & " " & cmd
  let p = startProcess("/bin/sh", workingDir = dir, args = ["-c", full], env = env,
                       options = {poStdErrToStdOut})
  let output = p.outputStream.readAll
  let code = p.waitForExit
  p.close
  result = Step(name: name, cmd: cmd, ms: elapsedMs(t0), ok: code == 0,
                log: clip(output.replace(dir & "/", "").strip))
  if code == 124: result.log.add "\n(timed out after " & $timeoutS & " s)"
  elif code != 0: result.log.add "\n(exit code " & $code & ")"

proc hostEnv(): StringTableRef =
  result = newStringTable(modeCaseSensitive)
  for k, v in envPairs(): result[k] = v
  result["LD_LIBRARY_PATH"] = rtlDir() & (if existsEnv("LD_LIBRARY_PATH"): ":" & getEnv("LD_LIBRARY_PATH") else: "")

proc ensureRtl(steps: var seq[Step]): bool =
  ## Builds the two runtime libraries hot code reloading needs, once.
  let dir = rtlDir()
  if fileExists(dir / "libnimhcr.so") and fileExists(dir / "libnimrtl.so"): return true
  createDir(dir)
  for (name, lib, def) in [("build libnimrtl.so", "nimrtl", "createNimRtl"),
                           ("build libnimhcr.so", "nimhcr", "createNimHcr")]:
    let s = run(name, nimExe & " c " & NimFlags & " --app:lib -d:" & def &
                " --nimcache:nimcache_" & lib & " --out:lib" & lib & ".so " &
                quoteShell(nimLib() / lib & ".nim"), dir, CompileTimeoutS)
    steps.add s
    if not s.ok: return false
  true

proc compileCmd(s: Session, main, output: string): string =
  result = nimExe & " " & $s.compiler & " " & NimFlags & " --nimcache:nimcache"
  if s.strategy == stHcr: result.add " --hotcodereloading:on"
  result.add " --out:" & output & " " & main

proc stopHost(s: Session) =
  if s.host != nil:
    try:
      s.host.terminate
      discard s.host.waitForExit(2000)
      if s.host.running: s.host.kill
      s.host.close
    except CatchableError: discard
    s.host = nil

proc readUntilMarker(s: Session, what: string, output: var string): bool =
  ## Reads the host's output up to the marker line `what`. False if the host died.
  var line: string
  while s.host.outputStream.readLine(line):
    if line.startsWith(Marker):
      if line == Marker & what: return true
    else:
      output.add line & "\n"
  false

proc writeCellFiles(s: Session, code: string): int =
  ## Writes cell_<k>.nim importing every earlier cell, and the `cells` module.
  let k = s.cells.len + 1
  var imports = ""
  for i in 1 ..< k: imports.add "import cell_" & $i & "\n"
  writeFile(s.dir / "cell_" & $k & ".nim", imports & code & "\n")
  var all = ""
  for i in 1 .. k: all.add "import cell_" & $i & "\n"
  writeFile(s.dir / "cells.nim", all)
  k

proc restoreCellFiles(s: Session, k: int) =
  removeFile(s.dir / "cell_" & $k & ".nim")
  var all = ""
  for i in 1 ..< k: all.add "import cell_" & $i & "\n"
  writeFile(s.dir / "cells.nim", all)

proc addCell*(s: Session, cellId, code: string): AddResult =
  let t0 = getMonoTime()
  let k = s.writeCellFiles(code)
  var output = ""
  template fail(msg: string) =
    s.restoreCellFiles(k)
    result.error = msg
    result.output = output
    result.totalMs = elapsedMs(t0)
    return
  case s.strategy
  of stRerun:
    let c = run("compile", s.compileCmd("prog.nim", "prog"), s.dir, CompileTimeoutS)
    result.steps.add c
    if not c.ok: fail "the cell does not compile"
    let r = run("run", "./prog", s.dir, RunTimeoutS)
    result.steps.add r
    output = r.log
    if not r.ok: fail "the program failed"
  of stHcr:
    if not ensureRtl(result.steps): fail "could not build the hot code reloading runtime"
    if s.host == nil:
      let c = run("compile host", s.compileCmd("host.nim", "host"), s.dir, CompileTimeoutS)
      result.steps.add c
      if not c.ok: fail "the cell does not compile"
      let t1 = getMonoTime()
      s.host = startProcess(s.dir / "host", workingDir = s.dir, env = hostEnv(),
                            options = {poStdErrToStdOut})
      let ok = s.readUntilMarker("ready", output)
      result.steps.add Step(name: "start host", cmd: "./host", ms: elapsedMs(t1), ok: ok,
                            log: clip(output.strip))
      if not ok:
        s.stopHost
        fail "the host process exited (hot code reloading needs Nim 2.4: it crashes at startup on 2.2)"
    else:
      # the running executable can't be overwritten: the cell libraries are what matter
      let c = run("compile", s.compileCmd("host.nim", "host.next"), s.dir, CompileTimeoutS)
      result.steps.add c
      if not c.ok: fail "the cell does not compile"
      let t1 = getMonoTime()
      var ok = false
      try:
        s.host.inputStream.write "reload\n"
        s.host.inputStream.flush
        ok = s.readUntilMarker("done", output)
      except CatchableError as e:
        output.add e.msg
      result.steps.add Step(name: "reload", cmd: "performCodeReload()", ms: elapsedMs(t1), ok: ok,
                            log: clip(output.strip))
      if not ok:
        s.stopHost
        s.cells.setLen(0)
        fail "the host process exited during the reload; restart the session"
  s.cells.add cellId
  result.ok = true
  result.index = k
  result.output = output.strip(leading = false)
  result.totalMs = elapsedMs(t0)

proc newSession(id, notebook: string, compiler: Compiler, strategy: Strategy): Session =
  result = Session(id: id, dir: workDir / "sessions" / id, notebook: notebook,
                   compiler: compiler, strategy: strategy, lastUsed: getMonoTime())
  removeDir(result.dir)
  createDir(result.dir)
  writeFile(result.dir / "host.nim", HostSource)
  writeFile(result.dir / "prog.nim", ProgSource)
  writeFile(result.dir / "cells.nim", "")

proc dropSession(id: string) =
  if id in sessions:
    let s = sessions[id]
    s.stopHost
    removeDir(s.dir)
    sessions.del id

proc sweep() =
  ## Ends idle sessions, and the oldest ones beyond MaxSessions.
  var idle: seq[string]
  for id, s in sessions:
    if getMonoTime() - s.lastUsed > IdleTimeout: idle.add id
  for id in idle: dropSession(id)
  while sessions.len >= MaxSessions:
    var oldest = ""
    for id, s in sessions:
      if oldest == "" or s.lastUsed < sessions[oldest].lastUsed: oldest = id
    dropSession(oldest)

proc validId*(id: string): bool =
  id.len in 8 .. 64 and id.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '-'})

proc addCellTo*(id, notebook: string, compiler: Compiler, strategy: Strategy,
                cellId, code: string): (AddResult, seq[string]) =
  ## Adds a cell to session `id`, starting a fresh session if there is none or
  ## if the notebook, compiler or strategy changed. Returns the result and the
  ## ids of the cells in the session afterwards.
  withLock lock:
    {.gcsafe.}:
      var s = sessions.getOrDefault(id)
      if s == nil or s.notebook != notebook or s.compiler != compiler or s.strategy != strategy:
        dropSession(id)
        sweep()
        s = newSession(id, notebook, compiler, strategy)
        sessions[id] = s
      s.lastUsed = getMonoTime()
      result = (s.addCell(cellId, code), s.cells)

proc restart*(id: string) =
  withLock lock:
    {.gcsafe.}:
      dropSession(id)

proc shutdown*() =
  withLock lock:
    {.gcsafe.}:
      var ids: seq[string]
      for id in sessions.keys: ids.add id
      for id in ids: dropSession(id)

proc nimVersion*(): string =
  try:
    let (o, _) = execCmdEx(nimExe & " -v")
    o.splitLines()[0]
  except CatchableError: "nim not found"

proc `%`*(s: Step): JsonNode =
  %*{"name": s.name, "cmd": s.cmd, "log": s.log, "ms": s.ms, "ok": s.ok}

proc `%`*(r: AddResult): JsonNode =
  %*{"ok": r.ok, "index": r.index, "output": r.output, "error": r.error,
     "steps": r.steps, "totalMs": r.totalMs}
