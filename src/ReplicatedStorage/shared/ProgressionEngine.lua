-- ProgressionEngine.lua
-- Pure logic: ship repair, upgrade/gun offers, score, rating, retirement.
-- No Roblox service calls.

local ProgressionEngine = {}

local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end

-- Cost per damage point for repair.
-- BR = INT((FN_R(60*(TI+3)/4) + 25*(TI+3)/4) * SC/50)
-- Minimum 1 to avoid division by zero.
function ProgressionEngine.repairRate(state)
  local ti = state.turnsElapsed
  local sc = state.shipCapacity
  local br = math.floor((fnR(60*(ti+3)/4) + 25*(ti+3)/4) * sc/50)
  return math.max(1, br)
end

-- Damage repaired when spending W cash at given repair rate.
-- = INT(W/BR + 0.5)  (round to nearest integer)
function ProgressionEngine.repairAmount(br, w)
  if br <= 0 then return 0 end
  return math.floor(w / br + 0.5)
end

-- Cash needed to repair all damage ("All" button).
-- BASIC formula: BR*DM+1 (DM was always integer in BASIC).
-- Luau adaptation: uses math.ceil(damage) because our damage is fractional
-- (combat accumulates I/2 terms). Raw DM=2.1 → BR*2.1+1=211 → repairAmount=2, leaving 0.1
-- damage; ceil ensures the "All" cost guarantees a complete repair.
function ProgressionEngine.repairAllCost(br, damage)
  return br * math.ceil(damage) + 1
end

-- Apply repair: spend W cash, reduce damage.
-- Uses pre-computed repairRate (stored in state.shipOffer.repairRate).
-- Returns number of damage points repaired, or 0 if invalid.
-- NOTE: W is capped at state.cash before calling (server must validate).
function ProgressionEngine.applyRepair(state, repairRate, w)
  if w <= 0 or w > state.cash or state.damage <= 0 then return 0 end
  local repaired = math.min(
    ProgressionEngine.repairAmount(repairRate, w),
    math.ceil(state.damage)
  )
  if repaired <= 0 then return 0 end
  state.cash   = state.cash - w
  state.damage = math.max(0, state.damage - repaired)
  return repaired
end

-- Upgrade offer: 1-in-4 chance (fnR(4)==0).
-- Cost = INT(1000 + FN_R(1000*(TI+5)/6)) * (INT(SC/50)*(DM>0)+1)
-- Returns cost (number) if offer fires, nil otherwise.
function ProgressionEngine.checkUpgradeOffer(state)
  if fnR(4) ~= 0 then return nil end
  local ti   = state.turnsElapsed
  local sc   = state.shipCapacity
  local dm   = state.damage
  local base = math.floor(1000 + fnR(1000*(ti+5)/6))
  local mult = math.floor(sc/50) * (dm > 0 and 1 or 0) + 1
  return base * mult
end

-- Apply upgrade: adds 50 hold capacity, repairs all damage, deducts cost.
-- Returns true on success, false if insufficient cash.
function ProgressionEngine.applyUpgrade(state, cost)
  if state.cash < cost then return false end
  state.cash         = state.cash - cost
  state.shipCapacity = state.shipCapacity + 50
  state.holdSpace    = state.holdSpace + 50
  state.damage       = 0
  return true
end

-- Gun offer: 1-in-3 chance (fnR(3)==0), requires holdSpace >= 10.
-- Cost = INT(FN_R(1000*(TI+5)/6) + 500)
-- Returns cost (number) if offer fires, nil otherwise.
function ProgressionEngine.checkGunOffer(state)
  if state.holdSpace < 10 then return nil end
  if fnR(3) ~= 0 then return nil end
  local ti = state.turnsElapsed
  return math.floor(fnR(1000*(ti+5)/6) + 500)
end

-- Apply gun purchase: +1 gun, -10 holdSpace, deducts cost.
-- Returns true on success, false if insufficient cash or hold.
function ProgressionEngine.applyGun(state, cost)
  if state.cash < cost then return false end
  if state.holdSpace < 10 then return false end
  state.cash      = state.cash - cost
  state.guns      = state.guns + 1
  state.holdSpace = state.holdSpace - 10
  return true
end

-- Net worth: CA + BA - DW
function ProgressionEngine.netWorth(state)
  return state.cash + state.bankBalance - state.debt
end

-- Score: INT((CA+BA-DW) / 100 / TI^1.1)
function ProgressionEngine.score(state)
  local nw = ProgressionEngine.netWorth(state)
  local ti = state.turnsElapsed
  return math.floor(nw / 100 / (ti ^ 1.1))
end

-- Rating based on score.
function ProgressionEngine.rating(sc)
  if sc >= 50000 then return "Ma Tsu"
  elseif sc >= 8000 then return "Master"
  elseif sc >= 1000 then return "Taipan"
  elseif sc >= 500  then return "Compradore"
  else                   return "Galley Hand"
  end
end

-- Whether player may retire (net worth >= 1,000,000).
function ProgressionEngine.canRetire(state)
  return ProgressionEngine.netWorth(state) >= 1000000
end

return ProgressionEngine
