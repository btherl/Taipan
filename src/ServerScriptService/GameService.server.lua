-- GameService.server.lua
-- Authoritative game state. All mutations happen here.
-- Clients receive state snapshots via StateUpdate RemoteEvent.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState   = require(ReplicatedStorage.shared.GameState)
local PriceEngine = require(ReplicatedStorage.shared.PriceEngine)
local Validators  = require(ReplicatedStorage.shared.Validators)
local TravelEngine = require(ReplicatedStorage.shared.TravelEngine)
local FinanceEngine  = require(ReplicatedStorage.shared.FinanceEngine)
local EventEngine    = require(ReplicatedStorage.shared.EventEngine)
local CombatEngine  = require(ReplicatedStorage.shared.CombatEngine)
local ProgressionEngine = require(ReplicatedStorage.shared.ProgressionEngine)
local PersistenceEngine = require(ReplicatedStorage.shared.PersistenceEngine)
local Constants   = require(ReplicatedStorage.shared.Constants)
local Remotes     = require(ReplicatedStorage.Remotes)

local DataStoreService  = game:GetService("DataStoreService")
local gameStore         = DataStoreService:GetDataStore("TaipanV1")

local playerStates: {[Player]: any} = {}

local function savePlayer(player, state)
  local data = PersistenceEngine.serialize(state)
  PersistenceEngine.dataStoreRetry(function()
    gameStore:SetAsync("player_" .. player.UserId, data)
  end)
end

local function loadPlayer(player)
  local data = PersistenceEngine.dataStoreRetry(function()
    return gameStore:GetAsync("player_" .. player.UserId)
  end)
  return PersistenceEngine.deserialize(data, PriceEngine)
end

local function pushState(player)
  local state = playerStates[player]
  if type(state) == "table" then  -- guard against boolean sentinel during async load
    Remotes.StateUpdate:FireClient(player, state)
  end
end

local function validGood(g)
  return type(g) == "number" and g >= 1 and g <= 4 and math.floor(g) == g
end
local function validQty(q)
  return type(q) == "number" and q > 0 and math.floor(q) == q
end

Remotes.ChooseStart.OnServerEvent:Connect(function(player, startChoice)
  if startChoice ~= "cash" and startChoice ~= "guns" then startChoice = "cash" end
  if playerStates[player] then return end           -- already initialised (or sentinel)
  playerStates[player] = true                       -- sentinel: claim slot before async
  -- RequestStateUpdate calling pushState during this window silently no-ops (type guard).

  local loaded = loadPlayer(player)                 -- yields on DataStore call
  if loaded then
    -- Works for both resumed games (gameOver=false) and game-over saves (gameOver=true).
    -- Client renders whichever screen is appropriate from the pushed state.
    playerStates[player] = loaded
    pushState(player)
    return
  end

  -- No save found: start a fresh game
  local state = GameState.newGame(startChoice)
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2]
    - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  -- state.seenTutorial is already false (set by GameState.newGame)
  state.pendingTutorial = true  -- fires tutorial on first HK arrival; not in newGame
  playerStates[player] = state
  pushState(player)
end)

Remotes.BuyGoods.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end
  local price = state.currentPrices[goodIndex]
  if not Validators.canBuy(state, quantity, goodIndex, price) then
    pushState(player) return
  end
  state.cash                   = state.cash - quantity * price
  state.shipCargo[goodIndex]   = state.shipCargo[goodIndex] + quantity
  state.holdSpace              = state.holdSpace - quantity
  pushState(player)
end)

Remotes.SellGoods.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end
  if not Validators.canSell(state, quantity, goodIndex) then
    pushState(player) return
  end
  local price = state.currentPrices[goodIndex]
  state.cash                   = state.cash + quantity * price
  state.shipCargo[goodIndex]   = state.shipCargo[goodIndex] - quantity
  state.holdSpace              = state.holdSpace + quantity
  pushState(player)
end)

Remotes.EndTurn.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  pushState(player)
end)

