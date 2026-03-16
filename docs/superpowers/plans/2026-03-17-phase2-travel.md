# Phase 2 Plan: Travel + All Ports + Time

**Goal:** Sail between all 7 ports. Debt starts hurting.

**Reference:** `DESIGN_DOCUMENT.md`, `BASIC_ANNOTATED.md`

**State field names** (from `GameState.lua`):
- `turnsElapsed` = TI, `month` = MO, `year` = YE, `destination` = D
- `bankBalance` = BA, `debt` = DW, `currentPort` = LO
- `enemyBaseHP` = EC, `enemyBaseDamage` = ED
- `warehouseCargo[1-4]`, `warehouseUsed` = WS
- `holdSpace` = MW, `shipCargo[1-4]`, `basePrices[port][good]`

**D=0 guard:** `state.destination` starts at 0. TravelTo always advances time (on first voyage D was 0 but we set it to destination before advancing — matches BASIC where D is set non-zero before looping to arrival processing). The guard at game start is implicit: we never call timeAdvance at startup.

---

## Task 1: TravelEngine.lua + TravelEngine.spec.lua

**New file:** `src/ReplicatedStorage/shared/TravelEngine.lua`
**New file:** `tests/TravelEngine.spec.lua`

### TravelEngine.lua

```lua
local Constants   = require(script.Parent.Constants)
local PriceEngine = require(script.Parent.PriceEngine)

local TravelEngine = {}

-- Advance time by one month (call on every TravelTo).
-- Modifies state in place.
function TravelEngine.timeAdvance(state)
  state.turnsElapsed = state.turnsElapsed + 1
  state.month        = state.month + 1

  -- Bank interest: BA = floor(BA + BA * 0.005)  [BASIC line ~1020]
  if state.bankBalance > 0 then
    state.bankBalance = math.floor(state.bankBalance + state.bankBalance * Constants.BANK_INTEREST_RATE)
  end

  -- Debt compound: DW = floor(DW + DW * 0.1)  [BASIC line ~1020]
  if state.debt > 0 then
    state.debt = math.floor(state.debt + state.debt * Constants.DEBT_INTEREST_RATE)
  end

  -- Year rollover: January annual event
  if state.month > 12 then
    state.month = 1
    state.year  = state.year + 1
    -- EC += 10, ED += 0.5  [BASIC line ~1030]
    state.enemyBaseHP     = state.enemyBaseHP     + 10
    state.enemyBaseDamage = state.enemyBaseDamage + 0.5
    -- Base price drift: each cell increments by 0 or 1  [BASIC line ~1030]
    PriceEngine.applyAnnualDrift(state.basePrices)
  end
end

-- Returns nil if departure is valid, or an error string if not.
-- destination: 1-7
function TravelEngine.canDepart(state, destination)
  if type(destination) ~= "number"
      or destination < 1 or destination > 7
      or math.floor(destination) ~= destination then
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
```

### TravelEngine.spec.lua (using TestEZ)

Tests to write:
1. `timeAdvance` increments `turnsElapsed` by 1
2. `timeAdvance` increments `month` by 1
3. `timeAdvance` applies 0.5% bank interest (floor)
4. `timeAdvance` applies 10% debt compound (floor)
5. `timeAdvance` does NOT apply interest when bankBalance = 0
6. `timeAdvance` does NOT apply debt compound when debt = 0
7. `timeAdvance` at month=12: month becomes 1 (year rollover)
8. `timeAdvance` at month=12: year increments
9. `timeAdvance` January event: EC increases by 10, ED increases by 0.5
10. `timeAdvance` January event: base prices drift (each cell same or +1)
11. `canDepart` returns nil for valid departure (different port, holdSpace ≥ 0)
12. `canDepart` returns error when destination == currentPort
13. `canDepart` returns error when holdSpace < 0
14. `canDepart` returns error for out-of-range destination (0, 8, non-integer)

Write the file to disk. Do NOT inject to Studio yet.

---

## Task 2: Constants + Remotes + GameService updates

**Modified:** `src/ReplicatedStorage/shared/Constants.lua`
**Modified:** `src/ReplicatedStorage/Remotes.lua`
**Modified:** `src/ServerScriptService/GameService.server.lua`

### Constants.lua: add MONTH_NAMES

Add after `Constants.HONG_KONG`:
```lua
Constants.MONTH_NAMES = {
  "Jan","Feb","Mar","Apr","May","Jun",
  "Jul","Aug","Sep","Oct","Nov","Dec"
}
```

### Remotes.lua: add TravelTo, TransferToWarehouse, TransferFromWarehouse

Add to "Client → Server actions" section:
```lua
Remotes.TravelTo             = getOrCreate("RemoteEvent", "TravelTo")             -- destination (1-7)
Remotes.TransferToWarehouse   = getOrCreate("RemoteEvent", "TransferToWarehouse")   -- goodIndex, quantity
Remotes.TransferFromWarehouse = getOrCreate("RemoteEvent", "TransferFromWarehouse") -- goodIndex, quantity
```

### GameService.server.lua: add handlers

Add `require(ReplicatedStorage.shared.TravelEngine)` at top.

**TravelTo handler:**
```lua
Remotes.TravelTo.OnServerEvent:Connect(function(player, destination)
  local state = playerStates[player]
  if not state then return end
  if type(destination) ~= "number" or destination < 1 or destination > 7
      or math.floor(destination) ~= destination then return end

  local err = TravelEngine.canDepart(state, destination)
  if err then
    pushState(player)  -- push back correct state (shows overload etc.)
    return
  end

  -- Advance time (always: matches BASIC where D is set non-zero before arrival processing)
  TravelEngine.timeAdvance(state)

  state.destination = destination
  state.currentPort = destination
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, destination)
  -- Recalculate holdSpace after port change (cargo unchanged, but be explicit)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2] - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  pushState(player)
end)
```

