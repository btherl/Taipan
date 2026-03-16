local TravelEngine = require(game.ReplicatedStorage.shared.TravelEngine)
local PriceEngine  = require(game.ReplicatedStorage.shared.PriceEngine)

-- Helper: builds a minimal valid state table with optional field overrides.
local function makeState(overrides)
  local s = {
    turnsElapsed    = 1,
    month           = 1,
    year            = 1860,
    bankBalance     = 0,
    debt            = 0,
    currentPort     = 1,
    holdSpace       = 60,
    enemyBaseHP     = 20,
    enemyBaseDamage = 0.5,
    basePrices      = (function()
      local t = {}
      for p = 1, 7 do t[p] = {11, 11, 12, 10} end
      return t
    end)(),
  }
  if overrides then
    for k, v in pairs(overrides) do s[k] = v end
  end
  return s
end

return function()
  describe("TravelEngine.timeAdvance", function()

    it("increments turnsElapsed by 1 (1 → 2)", function()
      local s = makeState()
      TravelEngine.timeAdvance(s)
      expect(s.turnsElapsed).to.equal(2)
    end)

    it("increments month by 1 (1 → 2)", function()
      local s = makeState()
      TravelEngine.timeAdvance(s)
      expect(s.month).to.equal(2)
    end)

    it("applies 0.5% bank interest floored: 1000 → 1005", function()
      local s = makeState({ bankBalance = 1000 })
      TravelEngine.timeAdvance(s)
      -- floor(1000 + 1000*0.005) = floor(1005) = 1005
      expect(s.bankBalance).to.equal(1005)
    end)

    it("applies 10% debt compound floored: 5000 → 5500", function()
      local s = makeState({ debt = 5000 })
      TravelEngine.timeAdvance(s)
      -- floor(5000 + 5000*0.1) = floor(5500) = 5500
      expect(s.debt).to.equal(5500)
    end)

    it("does NOT apply bank interest when bankBalance is 0", function()
      local s = makeState({ bankBalance = 0 })
      TravelEngine.timeAdvance(s)
      expect(s.bankBalance).to.equal(0)
    end)

    it("does NOT apply debt compound when debt is 0", function()
      local s = makeState({ debt = 0 })
      TravelEngine.timeAdvance(s)
      expect(s.debt).to.equal(0)
    end)

    it("year rollover: month wraps from 12 to 1", function()
      local s = makeState({ month = 12 })
      TravelEngine.timeAdvance(s)
      expect(s.month).to.equal(1)
    end)

    it("year rollover: year increments (1860 → 1861)", function()
      local s = makeState({ month = 12, year = 1860 })
      TravelEngine.timeAdvance(s)
      expect(s.year).to.equal(1861)
    end)

    it("January event: enemyBaseHP increases by 10 (20 → 30)", function()
      local s = makeState({ month = 12, enemyBaseHP = 20 })
      TravelEngine.timeAdvance(s)
      expect(s.enemyBaseHP).to.equal(30)
    end)

    it("January event: enemyBaseDamage increases by 0.5 (0.5 → 1.0)", function()
      local s = makeState({ month = 12, enemyBaseDamage = 0.5 })
      TravelEngine.timeAdvance(s)
      expect(s.enemyBaseDamage).to.equal(1.0)
    end)

    it("January event: each basePrices cell is same or +1 (all 28 cells)", function()
      local s = makeState({ month = 12 })
      -- Snapshot values before advance
      local before = {}
      for p = 1, 7 do
        before[p] = {}
        for g = 1, 4 do
          before[p][g] = s.basePrices[p][g]
        end
      end

      TravelEngine.timeAdvance(s)

      for p = 1, 7 do
        for g = 1, 4 do
          local delta = s.basePrices[p][g] - before[p][g]
          expect(delta >= 0).to.equal(true)
          expect(delta <= 1).to.equal(true)
        end
      end
    end)

  end)

  describe("TravelEngine.canDepart", function()

    it("returns nil for a valid departure (dest=2, currentPort=1, holdSpace=60)", function()
      local s = makeState({ currentPort = 1, holdSpace = 60 })
      expect(TravelEngine.canDepart(s, 2)).to.equal(nil)
    end)

    it("returns error string when destination equals currentPort", function()
      local s = makeState({ currentPort = 3 })
      local err = TravelEngine.canDepart(s, 3)
      expect(type(err)).to.equal("string")
    end)

    it("returns error string when holdSpace < 0 (ship overloaded)", function()
      local s = makeState({ holdSpace = -1 })
      local err = TravelEngine.canDepart(s, 2)
      expect(type(err)).to.equal("string")
    end)

    it("returns error string for out-of-range destination (dest=0)", function()
      local s = makeState()
      local err = TravelEngine.canDepart(s, 0)
      expect(type(err)).to.equal("string")
    end)

    it("returns error string for out-of-range destination (dest=8)", function()
      local s = makeState()
      local err = TravelEngine.canDepart(s, 8)
      expect(type(err)).to.equal("string")
    end)

    it("returns error string for non-integer destination (dest=1.5)", function()
      local s = makeState()
      local err = TravelEngine.canDepart(s, 1.5)
      expect(type(err)).to.equal("string")
    end)

  end)
end
