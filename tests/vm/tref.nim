static:
  var
    a: ref string
    b: ref string
  new a

  a[] = "Hello world"
  b = a

  b[5] = 'c'
  doAssert a[] == "Hellocworld"
  doAssert b[] == "Hellocworld"

  proc notGlobal() =
    var
      a: ref string
      b: ref string
    new a

    a[] = "Hello world"
    b = a

    b[5] = 'c'
    doAssert a[] == "Hellocworld"
    doAssert b[] == "Hellocworld"
  notGlobal()

static: # bug 6081
  block:
    type Obj = object
      field: ref int
    var i: ref int
    new(i)
    var r = Obj(field: i)
    var rr = r
    r.field = nil
    doAssert rr.field != nil

  proc foo() = # Proc to avoid special global logic
    var s: seq[ref int]
    var i: ref int
    new(i)
    s.add(i)
    var head = s[0]
    s[0] = nil
    doAssert head != nil

  foo()

static:

  block: # global alias
    var s: ref int
    new(s)
    var ss = s
    s[] = 1
    doAssert ss[] == 1