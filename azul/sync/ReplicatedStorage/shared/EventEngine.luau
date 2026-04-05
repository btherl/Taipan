-- EventEngine.lua
-- Pure logic module: random arrival events and storm.
-- No Roblox service calls. All functions modify state in place or return values.

local Constants = require(script.Parent.Constants)
local EventEngine = {}

-- FN_R helper: INT(RND * x) = random integer 0..floor(x)-1
-- Matches BASIC FN_R(x). Returns 0 if x <= 0.
local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end

-- Spices Seizure (BASIC lines 1900-1910)
-- Triggers: non-HK port, ship has spices (index 1), 1-in-18 chance.
-- Confiscates all hold spices, restores holdSpace, deducts fine from cash.
-- Fine = FN_R(CA / 1.8) -- can leave cash negative.
-- Returns fine amount (number) if fired, nil otherwise.
function EventEngine.spicesSeizure(state)
  if state.currentPort == Constants.HONG_KONG then return nil end
  if state.shipCargo[1] == 0 then return nil end
  if math.random(0, 17) ~= 0 then return nil end  -- 1-in-18

  local fine = fnR(state.cash / 1.8)
  state.holdSpace    = state.holdSpace + state.shipCargo[1]
  state.shipCargo[1] = 0
  state.cash         = state.cash - fine
  return fine
end

-- Cargo Theft (BASIC lines 2000-2030)
-- Triggers: warehouse has any goods, 1-in-50 chance.
-- Each warehouse good reduced to FN_R(W / 1.8); warehouseUsed updated.
-- Returns true if theft fired, false otherwise.
function EventEngine.cargoTheft(state)
  local total = 0
  for i = 1, 4 do total = total + state.warehouseCargo[i] end
  if total == 0 then return false end
  if math.random(0, 49) ~= 0 then return false end  -- 1-in-50

  for i = 1, 4 do
    local old = state.warehouseCargo[i]
    local new = fnR(old / 1.8)
    state.warehouseUsed     = state.warehouseUsed - old + new
    state.warehouseCargo[i] = new
  end
  return true
end

-- Cash Robbery (BASIC lines 2501-2556)
-- Triggers: CA > 25000, 1-in-20 chance.
-- Stolen = FN_R(CA / 1.4).
-- Returns stolen amount (number) if fired, nil otherwise.
function EventEngine.cashRobbery(state)
  if state.cash <= 25000 then return nil end
  if math.random(0, 19) ~= 0 then return nil end  -- 1-in-20

  local stolen = fnR(state.cash / 1.4)
  state.cash = state.cash - stolen
  return stolen
end

-- Storm: occurs? (BASIC line 3310: IF FN_R(10) THEN skip)
-- 1-in-10 chance of storm. Returns true if storm occurs.
function EventEngine.stormOccurs()
  return math.random(0, 9) == 0
end

-- Storm: severe? (BASIC line 3312: IF NOT(FN_R(30)))
-- 1-in-30 chance of "going down" severity. Only called if stormOccurs().
function EventEngine.stormGoingDown()
  return math.random(0, 29) == 0
end

-- Storm: ship sinks? (BASIC: IF FN_R(DM/SC*3) THEN sink)
-- FN_R(x) truthy = non-zero. Returns true if ship sinks.
-- Only called if stormGoingDown() was true.
-- Sets state.gameOver = true on sink.
function EventEngine.stormSinks(state)
  local x = state.damage / state.shipCapacity * 3
  local n = math.floor(x)
  if n <= 0 then return false end   -- undamaged: never sinks in storm
  if math.random(0, n - 1) ~= 0 then
    state.gameOver = true
    return true
  end
  return false
end

-- Storm: blown off course? (BASIC line 3330: IF FN_R(3) THEN skip)
-- 1-in-3 chance. Only called if ship survived storm.
-- Returns new port index (1-7, != destination) if blown off course, nil otherwise.
function EventEngine.stormBlownOffCourse(state, destination)
  if math.random(0, 2) ~= 0 then return nil end  -- 2-in-3 skip

  local newPort
  repeat
    newPort = math.random(1, 7)
  until newPort ~= destination

  return newPort
end

return EventEngine