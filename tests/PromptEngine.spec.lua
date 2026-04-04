-- PromptEngine lives in StarterGui (not ReplicatedStorage) per Rojo mapping
local PromptEngine = require(game:GetService("StarterGui").TaipanGui.Apple2.PromptEngine)

local function mockActions()
  return {
    combatFight = function() end, combatRun = function() end,
    combatThrow = function() end, retire = function() end,
    restartGame = function() end, quitGame    = function() end,
    buyGoods = function() end, sellGoods = function() end,
    travelTo = function() end, bankDeposit = function() end,
    bankWithdraw = function() end, wuRepay  = function() end,
    wuBorrow = function() end, leaveWu  = function() end,
    transferTo = function() end, transferFrom = function() end,
    acceptUpgrade = function() end, declineUpgrade = function() end,
    acceptGun = function() end, declineGun = function() end,
    shipRepair = function() end, shipPanelDone = function() end,
    setFirmName = function() end, chooseStart   = function() end,
    buyLiYuen = function() end, setUIMode = function() end,
  }
end

return function()
  describe("PromptEngine sceneCombatLayout", function()
    it("returns rows 17-24 and F/R/T promptDef when in combat", function()
      local state = {
        combat = {
          enemyTotal = 3,
          grid = { [1] = true, [2] = true, [3] = true },
          outcome = nil,
        },
        damage = 0, shipCapacity = 60, guns = 2,
        shipCargo = {0,0,0,0},
      }
      local cb = function() end
      local lines, promptDef = PromptEngine.processState(state, nil, mockActions(), cb)
      expect(lines.rows).to.be.ok()
      expect(lines.rows[17]).to.be.ok()   -- "N ships attacking..."
      expect(lines.rows[20]).to.be.ok()   -- seaworthiness row
      expect(promptDef.type).to.equal("key")
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["F"]).to.equal(true)
      expect(keySet["R"]).to.equal(true)
      expect(keySet["T"]).to.equal(true)
    end)
  end)

  describe("PromptEngine retirement flow", function()
    local function retiredState(score)
      return {
        gameOver = true, gameOverReason = "retired",
        finalScore = score, finalRating = "Taipan",
        cash = 1500000, debt = 0, bankBalance = 500000,
        shipCapacity = 110, guns = 3, turnsElapsed = 26,
        month = 3, year = 1862,
        shipCargo = {0,0,0,0},
        warehouseCargo = {0,0,0,0}, warehouseUsed = 0,
        holdSpace = 80, currentPort = 1, damage = 0,
      }
    end

    it("sceneMillionaire: no localScene → returns rows with inverted text, key promptDef", function()
      local lines, promptDef = PromptEngine.processState(retiredState(1234), nil, mockActions(), function() end)
      expect(lines.rows).to.be.ok()
      -- Rows 19-24 should have inverted segments
      local r20 = lines.rows[20]
      expect(r20).to.be.ok()
      expect(r20.segments or r20.text).to.be.ok()
      expect(promptDef.type).to.equal("key")
    end)

    it("sceneFinalStatus: localScene=final_status → row 9 inverted score, Y/N keys", function()
      local lines, promptDef = PromptEngine.processState(
        retiredState(1234), "final_status", mockActions(), function() end)
      expect(lines.rows).to.be.ok()
      -- Row 9 should have inverted segment containing the score
      local r9 = lines.rows[9]
      expect(r9).to.be.ok()
      local hasInverted = false
      if r9.segments then
        for _, seg in ipairs(r9.segments) do
          if seg.inverted then hasInverted = true end
        end
      end
      expect(hasInverted).to.equal(true)
      -- Y and N keys
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["Y"]).to.equal(true)
      expect(keySet["N"]).to.equal(true)
    end)
  end)

  describe("PromptEngine sceneBank sequential", function()
    local function bankState()
      return {
        cash = 500, bankBalance = 1000, debt = 0,
        currentPort = 1,  -- HONG_KONG
        shipCargo = {0,0,0,0}, warehouseCargo = {0,0,0,0},
        warehouseUsed = 0, holdSpace = 60, shipCapacity = 60,
        guns = 0, damage = 0, month = 1, year = 1860,
        turnsElapsed = 1, currentPrices = {0,0,0,0},
        inWuSession = false, startChoice = "cash", gameOver = false,
        liYuenProtection = 0, firmName = "TEST",
      }
    end

    it("bank localScene returns numeric deposit promptDef", function()
      local lines, promptDef = PromptEngine.processState(
        bankState(), "bank", mockActions(), function() end)
      expect(promptDef.type).to.equal("numeric")
      expect(promptDef.maxDigits).to.equal(9)
    end)

    it("bank_withdraw localScene returns numeric withdraw promptDef", function()
      local lines, promptDef = PromptEngine.processState(
        bankState(), "bank_withdraw", mockActions(), function() end)
      expect(promptDef.type).to.equal("numeric")
    end)
  end)
end
