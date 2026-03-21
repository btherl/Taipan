# Phase 5 Plan: Combat

**Goal:** Fight pirates, run, or throw cargo.

**Architecture note:** Roblox can't block on the server. Combat is event-driven:
- TravelTo initialises `state.combat`, pushes state → client shows CombatPanel
- CombatFight / CombatRun / CombatThrow remotes process one action each
- Server pushes updated state after each action
- When combat ends, server applies post-combat (booty → storm) and clears `state.combat`

---

## State additions

### `state.combat` sub-table (nil when not in combat)

```lua
state.combat = {
  active        = true,
  encounterType = 1,        -- F1: 1=generic pirates, 2=Li Yuen's fleet
  enemyTotal    = 0,        -- SN: remaining enemy ships (waiting + on screen)
  enemyOnScreen = 0,        -- SS: ships currently visible on grid
  enemyWaiting  = 0,        -- SA: ships waiting to spawn
  originalCount = 0,        -- S0: snapshot at combat start (for flee check)
  grid          = {},       -- [1..10]: nil=empty, {maxHP=N, damage=N}=occupied
  runMomentum   = 3,        -- OK: starts at 3 on first run attempt
  runAccel      = 1,        -- IK: acceleration increment
  lastCommand   = 0,        -- LC: 0=none, 1=run, 2=fight, 3=throw
  booty         = 0,        -- BT: pre-calculated loot value
  outcome       = nil,      -- "victory"|"fled"|"sunk"|"liYuen"|nil
}
```

### `state.gameOver` already exists. No other GameState changes needed.

---

## FN_R helper (same as FinanceEngine / EventEngine)
`math.random(0, math.max(0, math.floor(x) - 1))` — returns 0 if x <= 0.

---

## Task 1: CombatEngine.lua + CombatEngine.spec.lua

**New file:** `src/ReplicatedStorage/shared/CombatEngine.lua`
**New file:** `tests/CombatEngine.spec.lua`

### CombatEngine.lua

