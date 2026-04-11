-- FinanceEngine.lua
-- Pure logic module: Wu repay/borrow/bankruptcy, bank, Li Yuen protection.
-- No Roblox service calls. All functions modify state in place or return values.

local Constants = require(script.Parent.Constants)
local FinanceEngine = {}

-- FN_R helper: INT(RND * x) = random integer 0..floor(x)-1
-- Matches BASIC FN_R(x). Returns 0 if x <= 0.
local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end

-- Bankruptcy check: true if CA=0 AND BA=0 AND guns=0 AND all cargo=0
-- BASIC line 1330: IF CA=0 AND NOT(GN) AND NOT(BA) THEN ...
function FinanceEngine.isBankrupt(state)
  if state.cash ~= 0 or state.bankBalance ~= 0 or state.guns ~= 0 then return false end
  for i = 1, 4 do
    if state.shipCargo[i] ~= 0 or state.warehouseCargo[i] ~= 0 then return false end
  end
  return true
end

-- Emergency loan from Wu when completely broke. Modifies state in place.
-- BASIC lines 1330-1352:
--   BL% = BL% + 1
--   loan  = FN_R(1500) + 500       (range: 500..1999)
--   repay = FN_R(2000) * BL% + 1500
--   CA += loan, DW += repay
-- Returns loan, repay (both added to state).
function FinanceEngine.bankruptcyLoan(state)
  state.bankruptcyCount = state.bankruptcyCount + 1
  local loan  = fnR(1500) + 500
  local repay = fnR(2000) * state.bankruptcyCount + 1500
  state.cash = state.cash + loan
  state.debt = state.debt + repay
  return loan, repay
end

-- Wu warning check: returns braves count (50-149) if warning fires, nil otherwise.
-- Fires when: DW > 10000 AND wuWarningGiven=false AND destination ~= 0 (not game start)
-- Sets wuWarningGiven=true so it only fires once per game.
function FinanceEngine.wuWarningCheck(state)
  if state.debt > 10000 and not state.wuWarningGiven and state.destination ~= 0 then
    state.wuWarningGiven = true
    return math.random(50, 149)
  end
  return nil
end

-- Whether repayment prompt should appear: DW > 0 AND CA > 0 (BASIC line 1360)
function FinanceEngine.canRepay(state)
  return state.debt > 0 and state.cash > 0
end

-- Repay debt. amount must be > 0 and <= cash. Overpayment allowed: debt may go negative.
-- Returns true on success, false otherwise (state unchanged on failure).
function FinanceEngine.repay(state, amount)
  if amount <= 0 then return false end
  if amount > state.cash then return false end
  state.cash = state.cash - amount
  state.debt = state.debt - amount
  return true
end

-- Max borrowable from Wu: 2 * current cash (BASIC line 1410)
function FinanceEngine.maxBorrow(state)
  return 2 * state.cash
end

-- Borrow from Wu. amount must be > 0 and <= 2 * cash.
-- Returns true on success, false otherwise.
function FinanceEngine.borrow(state, amount)
  if amount <= 0 then return false end
  if amount > 2 * state.cash then return false end
  state.cash = state.cash + amount
  state.debt = state.debt + amount
  return true
end

-- Wu enforcers: called after player leaves Wu interaction.
-- BASIC line 1460: IF DW > 20000 AND NOT(FN_R(5)) THEN steal cash
-- 1-in-5 chance when debt > 20000. Sets cash=0.
-- Returns true if enforcers came.
function FinanceEngine.wuEnforcers(state)
  if state.debt > 20000 and math.random(0, 4) == 0 then
    state.cash = 0
    -- TODO Phase 5: kill 1-3 bodyguards
    return true
  end
  return false
end

-- Bank deposit: move amount from cash to bankBalance.
-- Returns true on success.
function FinanceEngine.bankDeposit(state, amount)
  if amount <= 0 then return false end
  if amount > state.cash then return false end
  state.cash        = state.cash - amount
  state.bankBalance = state.bankBalance + amount
  return true
end

-- Bank withdrawal: move amount from bankBalance to cash.
-- Returns true on success.
function FinanceEngine.bankWithdraw(state, amount)
  if amount <= 0 then return false end
  if amount > state.bankBalance then return false end
  state.bankBalance = state.bankBalance - amount
  state.cash        = state.cash + amount
  return true
end

-- Li Yuen protection cost. Called when arriving at HK with LI=0 and cash > 0.
-- BASIC lines 1050-1060:
--   if TI <= 12: cost = FN_R(CA / 1.8)
--   if TI > 12:  cost = FN_R(CA) + FN_R(1000*TI) + 1000*TI
function FinanceEngine.liYuenProtectionCost(state)
  if state.turnsElapsed <= 12 then
    return fnR(state.cash / 1.8)
  else
    return fnR(state.cash)
         + fnR(1000 * state.turnsElapsed)
         + 1000 * state.turnsElapsed
  end
end

-- Li Yuen protection lapse: 1-in-20 chance on every arrival.
-- BASIC: LI = LI AND FN_R(20)  (if LI=1, 1/20 chance becomes 0)
-- Returns true if protection lapsed (LI changed from 1 to 0).
function FinanceEngine.liYuenLapse(state)
  if state.liYuenProtection == 1 and math.random(0, 19) == 0 then
    state.liYuenProtection = 0
    return true
  end
  return false
end

-- Li Yuen warning: fires when arriving unprotected at a non-HK port.
-- 3-in-4 chance (FN_R(4) non-zero = 3 out of 4 values).
-- Returns true if warning should be shown. Does NOT modify state.
function FinanceEngine.liYuenWarningFires(state)
  return state.liYuenProtection == 0
    and state.currentPort ~= Constants.HONG_KONG
    and math.random(0, 3) ~= 0
end

-- Buy Li Yuen protection: deduct liYuenOfferCost from cash, set LI=1.
-- Returns true on success. liYuenOfferCost must be set and cash >= cost.
function FinanceEngine.buyLiYuenProtection(state)
  local cost = state.liYuenOfferCost
  if cost == nil then return false end
  if state.cash < cost then return false end
  state.cash = state.cash - cost
  state.liYuenProtection = 1
  state.liYuenOfferCost = nil
  return true
end

return FinanceEngine
