# Phase 4 Plan: Random Events + Storm

**Goal:** Every voyage carries risk.

**BASIC reference:** Sections 1900-2556 (events) and 3300-3350 (storm).

---

## State field names (from GameState.lua)
- `state.cash` = CA, `state.shipCapacity` = SC, `state.damage` = DM
- `state.holdSpace` = MW, `state.shipCargo[1-4]` = ST(2,J) (1=Opium,2=Silk,3=Arms,4=General)
- `state.warehouseCargo[1-4]` = ST(1,J), `state.warehouseUsed` = WS
- `state.currentPort` = LO, `state.destination` = D
- `state.liYuenProtection` = LI

## New state fields needed
- `state.gameOver = false` — set to true when ship sinks; panels check this

## FN_R helper
Same as FinanceEngine: `math.random(0, math.max(0, math.floor(x) - 1))`
If x <= 0, return 0.

---

## Task 1: EventEngine.lua + EventEngine.spec.lua

**New file:** `src/ReplicatedStorage/shared/EventEngine.lua`
**New file:** `tests/EventEngine.spec.lua`

### EventEngine.lua

Requires: `script.Parent.Constants` only.

```lua
-- EventEngine.lua
-- Pure logic module: random events and storm.
-- No Roblox service calls. All functions modify state in place or return values.

local Constants = require(script.Parent.Constants)
local EventEngine = {}

-- FN_R helper: INT(RND * x) = random integer 0..floor(x)-1
local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end

-- Opium Seizure (BASIC lines 1900-1910)
-- Triggers: non-HK port, ship has opium, 1-in-18 chance.
-- Confiscates all hold opium, restores holdSpace, deducts fine from cash.
-- Fine = FN_R(CA / 1.8) — can leave cash negative.
-- Returns fine amount if fired, nil otherwise.
function EventEngine.opiumSeizure(state)
  if state.currentPort == Constants.HONG_KONG then return nil end
  if state.shipCargo[1] == 0 then return nil end
  if math.random(0, 17) ~= 0 then return nil end  -- 1-in-18

  local fine = fnR(state.cash / 1.8)
  state.holdSpace          = state.holdSpace + state.shipCargo[1]
  state.shipCargo[1]       = 0
  state.cash               = state.cash - fine
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
    state.warehouseUsed        = state.warehouseUsed - old + new
    state.warehouseCargo[i]    = new
  end
  return true
end

-- Cash Robbery (BASIC lines 2501-2556)
-- Triggers: CA > 25000, 1-in-20 chance.
-- Stolen = FN_R(CA / 1.4).
-- Returns stolen amount if fired, nil otherwise.
function EventEngine.cashRobbery(state)
  if state.cash <= 25000 then return nil end
  if math.random(0, 19) ~= 0 then return nil end  -- 1-in-20

  local stolen = fnR(state.cash / 1.4)
  state.cash = state.cash - stolen
  return stolen
end

-- Storm: occurs? (BASIC line 3310: IF FN_R(10) THEN skip)
-- 1-in-10 chance.
function EventEngine.stormOccurs()
  return math.random(0, 9) == 0
end

-- Storm: severe? "going down" check (BASIC line 3312: IF NOT(FN_R(30)))
-- 1-in-30 chance. Only called if stormOccurs() was true.
function EventEngine.stormGoingDown()
  return math.random(0, 29) == 0
end

-- Storm: ship sinks? (BASIC: IF FN_R(DM/SC*3) THEN sink)
-- FN_R(x) truthy = non-zero. Returns true if sunk.
-- Only called if stormGoingDown() was true.
-- Sets state.gameOver = true and state.damage = state.shipCapacity on sink.
function EventEngine.stormSinks(state)
  local x = state.damage / state.shipCapacity * 3
  local n = math.floor(x)
  if n <= 0 then return false end        -- undamaged = never sinks in storm
  local roll = math.random(0, n - 1)
  if roll ~= 0 then
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
```

### EventEngine.spec.lua tests (~25 tests)

