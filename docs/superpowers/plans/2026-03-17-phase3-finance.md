# Phase 3 Plan: Financial System (Wu + Bank + Li Yuen)

**Goal:** Elder Brother Wu is breathing down your neck. The bank pays interest.

**BASIC key finding:** Wu visit (repay/borrow/bankruptcy) fires AUTOMATICALLY on HK arrival
(lines 1310-1450). The "Visit Wu" menu option opens the BANK (deposit/withdraw).
In Roblox: Wu panel fires on HK arrival; bank access is a separate HK-only panel.

**Reference:** `DESIGN_DOCUMENT.md`, `BASIC_ANNOTATED.md` (section 10)

---

## State field names (from GameState.lua)
- `state.cash` = CA, `state.bankBalance` = BA, `state.debt` = DW
- `state.guns` = GN, `state.shipCargo[1-4]`, `state.warehouseCargo[1-4]`
- `state.turnsElapsed` = TI, `state.currentPort` = LO
- `state.wuWarningGiven` = WN (bool), `state.liYuenProtection` = LI (0=unprotected)
- `state.bankruptcyCount` = BL% (int, starts 0)
- `state.destination` = D (0 on game start)

## New state field needed
- `state.liYuenOfferCost` — nil or number; set when arriving at HK with LI=0 and cash>0

## FN_R helper (for all random formulas)
`FN_R(x) = INT(RND(1) * x)` = random integer 0 to floor(x)-1.
In Lua: `math.random(0, math.max(0, math.floor(x) - 1))`
If x <= 0, return 0.

---

## Task 1: FinanceEngine.lua + FinanceEngine.spec.lua

**New file:** `src/ReplicatedStorage/shared/FinanceEngine.lua`
**New file:** `tests/FinanceEngine.spec.lua`

### FinanceEngine.lua

Requires: `script.Parent.Constants` only.

```lua
local Constants = require(script.Parent.Constants)
local FinanceEngine = {}

-- FN_R helper: INT(RND * x) = random 0..floor(x)-1
local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end

-- Bankruptcy: true if CA=0 AND BA=0 AND all cargo=0 AND guns=0
function FinanceEngine.isBankrupt(state)
  if state.cash ~= 0 or state.bankBalance ~= 0 or state.guns ~= 0 then return false end
  for i = 1, 4 do
    if state.shipCargo[i] ~= 0 or state.warehouseCargo[i] ~= 0 then return false end
  end
  return true
end

-- Emergency loan (called when isBankrupt). Modifies state in place.
-- BASIC line 1330-1352:
--   BL% = BL% + 1
--   loan = FN_R(1500) + 500       (500..1999)
--   repay = FN_R(2000) * BL% + 1500
--   CA += loan, DW += repay
function FinanceEngine.bankruptcyLoan(state)
  state.bankruptcyCount = state.bankruptcyCount + 1
  local loan  = fnR(1500) + 500
  local repay = fnR(2000) * state.bankruptcyCount + 1500
  state.cash = state.cash + loan
  state.debt = state.debt + repay
  return loan, repay
end

-- Wu warning check. Returns braves count (50-149) if warning fires, nil otherwise.
-- Fires when: DW > 10000 AND !wuWarningGiven AND destination != 0 (not game start)
-- Sets wuWarningGiven = true so it only fires once.
function FinanceEngine.wuWarningCheck(state)
  if state.debt > 10000 and not state.wuWarningGiven and state.destination ~= 0 then
    state.wuWarningGiven = true
    return math.random(50, 149)  -- braves count
  end
  return nil
end

-- Whether repayment prompt should appear: DW > 0 AND CA > 0  (BASIC line 1360)
function FinanceEngine.canRepay(state)
  return state.debt > 0 and state.cash > 0
end

-- Repay debt. Returns true on success.
-- amount must be <= CA and <= DW.
-- "A" (all): caller passes min(DW, CA).
function FinanceEngine.repay(state, amount)
  if amount <= 0 then return false end
  if amount > state.cash then return false end
  if amount > state.debt then return false end
  state.cash = state.cash - amount
  state.debt = state.debt - amount
  return true
end

-- Max borrowable: 2 * current CA  (BASIC line 1410)
function FinanceEngine.maxBorrow(state)
  return 2 * state.cash
end

-- Borrow from Wu. Returns true on success.
-- amount must be <= 2 * CA.
function FinanceEngine.borrow(state, amount)
  if amount <= 0 then return false end
  if amount > 2 * state.cash then return false end
  state.cash = state.cash + amount
  state.debt = state.debt + amount
  return true
end

-- Wu enforcers (called after Wu visit is complete via LeaveWu).
-- BASIC line 1460: IF DW > 20000 AND NOT(FN_R(5)) THEN steal cash + kill bodyguards
-- Returns true if enforcers came.
function FinanceEngine.wuEnforcers(state)
  if state.debt > 20000 and math.random(0, 4) == 0 then
    state.cash = 0
    -- TODO Phase 5: kill 1-3 bodyguards
    return true
  end
  return false
end

-- Bank deposit. Returns true on success.
function FinanceEngine.bankDeposit(state, amount)
  if amount <= 0 then return false end
  if amount > state.cash then return false end
  state.cash        = state.cash - amount
  state.bankBalance = state.bankBalance + amount
  return true
end

-- Bank withdrawal. Returns true on success.
function FinanceEngine.bankWithdraw(state, amount)
  if amount <= 0 then return false end
  if amount > state.bankBalance then return false end
  state.bankBalance = state.bankBalance - amount
  state.cash        = state.cash + amount
  return true
end

-- Li Yuen protection cost. Call when arriving at HK with LI=0 and CA>0.
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

-- Li Yuen protection lapse: fires at every arrival.
-- BASIC: LI = LI AND FN_R(20) → 1-in-20 chance LI becomes 0 (lose protection)
-- Returns true if protection lapsed.
function FinanceEngine.liYuenLapse(state)
  if state.liYuenProtection ~= 0 and math.random(0, 19) == 0 then
    state.liYuenProtection = 0
    return true
  end
  return false
end

-- Li Yuen warning: fires when unprotected AND not in HK.
-- 3-in-4 chance: FN_R(4) truthy (non-zero) = 3/4 of the time.
-- Returns true if warning should be shown. Does NOT modify state.
function FinanceEngine.liYuenWarningFires(state)
  return state.liYuenProtection == 0
    and state.currentPort ~= Constants.HONG_KONG
    and math.random(0, 3) ~= 0
end

-- Buy Li Yuen protection: pay liYuenOfferCost from cash, set LI=1.
-- Returns true on success.
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
```

