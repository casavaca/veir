// RUN: veir-opt %s -p=simplify-cfg | filecheck %s

// We can't erase regions yet, so a region is left alone when one of its
// unreachable blocks contains an operation with regions.

"builtin.module"() ({
  // CHECK:      func.func @dead_region_op() {
  // CHECK-NEXT:   "func.return"() : () -> ()
  // CHECK-NEXT:   ^{{.*}}():
  // CHECK-NEXT:     "test.test"() ({
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
}) : () -> ()