```lua
-- CombatEngine.lua
-- Pure logic module: pirate encounters, combat grid, fight/run/throw, enemy fire.
-- No Roblox service calls.

local CombatEngine = {}

local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end

-- ── Encounter checks ──────────────────────────────────────────────────────────

-- Generic pirates trigger: 1/BP chance. Returns true if encounter.
function CombatEngine.genericEncounterCheck(state)
  return math.random(0, math.floor(state.pirateBase) - 1) == 0
end

-- Li Yuen trigger: FN_R(4 + 8*LI) = 0
-- Unprotected (LI=0): 1-in-4; Protected (LI=1): 1-in-12.
function CombatEngine.liYuenEncounterCheck(state)
  return math.random(0, 3 + 8 * state.liYuenProtection) == 0
end

-- Generic fleet size: FN_R(SC/10 + GN) + 1
function CombatEngine.genericFleetSize(state)
  return fnR(state.shipCapacity / 10 + state.guns) + 1
end

-- Li Yuen fleet size: FN_R(SC/5 + GN) + 5
function CombatEngine.liYuenFleetSize(state)
  return fnR(state.shipCapacity / 5 + state.guns) + 5
end

-- ── Combat initialisation ─────────────────────────────────────────────────────

-- Build a fresh combat sub-table.
-- encounterType: 1=generic, 2=Li Yuen
function CombatEngine.initCombat(state, shipCount, encounterType)
  local booty = fnR(state.turnsElapsed / 4 * 1000 * shipCount ^ 1.05)
              + fnR(1000) + 250
  local combat = {
    active        = true,
    encounterType = encounterType,
    enemyTotal    = shipCount,
    enemyOnScreen = 0,
    enemyWaiting  = shipCount,
    originalCount = shipCount,
    grid          = {},
    runMomentum   = 3,
    runAccel      = 1,
    lastCommand   = 0,
    booty         = booty,
    outcome       = nil,
  }
  for i = 1, 10 do combat.grid[i] = nil end
  return combat
end

-- ── Ship grid ─────────────────────────────────────────────────────────────────

-- Spawn ships into empty grid slots until no waiting ships remain.
-- enemyBaseHP = state.enemyBaseHP (EC). New ship HP = FN_R(EC) + 20.
function CombatEngine.spawnShips(combat, enemyBaseHP)
  for i = 1, 10 do
    if combat.enemyWaiting <= 0 then break end
    if combat.grid[i] == nil then
      combat.grid[i] = { maxHP = fnR(enemyBaseHP) + 20, damage = 0 }
      combat.enemyOnScreen = combat.enemyOnScreen + 1
      combat.enemyWaiting  = combat.enemyWaiting  - 1
    end
  end
end

-- Count occupied grid slots.
function CombatEngine.onScreenCount(combat)
  local n = 0
  for i = 1, 10 do
    if combat.grid[i] ~= nil then n = n + 1 end
  end
  return n
end

-- ── Fight action ──────────────────────────────────────────────────────────────

-- Fire all guns. Returns { sunk=N, fleeCount=N, messages={} }.
-- Mutates combat grid, enemyTotal, enemyOnScreen, enemyWaiting.
-- If all enemies destroyed, sets combat.outcome = "victory".
function CombatEngine.fight(state, combat)
  if state.guns == 0 then
    return { sunk = 0, fleeCount = 0, noGuns = true }
  end

  local sunk = 0
  -- Fire each gun
  for _ = 1, state.guns do
    if combat.enemyTotal == 0 then break end
    -- Pick a random occupied slot (retry if empty)
    local attempts = 0
    local slot = nil
    repeat
      slot = math.random(1, 10)
      attempts = attempts + 1
    until combat.grid[slot] ~= nil or attempts > 50

    if combat.grid[slot] ~= nil then
      local dmg = fnR(30) + 10  -- 10-39
      combat.grid[slot].damage = combat.grid[slot].damage + dmg
      if combat.grid[slot].damage > combat.grid[slot].maxHP then
        -- Ship sunk
        combat.grid[slot] = nil
        combat.enemyTotal    = combat.enemyTotal    - 1
        combat.enemyOnScreen = combat.enemyOnScreen - 1
        sunk = sunk + 1
        -- Spawn replacement if waiting
        if combat.enemyWaiting > 0 and combat.enemyOnScreen == 0 then
          CombatEngine.spawnShips(combat, state.enemyBaseHP)
        end
      end
    end
  end

  -- Check victory
  if combat.enemyTotal == 0 then
    combat.outcome = "victory"
    return { sunk = sunk, fleeCount = 0 }
  end

  -- Enemy flee check: FN_R(S0) < SN * 0.6 / F1; skip if SN=0, SN=S0, SN<3
  local fleeCount = 0
  local sn = combat.enemyTotal
  local s0 = combat.originalCount
  local f1 = combat.encounterType
  if sn > 0 and sn ~= s0 and sn >= 3 then
    if fnR(s0) < sn * 0.6 / f1 then
      local w = fnR(sn / 3 / f1) + 1
      combat.enemyTotal   = combat.enemyTotal   - w
      combat.enemyWaiting = math.max(0, combat.enemyWaiting - w)
      -- Remove excess on-screen ships if needed
      local removed = 0
      for i = 10, 1, -1 do
        if removed >= w then break end
        if combat.grid[i] ~= nil then
          combat.grid[i] = nil
          combat.enemyOnScreen = combat.enemyOnScreen - 1
          removed = removed + 1
        end
      end
      fleeCount = w
    end
  end

  combat.lastCommand = 2
  return { sunk = sunk, fleeCount = fleeCount }
end

-- ── Run action ────────────────────────────────────────────────────────────────

-- Update run momentum based on last command.
-- Call BEFORE attemptRun.
function CombatEngine.updateRunMomentum(combat)
  local lc = combat.lastCommand
  if lc == 1 or lc == 3 then
    -- Consecutive run/throw: build momentum
    combat.runMomentum = combat.runMomentum + combat.runAccel
    combat.runAccel    = combat.runAccel + 1
  else
    -- Reset after fight or first run
    combat.runMomentum = 3
    combat.runAccel    = 1
  end
end

-- Attempt to run. Returns true if escaped.
-- Sets combat.outcome = "fled" on success.
function CombatEngine.attemptRun(combat)
  local escaped = fnR(combat.runMomentum) > fnR(combat.enemyTotal)
  if escaped then
    combat.outcome = "fled"
  end
  return escaped
end

-- Partial escape when run fails (1-in-5, only if SN > 2).
-- Returns number of ships that fled, 0 if did not fire.
function CombatEngine.partialEscape(combat)
  if combat.enemyTotal <= 2 then return 0 end
  if math.random(0, 4) ~= 0 then return 0 end

  local w = fnR(combat.enemyTotal / 2) + 1
  combat.enemyTotal   = combat.enemyTotal   - w
  combat.enemyWaiting = math.max(0, combat.enemyWaiting - w)
  local removed = 0
  for i = 10, 1, -1 do
    if removed >= w then break end
    if combat.grid[i] ~= nil then
      combat.grid[i] = nil
      combat.enemyOnScreen = combat.enemyOnScreen - 1
      removed = removed + 1
    end
  end
  return w
end

-- ── Throw cargo action ────────────────────────────────────────────────────────

-- Throw qty units of goodIndex overboard. Boosts run momentum.
-- Returns actual amount thrown (capped by available).
-- Chaining to run is handled by the GameService handler.
function CombatEngine.throwCargo(state, combat, goodIndex, qty)
  local available = state.shipCargo[goodIndex]
  local actual = math.min(qty, available)
  if actual <= 0 then return 0 end

  state.shipCargo[goodIndex] = state.shipCargo[goodIndex] - actual
  state.holdSpace            = state.holdSpace + actual
  -- OK += WW/10 (boost momentum proportional to amount thrown)
  combat.runMomentum = combat.runMomentum + math.floor(actual / 10)
  combat.lastCommand = 3
  return actual
end

-- ── Enemy fire ────────────────────────────────────────────────────────────────

-- Apply enemy fire for one round. Mutates state.damage, state.guns.
-- Returns { gunDestroyed=bool, damageDealt=N, liYuenIntervened=bool, sunk=bool }
function CombatEngine.enemyFire(state, combat)
  local f1  = combat.encounterType
  local sn  = combat.enemyTotal
  local i   = math.min(sn, 15)    -- effective shooters capped at 15
  local gunDestroyed    = false
  local liYuenIntervened = false

  -- Gun destruction check (only if player has guns)
  if state.guns > 0 then
    local dmgPct = state.damage / state.shipCapacity * 100
    if fnR(100) < dmgPct or dmgPct > 80 then
      gunDestroyed = true
      i = 1  -- only 1 effective shooter this round
      state.guns      = state.guns - 1
      state.holdSpace = state.holdSpace + 10
    end
  end

  -- Damage formula: FN_R(ED * I * F1) + I/2
  local dmg = fnR(state.enemyBaseDamage * i * f1) + i / 2
  state.damage = state.damage + dmg

  -- DM truncation happens at start of next round (replicated in GameService)

  -- Check if ship is sunk by accumulated damage
  local sunk = false
  if state.damage >= state.shipCapacity then
    sunk = true
    combat.outcome = "sunk"
    state.gameOver = true
  end

  -- Li Yuen intervention: 1-in-20, only for generic pirates (F1=1)
  if not sunk and f1 == 1 and math.random(0, 19) == 0 then
    liYuenIntervened = true
    combat.outcome = "liYuen"
  end

  return {
    gunDestroyed     = gunDestroyed,
    damageDealt      = dmg,
    liYuenIntervened = liYuenIntervened,
    sunk             = sunk,
  }
end

-- ── Booty ─────────────────────────────────────────────────────────────────────

-- Apply booty to cash. Call when outcome == "victory".
function CombatEngine.applyBooty(state, combat)
  state.cash = state.cash + combat.booty
end

-- ── Seaworthiness display ─────────────────────────────────────────────────────

-- Seaworthiness for in-combat display: TRUNCATION (not rounding).
-- BASIC line 5160: WW = 100 - INT(DM/SC*100)
function CombatEngine.seaworthiness(state)
  local pct = math.floor(state.damage / state.shipCapacity * 100)
  return math.max(0, 100 - pct)
end

return CombatEngine
```