Remotes.TravelTo.OnServerEvent:Connect(function(player, destination)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if type(destination) ~= "number" or destination < 1 or destination > 7
      or math.floor(destination) ~= destination then return end

  local err = TravelEngine.canDepart(state, destination)
  if err then pushState(player) return end

  TravelEngine.timeAdvance(state)
  state.destination   = destination
  state.currentPort   = destination
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, destination)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2] - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10

    if FinanceEngine.liYuenLapse(state) then
      Remotes.Notify:FireClient(player, "Li Yuen no longer protects you!")
    end
    if destination ~= Constants.HONG_KONG and FinanceEngine.liYuenWarningFires(state) then
      Remotes.Notify:FireClient(player,
        "Li Yuen wishes you to reconsider! He could protect you for a fee...")
    end

    if destination == Constants.HONG_KONG then
      state.inWuSession = true
      local braves = FinanceEngine.wuWarningCheck(state)
      if braves then
        Remotes.Notify:FireClient(player,
          string.format("ELDER BROTHER WU has heard of your debt! He is sending %d braves to collect!", braves))
      end
      if FinanceEngine.isBankrupt(state) then
        local loan, repay = FinanceEngine.bankruptcyLoan(state)
        Remotes.Notify:FireClient(player,
          string.format("WU: You have nothing! I will give you $%d... but you owe me $%d!", loan, repay))
      end
      if state.liYuenProtection == 0 and state.cash > 0 then
        state.liYuenOfferCost = FinanceEngine.liYuenProtectionCost(state)
      else
        state.liYuenOfferCost = nil
      end
    else
      state.liYuenOfferCost = nil
    end

    if not state.gameOver then
      local fine = EventEngine.opiumSeizure(state)
      if fine ~= nil then
        Remotes.Notify:FireClient(player,
          string.format("Bad joss!! The authorities have confiscated your opium and fined you $%d!", fine))
      end
      if EventEngine.cargoTheft(state) then
        Remotes.Notify:FireClient(player, "Bad joss!! Thieves have gotten into your warehouse!")
      end
      local stolen = EventEngine.cashRobbery(state)
      if stolen ~= nil then
        Remotes.Notify:FireClient(player,
          string.format("Bad joss!! You've been beaten up and robbed of $%d in cash!", stolen))
      end
      if EventEngine.stormOccurs() then
        Remotes.Notify:FireClient(player, "Storm, Taipan!!")
        if EventEngine.stormGoingDown() then
          Remotes.Notify:FireClient(player, "I think we're going down!!")
          if EventEngine.stormSinks(state) then
            Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
            -- stormSinks already sets state.gameOver = true; add reason + score
            local sc = ProgressionEngine.score(state)
            state.gameOverReason = "sunk"
            state.finalScore     = sc
            state.finalRating    = ProgressionEngine.rating(sc)
          else
            Remotes.Notify:FireClient(player, "We made it!!")
            local newPort = EventEngine.stormBlownOffCourse(state, destination)
            if newPort ~= nil then
              state.currentPort   = newPort
              state.destination   = newPort
              state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
              Remotes.Notify:FireClient(player,
                string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
            end
          end
        else
          Remotes.Notify:FireClient(player, "We made it!!")
          local newPort = EventEngine.stormBlownOffCourse(state, destination)
          if newPort ~= nil then
            state.currentPort   = newPort
            state.destination   = newPort
            state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
            Remotes.Notify:FireClient(player,
              string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
          end
        end
      end
    end

    if not state.gameOver and not state.combat then
      if CombatEngine.genericEncounterCheck(state) then
        local shipCount = CombatEngine.genericFleetSize(state)
        state.combat = CombatEngine.initCombat(state, shipCount, 1)
        CombatEngine.spawnShips(state.combat, state.enemyBaseHP)
        Remotes.Notify:FireClient(player,
          string.format("Taipan!! %d hostile ships approaching!!", shipCount))
      elseif CombatEngine.liYuenEncounterCheck(state) then
        if state.liYuenProtection ~= 0 then
          Remotes.Notify:FireClient(player, "Good joss!! Li Yuen's fleet let us be!!")
        else
          local shipCount = CombatEngine.liYuenFleetSize(state)
          state.combat = CombatEngine.initCombat(state, shipCount, 2)
          CombatEngine.spawnShips(state.combat, state.enemyBaseHP)
          Remotes.Notify:FireClient(player,
            string.format("Taipan!! Li Yuen's fleet!! %d ships!!", shipCount))
        end
      end
    end

  -- Phase 6: set ship offers on HK arrival
  if destination == Constants.HONG_KONG then
    local upgradeOffer = ProgressionEngine.checkUpgradeOffer(state)
    local gunOffer     = ProgressionEngine.checkGunOffer(state)
    local repairRate   = (state.damage > 0)
                         and ProgressionEngine.repairRate(state)
                         or  nil
    if repairRate or upgradeOffer or gunOffer then
      state.shipOffer = {
        repairRate    = repairRate,
        upgradeOffer  = upgradeOffer and { cost = upgradeOffer } or nil,
        gunOffer      = gunOffer     and { cost = gunOffer }     or nil,
      }
    else
      state.shipOffer = nil
    end
  else
    state.shipOffer = nil
  end

  -- Onboarding: fire tutorial messages on first HK arrival of a new game
  if destination == Constants.HONG_KONG and state.pendingTutorial then
    state.pendingTutorial = nil
    Remotes.Notify:FireClient(player,
      "Welcome, Taipan! Visit Elder Brother Wu to borrow cash or repay your debt.")
    Remotes.Notify:FireClient(player,
      "Use the Warehouse to store goods safely between voyages — holds up to 10,000 units.")
    Remotes.Notify:FireClient(player,
      "Li Yuen commands the seas. Pay for his protection in Hong Kong to avoid his fleet.")
    state.seenTutorial = true
    savePlayer(player, state)  -- persist immediately so tutorial never repeats on reconnect
  end

  pushState(player)
  savePlayer(player, state)  -- save on every departure
end)

Remotes.TransferToWarehouse.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end
  if state.shipCargo[goodIndex] < quantity then pushState(player) return end
  if state.warehouseUsed + quantity > Constants.WAREHOUSE_CAPACITY then pushState(player) return end
  state.shipCargo[goodIndex]      = state.shipCargo[goodIndex]      - quantity
  state.warehouseCargo[goodIndex] = state.warehouseCargo[goodIndex] + quantity
  state.warehouseUsed             = state.warehouseUsed + quantity
  state.holdSpace                 = state.holdSpace + quantity
  pushState(player)
end)

