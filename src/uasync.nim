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
    loop.drainQueue()
    let callbacksCount = loop.callbacks.len
    for _ in 1..callbacksCount:
      discard trampoline loop.callbacks.popFirst()
    let ready = loop.q.copyCqes(loop.cqes)
    # echo loop.cqes[0], loop.cqes[1], loop.cqes[2]
    for i in 0..<ready:
      var cqe = loop.cqes[i]
      echo cqe
      var index = cqe.userData.int
      var q = CqeCont loop.events[index]
      q.cqe = cqe
      var c: Continuation = q
      discard trampoline c
      loop.events.free(index)

template callSoon*(c: typed) =
  loop.callbacks.addLast(Continuation whelp c)

proc sqe*(): ptr Sqe {.inline.} =
  result = loop.q.getSqe()
  if result.isNil:
    loop.sqes.addLast(Sqe())
    result = addr loop.sqes.peekLast()

proc event(c: CqeCont, sqe: ptr Sqe): CqeCont {.cpsMagic.} =
  let index = loop.events.add(Continuation c)
  sqe.setUserData(index)
  return nil

proc data(c: CqeCont): Cqe {.cpsVoodoo.} =
  c.cqe

proc submit*(sqe: ptr Sqe): Cqe {.cps: CqeCont.} =
  event(sqe)
  data()

template asyncio*(prc: typed): untyped =
  cps(Continuation, prc)

proc nop*() {.asyncio.} =
  let cqe = submit sqe().nop()
  if cqe.res < 0:
    raise newException(OSError, osErrorMsg(OSErrorCode(cqe.res)))

# var d: CqeCont

# proc test2(c: CqeCont): CqeCont {.cpsMagic.} =
#   d = c
#   return nil

# proc test() {.cps: CqeCont.} =
#   echo "1"
#   test2()
#   echo "2"

# discard trampoline whelp test()
# discard trampoline d
#[
type AsyncFD* = distinct int

proc event*(cb: Callback): ptr Sqe {.discardable, inline.} =
  ## To create your own IO closures
  runnableExamples:
    proc nop(): owned(Future[void]) =
      ## Example wrapping callback into a future
      var retFuture = newFuture[void]("nop")
      proc cb(cqe: Cqe): bool =
        retFuture.complete()
      event(cb)
      return retFuture

    # enqueue an raw Callback
    proc pureCb(cqe: Cqe): bool =
      echo cqe
    event(cb)

  let loop = getLoop()
  loop.drainQueue()
  # move external queue before getting new sqe
  # so its FIFO for requests that doesn't fit previos iteration
  result = loop.q.getSqe()
  if result.isNil:
    loop.sqes.addLast(Sqe())
    result = addr loop.sqes.peekLast()
  
  let ind = loop.events.alloc()
  var event = loop.events.get(ind)
  event.cb = cb

  result.setUserData(ind)

proc nop*(): owned(Future[void]) =
  ## A simple, but nevertheless useful request
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    res.complete()
  discard event(cb)

proc close*(fd: AsyncFD): owned(Future[void]) =
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete()
  discard event(cb).close(cast[SocketHandle](fd))

proc write*(fd: AsyncFD; buffer: pointer; len: int; offset: int = 0): owned(Future[void]) =
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete()
  # TODO: probably buffer can leak if it would destroyed before io_uring it consume
  discard event(cb).write(cast[FileHandle](fd), buffer, len, offset)

proc read*(fd: AsyncFD; buffer: pointer; len: int; offset: int = 0): owned(Future[int]) =
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete(cqe.res)
  discard event(cb).read(cast[FileHandle](fd), buffer, len, offset)

proc accept*(fd: AsyncFD): owned(Future[AsyncFD]) =
  new result
  let res = result
  var accept_addr = create(SockAddr)
  var accept_addr_len = create(SockLen)
  proc cb(cqe: Cqe): bool =
    dealloc(accept_addr)
    dealloc(accept_addr_len)
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete(cast[AsyncFd](cqe.res))
  discard event(cb).accept(cast[SocketHandle](fd), accept_addr, accept_addr_len, O_CLOEXEC)

