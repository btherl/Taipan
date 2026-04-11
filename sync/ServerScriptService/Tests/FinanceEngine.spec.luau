-- FinanceEngine.spec.lua
-- Tests for the financial logic module.
-- Run via TestEZ in Roblox Studio.

return function()
  local FinanceEngine = require(game.ReplicatedStorage.shared.FinanceEngine)

  -- Helper: create a default state with optional overrides
  local function makeState(overrides)
    local s = {
      cash             = 400,
      bankBalance      = 0,
      debt             = 5000,
      guns             = 0,
      shipCargo        = {0, 0, 0, 0},
      warehouseCargo   = {0, 0, 0, 0},
      turnsElapsed     = 1,
      currentPort      = 1,   -- 1 = Hong Kong
      destination      = 1,   -- non-zero = has traveled
      wuWarningGiven   = false,
      liYuenProtection = 0,
      bankruptcyCount  = 0,
      liYuenOfferCost  = nil,
    }
    if overrides then
      for k, v in pairs(overrides) do
        s[k] = v
      end
    end
    return s
  end

  describe("isBankrupt", function()
    it("returns false when cash > 0", function()
      local s = makeState({ cash = 1, bankBalance = 0, guns = 0 })
      expect(FinanceEngine.isBankrupt(s)).to.equal(false)
    end)

    it("returns false when bankBalance > 0", function()
      local s = makeState({ cash = 0, bankBalance = 1, guns = 0 })
      expect(FinanceEngine.isBankrupt(s)).to.equal(false)
    end)

    it("returns false when guns > 0", function()
      local s = makeState({ cash = 0, bankBalance = 0, guns = 1 })
      expect(FinanceEngine.isBankrupt(s)).to.equal(false)
    end)

    it("returns false when shipCargo has goods", function()
      local s = makeState({ cash = 0, bankBalance = 0, guns = 0,
        shipCargo = {10, 0, 0, 0}, warehouseCargo = {0, 0, 0, 0} })
      expect(FinanceEngine.isBankrupt(s)).to.equal(false)
    end)

    it("returns true when all assets are zero", function()
      local s = makeState({ cash = 0, bankBalance = 0, guns = 0,
        shipCargo = {0, 0, 0, 0}, warehouseCargo = {0, 0, 0, 0} })
      expect(FinanceEngine.isBankrupt(s)).to.equal(true)
    end)
  end)

  describe("bankruptcyLoan", function()
    it("increments bankruptcyCount from 0 to 1", function()
      local s = makeState({ cash = 0, bankruptcyCount = 0 })
      FinanceEngine.bankruptcyLoan(s)
      expect(s.bankruptcyCount).to.equal(1)
    end)

    it("adds cash in range 500..1999 (run 200 times)", function()
      local allInRange = true
      for _ = 1, 200 do
        local s = makeState({ cash = 0, debt = 0, bankruptcyCount = 0 })
        local loan = FinanceEngine.bankruptcyLoan(s)
        if loan < 500 or loan > 1999 then allInRange = false end
      end
      expect(allInRange).to.equal(true)
    end)

    it("adds debt >= 1500 on first bankruptcy (BL%=1, min repay = 0*1+1500)", function()
      local s = makeState({ cash = 0, debt = 0, bankruptcyCount = 0 })
      local _, repay = FinanceEngine.bankruptcyLoan(s)
      expect(repay >= 1500).to.equal(true)
    end)
  end)

  describe("wuWarningCheck", function()
    it("returns nil when debt <= 10000", function()
      local s = makeState({ debt = 10000, wuWarningGiven = false, destination = 1 })
      expect(FinanceEngine.wuWarningCheck(s)).to.equal(nil)
    end)

    it("returns nil when wuWarningGiven is true", function()
      local s = makeState({ debt = 10001, wuWarningGiven = true, destination = 1 })
      expect(FinanceEngine.wuWarningCheck(s)).to.equal(nil)
    end)

    it("returns nil when destination = 0 (game start)", function()
      local s = makeState({ debt = 10001, wuWarningGiven = false, destination = 0 })
      expect(FinanceEngine.wuWarningCheck(s)).to.equal(nil)
    end)

    it("returns number in 50..149 when it fires", function()
      local s = makeState({ debt = 10001, wuWarningGiven = false, destination = 1 })
      local braves = FinanceEngine.wuWarningCheck(s)
      expect(braves ~= nil).to.equal(true)
      expect(braves >= 50).to.equal(true)
      expect(braves <= 149).to.equal(true)
    end)

    it("sets wuWarningGiven to true when it fires", function()
      local s = makeState({ debt = 10001, wuWarningGiven = false, destination = 1 })
      FinanceEngine.wuWarningCheck(s)
      expect(s.wuWarningGiven).to.equal(true)
    end)
  end)

  describe("canRepay", function()
    it("returns true when debt > 0 and cash > 0", function()
      local s = makeState({ debt = 100, cash = 50 })
      expect(FinanceEngine.canRepay(s)).to.equal(true)
    end)

    it("returns false when debt = 0", function()
      local s = makeState({ debt = 0, cash = 50 })
      expect(FinanceEngine.canRepay(s)).to.equal(false)
    end)

    it("returns false when cash = 0", function()
      local s = makeState({ debt = 100, cash = 0 })
      expect(FinanceEngine.canRepay(s)).to.equal(false)
    end)
  end)

  describe("repay", function()
    it("reduces cash and debt by amount", function()
      local s = makeState({ cash = 400, debt = 5000 })
      FinanceEngine.repay(s, 100)
      expect(s.cash).to.equal(300)
      expect(s.debt).to.equal(4900)
    end)

    it("returns false when amount > cash", function()
      local s = makeState({ cash = 100, debt = 5000 })
      expect(FinanceEngine.repay(s, 101)).to.equal(false)
      expect(s.cash).to.equal(100)  -- unchanged
    end)

    it("allows overpayment: debt goes negative", function()
      local s = makeState({ cash = 400, debt = 50 })
      expect(FinanceEngine.repay(s, 51)).to.equal(true)
      expect(s.debt).to.equal(-1)
      expect(s.cash).to.equal(349)
    end)
  end)

  describe("maxBorrow", function()
    it("returns 2 * cash", function()
      local s = makeState({ cash = 400 })
      expect(FinanceEngine.maxBorrow(s)).to.equal(800)
    end)
  end)

  describe("borrow", function()
    it("increases cash and debt by amount", function()
      local s = makeState({ cash = 400, debt = 0 })
      FinanceEngine.borrow(s, 200)
      expect(s.cash).to.equal(600)
      expect(s.debt).to.equal(200)
    end)

    it("returns false when amount > 2 * cash", function()
      local s = makeState({ cash = 400 })
      expect(FinanceEngine.borrow(s, 801)).to.equal(false)
      expect(s.cash).to.equal(400)  -- unchanged
    end)
  end)

  describe("wuEnforcers", function()
    it("returns false when debt <= 20000", function()
      local s = makeState({ debt = 20000, cash = 500 })
      -- Run multiple times — should always be false with debt exactly 20000
      local anyTrue = false
      for _ = 1, 50 do
        local s2 = makeState({ debt = 20000, cash = 500 })
        if FinanceEngine.wuEnforcers(s2) then anyTrue = true end
      end
      expect(anyTrue).to.equal(false)
    end)

    it("sets cash=0 when enforcers fire (run 1000 times with high debt)", function()
      local firedOnce = false
      for _ = 1, 1000 do
        local s = makeState({ debt = 20001, cash = 999 })
        if FinanceEngine.wuEnforcers(s) then
          firedOnce = true
          expect(s.cash).to.equal(0)
          break
        end
      end
      expect(firedOnce).to.equal(true)
    end)
  end)

  describe("bankDeposit", function()
    it("moves amount from cash to bankBalance", function()
      local s = makeState({ cash = 400, bankBalance = 100 })
      FinanceEngine.bankDeposit(s, 200)
      expect(s.cash).to.equal(200)
      expect(s.bankBalance).to.equal(300)
    end)

    it("returns false when amount > cash", function()
      local s = makeState({ cash = 100, bankBalance = 0 })
      expect(FinanceEngine.bankDeposit(s, 101)).to.equal(false)
      expect(s.cash).to.equal(100)
    end)
  end)

  describe("bankWithdraw", function()
    it("moves amount from bankBalance to cash", function()
      local s = makeState({ cash = 100, bankBalance = 500 })
      FinanceEngine.bankWithdraw(s, 300)
      expect(s.cash).to.equal(400)
      expect(s.bankBalance).to.equal(200)
    end)

    it("returns false when amount > bankBalance", function()
      local s = makeState({ cash = 100, bankBalance = 50 })
      expect(FinanceEngine.bankWithdraw(s, 51)).to.equal(false)
      expect(s.bankBalance).to.equal(50)
    end)
  end)

  describe("liYuenProtectionCost", function()
    it("TI<=12: returns value in range [0, floor(cash/1.8))", function()
      local s = makeState({ turnsElapsed = 5, cash = 1800 })
      local maxExpected = math.floor(1800 / 1.8)  -- = 1000
      local allInRange = true
      for _ = 1, 100 do
        local s2 = makeState({ turnsElapsed = 5, cash = 1800 })
        local cost = FinanceEngine.liYuenProtectionCost(s2)
        if cost < 0 or cost >= maxExpected then allInRange = false end
      end
      expect(allInRange).to.equal(true)
    end)

    it("TI>12: returns value >= 1000*TI (deterministic minimum component)", function()
      local s = makeState({ turnsElapsed = 13, cash = 1000 })
      local minExpected = 1000 * 13
      local allAboveMin = true
      for _ = 1, 50 do
        local s2 = makeState({ turnsElapsed = 13, cash = 1000 })
        local cost = FinanceEngine.liYuenProtectionCost(s2)
        if cost < minExpected then allAboveMin = false end
      end
      expect(allAboveMin).to.equal(true)
    end)
  end)

  describe("liYuenLapse", function()
    it("returns false when already unprotected (LI=0)", function()
      local s = makeState({ liYuenProtection = 0 })
      expect(FinanceEngine.liYuenLapse(s)).to.equal(false)
      expect(s.liYuenProtection).to.equal(0)
    end)

    it("returns false most of the time when protected (at least 170/200 false)", function()
      local falseCount = 0
      for _ = 1, 200 do
        local s = makeState({ liYuenProtection = 1 })
        if not FinanceEngine.liYuenLapse(s) then falseCount = falseCount + 1 end
      end
      expect(falseCount >= 170).to.equal(true)
    end)
  end)

  describe("liYuenWarningFires", function()
    it("returns false when already protected (LI=1)", function()
      -- LI=1 means protected; function should always return false regardless of port
      for _ = 1, 50 do
        local s = makeState({ liYuenProtection = 1, currentPort = 2 })
        expect(FinanceEngine.liYuenWarningFires(s)).to.equal(false)
      end
    end)

    it("returns false when at Hong Kong (currentPort=1) even if unprotected", function()
      for _ = 1, 50 do
        local s = makeState({ liYuenProtection = 0, currentPort = 1 })
        expect(FinanceEngine.liYuenWarningFires(s)).to.equal(false)
      end
    end)

    it("fires at least once in 100 attempts when unprotected at non-HK port", function()
      local firedOnce = false
      for _ = 1, 100 do
        local s = makeState({ liYuenProtection = 0, currentPort = 2 })
        if FinanceEngine.liYuenWarningFires(s) then
          firedOnce = true
          break
        end
      end
      expect(firedOnce).to.equal(true)
    end)
  end)

  describe("buyLiYuenProtection", function()
    it("deducts cost from cash, sets liYuenProtection=1, clears liYuenOfferCost", function()
      local s = makeState({ cash = 500, liYuenOfferCost = 200, liYuenProtection = 0 })
      local ok = FinanceEngine.buyLiYuenProtection(s)
      expect(ok).to.equal(true)
      expect(s.cash).to.equal(300)
      expect(s.liYuenProtection).to.equal(1)
      expect(s.liYuenOfferCost).to.equal(nil)
    end)

    it("returns false when liYuenOfferCost is nil", function()
      local s = makeState({ cash = 500, liYuenOfferCost = nil })
      expect(FinanceEngine.buyLiYuenProtection(s)).to.equal(false)
    end)

    it("returns false when cash < cost", function()
      local s = makeState({ cash = 100, liYuenOfferCost = 200 })
      expect(FinanceEngine.buyLiYuenProtection(s)).to.equal(false)
      expect(s.cash).to.equal(100)  -- unchanged
    end)
  end)
end