### CombatEngine.spec.lua tests (~35 tests)

State helper with: pirateBase=10, shipCapacity=60, guns=2, damage=0,
enemyBaseHP=20, enemyBaseDamage=0.5, liYuenProtection=0, turnsElapsed=12,
cash=5000, shipCargo={0,0,0,0}, holdSpace=60.

Combat helper: initCombat(state, 5, 1) = 5-ship generic encounter.

**genericEncounterCheck:** fires at roughly 1/BP rate (100 trials)
**liYuenEncounterCheck:** fires at ~1-in-4 unprotected, ~1-in-12 protected
**genericFleetSize:** always >= 1, <= floor(SC/10+GN)
**liYuenFleetSize:** always >= 5
**initCombat:** correct fields, booty >= 250, grid has 10 nil slots
**spawnShips:** fills empty slots, decrements enemyWaiting, each HP in [20, EC+19]
**onScreenCount:** counts occupied slots
**fight (no guns):** returns noGuns=true
**fight (sinks):** enemyTotal decreases when damage > maxHP
**fight (victory):** outcome = "victory" when all sunk
**updateRunMomentum (first run):** momentum=3, accel=1
**updateRunMomentum (consecutive):** momentum accumulates
**attemptRun (success):** outcome = "fled"; high momentum vs low SN
**partialEscape (SN<=2):** returns 0
**partialEscape (fires):** at least once in 200 trials; reduces enemyTotal
**throwCargo:** reduces shipCargo, increases holdSpace, boosts momentum
**throwCargo (nothing):** returns 0 when no goods
**enemyFire (no guns):** no gun destruction
**enemyFire (high damage):** guaranteed gun destruction when dmgPct > 80
**enemyFire (sinks ship):** outcome="sunk", gameOver=true when damage>=shipCapacity
**enemyFire (liYuen):** fires at least once in 500 trials with F1=1
**enemyFire (liYuen not F1=2):** never fires with F1=2 (run 200 trials)
**seaworthiness (0%):** returns 100
**seaworthiness (50%):** returns 50 (truncated)
**seaworthiness (100%):** returns 0

