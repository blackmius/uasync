import std/[deques, monotimes]
import times, os, posix

import pkg/nimuring
import pkg/cps

import pool

type
  CqeCont = ref object of Continuation
    cqe: Cqe
  Loop = ref object
    q: Queue
    sqes: Deque[Sqe]
    cqes: seq[Cqe]
    events: Pool[Continuation]
    callbacks: Deque[Continuation]

proc newLoop(): owned Loop =
  result = new(Loop)
  result.q = newQueue(4096, {SETUP_SQPOLL})
  result.sqes = initDeque[Sqe](4096)
  result.cqes = newSeq[Cqe](result.q.params.cqEntries)
  result.events = newPool[Continuation]()
  result.callbacks = initDeque[Continuation]()

var loop = newLoop()

template drainQueue(loop: Loop) =
  while loop.sqes.len != 0:
    var sqe = loop.q.getSqe()
    if sqe.isNil:
      break
    sqe[] = loop.sqes.popFirst()
  discard loop.q.submit()

template running(loop: Loop): bool =
  loop.callbacks.len > 0 or loop.events.len > 0

proc run*() =
  while loop.running():
    let callbacksCount = loop.callbacks.len
    for _ in 1..callbacksCount:
      discard trampoline loop.callbacks.popFirst()
    loop.drainQueue()
    var waitNr = 0.uint
    if loop.callbacks.len == 0 and loop.events.len > 0:
      waitNr = 1
    let ready = loop.q.copyCqes(loop.cqes, waitNr)
    for i in 0..<ready:
      var cqe = loop.cqes[i]
      var index = cqe.userData.int
      var q = CqeCont loop.events[index]
      q.cqe = cqe
      var c: Continuation = q
      discard trampoline c
      if likely(not cqe.flags.contains(CQE_F_MORE)):
        loop.events.free(index)

template spawn*(c: untyped) =
  loop.callbacks.addLast(Continuation whelp c)

proc sqe*(): ptr Sqe {.inline.} =
  result = loop.q.getSqe()
  if result.isNil:
    loop.sqes.addLast(Sqe())
    result = addr loop.sqes.peekLast()

proc event*(c: CqeCont, sqe: ptr Sqe): CqeCont {.cpsMagic.} =
  let index = loop.events.add(Continuation c)
  sqe.setUserData(index)
  return nil

proc jield*(c: Continuation): Continuation {.cpsMagic.} =
  discard

proc data*(c: CqeCont): Cqe {.cpsVoodoo.} =
  c.cqe

template submit*(sqe: ptr Sqe): Cqe =
  event(sqe)
  data()

template asyncio*(prc: typed): untyped =
  cps(CqeCont, prc)

proc checkCqe*(cqe: Cqe): Cqe {.discardable, inline.} =
  if cqe.res < 0:
    raise (ref OSError)(msg: osErrorMsg(OSErrorCode(-cqe.res)), errorCode: -cqe.res)
  cqe

proc nop*() {.asyncio.} =
  checkCqe submit sqe().nop()

proc sleepImpl*(ms: int | float) =
  if ms <= 0:
    return
  let ns = (ms * 1_000_000).int64
  let after = getMonoTime().ticks + ns
  var ts = create(Timespec)
  ts.tv_sec = posix.Time(after.int div 1_000_000_000)
  ts.tv_nsec = after.int mod 1_000_000_000
  # we are using TIMEOUT_ABS to avoid time mismatch
  # if sqe enqueued not now (sqe is overflowed)
  checkCqe submit sqe().timeout(ts, 0, {TIMEOUT_ABS})
  # XXX: create heap sorted by time and set only one timeout for nearest

proc sleep(ms: int) {.asyncio.} =
  sleepImpl(ms)
proc sleep(ms: float) {.asyncio.} =
  sleepImpl(ms)

# XXX: how to syncronize continuations?
# await all, one, race, with errors, ...
# cancel continuation?
