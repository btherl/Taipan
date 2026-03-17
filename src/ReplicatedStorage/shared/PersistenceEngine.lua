-- PersistenceEngine.lua
-- Serialise/deserialise game state for DataStore persistence.
-- No Roblox service calls; PriceEngine injected for testability.

local PersistenceEngine = {}

local SCALAR_FIELDS = {
  "startChoice", "cash", "debt", "bankBalance",
  "shipCapacity", "guns", "damage", "pirateBase",
  "currentPort", "month", "year", "turnsElapsed",
  "liYuenProtection", "wuWarningGiven", "bankruptcyCount",
  "enemyBaseDamage", "enemyBaseHP",
  "gameOver", "gameOverReason", "finalScore", "finalRating",
  "seenTutorial",
}

function PersistenceEngine.serialize(state)
  local data = { version = 1 }

  -- Scalar fields
  for _, field in ipairs(SCALAR_FIELDS) do
    data[field] = state[field]
  end

  -- Array fields (shallow copy)
  for _, field in ipairs({ "shipCargo", "warehouseCargo" }) do
    local arr = {}
    for i, v in ipairs(state[field]) do arr[i] = v end
    data[field] = arr
  end

  -- basePrices: deep copy 7x4 nested table
  local bp = {}
  for p = 1, 7 do
    bp[p] = {}
    for g = 1, 4 do bp[p][g] = state.basePrices[p][g] end
  end
  data.basePrices = bp

  return data
end

function PersistenceEngine.deserialize(data, PriceEngine)
  if data == nil then return nil end
  if data.version == nil or data.version ~= 1 then return nil end

  local state = {}

  -- Restore scalar fields
  for _, field in ipairs(SCALAR_FIELDS) do
    state[field] = data[field]
  end
  -- Default missing field from old saves
  if state.seenTutorial == nil then state.seenTutorial = false end

  -- Restore array fields
  for _, field in ipairs({ "shipCargo", "warehouseCargo" }) do
    local arr = {}
    for i, v in ipairs(data[field]) do arr[i] = v end
    state[field] = arr
  end

  -- Restore basePrices
  local bp = {}
  for p = 1, 7 do
    bp[p] = {}
    for g = 1, 4 do bp[p][g] = data.basePrices[p][g] end
  end
  state.basePrices = bp

  -- Derive computed fields from restored canonical data
  -- holdSpace: uses restored shipCapacity (includes upgrades) and restored shipCargo
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2]
    - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  state.warehouseUsed = state.warehouseCargo[1] + state.warehouseCargo[2]
    + state.warehouseCargo[3] + state.warehouseCargo[4]
  -- currentPrices: use the restored (drifted) basePrices, not original constants
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  state.destination   = state.currentPort

  -- Reset ephemeral fields
  state.liYuenOfferCost = nil
  state.inWuSession     = false
  state.pendingTutorial = nil
  state.combat          = nil
  state.shipOffer       = nil

  return state
end

-- Calls fn() up to maxAttempts times with exponential backoff.
-- Waits 1s after attempt 1, 2s after attempt 2 (no wait after last attempt).
-- Returns result on success, nil after all attempts exhausted.
-- Uses task.wait() (not deprecated wait()).
function PersistenceEngine.dataStoreRetry(fn, maxAttempts)
  maxAttempts = maxAttempts or 3
  local waitTime = 1
  for attempt = 1, maxAttempts do
    local ok, result = pcall(fn)
    if ok then return result end
    warn("PersistenceEngine: DataStore attempt " .. attempt
      .. " of " .. maxAttempts .. " failed: " .. tostring(result))
    if attempt < maxAttempts then
      task.wait(waitTime)
      waitTime = waitTime * 2
    end
  end
  return nil
end

return PersistenceEngine