### FinanceEngine.spec.lua tests (18+ tests)

State helper `makeState(overrides)` with fields:
- cash=400, bankBalance=0, debt=5000, guns=0
- shipCargo={0,0,0,0}, warehouseCargo={0,0,0,0}
- turnsElapsed=1, currentPort=1, destination=1 (non-zero = traveled)
- wuWarningGiven=false, liYuenProtection=0, bankruptcyCount=0
- liYuenOfferCost=nil

Tests:

**isBankrupt:**
1. false when cash > 0
2. false when bankBalance > 0
3. false when guns > 0
4. false when shipCargo has goods
5. true when all zero

**bankruptcyLoan:**
6. increments bankruptcyCount (0 → 1)
7. adds 500-1999 to cash (run 200 times, verify range)
8. adds debt >= 1500 (first bankruptcy: repay = 0*1 + 1500 = 1500 minimum with BL%=1)

**wuWarningCheck:**
9. returns nil when debt <= 10000
10. returns nil when wuWarningGiven=true
11. returns nil when destination=0 (game start)
12. returns number 50-149 when fires (debt=10001, !WN, dest≠0)
13. sets wuWarningGiven=true when fires

**canRepay:**
14. true when debt > 0 AND cash > 0
15. false when debt = 0
16. false when cash = 0

**repay:**
17. reduces cash and debt by amount
18. returns false when amount > cash
19. returns false when amount > debt

**maxBorrow:**
20. returns 2 * cash

**borrow:**
21. increases cash and debt by amount
22. returns false when amount > 2 * cash

**wuEnforcers:**
23. sets cash=0 when fires (mock: run 1000 times with DW=20001, verify at least one fires)
24. returns false when debt <= 20000

**bankDeposit:**
25. moves amount from cash to bankBalance
26. returns false when amount > cash

**bankWithdraw:**
27. moves amount from bankBalance to cash
28. returns false when amount > bankBalance

**liYuenProtectionCost:**
29. TI<=12: returns value in range [0, floor(CA/1.8))
30. TI>12: returns value >= 1000*TI (minimum is the deterministic TI component)

**liYuenLapse:**
31. returns false when already unprotected (LI=0)
32. returns false most of the time when protected (run 200 times, at least 170 false)

**buyLiYuenProtection:**
33. deducts cost from cash, sets liYuenProtection=1, clears liYuenOfferCost
34. returns false when liYuenOfferCost=nil
35. returns false when cash < cost

Write both files to disk. Do NOT inject to Studio.

---

## Task 2: GameState + Remotes + GameService updates

**Modified:** `src/ReplicatedStorage/shared/GameState.lua`
**Modified:** `src/ReplicatedStorage/Remotes.lua`
**Modified:** `src/ServerScriptService/GameService.server.lua`

