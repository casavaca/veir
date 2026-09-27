// RUN: veir-opt %s -p=simplify-cfg --allow-unregistered-dialect | filecheck %s
// RUN: %if mlir-min-24 %{ mlir-opt %s --allow-unregistered-dialect --trivial-dce --mlir-print-op-generic | veir-opt --allow-unregistered-dialect | filecheck %s %}

"builtin.module"() ({
  // The nested user and its outer definition are independently unreachable.
  // Unregistered multiblock regions must be traversed, and deletion must wait
  // until both blocks have been collected. Exercise results and block args.
  // CHECK-LABEL: func.func @nested_dead_use() {
  // CHECK-NEXT:    "unknown.region"() ({
  // CHECK-NEXT:    ^{{.*}}():
  // CHECK-NEXT:      "llvm.unreachable"() : () -> ()
  // CHECK-NEXT:    }) : () -> ()
  // CHECK-NEXT:    "func.return"() : () -> ()
  // CHECK-NEXT:  }
  "func.func"() <{function_type = () -> (), sym_name = "nested_dead_use"}> ({
  ^entry():
    "unknown.region"() ({
    ^inner_entry():
      "llvm.unreachable"() : () -> ()
    ^inner_dead():
      "test.test"(%dead_value, %dead_arg) : (i32, i32) -> ()
      "llvm.unreachable"() : () -> ()
    }) : () -> ()
    "func.return"() : () -> ()
  ^outer_dead(%dead_arg : i32):
    %dead_value = "arith.constant"() <{value = 7 : i32}> : () -> i32
    "func.return"() : () -> ()
  }) : () -> ()

  // A retained graph region may contain cycles and forward references. Its
  // single block survives, and traversal still reaches nested CFG regions.
  // CHECK-LABEL: func.func @through_graph_region() {
  // CHECK-NEXT:    "test.test"() ({
  // CHECK-NEXT:    ^{{.*}}():
  // CHECK-NEXT:      %[[X:.*]] = "test.test"(%[[Y:.*]]) : (i32) -> i32
  // CHECK-NEXT:      %[[Y]] = "test.test"(%[[X]]) : (i32) -> i32
  // CHECK-NEXT:      "unknown.region"() ({
  // CHECK-NEXT:      ^{{.*}}():
  // CHECK-NEXT:        "llvm.unreachable"() : () -> ()
  // CHECK-NEXT:      }) : () -> ()
  // CHECK-NEXT:      "test.test"() ({}) : () -> ()
  // CHECK-NEXT:    }) : () -> ()
  // CHECK-NEXT:    "func.return"() : () -> ()
  // CHECK-NEXT:  }
  "func.func"() <{function_type = () -> (), sym_name = "through_graph_region"}> ({
    "test.test"() ({
      %x = "test.test"(%y) : (i32) -> i32
      %y = "test.test"(%x) : (i32) -> i32
      "unknown.region"() ({
      ^inner_entry():
        "llvm.unreachable"() : () -> ()
      ^inner_dead():
        "test.test"(%x) : (i32) -> ()
        "llvm.unreachable"() : () -> ()
      }) : () -> ()
      "test.test"() ({}) : () -> ()
    }) : () -> ()
    "func.return"() : () -> ()
  }) : () -> ()
}) : () -> ()
