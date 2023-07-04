import strutils

import uasync
import posix
import net

import std/[monotimes, times]

const text = "A".repeat(1024)

proc main() {.async.} = 
  try:
    let socket = newSocket()
    socket.setSockOpt(OptNoDelay, true, level = posix.IPPROTO_TCP)
    let client = cast[AsyncFD](socket.getFd)
    await client.connect("127.0.0.1", 8080)
    for _ in 1..100000:
      discard client.send(text)
      discard await client.recv(1024)
  except Exception as e:
    echo repr(e)

let start = getMonoTime()
for _ in 1..10:
  discard main()

runForever()
echo getMonoTime() - start