Remotes.TransferFromWarehouse.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end
  if state.warehouseCargo[goodIndex] < quantity then pushState(player) return end
  if state.holdSpace < quantity then pushState(player) return end
  state.warehouseCargo[goodIndex] = state.warehouseCargo[goodIndex] - quantity
  state.shipCargo[goodIndex]      = state.shipCargo[goodIndex]      + quantity
  state.warehouseUsed             = state.warehouseUsed - quantity
  state.holdSpace                 = state.holdSpace - quantity
  pushState(player)
end)

Remotes.WuRepay.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.repay(state, amount) then pushState(player) return end
  pushState(player)
end)

Remotes.WuBorrow.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.borrow(state, amount) then pushState(player) return end
  pushState(player)
end)

Remotes.LeaveWu.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.inWuSession then return end
  state.inWuSession = false
  if FinanceEngine.wuEnforcers(state) then
    Remotes.Notify:FireClient(player, "WU'S MEN beat you and take all your cash!")
  end
  pushState(player)
end)

Remotes.BankDeposit.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.bankDeposit(state, amount) then pushState(player) return end
  pushState(player)
end)

Remotes.BankWithdraw.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if type(amount) ~= "number" or amount <= 0 or math.floor(amount) ~= amount then return end
  if not FinanceEngine.bankWithdraw(state, amount) then pushState(player) return end
  pushState(player)
end)

Remotes.BuyLiYuenProtection.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not FinanceEngine.buyLiYuenProtection(state) then pushState(player) return end
  Remotes.Notify:FireClient(player, "Li Yuen smiles. You are under his protection.")
  pushState(player)
end)

Remotes.RequestStateUpdate.OnServerEvent:Connect(function(player)
  pushState(player)
end)

Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.gameOver then return end
  local wasTutorialSeen = state.seenTutorial  -- preserve so tutorial doesn't replay
  local newState = GameState.newGame("cash")
  newState.currentPrices = PriceEngine.calculatePrices(newState.basePrices, newState.currentPort)
  newState.holdSpace = newState.shipCapacity
    - newState.shipCargo[1] - newState.shipCargo[2]
    - newState.shipCargo[3] - newState.shipCargo[4]
    - newState.guns * 10
  newState.seenTutorial = wasTutorialSeen
  if not wasTutorialSeen then
    newState.pendingTutorial = true  -- tutorial still pending; fires on first HK arrival
  end
  playerStates[player] = newState
  pushState(player)
