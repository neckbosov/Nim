#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

proc genericResetAux(dest: pointer, n: ptr TNimNode) {.benign.}

proc genericAssignAux(dest, src: pointer, mt: PNimType, shallow: bool) {.benign.}
proc genericAssignAux(dest, src: pointer, n: ptr TNimNode,
                      shallow: bool) {.benign.} =
  var
    d = cast[ByteAddress](dest)
    s = cast[ByteAddress](src)
  case n.kind
  of nkSlot:
    genericAssignAux(cast[pointer](d +% n.offset),
                     cast[pointer](s +% n.offset), n.typ, shallow)
  of nkList:
    for i in 0..n.len-1:
      genericAssignAux(dest, src, n.sons[i], shallow)
  of nkCase:
    var dd = selectBranch(dest, n)
    var m = selectBranch(src, n)
    # reset if different branches are in use; note different branches also
    # imply that's not self-assignment (``x = x``)!
    if m != dd and dd != nil:
      genericResetAux(dest, dd)
    copyMem(cast[pointer](d +% n.offset), cast[pointer](s +% n.offset),
            n.typ.size)
    if m != nil:
      genericAssignAux(dest, src, m, shallow)
  of nkNone: sysAssert(false, "genericAssignAux")
  #else:
  #  echo "ugh memory corruption! ", n.kind
  #  quit 1

proc genericAssignAux(dest, src: pointer, mt: PNimType, shallow: bool) =
  var
    d = cast[ByteAddress](dest)
    s = cast[ByteAddress](src)
  sysAssert(mt != nil, "genericAssignAux 2")
  case mt.kind
  of tyString:
    var x = cast[PPointer](dest)
    var s2 = cast[PPointer](s)[]
    if s2 == nil or shallow or (
        cast[PGenericSeq](s2).reserved and seqShallowFlag) != 0:
      unsureAsgnRef(x, s2)
    else:
      unsureAsgnRef(x, copyString(cast[NimString](s2)))
  of tySequence:
    var s2 = cast[PPointer](src)[]
    var seq = cast[PGenericSeq](s2)
    var x = cast[PPointer](dest)
    if s2 == nil or shallow or (seq.reserved and seqShallowFlag) != 0:
      # this can happen! nil sequences are allowed
      unsureAsgnRef(x, s2)
      return
    sysAssert(dest != nil, "genericAssignAux 3")
    if ntfNoRefs in mt.base.flags:
      var ss = nimNewSeqOfCap(mt, seq.len)
      cast[PGenericSeq](ss).len = seq.len
      unsureAsgnRef(x, ss)
      var dst = cast[ByteAddress](cast[PPointer](dest)[])
      copyMem(cast[pointer](dst +% GenericSeqSize),
              cast[pointer](cast[ByteAddress](s2) +% GenericSeqSize),
              seq.len * mt.base.size)
    else:
      unsureAsgnRef(x, newSeq(mt, seq.len))
      var dst = cast[ByteAddress](cast[PPointer](dest)[])
      for i in 0..seq.len-1:
        genericAssignAux(
          cast[pointer](dst +% i *% mt.base.size +% GenericSeqSize),
          cast[pointer](cast[ByteAddress](s2) +% i *% mt.base.size +%
                      GenericSeqSize),
          mt.base, shallow)
  of tyObject:
    var it = mt.base
    # don't use recursion here on the PNimType because the subtype
    # check should only be done at the very end:
    while it != nil:
      genericAssignAux(dest, src, it.node, shallow)
      it = it.base
    genericAssignAux(dest, src, mt.node, shallow)
    # we need to copy m_type field for tyObject, as it could be empty for
    # sequence reallocations:
    var pint = cast[ptr PNimType](dest)
    # We need to copy the *static* type not the dynamic type:
    #   if p of TB:
    #     var tbObj = TB(p)
    #     tbObj of TC # needs to be false!
    #c_fprintf(stdout, "%s %s\n", pint[].name, mt.name)
    chckObjAsgn(cast[ptr PNimType](src)[], mt)
    pint[] = mt # cast[ptr PNimType](src)[]
  of tyTuple:
    genericAssignAux(dest, src, mt.node, shallow)
  of tyArray, tyArrayConstr:
    for i in 0..(mt.size div mt.base.size)-1:
      genericAssignAux(cast[pointer](d +% i *% mt.base.size),
                       cast[pointer](s +% i *% mt.base.size), mt.base, shallow)
  of tyRef:
    unsureAsgnRef(cast[PPointer](dest), cast[PPointer](s)[])
  of tyOptAsRef:
    let s2 = cast[PPointer](src)[]
    let d = cast[PPointer](dest)
    if s2 == nil:
      unsureAsgnRef(d, s2)
    else:
      when declared(usrToCell):
        let realType = usrToCell(s2).typ
      else:
        let realType = if mt.base.kind == tyObject: cast[ptr PNimType](s2)[]
                       else: mt.base
      var z = newObj(realType, realType.base.size)
      genericAssignAux(d, addr z, mt.base, shallow)
  else:
    copyMem(dest, src, mt.size) # copy raw bits

proc genericAssign(dest, src: pointer, mt: PNimType) {.compilerProc.} =
  genericAssignAux(dest, src, mt, false)

proc genericShallowAssign(dest, src: pointer, mt: PNimType) {.compilerProc.} =
  genericAssignAux(dest, src, mt, true)

