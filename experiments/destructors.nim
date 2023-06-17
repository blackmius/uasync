type A = object
    id: int
    b: ref A
    c: ref A
type AA = ref A

proc `=destroy`(x: var A) = 
    if x.id < 1000 and x.id > 0: echo "destroy: ", x.id

var q = newSeq[AA](128)
for i in 0..<128:
    new q[i]
    q[i].b = AA(id: i+1000)
    q[i].b.b = q[i]
var a = AA(id: 1)
a.b = AA(id: 2)
a.b.b = AA(id: 3)
a.b.b.b = a.b

a.b = nil

# GC_fullCollect()