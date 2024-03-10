import std/httpcore
import std/options
import std/strutils
import std/uri
from std/httpclient import ProtocolError, HttpRequestError
import pkg/cps

import ../../loop
import ../../socket

import picohttpparser

type
  HttpServer* = ref object
    socket: Socket
  Request* = ref object
    buffer: string
    meth: string
    path: string
    headers: HttpHeaders
  ResponseType = enum
    Text
  Response* = ref object
    status: int
    msg: string
    headers: HttpHeaders
    case t: ResponseType
    of Text:
      data: string
  HttpHandler* = proc (req: Request): Response {.asyncio.}

const
  BUFFER_LEN = 1024
  MAX_HEADERS = 100

proc newHttpServer*(): HttpServer =
  new result

proc readRequest(client: Socket): Request {.asyncio.} =
  result = new Request
  var headersCount: csize_t
  var headers: array[MAX_HEADERS, picohttpparser.Header]
  var meth: cstring
  var methLen: csize_t
  var path: cstring
  var pathLen: csize_t
  var minorVersion: cint
  var parsed: cint
  var prevLen: int

  var buffer: string

  while true:
    prevLen = buffer.len
    buffer.add client.recv(BUFFER_LEN)
    headersCount = MAX_HEADERS
    parsed = picohttpparser.parseRequest(
      buffer.cstring, buffer.len.csize_t, addr meth, addr methLen,
      addr path, addr pathLen, addr minorVersion,
      addr headers[0], addr headersCount, prevLen.csize_t)
    if parsed == -1:
      raise newException(HttpRequestError, "Invalid HTTP response")
    elif parsed == -2:
      continue
    else:
      break
  result.buffer = buffer[parsed..^1]
  result.meth = newString(methLen)
  copyMem(addr result.meth[0], meth, methLen)
  result.path = newString(pathLen)
  copyMem(addr result.path[0], path, pathLen)
  result.headers = newHttpHeaders()
  for i in 0..<headersCount:
    var key = newString(headers[i].nameLen)
    copyMem(addr key[0], headers[i].name, headers[i].nameLen)
    var val = newString(headers[i].valueLen)
    copyMem(addr val[0], headers[i].value, headers[i].valueLen)
    result.headers.add(move(key), move(val))

proc handleResponse(client: Socket, res: Response) {.asyncio.} =
  if res.status == 0:
    res.status = 200
  if res.msg == "":
    res.msg = $(res.status.HttpCode)
  var resBuffer = "HTTP/1.1 "
  # XXX: can be made without allocation
  resBuffer.add $res.status
  resBuffer.add ' '
  resBuffer.add res.msg
  resBuffer.add httpNewLine
  if not res.headers.isNil:
    for key, val in res.headers.pairs:
      resBuffer.add key
      resBuffer.add ": "
      resBuffer.add val
      resBuffer.add httpNewLine
  resBuffer.add httpNewLine
  case res.t
  of Text:
    resBuffer.add res.data
  client.send(resBuffer)

proc listen*(server: HttpServer, port: int, handler: HttpHandler) {.asyncio.} =
  # XXX: make simple tcp server and reuse it
  server.socket = newSocket()
  server.socket.setSockOpt(OptReusePort, true)
  server.socket.setSockOpt(OptReuseAddr, true)
  server.socket.bindAddr(port)
  server.socket.listen()
  while true:
    let client = server.socket.accept()
    let req = client.readRequest()
    var res = handler(req)
    client.handleResponse(res)
    client.close()

func text*(T: type Response, data: string): Response =
  result = new Response
  result.t = Text
  result.data = data

when isMainModule:
  let client = newHttpServer()
  proc handler(req: Request): Response {.asyncio.} =
    return Response.text("Hello, World\n")
  client.listen(8080, whelp handler)
  run()