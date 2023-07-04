import std/[asyncnet, asyncdispatch]

proc processClient(client: AsyncSocket) {.async.} =
  while true:
    let line = await client.recv(1024)
    if line.len == 0: break
    await client.send(line)

proc serve() {.async.} =
  var server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(8080))
  server.listen()
  
  while true:
    let client = await server.accept()
    asyncCheck processClient(client)

asyncCheck serve()
runForever()