module

public import Veir.Pass
public import Veir.Interfaces.RegionKindInterfaces
import Veir.Rewriter.LinkedList

/-!
  # A minimal CFG simplification pass

  For now this pass only removes blocks that are unreachable from their
  region's entry block, in SSACFG regions.

  A region is left alone when any of its unreachable blocks contains an
  operation with regions, since we don't yet have a way to erase regions.
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

/-- Erase `dead`, a set of blocks of `region` that does not contain the
    entry block, where nothing outside `dead` refers to these blocks or to
    any value defined in them, and no operation in them has regions.

    First every operation in `dead` drops its operands and successors, so
    that no use lists mention them any more; after that the operations and
    blocks can be deallocated without regard to order, even when the dead
    blocks refer to each other.

    TODO: this belongs in the rewriter once we prove it preserves
    well-formedness. -/
def eraseBlocks (ctx : IRContext OpCode) (region : RegionPtr) (dead : Array BlockPtr) :
    IRContext OpCode := Id.run do
  let ops := dead.flatMap (blockOps ctx)
  let mut ctx := ctx
  for op in ops do
    for i in [0:op.getNumOperands! ctx] do
      ctx := (op.getOpOperand i).removeFromCurrent! ctx
    for i in [0:op.getNumSuccessors! ctx] do
      ctx := (op.getBlockOperand i).removeFromCurrent! ctx
  for op in ops do
    ctx := { ctx with operations := ctx.operations.erase op }
  for block in dead do
    let { prev, next, .. } := block.get! ctx
    -- The entry block is never dead, so every dead block has a predecessor.
    ctx := prev.get!.setNextBlock! ctx next
    ctx := match next with
      | some next => next.setPrevBlock! ctx prev
      | none => region.setLastBlock! ctx prev
    ctx := { ctx with blocks := ctx.blocks.erase block }
  return ctx

set_option warn.sorry false in
/-- Remove the unreachable blocks of `region`, if it is an SSACFG region. -/
def simplifyRegion (ctx : WfIRContext OpCode) (region : RegionPtr) :
    WfIRContext OpCode := Id.run do
  if region.getRegionKind ctx != .SSACFG then return ctx
  let blocks := regionBlocks ctx.raw region
  let some entry := blocks[0]? | return ctx
  let live := reachableFrom ctx.raw entry
  let dead := blocks.filter (!live.contains ·)
  if dead.isEmpty then return ctx
  if dead.any (fun block => (blockOps ctx.raw block).any (·.getNumRegions! ctx.raw > 0)) then
    return ctx
  return ⟨eraseBlocks ctx.raw region dead, sorry⟩

def run (ctx : WfIRContext OpCode) : WfIRContext OpCode :=
  ctx.raw.regions.keys.foldl simplifyRegion ctx

def SimplifyCFGPass.impl (ctx : WfIRContext OpCode) (op : OperationPtr) (_ : op.InBounds ctx.raw) :
    ExceptT String IO (WfIRContext OpCode) := do
  pure (SimplifyCFG.run ctx)

end SimplifyCFG

public def SimplifyCFGPass : Pass OpCode :=
  { name := "simplify-cfg"
    description := "Simplify the control flow graph by removing unreachable blocks."
    run := fun _ => SimplifyCFG.SimplifyCFGPass.impl }

end Veir
