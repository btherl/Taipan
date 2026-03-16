-- PriceEngine.lua
-- Calculates current port prices for all 4 goods.
-- Formula from BASIC line 2100:
--   CP(I) = BP%(LO,I) / 2 * (FN_R(3) + 1) * 10^(4-I)
-- Crash/boom events from BASIC lines 2410-2450:
--   1-in-9 chance per PORT VISIT (not per good): crash (price/5) or boom (price*5..9)
--   ONE random good is affected when the event fires

local Constants = require(script.Parent.Constants)

local PriceEngine = {}

-- Internal: base price for a single good before crash/boom
-- bp: base price value, goodIndex: 1-4, randFactor: 1-3
function PriceEngine._basePrice(bp, goodIndex, randFactor)
  local scale = Constants.PRICE_SCALE[goodIndex]
  return math.floor(bp / 2 * randFactor * scale)
end

function PriceEngine._crashPrice(price)
  return math.floor(price / 5)
end

function PriceEngine._boomPrice(price, multiplier)
  return math.floor(price * multiplier)
end

-- Calculates prices for all 4 goods at the given port.
-- basePrices: the mutable base price matrix from GameState (not Constants directly,
--             since it drifts each January)
-- portIndex: 1-7
-- Returns: array of 4 integer prices
function PriceEngine.calculatePrices(basePrices, portIndex)
  -- Calculate base prices for all 4 goods
  local prices = {}
  for good = 1, 4 do
    local bp = basePrices[portIndex][good]
    local randFactor = math.random(1, 3)           -- FN_R(3) + 1 → range 1-3
    prices[good] = PriceEngine._basePrice(bp, good, randFactor)
  end

  -- One crash/boom event per port visit: 1-in-9 chance (BASIC line 2410)
  if math.random(0, 8) == 0 then
    local affectedGood = math.random(1, 4)         -- FN R(4) + 1 (BASIC line 2420)
    if math.random(0, 1) == 0 then
      prices[affectedGood] = PriceEngine._crashPrice(prices[affectedGood])
    else
      local multiplier = math.random(5, 9)         -- FN R(5) + 5 → range 5-9
      prices[affectedGood] = PriceEngine._boomPrice(prices[affectedGood], multiplier)
    end
  end

  return prices
end

-- Applies the annual January base price drift to the mutable basePrices table.
-- Called once per in-game year. Mutates basePrices in place.
-- From BASIC line 1020: BP%(I,J) += FN_R(2) for all ports and goods.
function PriceEngine.applyAnnualDrift(basePrices)
  for port = 1, 7 do
    for good = 1, 4 do
      basePrices[port][good] = basePrices[port][good] + math.random(0, 1)
    end
  end
end

return PriceEngine
