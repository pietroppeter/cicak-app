# What runs again?
# Compare hot reload with re-run: in re-run mode every earlier cell runs again,
# so the clock and the counter change; with hot reloading they keep their values.

# %% start a clock
import std/[times, monotimes]
let started* = getMonoTime()
echo "clock started at ", now().format("HH:mm:ss'.'fff")

# %% a counter
var count* = 0
proc tick*(): int =
  inc count
  count
echo "tick -> ", tick()

# %% tick again
echo "tick -> ", tick(), " (", count, " ticks so far)"

# %% how long ago?
import std/[times, monotimes]
echo "the clock started ", (getMonoTime() - started).inMilliseconds, " ms ago"
