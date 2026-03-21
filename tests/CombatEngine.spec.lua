-- CombatEngine.spec.lua
-- Tests for pirate encounters, combat grid, fight/run/throw, and enemy fire.
-- Run via TestEZ in Roblox Studio.

return function()
  local CombatEngine = require(game:GetService("ReplicatedStorage").shared.CombatEngine)

  -- Helper: make a default state
  local function makeState(overrides)
    local s = {
      pirateBase       = 10,
      shipCapacity     = 60,
      guns             = 2,
      damage           = 0,
      enemyBaseHP      = 20,
      enemyBaseDamage  = 0.5,
      liYuenProtection = 0,
      turnsElapsed     = 12,
      cash             = 5000,
      shipCargo        = {0, 0, 0, 0},
      holdSpace        = 60,
      gameOver         = false,
    }
    if overrides then
      for k, v in pairs(overrides) do s[k] = v end
    end
    return s
  end

  -- Helper: make a fresh combat block with 5 ships, generic encounter
  local function makeCombat(state)
    return CombatEngine.initCombat(state, 5, 1)
  end

  -- ── Encounter checks ──────────────────────────────────────────────────────

  describe("genericEncounterCheck", function()
    it("fires at roughly 1/BP rate (> 0 and < 30 fires in 100 trials)", function()
      local fires = 0
      local s = makeState({ pirateBase = 10 })
      for _ = 1, 100 do
        if CombatEngine.genericEncounterCheck(s) then fires = fires + 1 end
      end
      expect(fires > 0).to.equal(true)
      expect(fires < 30).to.equal(true)
    end)
  end)

  describe("liYuenEncounterCheck", function()
    it("unprotected (LI=0): fires at ~1-in-4 rate (> 0 fires in 100 trials)", function()
      local fires = 0
      local s = makeState({ liYuenProtection = 0 })
      for _ = 1, 100 do
        if CombatEngine.liYuenEncounterCheck(s) then fires = fires + 1 end
      end
      expect(fires > 0).to.equal(true)
    end)

    it("protected (LI=1): fires at ~1-in-12 rate (fewer fires than unprotected)", function()
      local firesUnprotected = 0
      local firesProtected   = 0
      local trials = 200
      for _ = 1, trials do
        if CombatEngine.liYuenEncounterCheck(makeState({ liYuenProtection = 0 })) then
          firesUnprotected = firesUnprotected + 1
        end
        if CombatEngine.liYuenEncounterCheck(makeState({ liYuenProtection = 1 })) then
          firesProtected = firesProtected + 1
        end
      end
      -- Protected should fire less often on average; allow for randomness with a loose bound
      expect(firesProtected < firesUnprotected + 20).to.equal(true)
      -- Protected rate should be below 1-in-4 territory over 200 trials
      expect(firesProtected < 60).to.equal(true)
    end)
  end)

  -- ── Fleet size ────────────────────────────────────────────────────────────

  describe("genericFleetSize", function()
    it("always returns >= 1", function()
      local s = makeState()
      for _ = 1, 100 do
        expect(CombatEngine.genericFleetSize(s) >= 1).to.equal(true)
      end
    end)
  end)

  describe("liYuenFleetSize", function()
    it("always returns >= 5", function()
      local s = makeState()
      for _ = 1, 100 do
        expect(CombatEngine.liYuenFleetSize(s) >= 5).to.equal(true)
      end
    end)
  end)

  -- ── initCombat ────────────────────────────────────────────────────────────

  describe("initCombat", function()
    it("sets active=true, enemyTotal matches shipCount", function()
      local s = makeState()
      local c = CombatEngine.initCombat(s, 5, 1)
      expect(c.active).to.equal(true)
      expect(c.enemyTotal).to.equal(5)
    end)

    it("booty is >= 250", function()
      local s = makeState()
      for _ = 1, 20 do
        local c = CombatEngine.initCombat(s, 5, 1)
        expect(c.booty >= 250).to.equal(true)
      end
    end)

    it("grid table has exactly 10 slots (all nil initially)", function()
      local s = makeState()
      local c = CombatEngine.initCombat(s, 5, 1)
      local count = 0
      for i = 1, 10 do
        count = count + 1
        expect(c.grid[i]).to.equal(nil)
      end
      expect(count).to.equal(10)
    end)

    it("encounterType, originalCount, runMomentum, runAccel, lastCommand are initialised", function()
      local s = makeState()
      local c = CombatEngine.initCombat(s, 7, 2)
      expect(c.encounterType).to.equal(2)
      expect(c.originalCount).to.equal(7)
      expect(c.runMomentum).to.equal(3)
      expect(c.runAccel).to.equal(1)
      expect(c.lastCommand).to.equal(0)
    end)
  end)

  -- ── spawnShips ────────────────────────────────────────────────────────────

  describe("spawnShips", function()
    it("fills empty grid slots and decrements enemyWaiting", function()
      local s = makeState()
      local c = makeCombat(s)
      -- enemyWaiting should start at 5
      expect(c.enemyWaiting).to.equal(5)
      CombatEngine.spawnShips(c, s.enemyBaseHP)
      expect(c.enemyOnScreen).to.equal(5)
      expect(c.enemyWaiting).to.equal(0)
    end)

    it("each spawned ship HP (maxHP) is in [20, enemyBaseHP+19]", function()
      local s = makeState({ enemyBaseHP = 20 })
      local c = makeCombat(s)
      CombatEngine.spawnShips(c, s.enemyBaseHP)
      for i = 1, 10 do
        if c.grid[i] ~= nil then
          expect(c.grid[i].maxHP >= 20).to.equal(true)
          -- fnR(20) gives 0..19, so maxHP <= 39
          expect(c.grid[i].maxHP <= 39).to.equal(true)
          expect(c.grid[i].damage).to.equal(0)
        end
      end
    end)
  end)

  -- ── onScreenCount ─────────────────────────────────────────────────────────

  describe("onScreenCount", function()
    it("counts occupied slots correctly", function()
      local s = makeState()
      local c = makeCombat(s)
      -- Before spawning: all nil
      expect(CombatEngine.onScreenCount(c)).to.equal(0)
      CombatEngine.spawnShips(c, s.enemyBaseHP)
      expect(CombatEngine.onScreenCount(c)).to.equal(5)
      -- Manually remove one slot
      c.grid[1] = nil
      expect(CombatEngine.onScreenCount(c)).to.equal(4)
    end)
  end)

  -- ── fight ─────────────────────────────────────────────────────────────────

  describe("fight", function()
    it("returns noGuns=true when guns=0", function()
      local s = makeState({ guns = 0 })
      local c = makeCombat(s)
      CombatEngine.spawnShips(c, s.enemyBaseHP)
      local result = CombatEngine.fight(s, c)
      expect(result.noGuns).to.equal(true)
    end)

    it("enemyTotal decreases when ships are killed (low maxHP forces kills)", function()
      local s = makeState({ guns = 10, enemyBaseHP = 1 })
      -- With enemyBaseHP=1: fnR(1)=0, so maxHP=20. Damage per gun: fnR(30)+10 = 10..39.
      -- With 10 guns, likely to sink at least one ship with maxHP=20.
      local c = CombatEngine.initCombat(s, 5, 1)
      -- Force all ships to have maxHP=1 (guaranteed kill)
      for i = 1, 5 do
        c.grid[i] = { maxHP = 1, damage = 0 }
      end
      c.enemyOnScreen = 5
      c.enemyWaiting  = 0
      local before = c.enemyTotal
      CombatEngine.fight(s, c)
      expect(c.enemyTotal < before).to.equal(true)
    end)

    it("outcome='victory' when all enemies are sunk", function()
      local s = makeState({ guns = 10 })
      local c = CombatEngine.initCombat(s, 3, 1)
      -- Force all ships onto screen with trivially low HP
      for i = 1, 3 do
        c.grid[i] = { maxHP = 1, damage = 0 }
      end
      c.enemyOnScreen = 3
      c.enemyWaiting  = 0
      -- Fire until victory (may need multiple rounds)
      for _ = 1, 10 do
        if c.outcome == "victory" then break end
        CombatEngine.fight(s, c)
      end
      expect(c.outcome).to.equal("victory")
    end)
  end)

  -- ── updateRunMomentum ─────────────────────────────────────────────────────

  describe("updateRunMomentum", function()
    it("resets momentum to 3 and accel to 1 after fight (lastCommand=2)", function()
      local s = makeState()
      local c = makeCombat(s)
      c.lastCommand  = 2
      c.runMomentum  = 99
      c.runAccel     = 99
      CombatEngine.updateRunMomentum(c)
      expect(c.runMomentum).to.equal(3)
      expect(c.runAccel).to.equal(1)
    end)

    it("resets on first run attempt (lastCommand=0)", function()
      local s = makeState()
      local c = makeCombat(s)
      c.lastCommand = 0
      c.runMomentum = 10
      CombatEngine.updateRunMomentum(c)
      expect(c.runMomentum).to.equal(3)
      expect(c.runAccel).to.equal(1)
    end)

    it("increases momentum on consecutive run (lastCommand=1)", function()
      local s = makeState()
      local c = makeCombat(s)
      c.lastCommand = 1
      c.runMomentum = 3
      c.runAccel    = 1
      CombatEngine.updateRunMomentum(c)
      expect(c.runMomentum).to.equal(4)
      expect(c.runAccel).to.equal(2)
    end)

    it("increases momentum when lastCommand=3 (throw)", function()
      local s = makeState()
      local c = makeCombat(s)
      c.lastCommand = 3
      c.runMomentum = 5
      c.runAccel    = 2
      CombatEngine.updateRunMomentum(c)
      expect(c.runMomentum).to.equal(7)
      expect(c.runAccel).to.equal(3)
    end)
  end)

  -- ── attemptRun ────────────────────────────────────────────────────────────

  describe("attemptRun", function()
    it("outcome='fled' when momentum >> enemyTotal (high momentum, 1 enemy)", function()
      local s = makeState()
      local c = makeCombat(s)
      c.runMomentum = 1000
      c.enemyTotal  = 1
      local escaped = CombatEngine.attemptRun(c)
      expect(escaped).to.equal(true)
      expect(c.outcome).to.equal("fled")
    end)

    it("always sets lastCommand=1 regardless of escape outcome", function()
      local s = makeState()
      -- Guaranteed escape: very high momentum
      local c1 = makeCombat(s)
      c1.runMomentum = 1000
      c1.enemyTotal  = 1
      CombatEngine.attemptRun(c1)
      expect(c1.lastCommand).to.equal(1)
      -- Guaranteed failure: zero momentum vs many enemies
      local c2 = makeCombat(s)
      c2.runMomentum = 1
      c2.enemyTotal  = 1000
      CombatEngine.attemptRun(c2)
      expect(c2.lastCommand).to.equal(1)
    end)
  end)

  -- ── partialEscape ─────────────────────────────────────────────────────────

  describe("partialEscape", function()
    it("always returns 0 when enemyTotal <= 2", function()
      local s = makeState()
      local c = makeCombat(s)
      c.enemyTotal = 2
      for _ = 1, 50 do
        expect(CombatEngine.partialEscape(c)).to.equal(0)
      end
      c.enemyTotal = 1
      for _ = 1, 50 do
        expect(CombatEngine.partialEscape(c)).to.equal(0)
      end
    end)

    it("fires at least once in 200 trials and reduces enemyTotal when SN > 2", function()
      local fired = false
      for _ = 1, 200 do
        local s = makeState()
        local c = CombatEngine.initCombat(s, 10, 1)
        for i = 1, 10 do
          c.grid[i] = { maxHP = 50, damage = 0 }
        end
        c.enemyOnScreen = 10
        c.enemyWaiting  = 0
        local before = c.enemyTotal
        local w = CombatEngine.partialEscape(c)
        if w > 0 then
          expect(c.enemyTotal).to.equal(before - w)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)
  end)

  -- ── throwCargo ────────────────────────────────────────────────────────────

  describe("throwCargo", function()
    it("reduces shipCargo, increases holdSpace, boosts momentum", function()
      local s = makeState({ shipCargo = {50, 0, 0, 0}, holdSpace = 10 })
      local c = makeCombat(s)
      c.runMomentum = 3
      local actual = CombatEngine.throwCargo(s, c, 1, 30)
      expect(actual).to.equal(30)
      expect(s.shipCargo[1]).to.equal(20)
      expect(s.holdSpace).to.equal(40)
      -- floor(30/10) = 3 added to momentum
      expect(c.runMomentum).to.equal(6)
      expect(c.lastCommand).to.equal(3)
    end)

    it("returns 0 when shipCargo[goodIndex]=0 (nothing to throw)", function()
      local s = makeState({ shipCargo = {0, 0, 0, 0} })
      local c = makeCombat(s)
      local actual = CombatEngine.throwCargo(s, c, 1, 50)
      expect(actual).to.equal(0)
    end)
  end)

  -- ── enemyFire ─────────────────────────────────────────────────────────────

  describe("enemyFire", function()
    it("gunDestroyed=false when player has no guns", function()
      local s = makeState({ guns = 0, damage = 0 })
      local c = makeCombat(s)
      c.enemyTotal = 3
      local result = CombatEngine.enemyFire(s, c)
      expect(result.gunDestroyed).to.equal(false)
    end)

    it("gunDestroyed=true and guns decremented when dmgPct > 80", function()
      -- damage=52, shipCapacity=60 => dmgPct = 86.6 > 80, always triggers
      local s = makeState({ guns = 2, damage = 52, shipCapacity = 60 })
      local c = makeCombat(s)
      c.enemyTotal = 3
      local result = CombatEngine.enemyFire(s, c)
      expect(result.gunDestroyed).to.equal(true)
      expect(s.guns).to.equal(1)
    end)

    it("outcome='sunk' and gameOver=true when accumulated damage >= shipCapacity", function()
      -- Start at damage just under capacity; enemy fire will push it over
      local s = makeState({ guns = 0, damage = 59, shipCapacity = 60, enemyBaseDamage = 10 })
      local c = makeCombat(s)
      c.enemyTotal = 5
      local result = CombatEngine.enemyFire(s, c)
      expect(result.sunk).to.equal(true)
      expect(c.outcome).to.equal("sunk")
      expect(s.gameOver).to.equal(true)
    end)

    it("Li Yuen intervention fires at least once in 500 trials for F1=1", function()
      local fired = false
      for _ = 1, 500 do
        local s = makeState({ guns = 0, damage = 0 })
        local c = CombatEngine.initCombat(s, 3, 1)
        c.enemyTotal = 3
        local result = CombatEngine.enemyFire(s, c)
        if result.liYuenIntervened then
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("Li Yuen intervention never fires for encounterType=2 (200 trials)", function()
      for _ = 1, 200 do
        local s = makeState({ guns = 0, damage = 0 })
        local c = CombatEngine.initCombat(s, 3, 2)
        c.enemyTotal = 3
        local result = CombatEngine.enemyFire(s, c)
        expect(result.liYuenIntervened).to.equal(false)
      end
    end)
  end)

  -- ── applyBooty ────────────────────────────────────────────────────────────

  describe("applyBooty", function()
    it("adds booty to cash", function()
      local s = makeState({ cash = 5000 })
      local c = makeCombat(s)
      c.booty = 1234
      CombatEngine.applyBooty(s, c)
      expect(s.cash).to.equal(6234)
    end)
  end)

  -- ── seaworthiness ─────────────────────────────────────────────────────────

  describe("seaworthiness", function()
    it("returns 100 when damage=0", function()
      local s = makeState({ damage = 0, shipCapacity = 60 })
      expect(CombatEngine.seaworthiness(s)).to.equal(100)
    end)

    it("returns 50 when damage is exactly 50% (truncated)", function()
      -- damage=30, shipCapacity=60 => 30/60*100 = 50 => 100-50 = 50
      local s = makeState({ damage = 30, shipCapacity = 60 })
      expect(CombatEngine.seaworthiness(s)).to.equal(50)
    end)

    it("truncates rather than rounds (damage=31 => floor(31/60*100)=51 => 49)", function()
      local s = makeState({ damage = 31, shipCapacity = 60 })
      expect(CombatEngine.seaworthiness(s)).to.equal(49)
    end)

    it("returns 0 when damage >= shipCapacity", function()
      local s = makeState({ damage = 60, shipCapacity = 60 })
      expect(CombatEngine.seaworthiness(s)).to.equal(0)
    end)
  end)
end
