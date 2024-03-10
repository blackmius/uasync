import std/[os, posix, nativesockets, net]
import pkg/cps
import pkg/nimuring
import uasync

export Domain, SockType, Protocol, SOBool

type Socket* = object
  fd: SocketHandle

proc newSocket*(
  domain: Domain = AF_INET, sockType: SockType = SOCK_STREAM,
  protocol: Protocol = IPPROTO_TCP
): Socket {.asyncio.} =
  when false:
    let cqe = checkCqe submit sqe().socket(domain, SockType (sockType.cint or SOCK_CLOEXEC), protocol)
    result.fd = cast[SocketHandle](cqe.res)
  else:
    result.fd = socket(domain.cint, sockType.cint or SOCK_CLOEXEC, protocol.cint)

proc connect*(sock: Socket, address: string, port: int) {.asyncio.} =
  # xxx: make getAddrInfo async
  var ai = getAddrInfo(address, port.Port)
  # xxx: process ai_next
  checkCqe submit sqe().connect(sock.fd, ai.ai_addr, ai.ai_addrlen)
  freeAddrInfo(ai)

proc recv*(sock: Socket, buffer: pointer, len: int, flags: cint = 0): int {.asyncio.} =
  let cqe = checkCqe submit sqe().recv(sock.fd, buffer, len, flags)
  return cqe.res

proc recv*(sock: Socket, size: int): string {.asyncio.}  =
  var s = newString(size)
  var len = sock.recv(s[0].addr, size)
  s.setLen(len)
  return s

proc send*(sock: Socket; buffer: pointer; len: int; flags: cint = 0) {.asyncio.} =
  checkCqe submit sqe().send(sock.fd, buffer, len, flags)

proc send*(sock: Socket; text: string) {.asyncio.} =
  checkCqe submit sqe().send(sock.fd, text[0].addr, text.len, 0)

proc accept*(sock: Socket): Socket {.asyncio.} =
  var acceptAddr: SockAddr
  var acceptAddrLen: SockLen
  let cqe = checkCqe submit sqe().accept(sock.fd, addr acceptAddr, addr acceptAddrLen, O_CLOEXEC)
  result.fd = cast[SocketHandle](cqe.res)

proc acceptMultishot*(sock: Socket) {.asyncio.} =
  var acceptAddr: SockAddr
  var acceptAddrLen: SockLen
  event sqe().acceptMultishot(sock.fd, addr acceptAddr, addr acceptAddrLen, O_CLOEXEC)
  while true:
    let cqe = checkCqe data()
    # do something
    # CPS iterator?
    if not cqe.flags.contains(CQE_F_MORE):
      event sqe().acceptMultishot(sock.fd, addr acceptAddr, addr acceptAddrLen, O_CLOEXEC)
    else:
      jield()

proc listen*(sock: Socket, backlog=SOMAXCONN) =
  if nativesockets.listen(sock.fd, backlog) < 0'i32:
    raiseOSError(osLastError())

proc bindAddr*(sock: Socket, port: int = 0, address = "0.0.0.0") =
  var ai = getAddrInfo(address, port.Port)
  let res = bindAddr(sock.fd, ai.ai_addr, ai.ai_addrlen.SockLen)
  freeAddrInfo(ai)
  if res < 0:
    raiseOSError(osLastError())

proc setSockOpt*(socket: Socket, opt: SOBool, value: bool,
  level = SOL_SOCKET) =
  var valuei = cint(if value: 1 else: 0)
  setSockOptInt(socket.fd, cint(level), toCInt(opt), valuei)

proc close*(sock: Socket) {.asyncio.} =
  checkCqe submit sqe().close(sock.fd)

#[
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
]#
