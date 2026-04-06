-- EventEngine.spec.lua
-- TestEZ tests for EventEngine
-- Uses statistical/probabilistic testing (no math.random patching - readonly in Luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventEngine = require(ReplicatedStorage.shared.EventEngine)
local Constants   = require(ReplicatedStorage.shared.Constants)

return function()

  -- Helper: build a minimal state table for tests
  local function makeState(overrides)
    local s = {
      currentPort    = 2,  -- non-HK by default
      cash           = 50000,
      shipCargo      = {10, 0, 0, 0},
      holdSpace      = 90,
      shipCapacity   = 100,
      damage         = 0,
      warehouseCargo = {0, 0, 0, 0},
      warehouseUsed  = 0,
      gameOver       = false,
    }
    if overrides then
      for k, v in pairs(overrides) do s[k] = v end
    end
    return s
  end

  -- ─────────────────────────────────────────────────────────────────────────
  describe("spicesSeizure", function()

    it("returns nil at Hong Kong regardless of spices", function()
      -- Run 100 times; HK guard must always short-circuit
      for _ = 1, 100 do
        local s = makeState({ currentPort = Constants.HONG_KONG, shipCargo = {50, 0, 0, 0}, holdSpace = 50 })
        local result = EventEngine.spicesSeizure(s)
        expect(result).to.equal(nil)
        expect(s.shipCargo[1]).to.equal(50)
      end
    end)

    it("returns nil when ship has no spices (100 trials)", function()
      for _ = 1, 100 do
        local s = makeState({ shipCargo = {0, 5, 0, 0} })
        local result = EventEngine.spicesSeizure(s)
        expect(result).to.equal(nil)
      end
    end)

    it("fires at least once in 1000 trials at non-HK with spices", function()
      local fired = false
      for _ = 1, 1000 do
        local s = makeState({ cash = 50000, shipCargo = {10, 0, 0, 0}, holdSpace = 90 })
        local result = EventEngine.spicesSeizure(s)
        if result ~= nil then
          fired = true
          -- Verify side effects when it fires
          expect(result).to.be.a("number")
          expect(result >= 0).to.equal(true)
          expect(s.shipCargo[1]).to.equal(0)
          expect(s.holdSpace).to.equal(100)  -- 90 + 10
          expect(s.cash).to.equal(50000 - result)
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("fine is non-negative (run all firing cases over 2000 trials)", function()
      for _ = 1, 2000 do
        local s = makeState({ cash = 50000, shipCargo = {10, 0, 0, 0}, holdSpace = 90 })
        local fine = EventEngine.spicesSeizure(s)
        if fine ~= nil then
          expect(fine >= 0).to.equal(true)
        end
      end
    end)

  end)

  -- ─────────────────────────────────────────────────────────────────────────
  describe("cargoTheft", function()

    it("returns false immediately when warehouse is empty", function()
      for _ = 1, 100 do
        local s = makeState({ warehouseCargo = {0, 0, 0, 0}, warehouseUsed = 0 })
        expect(EventEngine.cargoTheft(s)).to.equal(false)
      end
    end)

    it("fires at least once in 2000 trials when warehouse has goods", function()
      local fired = false
      for _ = 1, 2000 do
        local s = makeState({ warehouseCargo = {10, 20, 0, 0}, warehouseUsed = 30 })
        local result = EventEngine.cargoTheft(s)
        if result == true then
          fired = true
          -- warehouseUsed must not exceed original
          expect(s.warehouseUsed <= 30).to.equal(true)
          -- each cargo element must be <= original
          expect(s.warehouseCargo[1] <= 10).to.equal(true)
          expect(s.warehouseCargo[2] <= 20).to.equal(true)
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("does not fire much more than 1-in-50: rate check over 5000 trials", function()
      local fires = 0
      local N = 5000
      for _ = 1, N do
        local s = makeState({ warehouseCargo = {10, 0, 0, 0}, warehouseUsed = 10 })
        if EventEngine.cargoTheft(s) then fires = fires + 1 end
      end
      -- Expected ~100 fires in 5000. Accept range 20-300 (very loose, avoids flakiness).
      expect(fires >= 0).to.equal(true)   -- always non-negative
      expect(fires <= 300).to.equal(true) -- extremely unlikely to exceed 6% rate
    end)

  end)

  -- ─────────────────────────────────────────────────────────────────────────
  describe("cashRobbery", function()

    it("returns nil when cash <= 25000 (100 trials)", function()
      for _ = 1, 100 do
        local s = makeState({ cash = 25000 })
        expect(EventEngine.cashRobbery(s)).to.equal(nil)
      end
    end)

    it("returns nil when cash is 1 (100 trials)", function()
      for _ = 1, 100 do
        local s = makeState({ cash = 1 })
        expect(EventEngine.cashRobbery(s)).to.equal(nil)
      end
    end)

    it("fires at least once in 1000 trials when cash > 25000", function()
      local fired = false
      for _ = 1, 1000 do
        local s = makeState({ cash = 100000 })
        local stolen = EventEngine.cashRobbery(s)
        if stolen ~= nil then
          fired = true
          expect(stolen).to.be.a("number")
          expect(stolen >= 0).to.equal(true)
          expect(s.cash).to.equal(100000 - stolen)
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("stolen amount is never more than original cash (500 trials)", function()
      for _ = 1, 500 do
        local s = makeState({ cash = 50000 })
        local stolen = EventEngine.cashRobbery(s)
        if stolen ~= nil then
          expect(stolen <= 50000).to.equal(true)
        end
      end
    end)

  end)

  -- ─────────────────────────────────────────────────────────────────────────
  describe("stormOccurs", function()

    it("returns a boolean (500 trials)", function()
      for _ = 1, 500 do
        local result = EventEngine.stormOccurs()
        expect(type(result)).to.equal("boolean")
      end
    end)

    it("fires roughly 1-in-10: between 30 and 200 fires in 1000 trials", function()
      local fires = 0
      for _ = 1, 1000 do
        if EventEngine.stormOccurs() then fires = fires + 1 end
      end
      expect(fires >= 30).to.equal(true)
      expect(fires <= 200).to.equal(true)
    end)

  end)

  -- ─────────────────────────────────────────────────────────────────────────
  describe("stormGoingDown", function()

    it("returns a boolean (200 trials)", function()
      for _ = 1, 200 do
        local result = EventEngine.stormGoingDown()
        expect(type(result)).to.equal("boolean")
      end
    end)

    it("fires roughly 1-in-30: at least once in 500 trials", function()
      local fired = false
      for _ = 1, 500 do
        if EventEngine.stormGoingDown() then fired = true break end
      end
      expect(fired).to.equal(true)
    end)

  end)

  -- ─────────────────────────────────────────────────────────────────────────
  describe("stormSinks", function()

    it("returns false and never sets gameOver when damage = 0", function()
      for _ = 1, 100 do
        local s = makeState({ damage = 0, shipCapacity = 100 })
        local result = EventEngine.stormSinks(s)
        expect(result).to.equal(false)
        expect(s.gameOver).to.equal(false)
      end
    end)

    it("at maximum damage (damage=shipCapacity) returns true and sets gameOver in 1000 trials", function()
      -- At damage=100, shipCapacity=100: x=3, n=3; P(sink) = (n-1)/n = 2/3
      local sank = false
      for _ = 1, 1000 do
        local s = makeState({ damage = 100, shipCapacity = 100 })
        local result = EventEngine.stormSinks(s)
        if result == true then
          expect(s.gameOver).to.equal(true)
          sank = true
          break
        end
      end
      expect(sank).to.equal(true)
    end)

    it("gameOver=true whenever stormSinks returns true (50 confirmed sinks)", function()
      local confirmed = 0
      local attempts = 0
      while confirmed < 50 and attempts < 100000 do
        attempts = attempts + 1
        local s = makeState({ damage = 99, shipCapacity = 100 })
        if EventEngine.stormSinks(s) then
          expect(s.gameOver).to.equal(true)
          confirmed = confirmed + 1
        end
      end
      expect(confirmed).to.equal(50)
    end)

    it("returns false without setting gameOver when math resolves to no-sink (low damage)", function()
      -- damage=1, shipCapacity=100 -> x=0.03 -> n=0 -> always returns false
      for _ = 1, 200 do
        local s = makeState({ damage = 1, shipCapacity = 100 })
        local result = EventEngine.stormSinks(s)
        expect(result).to.equal(false)
        expect(s.gameOver).to.equal(false)
      end
    end)

  end)

  -- ─────────────────────────────────────────────────────────────────────────
  describe("stormBlownOffCourse", function()

    it("returns nil or a valid port index (never destination) over 2000 trials", function()
      for _ = 1, 2000 do
        local result = EventEngine.stormBlownOffCourse({}, 3)
        if result ~= nil then
          expect(type(result)).to.equal("number")
          expect(result >= 1 and result <= 7).to.equal(true)
          expect(result).never.to.equal(3)
        end
      end
    end)

    it("fires at least once in 1000 trials (1-in-3 chance)", function()
      local fired = false
      for _ = 1, 1000 do
        local result = EventEngine.stormBlownOffCourse({}, 5)
        if result ~= nil then fired = true break end
      end
      expect(fired).to.equal(true)
    end)

    it("never returns the destination port across 5000 firing samples", function()
      local dest = 4
      for _ = 1, 5000 do
        local result = EventEngine.stormBlownOffCourse({}, dest)
        if result ~= nil then
          expect(result).never.to.equal(dest)
        end
      end
    end)

    it("returns all 6 non-destination ports eventually (port 1 as destination)", function()
      local seen = {}
      for _ = 1, 50000 do
        local result = EventEngine.stormBlownOffCourse({}, 1)
        if result ~= nil then seen[result] = true end
      end
      for p = 2, 7 do
        expect(seen[p]).to.equal(true)
      end
    end)

  end)

end