**TransferToWarehouse handler** (HK only — move hold → warehouse):
```lua
Remotes.TransferToWarehouse.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end
  if state.shipCargo[goodIndex] < quantity then pushState(player) return end
  if state.warehouseUsed + quantity > Constants.WAREHOUSE_CAPACITY then pushState(player) return end

  state.shipCargo[goodIndex]      = state.shipCargo[goodIndex]      - quantity
  state.warehouseCargo[goodIndex] = state.warehouseCargo[goodIndex] + quantity
  state.warehouseUsed             = state.warehouseUsed + quantity
  state.holdSpace                 = state.holdSpace + quantity
  pushState(player)
end)
```

**TransferFromWarehouse handler** (HK only — move warehouse → hold):
```lua
Remotes.TransferFromWarehouse.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if not state then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end
  if state.warehouseCargo[goodIndex] < quantity then pushState(player) return end
  if state.holdSpace < quantity then pushState(player) return end

  state.warehouseCargo[goodIndex] = state.warehouseCargo[goodIndex] - quantity
  state.shipCargo[goodIndex]      = state.shipCargo[goodIndex]      + quantity
  state.warehouseUsed             = state.warehouseUsed - quantity
  state.holdSpace                 = state.holdSpace - quantity
  pushState(player)
end)
```

Write all files to disk. Do NOT inject to Studio yet.

---

## Task 3: PortPanel.lua

**New file:** `src/StarterGui/TaipanGui/Panels/PortPanel.lua`

Panel shows:
- Current port name (left) and date "Jan 1860" (right) on top row
- 7 port buttons; current port dimmed/disabled; clicking valid port fires `onTravel(portIndex)`

Layout: frame at y=0, height=90 inside root (480px wide)
- Top row (h=28): port name label left, date label right
- Bottom row (h=54): 7 buttons across (each ~68px wide), current port grey/disabled

Colors: terminal amber theme — dark bg, amber text. Current port: dimmed bg. Hoverable ports: slightly lighter bg.

Signature:
```lua
function PortPanel.new(parent, onTravel)
  -- onTravel(destinationIndex: number)
  ...
  local panel = {}
  function panel.update(state)
    -- update port name, date, highlight current port button
  end
  return panel
end
```

Write file to disk. Do NOT inject to Studio yet.

---

## Task 4: WarehousePanel.lua

**New file:** `src/StarterGui/TaipanGui/Panels/WarehousePanel.lua`

HK-only panel. Shows:
- Title "GODOWN" + warehouse used/capacity (e.g. "Used: 0 / 10000")
- Per-good row: good name, hold qty, warehouse qty
- Shared amount TextBox at bottom ("Amount (A=All)")
- Good selector (4 buttons like BuySellPanel)
- [PUT] button: transfers selected good from hold → warehouse
- [TAKE] button: transfers selected good from warehouse → hold
- "A" shortcut: PUT → puts all of that good from hold; TAKE → takes all of that good from warehouse
- Visible only when at Hong Kong (caller sets Visible based on state.currentPort)

Signature:
```lua
function WarehousePanel.new(parent, onPut, onTake)
  -- onPut(goodIndex, quantity): transfer hold→warehouse
  -- onTake(goodIndex, quantity): transfer warehouse→hold
  ...
  local panel = {}
  function panel.update(state)
    -- update all labels; set Visible based on state.currentPort == 1
  end
  return panel
end
```

Layout: frame at y=490 (below BuySellPanel which ends at 285+200=485), height=160.

Write file to disk. Do NOT inject to Studio yet.

---

## Task 5: init.client.lua + Studio injection + tests

**Modified:** `src/StarterGui/TaipanGui/init.client.lua`

Changes:
1. Require PortPanel and WarehousePanel
2. Instantiate both panels
3. Wire TravelTo remote: `onTravel(dest) -> Remotes.TravelTo:FireServer(dest)`
4. Wire TransferToWarehouse: `onPut(good, qty) -> Remotes.TransferToWarehouse:FireServer(good, qty)`
5. Wire TransferFromWarehouse: `onTake(good, qty) -> Remotes.TransferFromWarehouse:FireServer(good, qty)`
6. In `StateUpdate` handler: call `portPanel.update(state)` and `warehousePanel.update(state)`

**Studio injection (via MCP run_code):**
1. Stop play mode if running
2. Inject TravelEngine.lua into ReplicatedStorage.shared
3. Update Constants.lua in Studio (add MONTH_NAMES)
4. Update Remotes.lua in Studio
5. Update GameService.server.lua in Studio
6. Inject PortPanel.lua into GameController.Panels
7. Inject WarehousePanel.lua into GameController.Panels
8. Update GameController (init.client.lua) in Studio
9. Inject TravelEngine.spec.lua into tests folder
10. Start play mode and run tests — verify all pass (expect 36 + 14 new = 50 tests)
11. Start play mode for gameplay test

**Acceptance criteria:**
- All tests pass (36 existing + new TravelEngine tests)
- Can travel between ports (port changes, date advances)
- Debt compounds on each voyage
- January triggers EC/ED increase and price drift
- Warehouse PUT/TAKE works at HK, hidden at other ports
- Cannot depart when overloaded
