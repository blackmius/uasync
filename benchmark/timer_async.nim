when defined(uasync):
  import uasync
# (seconds: 2, nanosecond: 122610)
# (seconds: 2, nanosecond: 68425)
# (seconds: 2, nanosecond: 110762)
# (seconds: 2, nanosecond: 101117)
# (seconds: 2, nanosecond: 73077)
# (seconds: 2, nanosecond: 99900)
# (seconds: 2, nanosecond: 102685)
# (seconds: 2, nanosecond: 62653)
# (seconds: 2, nanosecond: 107019)
# (seconds: 2, nanosecond: 105083)
# (seconds: 2, nanosecond: 110713)
else:
  import std/asyncdispatch
# (seconds: 2, nanosecond: 1366304)
# (seconds: 2, nanosecond: 2068084)
# (seconds: 2, nanosecond: 1686382)
# (seconds: 2, nanosecond: 919747)
# (seconds: 2, nanosecond: 643899)
# (seconds: 2, nanosecond: 812972)
# (seconds: 2, nanosecond: 1884320)
# (seconds: 2, nanosecond: 1484132)
# (seconds: 2, nanosecond: 1796494)
# (seconds: 2, nanosecond: 1396925)
# (seconds: 2, nanosecond: 1384705)

import std/monotimes

proc run() {.async.} =
  for i in 0..10:
    var time = getMonoTime()
    await sleepAsync(2000)
    echo getMonoTime() - time

discard run()

runForever()