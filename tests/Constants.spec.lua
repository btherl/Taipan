local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.shared.Constants)

return function()
  describe("Constants", function()
    it("has 7 port names (indices 1-7)", function()
      expect(#Constants.PORT_NAMES).to.equal(7)
      expect(Constants.PORT_NAMES[1]).to.equal("Hong Kong")
      expect(Constants.PORT_NAMES[7]).to.equal("Batavia")
    end)

    it("has 4 good names", function()
      expect(#Constants.GOOD_NAMES).to.equal(4)
      expect(Constants.GOOD_NAMES[1]).to.equal("Opium")
      expect(Constants.GOOD_NAMES[4]).to.equal("General Cargo")
    end)

    it("has base price matrix [7 ports][4 goods]", function()
      expect(#Constants.BASE_PRICES).to.equal(7)
      for _, row in ipairs(Constants.BASE_PRICES) do
        expect(#row).to.equal(4)
      end
    end)

    it("has correct base price for HK Opium (11)", function()
      expect(Constants.BASE_PRICES[1][1]).to.equal(11)
    end)

    it("has correct base price for Batavia General Cargo (16)", function()
      expect(Constants.BASE_PRICES[7][4]).to.equal(16)
    end)

    it("has starting config values", function()
      expect(Constants.WAREHOUSE_CAPACITY).to.equal(10000)
      expect(Constants.CASH_START_CASH).to.equal(400)
      expect(Constants.CASH_START_DEBT).to.equal(5000)
      expect(Constants.CASH_START_HOLD).to.equal(60)
      expect(Constants.GUNS_START_HOLD).to.equal(10)
      expect(Constants.GUNS_START_GUNS).to.equal(5)
    end)

    it("PRICE_SCALE has correct values (1000, 100, 10, 1)", function()
      expect(Constants.PRICE_SCALE[1]).to.equal(1000)
      expect(Constants.PRICE_SCALE[2]).to.equal(100)
      expect(Constants.PRICE_SCALE[3]).to.equal(10)
      expect(Constants.PRICE_SCALE[4]).to.equal(1)
    end)

    it("HONG_KONG is port index 1", function()
      expect(Constants.HONG_KONG).to.equal(1)
    end)

    it("financial rates are correct", function()
      expect(Constants.BANK_INTEREST_RATE).to.equal(0.005)
      expect(Constants.DEBT_INTEREST_RATE).to.equal(0.1)
    end)
  end)
end
