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
end