end)

local function combatTruncateDamage(state)
  state.damage = math.floor(state.damage)
end

-- Sets game-over state and computes final score/rating.
local function setGameOver(state, reason)
  state.gameOver       = true
  state.gameOverReason = reason
  local sc             = ProgressionEngine.score(state)
  state.finalScore     = sc
  state.finalRating    = ProgressionEngine.rating(sc)
  state.combat         = nil
  state.shipOffer      = nil
end

local function postCombatStorm(player, state)
  if not EventEngine.stormOccurs() then return end
  Remotes.Notify:FireClient(player, "Storm, Taipan!!")
  if EventEngine.stormGoingDown() then
    Remotes.Notify:FireClient(player, "I think we're going down!!")
    if EventEngine.stormSinks(state) then
      Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
      -- stormSinks sets gameOver=true; setGameOver adds reason/score (combat already nil)
      setGameOver(state, "sunk")
      return
    end
  end
  -- Survived the storm (either non-severe or severe but not sunk)
  Remotes.Notify:FireClient(player, "We made it!!")
  local newPort = EventEngine.stormBlownOffCourse(state, state.destination)
  if newPort then
    state.currentPort   = newPort
    state.destination   = newPort
    state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
    Remotes.Notify:FireClient(player,
      string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
  end
end

-- Shared enemy fire handler: applies one round of enemy fire, clears combat on terminal outcomes.
-- Returns true if combat ended (sunk or Li Yuen intervention).
local function applyEnemyFire(player, state, combat)
  combatTruncateDamage(state)
  local fireResult = CombatEngine.enemyFire(state, combat)
  if fireResult.gunDestroyed then
    Remotes.Notify:FireClient(player, "The buggers hit a gun, Taipan!!")
  end
  Remotes.Notify:FireClient(player, "We've been hit, Taipan!!")
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    setGameOver(state, "sunk")
    return true
  end
  if fireResult.liYuenIntervened then
    Remotes.Notify:FireClient(player, "Li Yuen's fleet drove them off!!")
    state.combat = nil
    return true
  end
  return false
end

-- CombatFight: fire all guns, enemy fires back
Remotes.CombatFight.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
  local combat = state.combat

  local result = CombatEngine.fight(state, combat)
  if result.noGuns then
    combat.lastCommand = 2
    Remotes.Notify:FireClient(player, "We have no guns, Taipan!!")
    applyEnemyFire(player, state, combat)
    pushState(player)
    return
  end
  if result.sunk > 0 then
    Remotes.Notify:FireClient(player,
      string.format("Sunk %d of the buggers, Taipan!", result.sunk))
  else
    Remotes.Notify:FireClient(player, "Hit 'em, but didn't sink 'em, Taipan!")
  end
  if result.fleeCount > 0 then
    Remotes.Notify:FireClient(player,
      string.format("%d ran away, Taipan!", result.fleeCount))
  end

  if combat.outcome == "victory" then
    CombatEngine.applyBooty(state, combat)
    Remotes.Notify:FireClient(player,
      string.format("We've captured some booty worth $%d!!", combat.booty))
    state.combat = nil
    postCombatStorm(player, state)
    pushState(player)
    return
  end

  applyEnemyFire(player, state, combat)
  pushState(player)
end)

-- CombatRun: attempt to flee
Remotes.CombatRun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
  local combat = state.combat

  CombatEngine.updateRunMomentum(combat)
  local escaped = CombatEngine.attemptRun(combat)
  if escaped then
    Remotes.Notify:FireClient(player, "We got away from 'em, Taipan!!")
    state.combat = nil
    postCombatStorm(player, state)
    pushState(player)
    return
  end

  Remotes.Notify:FireClient(player, "Can't lose 'em!!")
  local partialCount = CombatEngine.partialEscape(combat)
  if partialCount > 0 then
    Remotes.Notify:FireClient(player,
      string.format("But we escaped from %d of 'em, Taipan!", partialCount))
  end

  applyEnemyFire(player, state, combat)
  pushState(player)
end)