---

## Task 2: GameState + Remotes + GameService

**Modified:** `src/ReplicatedStorage/shared/GameState.lua` — add `combat = nil`
**Modified:** `src/ReplicatedStorage/Remotes.lua` — add combat remotes
**Modified:** `src/ServerScriptService/GameService.server.lua` — full combat integration

### GameState.lua
Add after `gameOver`:
```lua
combat = nil,  -- combat sub-table when in combat, nil otherwise
```

### Remotes.lua — add 3 new events
```lua
-- Phase 5: Combat
Remotes.CombatFight = getOrCreate("RemoteEvent", "CombatFight") -- client→server: fight action
Remotes.CombatRun   = getOrCreate("RemoteEvent", "CombatRun")   -- client→server: run action
Remotes.CombatThrow = getOrCreate("RemoteEvent", "CombatThrow") -- client→server: goodIndex, qty
```

### GameService.server.lua

**Add** `local CombatEngine = require(ReplicatedStorage.shared.CombatEngine)` to requires.

**Update TravelTo handler** — after Phase 4 event block and before pushState, add:

```lua
    -- Phase 5: Pirate encounters (only if game not over)
    if not state.gameOver and not state.combat then
      -- Generic pirates
      if CombatEngine.genericEncounterCheck(state) then
        local shipCount = CombatEngine.genericFleetSize(state)
        state.combat = CombatEngine.initCombat(state, shipCount, 1)
        CombatEngine.spawnShips(state.combat, state.enemyBaseHP)
        Remotes.Notify:FireClient(player,
          string.format("Taipan!! %d hostile ships approaching!!", shipCount))
      -- Li Yuen's pirates (only if no generic encounter this voyage)
      elseif CombatEngine.liYuenEncounterCheck(state) then
        if state.liYuenProtection ~= 0 then
          -- Protected: let pass
          Remotes.Notify:FireClient(player,
            "Good joss!! Li Yuen's fleet let us be!!")
        else
          -- Unprotected: engage
          local shipCount = CombatEngine.liYuenFleetSize(state)
          state.combat = CombatEngine.initCombat(state, shipCount, 2)
          CombatEngine.spawnShips(state.combat, state.enemyBaseHP)
          Remotes.Notify:FireClient(player,
            string.format("Taipan!! Li Yuen's fleet!! %d ships!!", shipCount))
        end
      end
    end
```

**Add combat action handlers** (after RestartGame handler):

