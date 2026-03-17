-- PersistenceEngine.spec.lua
return function()
  local RS = game:GetService("ReplicatedStorage")
  local PE = require(RS.shared.PersistenceEngine)
  local PriceEngine = require(RS.shared.PriceEngine)

  local function makeState(overrides)
    local s = {
      startChoice      = "cash",
      cash             = 10000,
      debt             = 5000,
      bankBalance      = 2000,
      shipCapacity     = 60,
      shipCargo        = {10, 5, 0, 0},
      guns             = 2,
      damage           = 10,
      pirateBase       = 10,
      warehouseCargo   = {20, 0, 0, 0},
      basePrices       = (function()
        local bp = {}
        for p = 1, 7 do
          bp[p] = {}
          for g = 1, 4 do bp[p][g] = p * 10 + g end
        end
        return bp
      end)(),
      currentPort      = 3,
      month            = 6,
      year             = 1862,
      turnsElapsed     = 5,
      liYuenProtection = 0,
      wuWarningGiven   = true,
      bankruptcyCount  = 1,
      enemyBaseDamage  = 11,
      enemyBaseHP      = 20,
      gameOver         = false,
      gameOverReason   = nil,
      finalScore       = nil,
      finalRating      = nil,
      seenTutorial     = true,
    }
    if overrides then
      for k, v in pairs(overrides) do s[k] = v end
    end
    return s
  end

  describe("serialize", function()
    it("includes version = 1", function()
      expect(PE.serialize(makeState()).version).to.equal(1)
    end)

    it("includes all canonical fields including pirateBase, wuWarningGiven, bankruptcyCount", function()
      local data = PE.serialize(makeState())
      expect(data.startChoice).to.equal("cash")
      expect(data.pirateBase).to.equal(10)
      expect(data.wuWarningGiven).to.equal(true)
      expect(data.bankruptcyCount).to.equal(1)
      expect(data.seenTutorial).to.equal(true)
      expect(data.shipCargo[1]).to.equal(10)
      expect(data.warehouseCargo[1]).to.equal(20)
      expect(data.basePrices[1][1]).to.equal(11)
    end)

    it("does not mutate state (version not added to original)", function()
      local s = makeState()
      PE.serialize(s)
      expect(s.version).to.equal(nil)
    end)

    it("does not include computed fields", function()
      local data = PE.serialize(makeState())
      expect(data.holdSpace).to.equal(nil)
      expect(data.warehouseUsed).to.equal(nil)
      expect(data.currentPrices).to.equal(nil)
      expect(data.combat).to.equal(nil)
    end)
  end)

  describe("deserialize", function()
    it("returns nil for nil input", function()
      expect(PE.deserialize(nil, PriceEngine)).to.equal(nil)
    end)

    it("returns nil for data with missing version", function()
      local data = PE.serialize(makeState())
      data.version = nil
      expect(PE.deserialize(data, PriceEngine)).to.equal(nil)
    end)

    it("restores all canonical fields", function()
      local s = makeState()
      local restored = PE.deserialize(PE.serialize(s), PriceEngine)
      expect(restored.cash).to.equal(10000)
      expect(restored.startChoice).to.equal("cash")
      expect(restored.pirateBase).to.equal(10)
      expect(restored.wuWarningGiven).to.equal(true)
      expect(restored.bankruptcyCount).to.equal(1)
      expect(restored.seenTutorial).to.equal(true)
      expect(restored.shipCargo[1]).to.equal(10)
      expect(restored.warehouseCargo[1]).to.equal(20)
    end)

    it("computes holdSpace from restored shipCapacity and shipCargo (not from constants)", function()
      -- shipCapacity=60, shipCargo={10,5,0,0}=15, guns=2 → 60-15-20=25
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.holdSpace).to.equal(60 - 10 - 5 - 0 - 0 - 2*10)
    end)

    it("computes warehouseUsed from warehouseCargo", function()
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.warehouseUsed).to.equal(20)
    end)

    it("sets destination to currentPort", function()
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.destination).to.equal(3)
    end)

    it("computes currentPrices (non-nil table)", function()
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.currentPrices).never.to.equal(nil)
      expect(type(restored.currentPrices)).to.equal("table")
    end)

    it("resets ephemeral fields to correct defaults", function()
      local s = makeState()
      s.combat    = { someField = true }
      s.shipOffer = { repairRate = 100 }
      local restored = PE.deserialize(PE.serialize(s), PriceEngine)
      expect(restored.combat).to.equal(nil)
      expect(restored.shipOffer).to.equal(nil)
      expect(restored.inWuSession).to.equal(false)
      expect(restored.liYuenOfferCost).to.equal(nil)
      expect(restored.pendingTutorial).to.equal(nil)
    end)

    it("defaults seenTutorial to false when absent from saved data", function()
      local data = PE.serialize(makeState())
      data.seenTutorial = nil  -- simulate save from older build
      local restored = PE.deserialize(data, PriceEngine)
      expect(restored.seenTutorial).to.equal(false)
    end)
  end)

  describe("dataStoreRetry", function()
    it("returns result on first-call success", function()
      local result = PE.dataStoreRetry(function() return "ok" end, 3)
      expect(result).to.equal("ok")
    end)

    it("retries on failure and returns result on later success", function()
      -- NOTE: this test waits ~1s (retry backoff). That is expected and correct.
      local callCount = 0
      local result = PE.dataStoreRetry(function()
        callCount = callCount + 1
        if callCount < 2 then error("fail") end
        return "success"
      end, 3)
      expect(result).to.equal("success")
      expect(callCount).to.equal(2)
    end)

    it("returns nil after exhausting all attempts", function()
      -- NOTE: this test waits ~3s (1s+2s backoff). That is expected and correct.
      local callCount = 0
      local result = PE.dataStoreRetry(function()
        callCount = callCount + 1
        error("always fail")
      end, 3)
      expect(result).to.equal(nil)
      expect(callCount).to.equal(3)
    end)
  end)
end