### GameState.lua: add liYuenOfferCost

Add to state table after `liYuenProtection`:
```lua
liYuenOfferCost  = nil,  -- set on HK arrival when LI=0 and CA>0; cost to buy Li Yuen protection
```

### Remotes.lua: add new events

Client → Server:
```lua
Remotes.WuRepay             = getOrCreate("RemoteEvent", "WuRepay")             -- amount
Remotes.WuBorrow            = getOrCreate("RemoteEvent", "WuBorrow")            -- amount
Remotes.LeaveWu             = getOrCreate("RemoteEvent", "LeaveWu")             -- triggers enforcer check
Remotes.BankDeposit         = getOrCreate("RemoteEvent", "BankDeposit")         -- amount
Remotes.BankWithdraw        = getOrCreate("RemoteEvent", "BankWithdraw")        -- amount
Remotes.BuyLiYuenProtection = getOrCreate("RemoteEvent", "BuyLiYuenProtection") -- no args
```
Server → Client:
```lua
Remotes.Notify = getOrCreate("RemoteEvent", "Notify")  -- message string
```

### GameService.server.lua: update TravelTo + add handlers

**Add** `local FinanceEngine = require(ReplicatedStorage.shared.FinanceEngine)` to requires.

**Update TravelTo handler** — after the existing time advance + price recalc, add HK arrival logic:

```lua
-- Li Yuen protection lapse at every arrival
if FinanceEngine.liYuenLapse(state) then
  Remotes.Notify:FireClient(player, "Li Yuen no longer protects you!")
end

-- Li Yuen warning when arriving at non-HK unprotected (3-in-4 chance)
if destination ~= Constants.HONG_KONG and FinanceEngine.liYuenWarningFires(state) then
  Remotes.Notify:FireClient(player,
    "Li Yuen wishes you to reconsider! He could protect you for a fee...")
end

if destination == Constants.HONG_KONG then
  -- Wu warning (fires once when DW > 10000)
  local braves = FinanceEngine.wuWarningCheck(state)
  if braves then
    Remotes.Notify:FireClient(player,
      string.format("ELDER BROTHER WU has heard of your debt! He is sending %d braves to collect!", braves))
  end
  -- Bankruptcy: auto emergency loan if broke
  if FinanceEngine.isBankrupt(state) then
    local loan, repay = FinanceEngine.bankruptcyLoan(state)
    Remotes.Notify:FireClient(player,
      string.format("WU: You have nothing! I will give you $%d... but you owe me $%d!", loan, repay))
  end
  -- Li Yuen protection offer
  if state.liYuenProtection == 0 and state.cash > 0 then
    state.liYuenOfferCost = FinanceEngine.liYuenProtectionCost(state)
  else
    state.liYuenOfferCost = nil
  end
else
  state.liYuenOfferCost = nil
end
```

**Add handlers:**

```lua
-- Wu: repay debt
Remotes.WuRepay.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.repay(state, amount) then pushState(player) return end
  pushState(player)
end)

-- Wu: borrow
Remotes.WuBorrow.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.borrow(state, amount) then pushState(player) return end
  pushState(player)
end)

-- Wu: leave (triggers enforcer check)
Remotes.LeaveWu.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if FinanceEngine.wuEnforcers(state) then
    Remotes.Notify:FireClient(player,
      "WU'S MEN beat you and take all your cash!")
  end
  pushState(player)
end)

-- Bank: deposit
Remotes.BankDeposit.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.bankDeposit(state, amount) then pushState(player) return end
  pushState(player)
end)

-- Bank: withdraw
Remotes.BankWithdraw.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.bankWithdraw(state, amount) then pushState(player) return end
  pushState(player)
end)

-- Li Yuen: buy protection
Remotes.BuyLiYuenProtection.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not FinanceEngine.buyLiYuenProtection(state) then pushState(player) return end
  Remotes.Notify:FireClient(player, "Li Yuen smiles. You are under his protection.")
  pushState(player)
end)
```

Write all files to disk. Do NOT inject to Studio.

---

## Task 3: WuPanel.lua + BankPanel.lua

**New file:** `src/StarterGui/TaipanGui/Panels/WuPanel.lua`
**New file:** `src/StarterGui/TaipanGui/Panels/BankPanel.lua`

### WuPanel.lua

HK-only panel for Wu interactions: repay debt, borrow, Li Yuen protection offer, Leave Wu.

Position: `y=750, h=225`
Visible: only when `state.currentPort == Constants.HONG_KONG`

