proc `+`*[T](p: ptr T, a: SomeNumber): ptr T =
  cast[ptr T](cast[uint](p) + uint(a))

proc read*[T](offset: var ptr): T {.inline.} =
  result = cast[ptr T](offset)[]
  offset = offset + sizeof(T)

proc readSeq*(offset: ptr, len: SomeNumber): seq[byte] {.inline.} =
  result = newSeq[byte](len)
  if len > 0:
    copyMem(result[0].addr, offset, len)

proc readSeq*(offset: var ptr, len: SomeNumber): seq[byte] {.inline.} =
  result = newSeq[byte](len)
  if len > 0:
    copyMem(result[0].addr, offset, len)
    offset = offset + len

proc readSeq*[T](offset: var ptr): seq[byte] {.inline.} =
  let len = read[T](offset)
  readSeq(offset, len)

proc readVarInt*(offset: var ptr): uint64 {.inline.} =
  # The length of variable-length integers is encoded in the
  # first two bits of the first byte.
  result = cast[ptr uint8](offset)[]
  offset = offset + 1
  let prefix = result shr 6
  let length = 1 shl prefix
  # Once the length is known, remove these bits and read any
  # remaining bytes.
  result = result and 0x3f
  for _ in 1..<length:
    result = (result shl 8) + cast[ptr uint8](offset)[]
    offset = offset + 1

proc readPacketNumber*(offset: var ptr, len: int, mask: string): uint64 {.inline.} =
  result = cast[ptr uint8](offset)[] xor mask[1].uint8
  for i in 1..<len:
    result = (result shl 8) + (cast[ptr uint8](offset)[] xor mask[i+1].uint8)
  offset = offset + len