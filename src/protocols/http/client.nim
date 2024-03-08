import std/httpcore
import std/options
import std/strutils
import std/uri
from std/httpclient import ProtocolError, HttpRequestError
import pkg/cps

import ../../uasync
import ../../socket
import picohttpparser

type HttpRequest* = object
  socket: Socket
  buffer: string
  headers: HttpHeaders
  status: int

proc generateRequest(url: Uri, `method`: HttpMethod, headers: HttpHeaders): string =
  result = ""
  result.add $`method`
  result.add " "
  if url.path != "":
    result.add url.path
  else:
    result.add "/"
  if url.query != "":
    result.add("?" & url.query)
  result.add(" HTTP 1.1" & httpNewLine)
  if headers != nil:
    for key, val in headers:
      result.add(key & ": " & val & httpNewLine)
  result.add(httpNewLine)

proc request*(url: string, `method`: HttpMethod, headers: HttpHeaders=nil, body: string=""): HttpRequest {.cps: Continuation, discardable.} =
  let uri = uri.parseUri(url)
  var port = 80
  if uri.port.len > 0:
    port = parseInt(uri.port)
  
  result.socket = newSocket()
  result.socket.connect(uri.hostname, port)
  
  let req = generateRequest(uri, `method`, headers)
  result.socket.send(req)
  if body.len > 0:
    result.socket.send(body)
  
  var buffer = ""
  # var headersEnd = 0
  var prevIndex = 0
  var lines = 0
  var headerSection = true
  while headerSection:
    let data = result.socket.recv(1024)
    buffer.add data
    for i in 0..<data.len:
      let index = prevIndex + i
      if buffer[index] == '\n':
        lines += 1
        if (buffer[index-1] == '\r' and buffer[index-2] == '\n' and buffer[index-3] == '\r') or buffer[index-1] == '\n':
          headerSection = false
          break
    prevIndex += data.len
  # total - status - end
  let headersCount = (lines - 2).csize_t
  var headers = newSeq[picohttpparser.Header](headersCount)
  var minorVersion: cint
  var msg: cstring
  var msgLen: csize_t
  var status: cint
  var parsed: cint

  parsed = picohttpparser.parseResponse(
    buffer.cstring, buffer.len.csize_t, addr minorVersion,
    addr status, addr msg, addr msgLen, addr headers[0],
    addr headersCount, 0.csize_t)
  if parsed == -1:
    raise newException(HttpRequestError, "Invalid HTTP response")
  result.headers = newHttpHeaders()
  for i in 0..<headersCount:
    var key = newString(headers[i].nameLen)
    copyMem(addr key[0], headers[i].name, headers[i].nameLen)
    var val = newString(headers[i].valueLen)
    copyMem(addr val[0], headers[i].value, headers[i].valueLen)
    result.headers.add(move(key), move(val))
  echo result.headers
  echo parsed

proc read(req: HttpRequest): string =
  let buf = req.socket.recv(1024)
  echo buf

when isMainModule:
  proc test() {.cps: Continuation.} =
    request("http://google.com", HttpGet)
  test()
  run()