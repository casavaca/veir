// RUN: veir-opt %s -p=simplify-cfg | filecheck %s

"builtin.module"() ({
  // An unreachable block is removed.
  // CHECK:      func.func @simple(%[[A:.*]]: i32) -> i32 {
  // CHECK-NEXT:   "func.return"(%[[A]]) : (i32) -> ()
  // CHECK-NEXT: }
  "func.func"() <{function_type = (i32) -> i32, sym_name = "simple"}> ({
  ^0(%a : i32):
    "func.return"(%a) : (i32) -> ()
  ^1():
    %c = "arith.constant"() <{value = 7 : i32}> : () -> i32
    "func.return"(%c) : (i32) -> ()
  }) : () -> ()

  // An unreachable block that branches to a live block is removed, and the
  // live block survives.
  // CHECK:      func.func @dead_to_live(%[[A:.*]]: i32) -> i32 {
  // CHECK-NEXT:   "cf.br"(%[[A]]) [^[[BB:.*]]] : (i32) -> ()
  // CHECK-NEXT:   ^[[BB]](%[[X:.*]] : i32):
  // CHECK-NEXT:     "func.return"(%[[X]]) : (i32) -> ()
  // CHECK-NEXT: }
  "func.func"() <{function_type = (i32) -> i32, sym_name = "dead_to_live"}> ({
  ^0(%a : i32):
    "cf.br"(%a) [^2] : (i32) -> ()
  ^1():
    %c = "arith.constant"() <{value = 7 : i32}> : () -> i32
    "cf.br"(%c) [^2] : (i32) -> ()
  ^2(%x : i32):
    "func.return"(%x) : (i32) -> ()
  }) : () -> ()

  // An unreachable cycle whose blocks use each other's values is removed.
  // CHECK:      func.func @dead_loop(%[[A:.*]]: i32) -> i32 {
  // CHECK-NEXT:   "func.return"(%[[A]]) : (i32) -> ()
  // CHECK-NEXT: }
  "func.func"() <{function_type = (i32) -> i32, sym_name = "dead_loop"}> ({
  ^0(%a : i32):
    "func.return"(%a) : (i32) -> ()
  ^1(%p : i32):
    %q = "arith.addi"(%p, %r) : (i32, i32) -> i32
    "cf.br"(%q) [^2] : (i32) -> ()
  ^2(%s : i32):
    %r = "arith.addi"(%s, %q) : (i32, i32) -> i32
    "cf.br"(%r) [^1] : (i32) -> ()
  }) : () -> ()

  // Reachable blocks, including ones only reachable through a loop, stay.
  // CHECK:      func.func @all_live(%[[A:.*]]: i1) {
  // CHECK-NEXT:   "cf.br"() [^[[BB1:.*]]] : () -> ()
  // CHECK-NEXT:   ^[[BB1]]():
  // CHECK-NEXT:     "cf.cond_br"(%[[A]]) [^[[BB1]], ^[[BB2:.*]]]
  // CHECK-NEXT:   ^[[BB2]]():
  // CHECK-NEXT:     "func.return"() : () -> ()
  // CHECK-NEXT: }
  "func.func"() <{function_type = (i1) -> (), sym_name = "all_live"}> ({
  ^0(%a : i1):
    "cf.br"() [^1] : () -> ()
  ^1():
    "cf.cond_br"(%a) [^1, ^2] <{operandSegmentSizes = array<i32: 1, 0, 0>}> : (i1) -> ()
  ^2():
    "func.return"() : () -> ()
  }) : () -> ()
}) : () -> ()
