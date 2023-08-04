import net
import strformat

import quic/quic
import uasync

var server = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
server.bindAddr(port=Port(4567))

let (ip, port) = server.getLocalAddr()
echo fmt"listening on {ip}:{port}"

let fd = cast[AsyncFd](server.getFd())

proc main() {.async.} =
  let msg = await fd.recvmsg(1024)
  try:
    echo repr(parsePacket(msg.data[0].addr))
  except Exception as e:
    echo repr(e)

discard main()

runForever()