when false:
  proc debugNimType(t: PNimType) =
    if t.isNil:
      cprintf("nil!")
      return
    var k: cstring
    case t.kind
    of tyBool: k = "bool"
    of tyChar: k = "char"
    of tyEnum: k = "enum"
    of tyArray: k = "array"
    of tyObject: k = "object"
    of tyTuple: k = "tuple"
    of tyRange: k = "range"
    of tyPtr: k = "ptr"
    of tyRef: k = "ref"
    of tyVar: k = "var"
    of tyOptAsRef: k = "optref"
    of tySequence: k = "seq"
    of tyProc: k = "proc"
    of tyPointer: k = "range"
    of tyOpenArray: k = "openarray"
    of tyString: k = "string"
    of tyCString: k = "cstring"
    of tyInt: k = "int"
    of tyInt32: k = "int32"
    else: k = "other"
    cprintf("%s %ld\n", k, t.size)
    debugNimType(t.base)

proc genericSeqAssign(dest, src: pointer, mt: PNimType) {.compilerProc.} =
  var src = src # ugly, but I like to stress the parser sometimes :-)
  genericAssign(dest, addr(src), mt)

proc genericAssignOpenArray(dest, src: pointer, len: int,
                            mt: PNimType) {.compilerproc.} =
  var
    d = cast[ByteAddress](dest)
    s = cast[ByteAddress](src)
  for i in 0..len-1:
    genericAssign(cast[pointer](d +% i *% mt.base.size),
                  cast[pointer](s +% i *% mt.base.size), mt.base)

proc objectInit(dest: pointer, typ: PNimType) {.compilerProc, benign.}
proc objectInitAux(dest: pointer, n: ptr TNimNode) {.benign.} =
  var d = cast[ByteAddress](dest)
  case n.kind
  of nkNone: sysAssert(false, "objectInitAux")
  of nkSlot: objectInit(cast[pointer](d +% n.offset), n.typ)
  of nkList:
    for i in 0..n.len-1:
      objectInitAux(dest, n.sons[i])
  of nkCase:
    var m = selectBranch(dest, n)
    if m != nil: objectInitAux(dest, m)

proc objectInit(dest: pointer, typ: PNimType) =
  # the generic init proc that takes care of initialization of complex
  # objects on the stack or heap
  var d = cast[ByteAddress](dest)
  case typ.kind
  of tyObject:
    # iterate over any structural type
    # here we have to init the type field:
    var pint = cast[ptr PNimType](dest)
    pint[] = typ
    objectInitAux(dest, typ.node)
  of tyTuple:
    objectInitAux(dest, typ.node)
  of tyArray, tyArrayConstr:
    for i in 0..(typ.size div typ.base.size)-1:
      objectInit(cast[pointer](d +% i * typ.base.size), typ.base)
  else: discard # nothing to do

# ---------------------- assign zero -----------------------------------------

proc nimDestroyRange[T](r: T) {.compilerProc.} =
  # internal proc used for destroying sequences and arrays
  mixin `=destroy`
  for i in countup(0, r.len - 1): `=destroy`(r[i])

proc genericReset(dest: pointer, mt: PNimType) {.compilerProc, benign.}
proc genericResetAux(dest: pointer, n: ptr TNimNode) =
  var d = cast[ByteAddress](dest)
  case n.kind
  of nkNone: sysAssert(false, "genericResetAux")
  of nkSlot: genericReset(cast[pointer](d +% n.offset), n.typ)
  of nkList:
    for i in 0..n.len-1: genericResetAux(dest, n.sons[i])
  of nkCase:
    var m = selectBranch(dest, n)
    if m != nil: genericResetAux(dest, m)
    zeroMem(cast[pointer](d +% n.offset), n.typ.size)

proc genericReset(dest: pointer, mt: PNimType) =
  var d = cast[ByteAddress](dest)
  sysAssert(mt != nil, "genericReset 2")
  case mt.kind
  of tyString, tyRef, tyOptAsRef, tySequence:
    unsureAsgnRef(cast[PPointer](dest), nil)
  of tyTuple:
    genericResetAux(dest, mt.node)
  of tyObject:
    genericResetAux(dest, mt.node)
    # also reset the type field for tyObject, for correct branch switching!
    var pint = cast[ptr PNimType](dest)
    pint[] = nil
  of tyArray, tyArrayConstr:
    for i in 0..(mt.size div mt.base.size)-1:
      genericReset(cast[pointer](d +% i *% mt.base.size), mt.base)
  else:
    zeroMem(dest, mt.size) # set raw bits to zero

proc selectBranch(discVal, L: int,
                  a: ptr array[0x7fff, ptr TNimNode]): ptr TNimNode =
  result = a[L] # a[L] contains the ``else`` part (but may be nil)
  if discVal <% L:
    var x = a[discVal]
    if x != nil: result = x

proc FieldDiscriminantCheck(oldDiscVal, newDiscVal: int,
                            a: ptr array[0x7fff, ptr TNimNode],
                            L: int) {.compilerProc.} =
  var oldBranch = selectBranch(oldDiscVal, L, a)
  var newBranch = selectBranch(newDiscVal, L, a)
  if newBranch != oldBranch and oldDiscVal != 0:
    sysFatal(FieldError, "assignment to discriminant changes object branch")
