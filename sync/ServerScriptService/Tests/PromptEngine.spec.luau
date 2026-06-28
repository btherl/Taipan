-- PromptEngine lives in StarterGui (not ReplicatedStorage) per Rojo mapping
local PromptEngine = require(game:GetService("StarterGui").TaipanGui.GameController.Apple2.PromptEngine)

local function mockActions()
  return {
    combatFight = function() end, combatRun = function() end,
    combatThrow = function() end, combatNoCommand = function() end,
    retire = function() end,
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
    abandonShip = function() end,
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

    -- Apple II lines 20180-20190: low-score parting messages at VTAB 11.
    it("sceneFinalStatus: score 0-98 → 'land based job' jab on row 11", function()
      local lines = PromptEngine.processState(
        retiredState(42), "final_status", mockActions(), function() end)
      expect(lines.rows[11].text).to.equal("Have you considered a land based job?")
      expect(lines.rows[12].text).to.equal("")
    end)

    it("sceneFinalStatus: negative score → 'stay on shore' insult wraps rows 11-12", function()
      local lines = PromptEngine.processState(
        retiredState(-5), "final_status", mockActions(), function() end)
      expect(lines.rows[11].text).to.equal("The crew has requested that you stay on")
      expect(lines.rows[12].text).to.equal("shore for their safety!!")
    end)

    it("sceneFinalStatus: score >= 99 → no parting message (rows 11-12 blank)", function()
      local lines = PromptEngine.processState(
        retiredState(1234), "final_status", mockActions(), function() end)
      expect(lines.rows[11].text).to.equal("")
      expect(lines.rows[12].text).to.equal("")
    end)

    -- Apple II line 20040 puts "Your Rating:" at VTAB 14; the box + "Play again?"
    -- follow below it. Guards against the rating block drifting up a row.
    it("sceneFinalStatus: 'Your Rating:' sits on row 14, 'Play again?' on row 23", function()
      local lines, promptDef = PromptEngine.processState(
        retiredState(1234), "final_status", mockActions(), function() end)
      expect(lines.rows[14].text).to.equal("Your Rating:")
      expect(lines.rows[23].text).to.equal("Play again? ")
      expect(promptDef._inputRow).to.equal(23)
    end)
  end)

  describe("PromptEngine sunk flow", function()
    local function sunkState(score)
      return {
        gameOver = true, gameOverReason = "sunk",
        finalScore = score, finalRating = "Galley Hand",
        cash = 0, debt = 5000, bankBalance = 0,
        shipCapacity = 60, guns = 0, turnsElapsed = 4,
        month = 5, year = 1860,
        shipCargo = {0,0,0,0},
        warehouseCargo = {0,0,0,0}, warehouseUsed = 0,
        holdSpace = 60, currentPort = 1, damage = 60,
      }
    end

    it("sunk: routes straight to final status (inverted score row 9, Y/N keys)", function()
      -- No localScene: sunk must NOT show the millionaire screen; it goes
      -- directly to the final-status / rating layout.
      local lines, promptDef = PromptEngine.processState(
        sunkState(42), nil, mockActions(), function() end)
      expect(lines.rows).to.be.ok()
      -- Row 9 carries the inverted "Your score is N." segment (final-status marker)
      local r9 = lines.rows[9]
      expect(r9).to.be.ok()
      local hasInverted = false
      if r9.segments then
        for _, seg in ipairs(r9.segments) do
          if seg.inverted then hasInverted = true end
        end
      end
      expect(hasInverted).to.equal(true)
      -- Final-status prompt offers Y/N (Play again?)
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["Y"]).to.equal(true)
      expect(keySet["N"]).to.equal(true)
    end)
  end)

  describe("PromptEngine HK Restart option", function()
    local function hkState(netWorth)
      -- cash carries the whole net worth; debt/bank zero.
      -- startChoice set so processState routes to sceneAtPort, not the
      -- new-game firm-name branch (which fires when startChoice == nil).
      return {
        currentPort = 1, gameOver = false, startChoice = "cash",
        cash = netWorth, bankBalance = 0, debt = 0,
        currentPrices = {1,2,3,4},
        shipCargo = {0,0,0,0}, warehouseCargo = {0,0,0,0},
        holdSpace = 60, shipCapacity = 60, guns = 0,
      }
    end

    it("shows Restart (not Retire) at HK when net worth < 1,000,000", function()
      local lines, promptDef = PromptEngine.processState(hkState(500000), nil, mockActions(), function() end)
      expect(lines.rows[24].text).to.equal("cargo, Quit trading, or Restart?")
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["R"]).to.equal(true)
    end)

    it("routes R to restart_confirm when not retire-eligible", function()
      local routed
      local promptDef = select(2, PromptEngine.processState(
        hkState(500000), nil, mockActions(), function(scene) routed = scene end))
      promptDef.onKey("R", hkState(500000), mockActions())
      expect(routed).to.equal("restart_confirm")
    end)

    it("still shows Retire and calls retire() when net worth >= 1,000,000", function()
      local retired = false
      local actions = mockActions(); actions.retire = function() retired = true end
      local lines, promptDef = PromptEngine.processState(hkState(1000000), nil, actions, function() end)
      expect(lines.rows[24].text).to.equal("cargo, Quit trading, or Retire?")
      promptDef.onKey("R", hkState(1000000), actions)
      expect(retired).to.equal(true)
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

  describe("PromptEngine sceneRestartConfirm", function()
    local function hkState()
      -- startChoice set so processState does not route to the new-game
      -- firm-name branch (which fires when startChoice == nil).
      return {
        currentPort = 1, gameOver = false, startChoice = "cash",
        cash = 500000, bankBalance = 0, debt = 0,
        currentPrices = {1,2,3,4},
        shipCargo = {0,0,0,0}, warehouseCargo = {0,0,0,0},
        holdSpace = 60, shipCapacity = 60, guns = 0,
      }
    end

    it("renders the abandon confirmation prompt", function()
      local lines, promptDef = PromptEngine.processState(hkState(), "restart_confirm", mockActions(), function() end)
      local l1, l2 = false, false
      for _, row in pairs(lines.rows) do
        if row.text == "Do you wish to abandon your ship," then l1 = true end
        if row.text == "Taipan? (Y/N)" then l2 = true end
      end
      expect(l1).to.equal(true)
      expect(l2).to.equal(true)
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["Y"]).to.equal(true)
      expect(keySet["N"]).to.equal(true)
    end)

    it("Y calls abandonShip()", function()
      local called = false
      local actions = mockActions(); actions.abandonShip = function() called = true end
      local promptDef = select(2, PromptEngine.processState(hkState(), "restart_confirm", actions, function() end))
      promptDef.onKey("Y", hkState(), actions)
      expect(called).to.equal(true)
    end)

    it("N returns to the port menu via localSceneCb(nil)", function()
      local routedToNil = false
      local promptDef = select(2, PromptEngine.processState(
        hkState(), "restart_confirm", mockActions(),
        function(scene) if scene == nil then routedToNil = true end end))
      promptDef.onKey("N", hkState(), mockActions())
      expect(routedToNil).to.equal(true)
    end)
  end)

  describe("PromptEngine abandon flow", function()
    local function abandonedState()
      return {
        gameOver = true, gameOverReason = "abandoned",
        finalScore = 42, finalRating = "Galley Hand",
        cash = 1000, bankBalance = 0, debt = 0,
        shipCapacity = 60, guns = 0, turnsElapsed = 3,
        month = 4, year = 1860, currentPort = 1, damage = 0,
        shipCargo = {0,0,0,0}, warehouseCargo = {0,0,0,0}, warehouseUsed = 0,
        holdSpace = 60,
      }
    end

    it("shows the abandon message first, then advances to final_status", function()
      local routed
      local lines, promptDef = PromptEngine.processState(
        abandonedState(), nil, mockActions(), function(scene) routed = scene end)
      local line1, line2 = false, false
      for _, row in pairs(lines.rows) do
        if row.text == "Ashamed of your failure, you disappear" then line1 = true end
        if row.text == "into the night, never to be seen again." then line2 = true end
      end
      expect(line1).to.equal(true)
      expect(line2).to.equal(true)
      expect(promptDef.anyKey).to.equal(true)
      promptDef.onKey("X", abandonedState(), mockActions())
      expect(routed).to.equal("final_status")
    end)

    it("routes to the score screen at localScene final_status", function()
      local lines = PromptEngine.processState(abandonedState(), "final_status", mockActions(), function() end)
      local found = false
      for _, row in pairs(lines.rows) do
        if row.text == "Your final status:" then found = true end
      end
      expect(found).to.equal(true)
    end)
  end)
end