State helper `makeState(overrides)` with fields:
- cash=50000, damage=0, shipCapacity=60, holdSpace=60
- shipCargo={100,0,0,0} (opium in hold), warehouseCargo={0,0,0,0}
- warehouseUsed=0, currentPort=2 (non-HK), destination=3
- gameOver=false

Tests:

**opiumSeizure:**
1. Returns nil when at Hong Kong (currentPort=1)
2. Returns nil when no opium in hold (shipCargo[1]=0)
3. When fires: sets shipCargo[1]=0, holdSpace increases by old opium amount, cash decreases by fine
4. Fine is in range [0, floor(CA/1.8)) — run 200 times with forced fire (set random seed via repeated trials)
5. Cash can go negative (start with cash=1, force fire)
6. Returns nil most of the time (run 100 trials at 1/18, expect < 30 fires)

**cargoTheft:**
7. Returns false when all warehouse goods are 0
8. When fires: each warehouseCargo[i] <= original, warehouseUsed updated correctly
9. Returns false most of the time (run 100 trials at 1/50, expect < 10 fires)
10. When fires: new qty is in range [0, floor(old/1.8))

**cashRobbery:**
11. Returns nil when cash <= 25000
12. When fires: cash decreases by stolen amount, returns stolen amount
13. Stolen is in range [0, floor(CA/1.4))
14. Returns nil most of the time (run 100 trials at 1/20 with cash=50000, expect < 30 fires)

**stormOccurs:**
15. Returns false most of the time (run 100 trials, expect < 30 true)
16. Returns true at least once in 200 trials

**stormGoingDown:**
17. Returns false most of the time (run 100 trials, expect < 10 true)

**stormSinks:**
18. Returns false when damage = 0 (undamaged ship never sinks)
19. Returns false most of the time when damage = shipCapacity * 0.5 (x=1.5→n=1, returns 0 always since range is [0,0])
20. Returns true at least once in 100 trials when damage = shipCapacity (100% damaged, x=3→n=3, 2/3 sink chance)
21. Sets gameOver=true when sinks

**stormBlownOffCourse:**
22. Returns nil most of the time (run 100 trials, expect < 50 non-nil)
23. When returns non-nil: port is in 1..7
24. When returns non-nil: port != destination
25. Returns non-nil at least once in 100 trials

Write both files to disk. Do NOT inject to Studio.

---

## Task 2: GameState + GameService updates

**Modified:** `src/ReplicatedStorage/shared/GameState.lua`
**Modified:** `src/ServerScriptService/GameService.server.lua`

### GameState.lua: add gameOver

Add to state table after `bankruptcyCount`:
```lua
gameOver         = false,  -- true when ship sinks; client shows game over screen
```

### GameService.server.lua changes

**Add** `local EventEngine = require(ReplicatedStorage.shared.EventEngine)` to requires.

**Update TravelTo handler** — after the existing Phase 3 HK arrival block and BEFORE the final `pushState(player)`, add:

```lua
    -- Random events (Phase 4) — fire in BASIC order
    -- 1. Opium seizure (non-HK, ship has opium, 1-in-18)
    local fine = EventEngine.opiumSeizure(state)
    if fine ~= nil then
      Remotes.Notify:FireClient(player,
        string.format("Bad joss!! The authorities have confiscated your opium and fined you $%d!", fine))
    end

    -- 2. Cargo theft (warehouse has goods, 1-in-50)
    if EventEngine.cargoTheft(state) then
      Remotes.Notify:FireClient(player,
        "Bad joss!! Thieves have gotten into your warehouse!")
    end

    -- 3. Cash robbery (cash > 25000, 1-in-20)
    local stolen = EventEngine.cashRobbery(state)
    if stolen ~= nil then
      Remotes.Notify:FireClient(player,
        string.format("Bad joss!! You've been beaten up and robbed of $%d in cash!", stolen))
    end

    -- 4. Storm (1-in-10)
    if not state.gameOver and EventEngine.stormOccurs() then
      Remotes.Notify:FireClient(player, "Storm, Taipan!!")
      if EventEngine.stormGoingDown() then
        Remotes.Notify:FireClient(player, "I think we're going down!!")
        if EventEngine.stormSinks(state) then
          Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
          -- gameOver already set by stormSinks
        else
          Remotes.Notify:FireClient(player, "We made it!!")
          -- Blown off course?
          local newPort = EventEngine.stormBlownOffCourse(state, destination)
          if newPort ~= nil then
            state.currentPort   = newPort
            state.destination   = newPort
            state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
            Remotes.Notify:FireClient(player,
              string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
          end
        end
      else
        -- Non-severe storm — survived, check blown off course
        Remotes.Notify:FireClient(player, "We made it!!")
        local newPort = EventEngine.stormBlownOffCourse(state, destination)
        if newPort ~= nil then
          state.currentPort   = newPort
          state.destination   = newPort
          state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
          Remotes.Notify:FireClient(player,
            string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
        end
      end
    end
```

