-- TravelEngine.lua
-- Handles time advancement and departure validation for each voyage.

local Constants   = require(script.Parent.Constants)
local PriceEngine = require(script.Parent.PriceEngine)

local TravelEngine = {}

function TravelEngine.timeAdvance(state)
  state.turnsElapsed = state.turnsElapsed + 1
  state.month        = state.month + 1

  if state.bankBalance > 0 then
    state.bankBalance = math.floor(state.bankBalance + state.bankBalance * Constants.BANK_INTEREST_RATE)
  end

  if state.debt ~= 0 then
    state.debt = math.floor(state.debt + state.debt * Constants.DEBT_INTEREST_RATE)
  end

  if state.month > 12 then
    state.month = 1
    state.year  = state.year + 1
    state.enemyBaseHP     = state.enemyBaseHP + 10
    state.enemyBaseDamage = state.enemyBaseDamage + 0.5
    PriceEngine.applyAnnualDrift(state.basePrices)
  end
end

function TravelEngine.canDepart(state, destination)
  if type(destination) ~= "number"
      or destination ~= math.floor(destination)
      or destination < 1
      or destination > 7 then
    return "invalid destination"
  end
  if destination == state.currentPort then
    return "already at this port"
  end
  if state.holdSpace < 0 then
    return "ship is overloaded"
  end
  return nil
end

return TravelEngine