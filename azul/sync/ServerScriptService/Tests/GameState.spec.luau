local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameState = require(ReplicatedStorage.shared.GameState)
local Constants = require(ReplicatedStorage.shared.Constants)

return function()
  describe("GameState.newGame", function()
    it("cash start: correct opening values", function()
      local s = GameState.newGame("cash")
      expect(s.cash).to.equal(Constants.CASH_START_CASH)
      expect(s.debt).to.equal(Constants.CASH_START_DEBT)
      expect(s.shipCapacity).to.equal(Constants.CASH_START_HOLD)
      expect(s.holdSpace).to.equal(Constants.CASH_START_HOLD)
      expect(s.guns).to.equal(Constants.CASH_START_GUNS)
      expect(s.pirateBase).to.equal(Constants.CASH_START_BP)
    end)

    it("guns start: correct opening values", function()
      local s = GameState.newGame("guns")
      expect(s.cash).to.equal(Constants.GUNS_START_CASH)
      expect(s.debt).to.equal(Constants.GUNS_START_DEBT)
      expect(s.guns).to.equal(Constants.GUNS_START_GUNS)
      expect(s.shipCapacity).to.equal(Constants.GUNS_START_HOLD)
    end)

    it("starts at Hong Kong (port 1), TI=1, January 1860", function()
      local s = GameState.newGame("cash")
      expect(s.currentPort).to.equal(1)
      expect(s.month).to.equal(1)
      expect(s.year).to.equal(1860)
      expect(s.turnsElapsed).to.equal(1)
    end)

    it("has empty cargo arrays (4 goods, hold and warehouse)", function()
      local s = GameState.newGame("cash")
      expect(#s.shipCargo).to.equal(4)
      expect(#s.warehouseCargo).to.equal(4)
      for i = 1, 4 do
        expect(s.shipCargo[i]).to.equal(0)
        expect(s.warehouseCargo[i]).to.equal(0)
      end
    end)

    it("bank starts at 0", function()
      local s = GameState.newGame("cash")
      expect(s.bankBalance).to.equal(0)
    end)

    it("has empty prices array (4 goods)", function()
      local s = GameState.newGame("cash")
      expect(#s.currentPrices).to.equal(4)
    end)

    it("destination is 0 (D=0 guard for first turn)", function()
      local s = GameState.newGame("cash")
      expect(s.destination).to.equal(0)
    end)

    it("basePrices is a deep copy (mutations don't affect Constants)", function()
      local s = GameState.newGame("cash")
      local original = Constants.BASE_PRICES[1][1]
      s.basePrices[1][1] = original + 999
      expect(Constants.BASE_PRICES[1][1]).to.equal(original)
    end)

    it("guns start: pirateBase is 7", function()
      local s = GameState.newGame("guns")
      expect(s.pirateBase).to.equal(Constants.GUNS_START_BP)
    end)
  end)
end
