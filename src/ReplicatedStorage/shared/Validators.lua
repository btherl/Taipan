-- Validators.lua
-- Pure functions that check whether a game action is legal.
-- All validation must also be performed server-side before mutating state.

local Validators = {}

-- Can the player buy `quantity` units of `goodIndex` at `pricePerUnit`?
-- NOTE: `goodIndex` is not used here — callers (GameService) are responsible for
-- resolving `pricePerUnit` from state.currentPrices[goodIndex] server-side,
-- never from untrusted client input.
-- NOTE: state.holdSpace must be up-to-date before calling this function.
function Validators.canBuy(state, quantity, goodIndex, pricePerUnit)
  local totalCost = quantity * pricePerUnit
  if totalCost > state.cash then return false end
  if quantity > state.holdSpace then return false end
  return true
end

-- Can the player sell `quantity` units of `goodIndex` from their ship hold?
function Validators.canSell(state, quantity, goodIndex)
  local held = state.shipCargo[goodIndex]
  if type(held) ~= "number" then return false end
  return held >= quantity
end

-- How many units of cargo can fit in the hold right now?
-- Precondition: state.holdSpace must have been recalculated after any cargo
-- change (shipCapacity - sum(shipCargo) - guns*10).
function Validators.holdSpaceFor(state)
  return state.holdSpace
end

return Validators
