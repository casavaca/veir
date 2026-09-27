// RUN: veir-opt %s -p=simplify-cfg | filecheck %s

// Erasing a dead block also erases all operations and regions nested in it.

"builtin.module"() ({
  // CHECK:      func.func @dead_region_op() {
  // CHECK-NEXT:   "func.return"() : () -> ()
  // CHECK-NEXT: }
  "func.func"() <{function_type = () -> (), sym_name = "dead_region_op"}> ({
  ^0():
    "func.return"() : () -> ()
  ^1():
    "test.test"() ({
    ^0():
      "test.test"() : () -> ()
    }) : () -> ()
    "func.return"() : () -> ()
  }) : () -> ()

  // Delete every descendant of a dead block, including graph cycles and
  // empty regions. Uses of the live constant must be unlinked as well.
  // CHECK-LABEL: func.func @dead_nested_tree() -> i32 {
  // CHECK-NEXT:    %[[LIVE:.*]] = "arith.constant"() <{"value" = 42 : i32}> : () -> i32
  // CHECK-NEXT:    "func.return"(%[[LIVE]]) : (i32) -> ()
  // CHECK-NEXT:  }
  "func.func"() <{function_type = () -> i32, sym_name = "dead_nested_tree"}> ({
  ^entry():
    %live = "arith.constant"() <{value = 42 : i32}> : () -> i32
    "func.return"(%live) : (i32) -> ()
  ^dead():
    "test.test"() ({
      %x = "test.test"(%y, %live) : (i32, i32) -> i32
      %y = "test.test"(%x) : (i32) -> i32
      "test.test"() ({}) : () -> ()
    }) : () -> ()
    "func.return"(%live) : (i32) -> ()
  }) : () -> ()
}) : () -> ()
