import nimuring/async

import std/monotimes, times

var
  i = 0
  prev = 0

proc cb() =
  i += 1

for coros in @[1, 10, 100, 1000, 100_000, 1_000_000]:
  i = 0
  prev = 0
  for _ in 0..coros:
    callSoon(cb)
  let start = getMonoTime()
  while i < 1_000_000:
    poll()
    for _ in 0..(i - prev):
      callSoon(cb)
    prev = i
  echo "coro: ", coros, " time: ", (getMonoTime() - start).inMilliseconds, "ms"