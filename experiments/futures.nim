import std/deques
import std/monotimes
import macros

var queue: iterator()

type Future[T] = ref object
  res: T
  next: iterator ()
  callback: iterator ()


proc then(fut: Future, p: iterator ()) =
  fut.callback = p

template runMicrotask(task: iterator()) =
  queue = task

template runMicrotask[T](fut: Future[T]) =
  queue = fut.next

proc gen2(): Future[int] =
  var res = new Future[int]
  res.next = iterator() =
    runMicrotask res.next
    yield
    res.res = 10
    runMicrotask res.callback
  return res

proc gen(): Future[int] =
  var res = new Future[int]
  res.next = iterator() =
    let start = getMonoTime().ticks
    for i in 0..1_000_000:
      let fut = gen2()
      fut.then(res.next)
      fut.next()
      yield
    let duration = getMonoTime().ticks - start
    echo "closure: ", duration.float / 1_000_000, "ms"
    echo "done"
    res.res = 10
  return res

runMicrotask gen()

while not finished(queue):
  queue()

# let q = @[a, a, a, a]
# var tick = 0

# while true:
#   let c = q[tick mod q.len]
#   if finished(c):
#     break
#   echo c()
#   tick += 1