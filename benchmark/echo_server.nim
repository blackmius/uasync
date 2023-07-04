import uasync
import net
import posix

const readSize = 1024

let server = newSocket()

import std/monotimes

proc connection(c: AsyncFD) {.async.} =
  var buf = newString(readSize)
  var size = readSize
  while size != 0:
    size = await c.recv(buf[0].addr, readSize)
    if size != 0:
      await c.send(buf[0].addr, size, 0)
  await c.close()

proc addAccept() =
  accept(cast[AsyncFD](server.getFd)).then(proc (client: AsyncFD, error: ref Exception) =
    addAccept()
    discard connection(client)
  )

server.setSockOpt(OptReuseAddr, true)
server.setSockOpt(OptNoDelay, true, level = posix.IPPROTO_TCP)
server.bindAddr(Port(8080))
server.listen()
for _ in 1..100:
  addAccept()

runForever()
