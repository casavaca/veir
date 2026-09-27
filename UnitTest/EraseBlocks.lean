module

import all Veir.Passes.SimplifyCFG
import Veir.Parser.MlirParser
import Veir.Rewriter.EraseBlocks
meta import Veir.Passes.SimplifyCFG
meta import Veir.Parser.MlirParser
meta import Veir.GlobalOpInfo

open Veir
open Veir.Parser

private def parse (s : String) : OperationPtr × WfIRContext OpCode :=
  match WfIRContext.create OpCode with
  | none => panic! "failed to create IR context"
  | some (ctx, _) =>
    match ParserState.fromInput s.toByteArray with
    | .error _ => panic! "lex error"
    | .ok parser =>
      match parseTopLevelOp.run (MlirParserState.fromContext ctx) parser with
      | .error _ => panic! "parse error"
      | .ok (op, state, _) => (op, state.ctx)

private def uses := parse r#"
"func.func"() <{function_type = () -> (), sym_name = "uses"}> ({
^entry():
  %v = "arith.constant"() <{value = 1 : i32}> : () -> i32
  "cf.br"(%v) [^body] : (i32) -> ()
^body(%arg : i32):
  "test.test"(%v) : (i32) -> ()
  "cf.br"() [^exit] : () -> ()
^exit():
  "test.test"(%arg) : (i32) -> ()
  "func.return"() : () -> ()
}) : () -> ()
"#

private def useBlocks : Array BlockPtr :=
  SimplifyCFG.regionBlocks uses.2.raw (uses.1.getRegion! uses.2.raw 0)

private def rejects (block : BlockPtr) (expected : String) : Bool :=
  match WfRewriter.eraseBlockTrees uses.2 #[block] with
  | .error message => message == expected
  | .ok _ => false

-- Each kind of incoming reference is checked before any deletion.
#guard rejects useBlocks[0]! "cannot erase blocks: an operation result has a surviving user"
#guard rejects useBlocks[1]! "cannot erase blocks: a block argument has a surviving user"
#guard rejects useBlocks[2]! "cannot erase blocks: a block has a surviving predecessor"

-- Removing every user together with its definition succeeds. Repeated roots
-- are harmless, and removing the entry and last block leaves an empty region.
private def eraseWholeBody : Bool := Id.run do
  let .ok ctx := WfRewriter.eraseBlockTrees uses.2 (useBlocks ++ #[useBlocks[1]!])
    | return false
  let region := uses.1.getRegion! ctx.raw 0
  return (region.get! ctx.raw).firstBlock.isNone &&
    (region.get! ctx.raw).lastBlock.isNone &&
    useBlocks.all (fun block => !ctx.raw.blocks.contains block) &&
    ctx.raw.operations.size + 6 == uses.2.raw.operations.size

#guard eraseWholeBody

private def nested := parse r#"
"func.func"() <{function_type = () -> i32, sym_name = "nested"}> ({
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
"#

-- Printed output alone cannot detect orphaned allocations or stale use lists.
private def deletesNestedAllocations : Bool := Id.run do
  let (root, before) := nested
  let .ok ctx := SimplifyCFG.run before root | return false
  let entry := ((root.getRegion! ctx.raw 0).get! ctx.raw).firstBlock.get!
  let constant := (entry.get! ctx.raw).firstOp.get!
  let ret := (constant.get! ctx.raw).next.get!
  let value : ValuePtr := constant.getResult 0
  let some use := value.getFirstUse! ctx.raw | return false
  return ctx.raw.operations.size + 5 == before.raw.operations.size &&
    ctx.raw.blocks.size + 2 == before.raw.blocks.size &&
    ctx.raw.regions.size + 2 == before.raw.regions.size &&
    use.op == ret && (use.get! ctx.raw).nextUse.isNone &&
    (ctx.verify root).toBool

#guard deletesNestedAllocations

private def siblings := parse r#"
"builtin.module"() ({
  "func.func"() <{function_type = () -> (), sym_name = "first"}> ({
  ^entry():
    "func.return"() : () -> ()
  ^dead():
    "func.return"() : () -> ()
  }) : () -> ()
  "func.func"() <{function_type = () -> (), sym_name = "second"}> ({
  ^entry():
    "func.return"() : () -> ()
  ^dead():
    "func.return"() : () -> ()
  }) : () -> ()
}) : () -> ()
"#

-- A function-scoped invocation must leave its sibling function alone.
private def respectsRoot : Bool := Id.run do
  let (root, before) := siblings
  let moduleBlock := ((root.getRegion! before.raw 0).get! before.raw).firstBlock.get!
  let first := (moduleBlock.get! before.raw).firstOp.get!
  let second := (first.get! before.raw).next.get!
  let firstRegion := first.getRegion! before.raw 0
  let secondRegion := second.getRegion! before.raw 0
  let firstDead := (firstRegion.get! before.raw).lastBlock.get!
  let secondDead := (secondRegion.get! before.raw).lastBlock.get!
  let .ok ctx := SimplifyCFG.run before first | return false
  return !ctx.raw.blocks.contains firstDead && ctx.raw.blocks.contains secondDead &&
    (secondRegion.get! ctx.raw).lastBlock == some secondDead &&
    (ctx.verify root).toBool

#guard respectsRoot
