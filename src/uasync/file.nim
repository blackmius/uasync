import std/[os, posix]
import pkg/cps
import pkg/nimuring
import uasync

type File* = object
  fd: FileHandle

proc newFile(fname: string): File {.asyncio.} =
  discard

proc read(f: File) {.asyncio.} =
  discard
proc write(f: File) {.asyncio.} =
  discard
proc close(f: File) {.asyncio.} =
  discard

#[
  proc write*(fd: AsyncFD; buffer: pointer; len: int; offset: int = 0): owned(Future[void]) =
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete()
  # TODO: probably buffer can leak if it would destroyed before io_uring it consume
  discard event(cb).write(cast[FileHandle](fd), buffer, len, offset)

proc read*(fd: AsyncFD; buffer: pointer; len: int; offset: int = 0): owned(Future[int]) =
  new result
  let res = result
  proc cb(cqe: Cqe): bool =
    if cqe.res < 0:
      res.fail(newException(OSError, osErrorMsg(OSErrorCode(cqe.res))))
    else:
      res.complete(cqe.res)
  discard event(cb).read(cast[FileHandle](fd), buffer, len, offset)
]#