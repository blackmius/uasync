import std/httpcore
import std/options
import std/strutils
import std/parseutils
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
    socket: Socket
    buffer: string
    bufpos: int
    contentLength: int
    meth*: string
    path*: string
    headers*: HttpHeaders
  ResponseType = enum
    Text
  Response* = ref object
    statusCode: int
    msg: string
    headers: HttpHeaders
    case t: ResponseType
    of Text:
      data: string
  HttpHandler* = proc (req: Request): Response {.cps: Continuation.}

const
  BUFFER_LEN = 1024
  MAX_HEADERS = 100

func text*(T: type Response, data: string): Response =
  result = new Response
  result.t = Text
  result.data = data

func status*(T: type Response, data: int): Response =
  result = new Response
  result.statusCode = data

proc read*(req: Request, size: int): string {.cps: Continuation.} =
  while true:
    if req.buffer.len >= size:
      req.bufPos += size
      let data = req.buffer[0..size]
      req.buffer = req.buffer[size..^1]
      return data
    if req.bufPos + req.buffer.len == req.contentLength:
      req.bufPos = req.contentLength
      let data = req.buffer
      req.buffer = ""
      return data
    req.buffer.add req.socket.recv(BUFFER_LEN)

proc newHttpServer*(): HttpServer =
  new result

proc readRequest(client: Socket): Request {.cps: Continuation.} =
  result = new Request
  result.socket = client
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
  
  if not result.headers.isNil and result.headers.hasKey("Content-Length"):
    discard result.headers["Content-Length"].parseSaturatedNatural(result.contentLength)

proc handleResponse(client: Socket, res: Response) {.cps: Continuation.} =
  if res.statusCode == 0:
    res.statusCode = 200
  if res.msg == "":
    res.msg = $(res.statusCode.HttpCode)
  var resBuffer = "HTTP/1.1 "
  # XXX: can be made without allocation
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

proc handle(client: Socket, handler: HttpHandler) {.cps: Continuation.} =
  let req = client.readRequest()
  var res: Response
  try:
    res = handler(req)
  except Exception as e:
    res = Response.status(500)
  client.handleResponse(res)
  client.close()

proc listen*(server: HttpServer, port: int, handler: HttpHandler) {.cps: Continuation.} =
  # XXX: make simple tcp server and reuse it
  server.socket = newSocket()
  server.socket.setSockOpt(OptReusePort, true)
  server.socket.setSockOpt(OptReuseAddr, true)
  server.socket.bindAddr(port)
  server.socket.listen()
  while true:
    let client = server.socket.accept()
    spawn handle(client, handler)

when isMainModule:
  let server = newHttpServer()
  proc handler(req: Request): Response {.asyncio.} =
    return Response.text("Hello, World\n")
  server.listen(8080, whelp handler)
  run()