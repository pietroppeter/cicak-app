## cicak playground: run predefined notebook cells in a live Nim process.
##
##   GET  /                 the page
##   GET  /api/info         Nim version and the notebooks with their cells
##   POST /api/add          {session, notebook, cell, compiler, strategy} -> result
##   POST /api/restart      {session}
##   GET  /health
##
## Visitors only pick cells from `notebooks/`; no code is ever sent by the page.

import std/[os, strutils, json]
import mummy, mummy/routers
import cicak_app/[engine, notebooks]

const
  pageHtml = staticRead("page.html")
  clientJs = staticRead("client.js")

let
  port = getEnv("PORT", "8000").parseInt
  notebooksDir = getEnv("NOTEBOOKS_DIR", getAppDir() / "notebooks")
  allNotebooks = loadNotebooks(notebooksDir)
  infoJson = block:
    var nbs = newJArray()
    for nb in allNotebooks:
      var cells = newJArray()
      for c in nb.cells: cells.add %*{"id": c.id, "title": c.title, "code": c.code}
      nbs.add %*{"id": nb.id, "title": nb.title, "about": nb.about, "cells": cells}
    $ %*{"nim": nimVersion(), "notebooks": nbs}

proc findCell(cellId: string): (string, string) =
  ## (notebook id, code) of a cell, or ("", "") if there is no such cell.
  {.gcsafe.}:
    for nb in allNotebooks:
      for c in nb.cells:
        if c.id == cellId: return (nb.id, c.code)

proc jsonResponse(request: Request, code: int, body: JsonNode) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(code, headers, $body)

proc badRequest(request: Request, msg: string) =
  request.jsonResponse(400, %*{"ok": false, "error": msg})

proc indexHandler(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html; charset=utf-8"
  request.respond(200, headers, pageHtml.replace("/*CLIENT_JS*/", clientJs))

proc infoHandler(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  {.gcsafe.}:
    request.respond(200, headers, infoJson)

proc addHandler(request: Request) =
  var body: JsonNode
  try: body = parseJson(request.body)
  except CatchableError:
    request.badRequest("invalid JSON"); return
  let session = body{"session"}.getStr
  if not validId(session):
    request.badRequest("invalid session id"); return
  let (notebook, code) = findCell(body{"cell"}.getStr)
  if notebook.len == 0:
    request.badRequest("unknown cell"); return
  var compiler: Compiler
  var strategy: Strategy
  try:
    compiler = parseEnum[Compiler](body{"compiler"}.getStr("c"))
    strategy = parseEnum[Strategy](body{"strategy"}.getStr("hcr"))
  except ValueError:
    request.badRequest("unknown compiler or strategy"); return
  let (res, cells) = addCellTo(session, notebook, compiler, strategy, body{"cell"}.getStr, code)
  var j = %res
  j["cells"] = %cells
  request.jsonResponse(200, j)

proc restartHandler(request: Request) =
  var body: JsonNode
  try: body = parseJson(request.body)
  except CatchableError:
    request.badRequest("invalid JSON"); return
  let session = body{"session"}.getStr
  if not validId(session):
    request.badRequest("invalid session id"); return
  restart(session)
  request.jsonResponse(200, %*{"ok": true})

proc healthHandler(request: Request) =
  request.respond(200, emptyHttpHeaders(), "ok")

when isMainModule:
  var router: Router
  router.get("/", indexHandler)
  router.get("/api/info", infoHandler)
  router.post("/api/add", addHandler)
  router.post("/api/restart", restartHandler)
  router.get("/health", healthHandler)
  let server = newServer(router)
  echo "cicak playground on 0.0.0.0:", port, " with ", allNotebooks.len,
    " notebooks from ", notebooksDir, ", work dir ", workDir, ", ", nimVersion()
  server.serve(Port(port), "0.0.0.0")
