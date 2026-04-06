local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PriceEngine = require(ReplicatedStorage.shared.PriceEngine)
local Constants   = require(ReplicatedStorage.shared.Constants)

return function()
  describe("PriceEngine.calculatePrices", function()
    it("returns a table of 4 prices", function()
      local prices = PriceEngine.calculatePrices(Constants.BASE_PRICES, 1)
      expect(#prices).to.equal(4)
    end)

    it("_basePrice produces values in expected range for spices", function()
      -- HK spices BP=11, scale=1000
      -- randFactor range: 1-3 -> prices: floor(11/2*1*1000) to floor(11/2*3*1000)
      local minPrice = PriceEngine._basePrice(11, 1, 1)  -- = floor(5.5*1000) = 5500
      local maxPrice = PriceEngine._basePrice(11, 1, 3)  -- = floor(16.5*1000) = 16500
      expect(minPrice).to.equal(5500)
      expect(maxPrice).to.equal(16500)
      -- Verify all randFactors produce values in this range
      for rf = 1, 3 do
        local p = PriceEngine._basePrice(11, 1, rf)
        expect(p >= minPrice).to.equal(true)
        expect(p <= maxPrice).to.equal(true)
      end
    end)

    it("General Cargo price is much lower than Spices", function()
      -- General Cargo scale=1 vs Spices scale=1000
      -- Even at max BP=16, General max normal = 16/2*3*1 = 24
      -- Spices at min BP=10, min normal = 10/2*1*1000 = 5000
      local bp = Constants.BASE_PRICES
      local totalSpices, totalGeneral = 0, 0
      for _ = 1, 50 do
        local prices = PriceEngine.calculatePrices(bp, 1)
        totalSpices = totalSpices + prices[1]
        totalGeneral = totalGeneral + prices[4]
      end
      expect(totalSpices > totalGeneral * 100).to.equal(true)
    end)

    it("uses port-specific base prices (HK vs Shanghai differ)", function()
      -- Shanghai spices BP=16 vs HK BP=11 -- Shanghai prices should average higher
      local bp = Constants.BASE_PRICES
      local hkTotal, shTotal = 0, 0
      for _ = 1, 500 do
        hkTotal = hkTotal + PriceEngine.calculatePrices(bp, 1)[1]
        shTotal = shTotal + PriceEngine.calculatePrices(bp, 2)[1]
      end
      -- Shanghai average should be higher (ratio ~16/11 ~= 1.45)
      expect(shTotal > hkTotal).to.equal(true)
    end)
  end)

  describe("PriceEngine crash/boom events", function()
    it("crash produces price ~1/5 of normal", function()
      -- We can't force a crash, but we can verify the formula
      local normalPrice = PriceEngine._basePrice(11, 1, 2)  -- BP=11, good=1, rand=2
      local crashPrice  = PriceEngine._crashPrice(normalPrice)
      expect(crashPrice).to.equal(math.floor(normalPrice / 5))
    end)

    it("boom multiplies price by 5-9x", function()
      local normalPrice = PriceEngine._basePrice(11, 1, 2)
      for mult = 5, 9 do
        local boomedPrice = PriceEngine._boomPrice(normalPrice, mult)
        expect(boomedPrice).to.equal(math.floor(normalPrice * mult))
      end
    end)

    it("calculatePrices returns nil event when no crash/boom", function()
      -- Run 1000 trials: at least some should have no event
      local sawNil = false
      for _ = 1, 1000 do
        local _, event = PriceEngine.calculatePrices(Constants.BASE_PRICES, 1)
        if event == nil then sawNil = true break end
      end
      expect(sawNil).to.equal(true)
    end)

    it("calculatePrices returns event table with good/direction/price on crash/boom", function()
      local sawEvent = false
      for _ = 1, 1000 do
        local prices, event = PriceEngine.calculatePrices(Constants.BASE_PRICES, 1)
        if event ~= nil then
          expect(type(event.good)).to.equal("number")
          expect(event.good >= 1 and event.good <= 4).to.equal(true)
          expect(event.direction == "drop" or event.direction == "rise").to.equal(true)
          expect(event.price).to.equal(prices[event.good])
          sawEvent = true
          break
        end
      end
      expect(sawEvent).to.equal(true)
    end)
  end)

  describe("PriceEngine.applyAnnualDrift", function()
    it("increments each base price by 0 or 1 (never more, never less)", function()
      -- Deep copy a known matrix to test mutation
      local bp = {}
      for p = 1, 7 do
        bp[p] = {}
        for g = 1, 4 do
          bp[p][g] = Constants.BASE_PRICES[p][g]
        end
      end
      local before = {}
      for p = 1, 7 do
        before[p] = {}
        for g = 1, 4 do
          before[p][g] = bp[p][g]
        end
      end

      PriceEngine.applyAnnualDrift(bp)

      for p = 1, 7 do
        for g = 1, 4 do
          local delta = bp[p][g] - before[p][g]
          expect(delta >= 0).to.equal(true)
          expect(delta <= 1).to.equal(true)
        end
      end
    end)
  end)
end