```lua
-- Helper: truncate damage and check seaworthiness
local function combatTruncateDamage(state)
  state.damage = math.floor(state.damage)
end

-- CombatFight: fire all guns, enemy fires back
Remotes.CombatFight.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or not state.combat or state.combat.outcome ~= nil then return end
  local combat = state.combat

  -- Fight
  local result = CombatEngine.fight(state, combat)
  if result.noGuns then
    Remotes.Notify:FireClient(player, "We have no guns, Taipan!!")
    pushState(player)
    return
  end
  if result.sunk > 0 then
    Remotes.Notify:FireClient(player,
      string.format("Sunk %d of the buggers, Taipan!", result.sunk))
  else
    Remotes.Notify:FireClient(player, "Hit 'em, but didn't sink 'em, Taipan!")
  end
  if result.fleeCount > 0 then
    Remotes.Notify:FireClient(player,
      string.format("%d ran away, Taipan!", result.fleeCount))
  end
  combat.lastCommand = 2

  if combat.outcome == "victory" then
    CombatEngine.applyBooty(state, combat)
    Remotes.Notify:FireClient(player,
      string.format("We've captured some booty worth $%d!!", combat.booty))
    state.combat = nil
    -- Post-combat storm check
    if EventEngine.stormOccurs() then
      Remotes.Notify:FireClient(player, "Storm, Taipan!!")
      if EventEngine.stormGoingDown() and EventEngine.stormSinks(state) then
        Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
      else
        Remotes.Notify:FireClient(player, "We made it!!")
        local newPort = EventEngine.stormBlownOffCourse(state, state.destination)
        if newPort then
          state.currentPort   = newPort
          state.destination   = newPort
          state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
          Remotes.Notify:FireClient(player,
            string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
        end
      end
    end
    pushState(player)
    return
  end

  -- Enemy fires back
  combatTruncateDamage(state)
  local fireResult = CombatEngine.enemyFire(state, combat)
  if fireResult.gunDestroyed then
    Remotes.Notify:FireClient(player, "The buggers hit a gun, Taipan!!")
  end
  Remotes.Notify:FireClient(player, "We've been hit, Taipan!!")
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    state.combat = nil
    pushState(player)
    return
  end
  if fireResult.liYuenIntervened then
    Remotes.Notify:FireClient(player, "Li Yuen's fleet drove them off!!")
    state.combat = nil
    pushState(player)
    return
  end
  pushState(player)
end)

-- CombatRun: attempt to flee
Remotes.CombatRun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or not state.combat or state.combat.outcome ~= nil then return end
  local combat = state.combat

  CombatEngine.updateRunMomentum(combat)
  local escaped = CombatEngine.attemptRun(combat)
  if escaped then
    Remotes.Notify:FireClient(player, string.format("We got away from 'em, Taipan!!"))
    state.combat = nil
    -- Post-combat storm
    if EventEngine.stormOccurs() then
      Remotes.Notify:FireClient(player, "Storm, Taipan!!")
      if EventEngine.stormGoingDown() and EventEngine.stormSinks(state) then
        Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
      else
        Remotes.Notify:FireClient(player, "We made it!!")
        local newPort = EventEngine.stormBlownOffCourse(state, state.destination)
        if newPort then
          state.currentPort   = newPort
          state.destination   = newPort
          state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
          Remotes.Notify:FireClient(player,
            string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
        end
      end
    end
    pushState(player)
    return
  end

  Remotes.Notify:FireClient(player, "Can't lose 'em!!")
  -- Partial escape?
  local escaped2 = CombatEngine.partialEscape(combat)
  if escaped2 > 0 then
    Remotes.Notify:FireClient(player,
      string.format("But we escaped from %d of 'em, Taipan!", escaped2))
  end
  combat.lastCommand = 1

  -- Enemy fires back
  combatTruncateDamage(state)
  local fireResult = CombatEngine.enemyFire(state, combat)
  if fireResult.gunDestroyed then
    Remotes.Notify:FireClient(player, "The buggers hit a gun, Taipan!!")
  end
  Remotes.Notify:FireClient(player, "We've been hit, Taipan!!")
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    state.combat = nil
    pushState(player)
    return
  end
  if fireResult.liYuenIntervened then
    Remotes.Notify:FireClient(player, "Li Yuen's fleet drove them off!!")
    state.combat = nil
    pushState(player)
    return
  end
  pushState(player)
end)

-- CombatThrow: throw cargo, auto-attempt run
Remotes.CombatThrow.OnServerEvent:Connect(function(player, goodIndex, qty)
  local state = playerStates[player]
  if not state or not state.combat or state.combat.outcome ~= nil then return end
  if not validGood(goodIndex) or not validQty(qty) then return end
  local combat = state.combat

  local thrown = CombatEngine.throwCargo(state, combat, goodIndex, qty)
  if thrown == 0 then
    Remotes.Notify:FireClient(player, "There's nothing there, Taipan!")
    pushState(player)
    return
  end
  Remotes.Notify:FireClient(player,
    string.format("Threw %d overboard. Let's hope we lose 'em, Taipan!", thrown))

  -- Auto-attempt run (throw always chains to run)
  CombatEngine.updateRunMomentum(combat)
  local escaped = CombatEngine.attemptRun(combat)
  if escaped then
    Remotes.Notify:FireClient(player, "We got away from 'em, Taipan!!")
    state.combat = nil
    if EventEngine.stormOccurs() then
      Remotes.Notify:FireClient(player, "Storm, Taipan!!")
      if EventEngine.stormGoingDown() and EventEngine.stormSinks(state) then
        Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
      else
        Remotes.Notify:FireClient(player, "We made it!!")
        local newPort = EventEngine.stormBlownOffCourse(state, state.destination)
        if newPort then
          state.currentPort   = newPort
          state.destination   = newPort
          state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
          Remotes.Notify:FireClient(player,
            string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
        end
      end
    end
    pushState(player)
    return
  end

  Remotes.Notify:FireClient(player, "Can't lose 'em!!")
  local escaped2 = CombatEngine.partialEscape(combat)
  if escaped2 > 0 then
    Remotes.Notify:FireClient(player,
      string.format("But we escaped from %d of 'em, Taipan!", escaped2))
  end

  combatTruncateDamage(state)
  local fireResult = CombatEngine.enemyFire(state, combat)
  if fireResult.gunDestroyed then
    Remotes.Notify:FireClient(player, "The buggers hit a gun, Taipan!!")
  end
  Remotes.Notify:FireClient(player, "We've been hit, Taipan!!")
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    state.combat = nil
    pushState(player)
    return
  end
  if fireResult.liYuenIntervened then
    Remotes.Notify:FireClient(player, "Li Yuen's fleet drove them off!!")
    state.combat = nil
    pushState(player)
    return
  end
  pushState(player)
end)
```

