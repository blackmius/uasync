import std/[monotimes, times]

block:
    proc fn() = discard

    let start = getMonoTime().ticks
    for _ in 0..<1_000_000:
        fn()
    let duration = getMonoTime().ticks - start
    echo duration.float / 1_000_000, "ms"

block:
    proc fn(): proc() =
        var i = 0
        proc cb() =
            i += 1
        return cb

    let c = fn()
    let start = getMonoTime().ticks
    for _ in 0..<1_000_000:
        c()
    let duration = getMonoTime().ticks - start
    echo duration.float / 1_000_000, "ms"

block:
    proc fn(): iterator() =
        var i = 0
        iterator cb() =
            i += 1
        return cb

    let c = fn()
    let start = getMonoTime()
    for _ in 0..<1_000_000:
        c()
    echo (getMonoTime() - start).inMilliseconds, "ms"

import std/[asyncmacro, asyncfutures]
block:
    proc a(): Future[int] {.async.} =
        return 1
    proc b() {.async.} =
        var i = 0
        for _ in 0..<1_000_000:
            i += await a()
    let start = getMonoTime()
    asyncCheck b()
    echo (getMonoTime() - start).inMilliseconds, "ms"