-- CombatThrow: throw cargo, auto-attempt run
Remotes.CombatThrow.OnServerEvent:Connect(function(player, goodIndex, qty)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
  if not validGood(goodIndex) or not validQty(qty) then return end
  local combat = state.combat

  local thrown = CombatEngine.throwCargo(state, combat, goodIndex, qty)
  if thrown == 0 then
    Remotes.Notify:FireClient(player, "There's nothing there, Taipan!")
    pushState(player)
    return
  end
  Remotes.Notify:FireClient(player,
    string.format("Threw %d overboard. Let's hope we lose 'em, Taipan!", thrown))

  CombatEngine.updateRunMomentum(combat)
  local escaped = CombatEngine.attemptRun(combat)
  if escaped then
    Remotes.Notify:FireClient(player, "We got away from 'em, Taipan!!")
    state.combat = nil
    postCombatStorm(player, state)
    pushState(player)
    return
  end

  Remotes.Notify:FireClient(player, "Can't lose 'em!!")
  local partialCount = CombatEngine.partialEscape(combat)
  if partialCount > 0 then
    Remotes.Notify:FireClient(player,
      string.format("But we escaped from %d of 'em, Taipan!", partialCount))
  end

  applyEnemyFire(player, state, combat)
  pushState(player)
end)

Remotes.ShipRepair.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.repairRate then return end
  if type(amount) ~= "number" or amount <= 0 then return end
  local br      = state.shipOffer.repairRate
  local allCost = ProgressionEngine.repairAllCost(br, state.damage)
  local w       = math.min(amount, allCost, state.cash)
  local repaired = ProgressionEngine.applyRepair(state, br, w)
  if repaired > 0 then
    Remotes.Notify:FireClient(player,
      string.format("Repaired %d damage for $%d, Taipan.", repaired, w))
  end
  if state.damage <= 0 then
    state.shipOffer.repairRate = nil
  else
    state.shipOffer.repairRate = ProgressionEngine.repairRate(state)
  end
  pushState(player)
end)

Remotes.AcceptUpgrade.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.upgradeOffer then return end
  local cost = state.shipOffer.upgradeOffer.cost
  if not ProgressionEngine.applyUpgrade(state, cost) then
    Remotes.Notify:FireClient(player, "You can't afford that, Taipan!")
    pushState(player)
    return
  end
  state.shipOffer.upgradeOffer = nil
  state.shipOffer.repairRate   = nil
  Remotes.Notify:FireClient(player,
    string.format("New ship! Capacity now %d tons, fully repaired!", state.shipCapacity))
  pushState(player)
end)

Remotes.DeclineUpgrade.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if not state.shipOffer then return end
  state.shipOffer.upgradeOffer = nil
  pushState(player)
end)

Remotes.AcceptGun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.gunOffer then return end
  local cost = state.shipOffer.gunOffer.cost
  if not ProgressionEngine.applyGun(state, cost) then
    Remotes.Notify:FireClient(player, "You can't do that, Taipan!")
    pushState(player)
    return
  end
  state.shipOffer.gunOffer = nil
  Remotes.Notify:FireClient(player,
    string.format("Purchased a gun! You now have %d gun(s).", state.guns))
  pushState(player)
end)

Remotes.DeclineGun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if not state.shipOffer then return end
  state.shipOffer.gunOffer = nil
  pushState(player)
end)

Remotes.ShipPanelDone.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  state.shipOffer = nil
  pushState(player)
end)

Remotes.Retire.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not ProgressionEngine.canRetire(state) then return end
  Remotes.Notify:FireClient(player, "You've retired as a Taipan!! Well done!!")
  setGameOver(state, "retired")
  pushState(player)
end)

Remotes.QuitGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  setGameOver(state, "quit")
  pushState(player)
end)

-- Cleanup on disconnect
Players.PlayerRemoving:Connect(function(player)
  local state = playerStates[player]
  if type(state) == "table" then
    savePlayer(player, state)  -- save before removing from map
  end
  playerStates[player] = nil
end)

-- Failsafe save on server shutdown (covers force-close / studio stop).
-- DataStore calls yield the coroutine; saves are sequential.
-- Max 3s backoff per player; well within Roblox's ~30s BindToClose budget.
game:BindToClose(function()
  for player, state in pairs(playerStates) do
    if type(state) == "table" then
      savePlayer(player, state)
    end
  end
end)
