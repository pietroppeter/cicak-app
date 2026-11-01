# Types, generics and the standard library
# New types and generic procs in one cell, used from the next ones.
# Each cell imports the standard modules it needs.

# %% a type
import std/strutils
type Gecko* = object
  name*: string
  chirps*: int
proc chirp*(g: Gecko): string = g.name & ": " & "cak ".repeat(g.chirps).strip
echo chirp(Gecko(name: "cicak", chirps: 3))

# %% a table of geckos
import std/tables
var geckos* = initTable[string, Gecko]()
for (name, n) in [("cicak", 3), ("tokek", 2)]:
  geckos[name] = Gecko(name: name, chirps: n)
echo geckos.len, " geckos"

# %% a generic proc
proc loudest*[T](xs: openArray[T], key: proc (x: T): int): T =
  result = xs[0]
  for x in xs:
    if key(x) > key(result): result = x
echo "loudest number: ", loudest([3, 9, 4], proc (x: int): int = x)

# %% use all of it
import std/[tables, sequtils]
let all = toSeq(geckos.values)
echo chirp(loudest(all, proc (g: Gecko): int = g.chirps))
