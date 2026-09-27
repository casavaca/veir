module

public import Veir.Pass
import Veir.Rewriter.EraseBlocks

/-!
  # A minimal CFG simplification pass

  For now this pass only removes blocks that are unreachable from their
  region's entry block, recursively beneath the pass's root operation.

  Like MLIR, every multiblock region is treated as a CFG, including regions of
  unregistered operations. Single-block regions only need recursive traversal.
  All dead blocks are collected before deletion so that uses in independently
  unreachable nested blocks can be removed together with their definitions.
-/

namespace Veir
namespace SimplifyCFG

/-- The blocks of `region`, in order. -/
def regionBlocks (ctx : IRContext OpCode) (region : RegionPtr) : Array BlockPtr := Id.run do
  let mut blocks := #[]
  let mut cur := (region.get! ctx).firstBlock
  while h : cur.isSome do
    let block := cur.get h
    blocks := blocks.push block
    cur := (block.get! ctx).next
  return blocks

/-- The operations of `block`, in order. -/
def blockOps (ctx : IRContext OpCode) (block : BlockPtr) : Array OperationPtr := Id.run do
  let mut ops := #[]
  let mut cur := (block.get! ctx).firstOp
  while h : cur.isSome do
    let op := cur.get h
    ops := ops.push op
    cur := (op.get! ctx).next
  return ops

/-- The blocks reachable from `entry` along successor edges. -/
def reachableFrom (ctx : IRContext OpCode) (entry : BlockPtr) : Std.HashSet BlockPtr := Id.run do
  let mut seen : Std.HashSet BlockPtr := {entry}
  let mut worklist := #[entry]
  while h : worklist.size > 0 do
    let block := worklist.back
    worklist := worklist.pop
    for succ in block.getSuccessors! ctx do
      unless seen.contains succ do
        seen := seen.insert succ
        worklist := worklist.push succ
  return seen

/-- Collect the roots of dead block trees beneath `root`. Regions inside live
    blocks are analyzed independently; everything inside a dead block will be
    erased with that block, regardless of its local reachability. -/
def collectUnreachableBlocks (ctx : IRContext OpCode) (root : OperationPtr) :
    Array BlockPtr := Id.run do
  let mut dead := #[]
  let mut worklist := root.getRegions! ctx
  while !worklist.isEmpty do
    let region := worklist.back!
    worklist := worklist.pop
    let blocks := regionBlocks ctx region
    let some entry := blocks[0]? | continue
    let live := if blocks.size == 1 then {entry} else reachableFrom ctx entry
    for block in blocks do
      if live.contains block then
        for op in blockOps ctx block do
          worklist := worklist ++ op.getRegions! ctx
      else
        dead := dead.push block
  return dead

def run (ctx : WfIRContext OpCode) (root : OperationPtr) :
    Except String (WfIRContext OpCode) := do
  unless ctx.raw.operations.contains root do
    throw "simplify-cfg: root operation is out of bounds"
  WfRewriter.eraseBlockTrees ctx (collectUnreachableBlocks ctx.raw root)

def SimplifyCFGPass.impl (ctx : WfIRContext OpCode) (op : OperationPtr) (_ : op.InBounds ctx.raw) :
    ExceptT String IO (WfIRContext OpCode) := do
  match SimplifyCFG.run ctx op with
  | .ok ctx => pure ctx
  | .error message => throw message

end SimplifyCFG

public def SimplifyCFGPass : Pass OpCode :=
  { name := "simplify-cfg"
    description := "Simplify the control flow graph by removing unreachable blocks."
    run := fun _ => SimplifyCFG.SimplifyCFGPass.impl }

end Veir
