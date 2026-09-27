module

public import Veir.Rewriter.LinkedList
import Std.Data.HashSet

/-!
  # Batch erasure of blocks and their nested IR

  Collect the complete deletion set and check its users before changing the
  context. Detaching all outgoing uses while the definitions still exist lets
  us erase cycles and nested regions without introducing nullable operands.
-/

namespace Veir

variable {OpInfo : Type} [HasOpInfo OpInfo]

private structure BlockErasure where
  blocks : Std.HashSet BlockPtr := {}
  operations : Std.HashSet OperationPtr := {}
  regions : Std.HashSet RegionPtr := {}

/-- Expand the requested blocks to include every operation, region, and block
    nested within them. Overlapping or repeated roots are collected once. -/
private def collectBlockTrees (ctx : IRContext OpInfo) (roots : Array BlockPtr) :
    Except String BlockErasure := do
  let mut dead : BlockErasure := {}
  let mut worklist := roots
  while !worklist.isEmpty do
    let block := worklist.back!
    worklist := worklist.pop
    unless ctx.blocks.contains block do
      throw "cannot erase blocks: a requested block is out of bounds"
    if dead.blocks.contains block then continue
    dead := { dead with blocks := dead.blocks.insert block }
    let mut currentOp := (block.get! ctx).firstOp
    while let some op := currentOp do
      dead := { dead with operations := dead.operations.insert op }
      for region in op.getRegions! ctx do
        dead := { dead with regions := dead.regions.insert region }
        let mut currentBlock := (region.get! ctx).firstBlock
        while let some child := currentBlock do
          worklist := worklist.push child
          currentBlock := (child.get! ctx).next
      currentOp := (op.get! ctx).next
  return dead

/-- Every use of a deleted value must itself be deleted. -/
private def checkValueUsers (ctx : IRContext OpInfo) (dead : BlockErasure)
    (value : ValuePtr) (description : String) : Except String Unit := do
  let mut current := value.getFirstUse! ctx
  while let some use := current do
    unless dead.operations.contains use.op do
      throw s!"cannot erase blocks: {description} has a surviving user"
    current := (use.get! ctx).nextUse

/-- Check references from the entire context, including users outside the
    caller's traversal root. This needs no dominance assumptions. -/
private def checkBlockTreeUsers (ctx : IRContext OpInfo) (dead : BlockErasure) :
    Except String Unit := do
  for op in dead.operations.toArray do
    for result in op.getResults! ctx do
      checkValueUsers ctx dead result "an operation result"
  for block in dead.blocks.toArray do
    for arg in block.getArguments! ctx do
      checkValueUsers ctx dead arg "a block argument"
    let mut current := (block.get! ctx).firstUse
    while let some use := current do
      unless dead.operations.contains use.op do
        throw "cannot erase blocks: a block has a surviving predecessor"
      current := (use.get! ctx).nextUse

/-- Apply a checked deletion set. Intermediate contexts are internal: operands
    are detached before any allocation disappears, and only the final context
    is returned to the caller. -/
private def applyBlockErasure (ctx : IRContext OpInfo) (dead : BlockErasure) :
    IRContext OpInfo := Id.run do
  let mut ctx := ctx
  for op in dead.operations.toArray do
    for i in [0:op.getNumOperands! ctx] do
      ctx := (op.getOpOperand i).removeFromCurrent! ctx
    for i in [0:op.getNumSuccessors! ctx] do
      ctx := (op.getBlockOperand i).removeFromCurrent! ctx

  -- Only surviving regions need their block lists repaired. Read the current
  -- neighbors so that adjacent deletions work in any order. This also handles
  -- erasing the first block or all blocks of a region.
  for block in dead.blocks.toArray do
    let { parent, prev, next, .. } := block.get! ctx
    if let some region := parent then
      unless dead.regions.contains region do
        ctx := match prev with
          | some prev => prev.setNextBlock! ctx next
          | none => region.setFirstBlock! ctx next
        ctx := match next with
          | some next => next.setPrevBlock! ctx prev
          | none => region.setLastBlock! ctx prev

  for op in dead.operations.toArray do
    ctx := { ctx with operations := ctx.operations.erase op }
  for block in dead.blocks.toArray do
    ctx := { ctx with blocks := ctx.blocks.erase block }
  for region in dead.regions.toArray do
    ctx := { ctx with regions := ctx.regions.erase region }
  return ctx

set_option warn.sorry false in
/-- Erase the requested blocks and everything nested in them, allowing cycles
    within the deletion set. Fail before mutation if any block is out of bounds
    or any deleted value or block has a surviving user.

    TODO: prove that collection, the user checks, and batch erasure preserve
    well-formedness. -/
public def WfRewriter.eraseBlockTrees (ctx : WfIRContext OpInfo) (roots : Array BlockPtr) :
    Except String (WfIRContext OpInfo) := do
  if roots.isEmpty then return ctx
  let dead ← collectBlockTrees ctx.raw roots
  checkBlockTreeUsers ctx.raw dead
  return ⟨applyBlockErasure ctx.raw dead, sorry⟩

end Veir