Guard the existing HK-arrival block (Phase 3) so it only fires if not gameOver, and also update pushState — if gameOver, we still push so client knows.

Write all files to disk. Do NOT inject to Studio.

---

## Task 3: GameOverPanel.lua + init.client.lua + Studio injection + tests

**New file:** `src/StarterGui/TaipanGui/Panels/GameOverPanel.lua`
**Modified:** `src/StarterGui/TaipanGui/init.client.lua`

### GameOverPanel.lua

Full-screen overlay shown when state.gameOver = true.

- Frame: full-width (480px), full-height (1, 0), position (0, 0, 0, 0)
- ZIndex: 20 (above everything)
- Dark red background (BackgroundColor3 = Color3.fromRGB(30, 5, 5), BackgroundTransparency = 0.1)
- Initially Visible = false

Contents:
1. Large "GAME OVER" title in red (TextSize=36)
2. "Your ship has sunk, Taipan!" message
3. "RESTART" button that fires Remotes.RestartGame (new remote)

Signature:
```lua
function GameOverPanel.new(parent)
  local panel = {}
  function panel.update(state)
    frame.Visible = (state.gameOver == true)
  end
  return panel
end
```

### New Remote: RestartGame

Add to `Remotes.lua`:
```lua
Remotes.RestartGame = getOrCreate("RemoteEvent", "RestartGame")  -- client→server: restart
```

### GameService handler for RestartGame

```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state then return end
  if not state.gameOver then return end  -- only allow restart when game is over
  -- Reset to fresh game (cash start default)
  local newState = GameState.newGame("cash")
  newState.currentPrices = PriceEngine.calculatePrices(newState.basePrices, newState.currentPort)
  newState.holdSpace = newState.shipCapacity
  playerStates[player] = newState
  pushState(player)
end)
```

### init.client.lua changes

Add:
```lua
local GameOverPanel = require(script.Panels.GameOverPanel)
```

Wire:
```lua
local gameOverPanel = GameOverPanel.new(root)
```

Add to StateUpdate handler:
```lua
gameOverPanel.update(state)
```

Wire RESTART button via callback in GameOverPanel.new — pass `function() Remotes.RestartGame:FireServer() end` as callback.

Updated signature:
```lua
function GameOverPanel.new(parent, onRestart)
```

### Studio injection order:
1. Stop play
2. Inject EventEngine.lua → ReplicatedStorage.shared
3. Update GameState.lua (add gameOver field)
4. Update Remotes.lua (add RestartGame)
5. Update GameService.server.lua (EventEngine require + event calls + RestartGame handler)
6. Inject GameOverPanel.lua → GameController.Panels
7. Update GameController (init.client.lua)
8. Inject EventEngine.spec → Tests folder
9. Start play → run tests
10. Verify: 91 existing + new EventEngine tests all pass

### Acceptance criteria:
- All tests pass (91 existing + EventEngine tests)
- Sail to non-HK port with opium: seizure can occur with notification
- Fill warehouse then sail: theft can occur
- Accumulate 25k+ cash: robbery can occur
- Storm notification appears on voyages
- Ship sinking shows game over panel
- RESTART button resets the game correctly