# proc acceptStream*(fd: AsyncFD): owned(FutureStream[AsyncFD]) =
#   var retFuture = newFutureStream[AsyncFD]("accept")
#   var accept_addr: SockAddr
#   var accept_addr_len: SockLen
#   proc cb(cqe: Cqe): bool {.gcsafe.} =
#     if cqe.res < 0:
#       retFuture.complete()
#       return true
#     else:
#       discard retFuture.write(cast[AsyncFD](cqe.res))
#       if not cqe.flags.contains(CQE_F_MORE):
#         # application should look at the CQE flags and see if
#         # IORING_CQE_F_MORE is set on completion as an indication of
#         # whether or not the accept request will generate further CQEs.
#         event(cb).accept_multishot(cast[SocketHandle](fd), addr accept_addr, addr accept_addr_len, O_CLOEXEC)
#   event(cb).accept_multishot(cast[SocketHandle](fd), addr accept_addr, addr accept_addr_len, O_CLOEXEC)
#   return retFuture

import nativesockets

proc connect*(fd: AsyncFD; address: string, port: int): owned(Future[void]) =
  var ai = getAddrInfo(address, port.Port)
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete()
  discard event(cb).connect(cast[SocketHandle](fd), ai.ai_addr, ai.ai_addrlen)

proc send*(fd: AsyncFD; buffer: pointer; len: int; flags: cint = 0): owned(Future[void]) =
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete()
  # TODO: probably buffer can leak if it would destroyed before io_uring it consume
  discard event(cb).send(cast[SocketHandle](fd), buffer, len, flags)

proc send*(fd: AsyncFD; text: string): owned(Future[void]) =
  return send(fd, text[0].addr, text.len)

proc recv*(fd: AsyncFD; buffer: pointer; len: int; flags: cint = 0): owned(Future[int]) =
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete(cqe.res)
  discard event(cb).recv(cast[SocketHandle](fd), buffer, len, flags)

proc recv*(fd: AsyncFD; size: int): owned(Future[string])  =
  # todo: rewrite using {.async.}
  # Error: undeclared field: '<h>1' for type recv:iter.Env_yasync.nim_recv:iter
  new result
  let res = result
  var str = newString(size)
  recv(fd, str[0].addr, size).then(proc (len: int, err: ref Exception) =
    str.setLen(len)
    res.complete(str)
  )

type
  Conn* = object
    name: ref Sockaddr_storage
    len: SockLen
  Msg* = object
    data*: string
    conn*: Conn

proc recvmsg*(fd: AsyncFD; size: int): owned(Future[ref Msg]) =
  new result
  let res = result

  var msg = new Msg
  msg.conn.name = new Sockaddr_storage
  msg.data = newString(size)
  var tmsg = new Tmsghdr
  tmsg.msg_name = msg.conn.name.addr
  tmsg.msg_namelen = sizeof(Sockaddr_storage).SockLen
  var iov = new IOVec
  iov.iov_base = msg.data[0].addr
  iov.iov_len = size.uint
  tmsg.msg_iov = cast[ptr IOVec](iov)
  tmsg.msg_iovlen = 1

  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete(msg)

  discard event(cb).recvmsg(cast[SocketHandle](fd), cast[ptr Tmsghdr](tmsg), 0)

proc sleepAsync*(ms: int | float): owned(Future[void]) =
  new result
  let res = result
  if ms == 0:
    callSoon(proc () = res.complete())
    return res
  let ns = (ms * 1_000_000).int64
  let after = getMonoTime().ticks + ns
  var ts = create(Timespec)
  ts.tv_sec = posix.Time(after.int div 1_000_000_000)
  ts.tv_nsec = after.int mod 1_000_000_000
  proc cb(cqe: Cqe): bool =
    dealloc(ts)
    res.complete()
  # we are using TIMEOUT_ABS to avoid time mismatch
  # if sqe enqueued not now (sqe is overflowed)
  discard event(cb).timeout(ts, 0, {TIMEOUT_ABS})

export yasync
export Cqe
]#