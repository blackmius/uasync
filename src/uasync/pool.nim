import deques

type
  Pool*[T] = ref object
    arr: seq[T]
    freelist: Deque[int]

proc newPool*[T](): Pool[T] =
  new Pool[T]

proc add*[T](p: Pool[T], v: T): int =
  if p.freelist.len == 0:
    p.arr.add(v)
    return p.arr.len - 1
  let ind = p.freelist.popFirst()
  p.arr[ind] = v
  return ind

proc free*[T](p: Pool[T], ind: int) =
  p.freelist.addLast(ind)

proc `[]`*[T](p: Pool[T], ind: int): T =
  p.arr[ind]

proc len*[T](p: Pool[T]): int =
  p.arr.len - p.freelist.len
