-- EventEngine.spec.lua
-- Tests for random arrival events and storm.
-- Run via TestEZ in Roblox Studio.

return function()
  local EventEngine = require(game.ReplicatedStorage.shared.EventEngine)

  -- Helper: make a default state
  local function makeState(overrides)
    local s = {
      cash             = 50000,
      damage           = 0,
      shipCapacity     = 60,
      holdSpace        = 60,
      shipCargo        = {100, 0, 0, 0},  -- 100 opium in hold
      warehouseCargo   = {0, 0, 0, 0},
      warehouseUsed    = 0,
      currentPort      = 2,               -- non-HK port
      destination      = 3,
      gameOver         = false,
    }
    if overrides then
      for k, v in pairs(overrides) do
        s[k] = v
      end
    end
    return s
  end

  describe("opiumSeizure", function()
    it("returns nil when at Hong Kong (port 1)", function()
      for _ = 1, 50 do
        local s = makeState({ currentPort = 1 })
        expect(EventEngine.opiumSeizure(s)).to.equal(nil)
      end
    end)

    it("returns nil when no opium in hold", function()
      for _ = 1, 50 do
        local s = makeState({ shipCargo = {0, 0, 0, 0} })
        expect(EventEngine.opiumSeizure(s)).to.equal(nil)
      end
    end)

    it("when fires: sets shipCargo[1]=0 and increases holdSpace", function()
      local fired = false
      for _ = 1, 2000 do
        local s = makeState({ shipCargo = {50, 0, 0, 0}, holdSpace = 10 })
        local result = EventEngine.opiumSeizure(s)
        if result ~= nil then
          expect(s.shipCargo[1]).to.equal(0)
          expect(s.holdSpace).to.equal(60)  -- 10 + 50
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("when fires: fine is in range [0, floor(cash/1.8))", function()
      local fired = false
      for _ = 1, 2000 do
        local s = makeState({ cash = 1800, shipCargo = {10, 0, 0, 0} })
        local fine = EventEngine.opiumSeizure(s)
        if fine ~= nil then
          local maxFine = math.floor(1800 / 1.8)  -- = 1000
          expect(fine >= 0).to.equal(true)
          expect(fine < maxFine).to.equal(true)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("cash can go negative (fine can exceed cash)", function()
      -- With cash=1 and large opium, fine = FN_R(1/1.8) = FN_R(0) = 0, so cash stays 1.
      -- With cash=200 and opium, fine can be 0 to floor(200/1.8)=111. If fine>cash, negative.
      -- We just verify no error is thrown and cash is mutated.
      local fired = false
      for _ = 1, 2000 do
        local s = makeState({ cash = 100, shipCargo = {20, 0, 0, 0} })
        local fine = EventEngine.opiumSeizure(s)
        if fine ~= nil then
          expect(s.cash).to.equal(100 - fine)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("returns nil most of the time (expect < 30 fires in 100 trials)", function()
      local fires = 0
      for _ = 1, 100 do
        local s = makeState()
        if EventEngine.opiumSeizure(s) ~= nil then fires = fires + 1 end
      end
      expect(fires < 30).to.equal(true)
    end)
  end)

  describe("cargoTheft", function()
    it("returns false when warehouse is empty", function()
      for _ = 1, 50 do
        local s = makeState({ warehouseCargo = {0, 0, 0, 0} })
        expect(EventEngine.cargoTheft(s)).to.equal(false)
      end
    end)

    it("returns false most of the time (expect < 10 fires in 100 trials)", function()
      local fires = 0
      for _ = 1, 100 do
        local s = makeState({ warehouseCargo = {100, 100, 100, 100}, warehouseUsed = 400 })
        if EventEngine.cargoTheft(s) then fires = fires + 1 end
      end
      expect(fires < 10).to.equal(true)
    end)

    it("when fires: each warehouse good is <= original and warehouseUsed is updated", function()
      local fired = false
      for _ = 1, 5000 do
        local origCargo = {200, 150, 100, 50}
        local origUsed = 500
        local s = makeState({
          warehouseCargo = {origCargo[1], origCargo[2], origCargo[3], origCargo[4]},
          warehouseUsed = origUsed
        })
        if EventEngine.cargoTheft(s) then
          local newUsed = 0
          for i = 1, 4 do
            expect(s.warehouseCargo[i] <= origCargo[i]).to.equal(true)
            expect(s.warehouseCargo[i] >= 0).to.equal(true)
            newUsed = newUsed + s.warehouseCargo[i]
          end
          expect(s.warehouseUsed).to.equal(newUsed)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("when fires: new qty is in range [0, floor(old/1.8))", function()
      local fired = false
      for _ = 1, 5000 do
        local s = makeState({
          warehouseCargo = {180, 0, 0, 0},  -- floor(180/1.8) = 100
          warehouseUsed = 180
        })
        if EventEngine.cargoTheft(s) then
          expect(s.warehouseCargo[1] >= 0).to.equal(true)
          expect(s.warehouseCargo[1] < 100).to.equal(true)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)
  end)

  describe("cashRobbery", function()
    it("returns nil when cash <= 25000", function()
      for _ = 1, 50 do
        local s = makeState({ cash = 25000 })
        expect(EventEngine.cashRobbery(s)).to.equal(nil)
      end
    end)

    it("returns nil most of the time when cash > 25000 (expect < 30 in 100)", function()
      local fires = 0
      for _ = 1, 100 do
        local s = makeState({ cash = 50000 })
        if EventEngine.cashRobbery(s) ~= nil then fires = fires + 1 end
      end
      expect(fires < 30).to.equal(true)
    end)

    it("when fires: cash decreases by stolen amount and returns stolen amount", function()
      local fired = false
      for _ = 1, 2000 do
        local s = makeState({ cash = 50000 })
        local stolen = EventEngine.cashRobbery(s)
        if stolen ~= nil then
          expect(s.cash).to.equal(50000 - stolen)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)

    it("stolen is in range [0, floor(CA/1.4))", function()
      local fired = false
      for _ = 1, 2000 do
        local s = makeState({ cash = 28000 })
        local stolen = EventEngine.cashRobbery(s)
        if stolen ~= nil then
          local maxStolen = math.floor(28000 / 1.4)  -- = 20000
          expect(stolen >= 0).to.equal(true)
          expect(stolen < maxStolen).to.equal(true)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)
  end)

  describe("stormOccurs", function()
    it("returns false most of the time (expect < 30 true in 100 trials)", function()
      local trues = 0
      for _ = 1, 100 do
        if EventEngine.stormOccurs() then trues = trues + 1 end
      end
      expect(trues < 30).to.equal(true)
    end)

    it("returns true at least once in 200 trials", function()
      local found = false
      for _ = 1, 200 do
        if EventEngine.stormOccurs() then found = true break end
      end
      expect(found).to.equal(true)
    end)
  end)

  describe("stormGoingDown", function()
    it("returns false most of the time (expect < 10 true in 100 trials)", function()
      local trues = 0
      for _ = 1, 100 do
        if EventEngine.stormGoingDown() then trues = trues + 1 end
      end
      expect(trues < 10).to.equal(true)
    end)
  end)

  describe("stormSinks", function()
    it("returns false when damage = 0 (undamaged ship never sinks in storm)", function()
      for _ = 1, 100 do
        local s = makeState({ damage = 0, shipCapacity = 60 })
        expect(EventEngine.stormSinks(s)).to.equal(false)
        expect(s.gameOver).to.equal(false)
      end
    end)

    it("returns false when damage/SC*3 < 1 (x=1.0 → n=1 → only value is 0 → always false)", function()
      -- damage = 20, SC = 60: x = 20/60*3 = 1.0, n=1, math.random(0,0)=0, 0 != 0 is false
      for _ = 1, 50 do
        local s = makeState({ damage = 20, shipCapacity = 60 })
        expect(EventEngine.stormSinks(s)).to.equal(false)
      end
    end)

    it("returns true at least once in 100 trials when fully damaged (100%)", function()
      local sank = false
      for _ = 1, 100 do
        local s = makeState({ damage = 60, shipCapacity = 60 })
        if EventEngine.stormSinks(s) then
          sank = true
          break
        end
      end
      expect(sank).to.equal(true)
    end)

    it("sets gameOver=true when ship sinks", function()
      local sank = false
      for _ = 1, 500 do
        local s = makeState({ damage = 60, shipCapacity = 60 })
        if EventEngine.stormSinks(s) then
          expect(s.gameOver).to.equal(true)
          sank = true
          break
        end
      end
      expect(sank).to.equal(true)
    end)
  end)

  describe("stormBlownOffCourse", function()
    it("returns nil most of the time (expect < 50 non-nil in 100 trials)", function()
      local nils = 0
      for _ = 1, 100 do
        local s = makeState()
        if EventEngine.stormBlownOffCourse(s, 3) == nil then nils = nils + 1 end
      end
      expect(nils > 50).to.equal(true)
    end)

    it("returns non-nil at least once in 100 trials", function()
      local found = false
      for _ = 1, 100 do
        local s = makeState()
        if EventEngine.stormBlownOffCourse(s, 3) ~= nil then found = true break end
      end
      expect(found).to.equal(true)
    end)

    it("when returns non-nil: port is in range 1..7", function()
      for _ = 1, 1000 do
        local s = makeState()
        local port = EventEngine.stormBlownOffCourse(s, 3)
        if port ~= nil then
          expect(port >= 1).to.equal(true)
          expect(port <= 7).to.equal(true)
        end
      end
    end)

    it("when returns non-nil: port != destination", function()
      for _ = 1, 1000 do
        local s = makeState()
        local port = EventEngine.stormBlownOffCourse(s, 3)
        if port ~= nil then
          expect(port ~= 3).to.equal(true)
        end
      end
    end)
  end)
end