Sections:
1. Title: "ELDER BROTHER WU" (blue-purple text)
2. Debt line: "Debt: $5000 | Max Repay: $400" (updates dynamically)
3. Repay row: amount box + REPAY button (disabled when !canRepay)
4. Borrow row: "Max borrow: $800" label + amount box + BORROW button
5. Li Yuen row: "Li Yuen asks $X for protection" + BUY button (hidden when liYuenOfferCost=nil)
6. LEAVE WU button (fires LeaveWu)

"A" shortcut: Repay amount box A → min(debt, cash). Borrow amount box A → max borrow.
Use `latestState` reference (same pattern as BuySellPanel).

Signature:
```lua
function WuPanel.new(parent, onRepay, onBorrow, onLeaveWu, onBuyLiYuen)
  local panel = {}
  function panel.update(state)
    frame.Visible = (state.currentPort == Constants.HONG_KONG)
    -- update labels, enable/disable buttons, show/hide Li Yuen row
    latestState = state
  end
  return panel
end
```

### BankPanel.lua

HK-only panel for bank deposit/withdraw.

Position: `y=980, h=110`
Visible: only when `state.currentPort == Constants.HONG_KONG`

Sections:
1. Title: "COMPRADOR'S HOUSE" + balance label: "Balance: $0"
2. Amount box (shared for deposit and withdraw, "A"=All)
3. DEPOSIT button + WITHDRAW button
4. "A" for deposit = all cash; "A" for withdraw = all bank balance

Signature:
```lua
function BankPanel.new(parent, onDeposit, onWithdraw)
  local panel = {}
  function panel.update(state) ... end
  return panel
end
```

Colors: light blue/teal theme to distinguish from Wu (dark purple) and warehouse (dark blue).

Write both files to disk. Do NOT inject to Studio.

---

## Task 4: MessagePanel.lua + init.client.lua + Studio injection + tests

**New file:** `src/StarterGui/TaipanGui/Panels/MessagePanel.lua`
**Modified:** `src/StarterGui/TaipanGui/init.client.lua`

### MessagePanel.lua

Floating notification bar. Shows a message for 5 seconds then hides.

- Frame: full-width (480px), h=36, y=0
- Semi-transparent dark background (BackgroundTransparency=0.3)
- Text: amber/white, centered
- ZIndex: 10 (on top of everything)
- Initially Visible=false

Signature:
```lua
function MessagePanel.new(parent)
  local panel = {}
  function panel.show(message)
    -- Show frame, set text, auto-hide after 5 seconds via task.delay
  end
  return panel
end
```

### init.client.lua changes

Add:
1. `local WuPanel = require(script.Panels.WuPanel)`
2. `local BankPanel = require(script.Panels.BankPanel)`
3. `local MessagePanel = require(script.Panels.MessagePanel)`

Wire:
```lua
local messagePanel = MessagePanel.new(root)
local wuPanel = WuPanel.new(root,
  function(amount) Remotes.WuRepay:FireServer(amount) end,
  function(amount) Remotes.WuBorrow:FireServer(amount) end,
  function() Remotes.LeaveWu:FireServer() end,
  function() Remotes.BuyLiYuenProtection:FireServer() end
)
local bankPanel = BankPanel.new(root,
  function(amount) Remotes.BankDeposit:FireServer(amount) end,
  function(amount) Remotes.BankWithdraw:FireServer(amount) end
)
```

Add to StateUpdate handler:
```lua
wuPanel.update(state)
bankPanel.update(state)
```

Add Notify listener:
```lua
Remotes.Notify.OnClientEvent:Connect(function(message)
  messagePanel.show(message)
end)
```

### Studio injection order:
1. Stop play if running
2. Inject FinanceEngine.lua → ReplicatedStorage.shared
3. Update GameState.lua (add liYuenOfferCost field)
4. Update Constants.lua in Studio (if any changes — none needed for Phase 3)
5. Update Remotes.lua in Studio
6. Update GameService.server.lua in Studio
7. Inject WuPanel.lua → GameController.Panels
8. Inject BankPanel.lua → GameController.Panels
9. Inject MessagePanel.lua → GameController.Panels
10. Update GameController (init.client.lua) in Studio
11. Inject FinanceEngine.spec → Tests folder in Studio
12. Run tests — verify 53 + new = passing

### Acceptance criteria:
- All tests pass (53 existing + FinanceEngine tests)
- Travel to HK with debt > 10000 triggers Wu warning notification
- Repay debt at Wu panel reduces cash and debt
- Borrow from Wu increases both
- Bankruptcy loan fires when completely broke
- Bank deposit/withdraw works
- Li Yuen offer appears when arriving at HK with LI=0 and cash > 0
- Notifications appear as floating message
