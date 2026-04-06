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

-- ── Consistency guard ────────────────────────────────────────────────────────

-- Reconcile enemyTotal with actual on-screen + waiting ships.
-- Fixes desync caused by flee/partial-escape double-counting (pre-fix saves).
local function reconcileEnemyTotal(combat)
  local actual = CombatEngine.onScreenCount(combat) + combat.enemyWaiting
  if combat.enemyTotal > actual then
    combat.enemyTotal = actual
  end
end

-- ── Fight action ──────────────────────────────────────────────────────────────

-- Fire all guns. Returns { sunk=N, fleeCount=N }.
-- Mutates combat grid, enemyTotal, enemyOnScreen, enemyWaiting.
-- If all enemies destroyed, sets combat.outcome = "victory".
function CombatEngine.fight(state, combat)
  reconcileEnemyTotal(combat)

  -- Check for no remaining enemies first (before guns check, so victory is
  -- detected even when the player has no guns)
  if CombatEngine.onScreenCount(combat) == 0 then
    if combat.enemyTotal == 0 then
      combat.outcome = "victory"
    end
    return { sunk = 0, fleeCount = 0 }
  end

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
      -- Subtract from waiting pool first; remainder must come from on-screen
      local fromWaiting = math.min(w, combat.enemyWaiting)
      combat.enemyWaiting = combat.enemyWaiting - fromWaiting
      local fromScreen = w - fromWaiting
      local removed = 0
      for i = 10, 1, -1 do
        if removed >= fromScreen then break end
        if combat.grid[i] ~= nil then
          combat.grid[i] = nil
          combat.enemyOnScreen = math.max(0, combat.enemyOnScreen - 1)
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
  reconcileEnemyTotal(combat)
  local escaped = fnR(combat.runMomentum) > fnR(combat.enemyTotal)
  if escaped then
    combat.outcome = "fled"
  end
  combat.lastCommand = 1
  return escaped
end

-- Partial escape when run fails (1-in-5, only if SN > 2).
-- Returns number of ships that fled, 0 if did not fire.
function CombatEngine.partialEscape(combat)
  if combat.enemyTotal <= 2 then return 0 end
  if math.random(0, 4) ~= 0 then return 0 end

  local w = fnR(combat.enemyTotal / 2) + 1
  combat.enemyTotal   = combat.enemyTotal   - w
  -- Subtract from waiting pool first; remainder must come from on-screen
  local fromWaiting = math.min(w, combat.enemyWaiting)
  combat.enemyWaiting = combat.enemyWaiting - fromWaiting
  local fromScreen = w - fromWaiting
  local removed = 0
  for i = 10, 1, -1 do
    if removed >= fromScreen then break end
    if combat.grid[i] ~= nil then
      combat.grid[i] = nil
      combat.enemyOnScreen = math.max(0, combat.enemyOnScreen - 1)
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
  reconcileEnemyTotal(combat)
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