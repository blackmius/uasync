import std/[os, posix, nativesockets]
import pkg/cps
import pkg/nimuring
import uasync

export Domain, SockType, Protocol

type Socket* = object
  fd: SocketHandle

proc newSocket*(
  domain: Domain = AF_INET, sockType: SockType = SOCK_STREAM,
  protocol: Protocol = IPPROTO_TCP
): Socket {.asyncio.} =
  when false:
    let cqe = submit sqe().socket(domain, SockType (sockType.cint or SOCK_CLOEXEC), protocol)
    if cqe.res < 0:
      raise newException(OSError, osErrorMsg(OSErrorCode(cqe.res)))
    result.fd = cqe.res
  else:
    result.fd = socket(domain.cint, sockType.cint or SOCK_CLOEXEC, protocol.cint)

proc connect*(sock: Socket, address: string, port: int) {.asyncio.} =
  # xxx: make getAddrInfo async
  var ai = getAddrInfo(address, port.Port)
  let cqe = submit sqe().connect(sock.fd, ai.ai_addr, ai.ai_addrlen)
  if cqe.res < 0:
    raise newException(OSError, osErrorMsg(OSErrorCode(cqe.res)))

proc recv*(sock: Socket, buffer: pointer, len: int, flags: cint = 0): int {.asyncio.} =
  let cqe = submit sqe().recv(sock.fd, buffer, len, flags)
  if cqe.res < 0:
    raise newException(OSError, osErrorMsg(OSErrorCode(cqe.res)))
  return cqe.res

proc recv*(sock: Socket, size: int): string {.asyncio.}  =
  var s = newString(size)
  var len = sock.recv(s[0].addr, size)
  s.setLen(len)
  return s

proc send*(sock: Socket; buffer: pointer; len: int; flags: cint = 0) {.asyncio.} =
  let cqe = submit sqe().send(sock.fd, buffer, len, flags)
  if cqe.res < 0:
    raise newException(OSError, osErrorMsg(OSErrorCode(cqe.res)))

proc send*(sock: Socket; text: string) =
  let cqe = submit sqe().send(sock.fd, text[0].addr, text.len, 0)
  if cqe.res < 0:
    raise newException(OSError, osErrorMsg(OSErrorCode(cqe.res)))

proc test() {.cps: Continuation.} =
  let s = newSocket()
  s.connect("google.com", 80)
  s.send("GET / HTTP 1.1\n\n")
  let q = s.recv(100)
  echo q
test()
run()