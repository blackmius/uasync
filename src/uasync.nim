import std/[deques, monotimes]
import times, os, posix

import nimuring
import yasync

## Сохранинение Event в памяти GC
## Ускоряет общий код на 50%
## 1. нам не надо теперь хранить rawEnv замыкания
## 2. не надо выделять и удалять структуры под события
type
  Pool[T] = ref object
    arr: seq[T]
    freelist: Deque[int]

proc newPool[T](): owned(Pool[T]) =
  result = new Pool[T]

proc alloc[T](p: var Pool[T]): int =
  if p.freelist.len == 0:
    p.arr.add(T())
    return p.arr.len - 1
  return p.freelist.popFirst()

proc dealloc[T](p: var Pool[T], ind: int) =
  p.freelist.addLast(ind)

proc get[T](p: var Pool[T], ind: int): ptr T =
  result = addr p.arr[ind]

proc waiting[T](p: var Pool[T]): int =
  result = p.arr.len - p.freelist.len


type
  Callback = proc (res: Cqe): bool {.gcsafe, closure.}
  ## Callback takes Cqe and return should loop dealloc Event
  ## or we waiting another cqe
  ## all resubmitting considered to be in that callback
  Event = object
    cb: owned(Callback)
  Loop = ref object
    q: Queue
    sqes: Deque[Sqe]
    cqes: seq[Cqe]
    callbacks: Deque[proc () {.gcsafe.}]
    events: Pool[Event]

var gLoop {.threadvar.}: owned Loop

proc newLoop(): owned Loop =
  result = new(Loop)
  result.q = newQueue(4096, {SETUP_SQPOLL})
  result.sqes = initDeque[Sqe](4096)
  result.cqes = newSeq[Cqe](result.q.params.cqEntries)
  result.events = newPool[Event]()

proc setLoop*(loop: sink Loop) =
  gLoop = loop

proc getLoop*(): Loop =
  if gLoop.isNil:
    setLoop(newLoop())
  result = gLoop

proc callSoon*(cbproc: proc () {.closure, gcsafe.}) {.gcsafe.} =
  let loop = getLoop()
  loop.callbacks.addLast(cbproc)
    

template drainQueue(loop: Loop) =
  while loop.sqes.len != 0:
    var sqe = loop.q.getSqe()
    if sqe.isNil:
      break
    sqe[] = loop.sqes.popFirst()

proc poll*(): bool {.gcsafe, discardable.} =
  let loop = getLoop()
  loop.drainQueue()
  discard loop.q.submit()
  let callbacksCount = loop.callbacks.len
  for _ in 1..callbacksCount:
    let cb = loop.callbacks.popFirst()
    cb()
  var waitNr: uint = 0
  if unlikely(loop.callbacks.len > 0):
    waitNr = loop.q.cqReady()
  elif likely(loop.events.waiting() > 0):
    waitNr = 1
  let ready = loop.q.copyCqes(loop.cqes, waitNr)
  # new sqes can be added only from callbacks
  # so it doesn't make sense to skip the iteration
  for i in 0..<ready:
    let cqe = loop.cqes[i]
    let ev = loop.events.get(cqe.userData.int)
    if likely(not ev.cb(cqe)):
      loop.events.dealloc(cqe.userData.int)
  return loop.callbacks.len > 0 or loop.events.waiting() > 0

proc runForever*() {.gcsafe.} =
  while poll():
    discard

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