Write to disk. Do NOT inject to Studio.

---

## Task 3: CombatPanel.lua + init.client.lua + Studio injection + tests

**New file:** `src/StarterGui/TaipanGui/Panels/CombatPanel.lua`
**Modified:** `src/StarterGui/TaipanGui/init.client.lua`

### CombatPanel.lua

Full-screen combat overlay (like GameOverPanel). ZIndex=15.
Visible when `state.combat ~= nil`.

Layout (all within 480px width):
- Header row: "BATTLE!!" title + seaworthiness + enemy count
- Enemy grid: 10 small ship indicators (green=alive, grey=empty)
- Action row: FIGHT button + RUN button
- Throw row: good selector (4 buttons) + amount box + THROW button

Signature:
```lua
function CombatPanel.new(parent, onFight, onRun, onThrow)
  -- onFight()
  -- onRun()
  -- onThrow(goodIndex, qty)
  local panel = {}
  function panel.update(state)
    if not state.combat then
      frame.Visible = false
      return
    end
    frame.Visible = true
    -- update seaworthiness, enemy count, grid indicators
    latestState = state
  end
  return panel
end
```

Colors: amber/red combat theme. FIGHT = red, RUN = blue, THROW = orange.
Enemy grid: 10 small squares (24x24), green when occupied, dark when empty.
Seaworthiness shown as percentage with color: >60%=green, 30-60%=yellow, <30%=red.

### init.client.lua changes

Add:
```lua
local CombatPanel = require(script.Panels.CombatPanel)
```

Wire:
```lua
local combatPanel = CombatPanel.new(root,
  function() Remotes.CombatFight:FireServer() end,
  function() Remotes.CombatRun:FireServer() end,
  function(goodIndex, qty) Remotes.CombatThrow:FireServer(goodIndex, qty) end
)
```

Add to StateUpdate handler:
```lua
combatPanel.update(state)
```

### Studio injection order
1. Stop play
2. Inject CombatEngine.lua → ReplicatedStorage.shared (edit mode)
3. Update GameState.lua (edit mode)
4. Update Remotes.lua (edit mode)
5. Update GameService.server.lua (edit mode)
6. Inject CombatPanel.lua → GameController.Panels (edit mode)
7. Update GameController init.client.lua (edit mode)
8. Inject CombatEngine.spec → Tests (edit mode)
9. Start play → run tests
10. Verify no errors: 114 existing + CombatEngine tests all pass

### Acceptance criteria
- All tests pass (114 + CombatEngine suite)
- No console errors on game launch
- Sailing triggers pirate encounters
- CombatPanel appears with correct enemy count
- FIGHT reduces enemy count, FIGHT enough kills all → victory + booty notification
- RUN eventually escapes
- THROW boosts run chance
- Ship damage accumulates; reaching 100% triggers game over
