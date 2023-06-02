iterator a(): int {.closure.} =
  var c = 0
  yield c
  c += 1
  yield c

type A {.acyclic.} = ref object
  p: typeof a
  res: int

import std/monotimes
import std/times

let start = getMonoTime()
var b = new A
for i in 0..1_000_000:
  b.p = a
  discard b.p()
let e = getMonoTime()
echo (e - start).inMilliseconds