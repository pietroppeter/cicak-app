## Predefined notebooks: one `.nim` file per notebook in `notebooks/`.
##
## Format (close to jupytext's percent format):
##
##   # Title of the notebook
##   # Any further comment lines before the first cell are the description.
##
##   # %% title of the first cell
##   var x* = 41
##   echo "x = ", x
##
##   # %% title of the second cell
##   ...
##
## Top-level symbols that later cells use must be exported with `*`: each cell
## becomes a module that imports all the cells added before it.

import std/[os, strutils, algorithm]

type
  Cell* = object
    id*: string      ## "<notebook>/<n>", n from 1
    title*: string
    code*: string
  Notebook* = object
    id*: string      ## file name without extension
    title*: string
    about*: string
    cells*: seq[Cell]

proc parseNotebook*(id, text: string): Notebook =
  result.id = id
  var
    inCells = false
    title = ""
    code: seq[string]
  proc flush(nb: var Notebook) =
    if inCells:
      while code.len > 0 and code[^1].strip.len == 0: code.setLen(code.len - 1)
      nb.cells.add Cell(id: id & "/" & $(nb.cells.len + 1), title: title, code: code.join("\n"))
    code = @[]
  for line in text.splitLines:
    if line.startsWith("# %%"):
      result.flush()
      inCells = true
      title = line[4 .. ^1].strip
      if title.len == 0: title = "cell " & $(result.cells.len + 1)
    elif inCells:
      if code.len > 0 or line.strip.len > 0: code.add line
    elif line.startsWith("#"):
      let s = line[1 .. ^1].strip
      if result.title.len == 0: result.title = s
      elif s.len > 0: result.about.add (if result.about.len > 0: " " else: "") & s
  result.flush()
  if result.title.len == 0: result.title = id

proc loadNotebooks*(dir: string): seq[Notebook] =
  var files: seq[string]
  for f in walkFiles(dir / "*.nim"): files.add f
  files.sort()
  for f in files:
    result.add parseNotebook(f.splitFile.name, readFile(f))
