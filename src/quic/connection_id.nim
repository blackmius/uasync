import std/sysrand
import std/hashes
import std/strutils

type ConnectionId* = distinct seq[byte]

const DefaultConnectionIdLength* = 16

proc `==`*(x: ConnectionId, y: ConnectionId): bool {.borrow.}
proc `len`*(x: ConnectionId): int {.borrow.}
proc `hash`*(x: ConnectionId): Hash {.borrow.}

proc `$`*(id: ConnectionId): string =
  "0x" & cast[string](id).toHex

proc randomConnectionId*(len = DefaultConnectionIdLength): ConnectionId =
  ConnectionId(urandom(len))