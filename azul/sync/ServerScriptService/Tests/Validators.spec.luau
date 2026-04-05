local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Validators = require(ReplicatedStorage.shared.Validators)
local GameState  = require(ReplicatedStorage.shared.GameState)

return function()
  describe("Validators.canBuy", function()
    it("returns true when player can afford and has hold space", function()
      local s = GameState.newGame("cash")  -- 400 cash, 60 hold
      expect(Validators.canBuy(s, 1, 1, 100)).to.equal(true)  -- buy 1 spices at 100
    end)

    it("returns false when price exceeds cash", function()
      local s = GameState.newGame("cash")
      expect(Validators.canBuy(s, 1, 1, 1000)).to.equal(false) -- 1 spices at 1000 > 400 cash
    end)

    it("returns false when quantity exceeds hold space", function()
      local s = GameState.newGame("cash")
      s.cash = 1000000
      expect(Validators.canBuy(s, 61, 1, 1)).to.equal(false)  -- 61 units, only 60 hold
    end)

    it("returns true when total cost exactly equals cash", function()
      local s = GameState.newGame("cash")  -- 400 cash
      -- Exactly spend all cash: 4 units at 100 each = 400
      expect(Validators.canBuy(s, 4, 4, 100)).to.equal(true)
    end)

    it("returns true when quantity exactly fills hold", function()
      local s = GameState.newGame("cash")  -- 60 hold
      s.cash = 1000000
      expect(Validators.canBuy(s, 60, 4, 1)).to.equal(true)
    end)
  end)

  describe("Validators.canSell", function()
    it("returns true when player has the goods", function()
      local s = GameState.newGame("cash")
      s.shipCargo[2] = 10  -- 10 silk on ship
      expect(Validators.canSell(s, 5, 2)).to.equal(true)
    end)

    it("returns false when player has fewer goods than requested", function()
      local s = GameState.newGame("cash")
      s.shipCargo[2] = 3
      expect(Validators.canSell(s, 5, 2)).to.equal(false)
    end)

    it("returns true when selling exactly all held goods", function()
      local s = GameState.newGame("cash")
      s.shipCargo[3] = 5
      expect(Validators.canSell(s, 5, 3)).to.equal(true)
    end)

    it("returns false when goodIndex is out of bounds", function()
      local s = GameState.newGame("cash")
      expect(Validators.canSell(s, 1, 99)).to.equal(false)  -- nil guard
    end)
  end)

  describe("Validators.holdSpaceFor", function()
    it("returns correct available hold space", function()
      local s = GameState.newGame("cash")  -- 60 hold, 0 used
      expect(Validators.holdSpaceFor(s)).to.equal(60)
    end)

    it("returns the current holdSpace value", function()
      local s = GameState.newGame("cash")
      s.holdSpace = 40
      expect(Validators.holdSpaceFor(s)).to.equal(40)
    end)
  end)
end
