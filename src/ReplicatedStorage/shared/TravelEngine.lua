-- TravelEngine.lua
-- Handles time advancement and departure validation for each voyage.

local Constants   = require(script.Parent.Constants)
local PriceEngine = require(script.Parent.PriceEngine)

local TravelEngine = {}

-- Advances game time by one turn (called on every TravelTo).
-- Mutates state in place.
function TravelEngine.timeAdvance(state)
  -- 1. Increment turn counter
  state.turnsElapsed = state.turnsElapsed + 1

  -- 2. Advance month
  state.month = state.month + 1

  -- 3. Apply bank interest (only when balance is positive)
  if state.bankBalance > 0 then
    state.bankBalance = math.floor(state.bankBalance + state.bankBalance * Constants.BANK_INTEREST_RATE)
  end

  -- 4. Apply debt compound interest (only when debt is positive)
  if state.debt > 0 then
    state.debt = math.floor(state.debt + state.debt * Constants.DEBT_INTEREST_RATE)
  end

  -- 5. Year rollover when month exceeds 12
  if state.month > 12 then
    state.month = 1
    state.year  = state.year + 1

    -- January annual events
    state.enemyBaseHP     = state.enemyBaseHP + 10
    state.enemyBaseDamage = state.enemyBaseDamage + 0.5
    PriceEngine.applyAnnualDrift(state.basePrices)
  end
end

-- Validates whether the player may depart to the given destination.
-- Returns nil if the departure is valid, or an error string if not.
function TravelEngine.canDepart(state, destination)
  -- Destination must be an integer in range 1-7
  if type(destination) ~= "number"
      or destination ~= math.floor(destination)
      or destination < 1
      or destination > 7 then
    return "invalid destination"
  end

  -- Cannot travel to the port the ship is already at
  if destination == state.currentPort then
    return "already at this port"
  end

  -- Cannot depart while overloaded
  if state.holdSpace < 0 then
    return "ship is overloaded"
  end

  return nil
end

return TravelEngine
