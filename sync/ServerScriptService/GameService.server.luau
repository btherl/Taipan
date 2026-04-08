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

-- Colour used in Apple2 notification rows (sent to client via RemoteEvent)
local AMBER_S = Color3.fromRGB(200, 180, 80)

-- Build a pendingMessages entry in Captain's Report format.
-- lines: array of content strings starting at row 19.
-- duration: seconds the client displays this entry.
local function makeCaptainNotif(lines, duration)
  local rows = {}
  rows[17] = { text = "  Captain's Report", color = AMBER_S }
  rows[18] = { text = "",                   color = AMBER_S }
  for i, line in ipairs(lines) do
    rows[18 + i] = { text = line, color = AMBER_S }
  end
  for r = 17, 24 do
    if not rows[r] then rows[r] = { text = "", color = AMBER_S } end
  end
  return { rows = rows, duration = duration }
end

-- Build a pendingMessages entry in Comprador's Report format.
local function makeCompradorNotif(lines, duration)
  local rows = {}
  rows[17] = { text = "Comprador's Report", color = AMBER_S }
  rows[18] = { text = "",                   color = AMBER_S }
  for i, line in ipairs(lines) do
    rows[18 + i] = { text = line, color = AMBER_S }
  end
  for r = 17, 24 do
    if not rows[r] then rows[r] = { text = "", color = AMBER_S } end
  end
  return { rows = rows, duration = duration }
end

local RunService        = game:GetService("RunService")
local DataStoreService  = game:GetService("DataStoreService")
local gameStore         = DataStoreService:GetDataStore("TaipanV1")

-- Taipan is pure 2D — no 3D world or avatar needed
Players.CharacterAutoLoads = false

local playerStates: {[Player]: any} = {}
local pendingModes: {[Player]: string} = {}
local pendingTutorialSeen: {[Player]: boolean} = {}

local function savePlayer(player, state)
  if RunService:IsStudio() then return end
  local data = PersistenceEngine.serialize(state)
  PersistenceEngine.dataStoreRetry(function()
    gameStore:SetAsync("player_" .. player.UserId, data)
  end)
end

local function loadPlayer(player)
  if RunService:IsStudio() then return nil end
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

Remotes.ChooseStart.OnServerEvent:Connect(function(player, startChoice, firmName)
  if startChoice ~= "cash" and startChoice ~= "guns" then startChoice = "cash" end
  local existing = playerStates[player]
  if type(existing) == "table" and existing.startChoice ~= nil then return end
  -- nil slot (new player or post-restart) → allowed through

  -- New player: start a fresh game
  local state = GameState.newGame(startChoice, firmName)
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2]
    - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  if pendingTutorialSeen[player] ~= nil then
    state.seenTutorial = pendingTutorialSeen[player]
    if not pendingTutorialSeen[player] then
      state.pendingTutorial = true  -- tutorial not yet seen; fires on first HK arrival
    end
    pendingTutorialSeen[player] = nil
  else
    state.pendingTutorial = true  -- new player; fires tutorial on first HK arrival
  end
  if pendingModes[player] then
    state.uiMode = pendingModes[player]
    pendingModes[player] = nil
  end
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
  if err then
    if err == "ship is overloaded" then
      Remotes.Notify:FireClient(player, "Ship is overloaded! Offload cargo to warehouse before departing.")
    end
    pushState(player)
    return
  end

  TravelEngine.timeAdvance(state)
  state.destination   = destination
  state.currentPort   = destination
  local priceEvent
  state.currentPrices, priceEvent = PriceEngine.calculatePrices(state.basePrices, destination)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2] - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10

  local pending = {}
  local arrivalPending = {}

  -- Combat is an at-sea event: check for pirates BEFORE arrival notifications.
  -- If real combat occurs, arrival messages are deferred until after combat resolves.
  if not state.gameOver then
    if CombatEngine.genericEncounterCheck(state) then
      local shipCount = CombatEngine.genericFleetSize(state)
      state.combat = CombatEngine.initCombat(state, shipCount, 1)
      CombatEngine.spawnShips(state.combat, state.enemyBaseHP)
      table.insert(pending, makeCaptainNotif({
        string.format("%d hostile ships approaching, Taipan!!", shipCount),
      }, 1))
      Remotes.Notify:FireClient(player,
        string.format("Taipan!! %d hostile ships approaching!!", shipCount))
    elseif CombatEngine.liYuenEncounterCheck(state) then
      if state.liYuenProtection ~= 0 then
        table.insert(pending, makeCaptainNotif({
          "Li Yuen's pirates, Taipan!!",
          "",
          "Good joss!! They let us be!!",
        }, 5))
        Remotes.Notify:FireClient(player, "Good joss!! Li Yuen's fleet let us be!!")
      else
        local shipCount = CombatEngine.liYuenFleetSize(state)
        state.combat = CombatEngine.initCombat(state, shipCount, 2)
        CombatEngine.spawnShips(state.combat, state.enemyBaseHP)
        table.insert(pending, makeCaptainNotif({
          "Li Yuen's pirates, Taipan!!",
        }, 1))
        Remotes.Notify:FireClient(player,
          string.format("Taipan!! Li Yuen's fleet!! %d ships!!", shipCount))
      end
    end
  end

  -- Build arrival notifications (shown immediately if no combat, deferred if combat occurs).
  table.insert(arrivalPending, makeCompradorNotif(
    { "Arriving at " .. Constants.PORT_NAMES[destination] }, 3
  ))

    if FinanceEngine.liYuenLapse(state) then
      Remotes.Notify:FireClient(player, "Li Yuen no longer protects you!")
    end
    if destination ~= Constants.HONG_KONG and FinanceEngine.liYuenWarningFires(state) then
      Remotes.Notify:FireClient(player,
        "Li Yuen wishes you to reconsider! He could protect you for a fee...")
      table.insert(arrivalPending, makeCompradorNotif({
        "Li Yuen has sent a lieutenant,",
        "Taipan.  He says his admiral wishes",
        "to see you in Hong Kong, posthaste!",
      }, 5))
    end

  if priceEvent then
    local goodName  = Constants.GOOD_NAMES[priceEvent.good]
    local direction = priceEvent.direction == "drop" and "dropped" or "risen"
    table.insert(arrivalPending, makeCompradorNotif({
      string.format("Taipan!!  The price of %s", goodName),
      string.format("has %s to %d!!", direction, priceEvent.price),
    }, 5))
  end

  if state.combat then
    state.pendingArrival = arrivalPending  -- defer until after combat
  else
    for _, entry in ipairs(arrivalPending) do table.insert(pending, entry) end
  end

    if destination == Constants.HONG_KONG then
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
        state.liYuenPending   = true
      else
        state.liYuenOfferCost = nil
        state.liYuenPending   = false
      end
      state.wuPending   = true
      state.inWuSession = false
    else
      state.liYuenOfferCost = nil
      state.liYuenPending   = false
    end

    if not state.gameOver then
      local fine = EventEngine.spicesSeizure(state)
      if fine ~= nil then
        Remotes.Notify:FireClient(player,
          string.format("Bad joss!! The authorities have confiscated your spices and fined you $%d!", fine))
      end
      if EventEngine.cargoTheft(state) then
        Remotes.Notify:FireClient(player, "Bad joss!! Thieves have gotten into your warehouse!")
      end
      local stolen = EventEngine.cashRobbery(state)
      if stolen ~= nil then
        Remotes.Notify:FireClient(player,
          string.format("Bad joss!! You've been beaten up and robbed of $%d in cash!", stolen))
      end
      if not state.combat and EventEngine.stormOccurs() then
        Remotes.Notify:FireClient(player, "Storm, Taipan!!")
        if EventEngine.stormGoingDown() then
          Remotes.Notify:FireClient(player, "I think we're going down!!")
          if EventEngine.stormSinks(state) then
            Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
            table.insert(pending, makeCaptainNotif({ "Storm, Taipan!!", "", "We're going down!!" }, 5))
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
              destination         = newPort  -- sync local so HK offer check uses actual port
              Remotes.Notify:FireClient(player,
                string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
              table.insert(pending, makeCaptainNotif({
                "Storm, Taipan!!",
                "",
                "We've been blown off course",
                "to " .. Constants.PORT_NAMES[newPort],
              }, 5))
            else
              table.insert(pending, makeCaptainNotif({ "Storm, Taipan!!", "", "    We made it!!" }, 5))
            end
          end
        else
          Remotes.Notify:FireClient(player, "We made it!!")
          local newPort = EventEngine.stormBlownOffCourse(state, destination)
          if newPort ~= nil then
            state.currentPort   = newPort
            state.destination   = newPort
            state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
            destination         = newPort  -- sync local so HK offer check uses actual port
            Remotes.Notify:FireClient(player,
              string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
            table.insert(pending, makeCaptainNotif({
              "Storm, Taipan!!",
              "",
              "We've been blown off course",
              "to " .. Constants.PORT_NAMES[newPort],
            }, 5))
          else
            table.insert(pending, makeCaptainNotif({ "Storm, Taipan!!", "", "    We made it!!" }, 5))
          end
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
      state.repairPending = repairRate ~= nil
    else
      state.shipOffer     = nil
      state.repairPending = false
    end
  else
    state.shipOffer     = nil
    state.repairPending = false
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

  state.pendingMessages = pending
  pushState(player)
  state.pendingMessages = nil
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
  state.liYuenPending = false
  Remotes.Notify:FireClient(player, "Li Yuen smiles. You are under his protection.")
  pushState(player)
end)

Remotes.DeclineLiYuenTribute.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  state.liYuenPending   = false
  state.liYuenOfferCost = nil
  pushState(player)
end)

Remotes.ConfirmWu.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  state.wuPending   = false
  state.inWuSession = true
  pushState(player)
end)

Remotes.DeclineWu.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  state.wuPending   = false
  state.inWuSession = false
  pushState(player)
end)

Remotes.RequestStateUpdate.OnServerEvent:Connect(function(player)
  pushState(player)
end)

Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.gameOver then return end
  -- Push a minimal lobby state so the client shows the firm name screen.
  -- Then nil the slot: all existing handler guards (type ~= "table") block
  -- game actions during lobby, and PlayerRemoving skips the DataStore save.
  local lobbyState = {
    startChoice  = nil,
    gameOver     = false,
    turnsElapsed = 1,
    destination  = 0,
    uiMode       = state.uiMode,
    seenTutorial = state.seenTutorial,
  }
  pendingTutorialSeen[player] = state.seenTutorial
  Remotes.StateUpdate:FireClient(player, lobbyState)
  playerStates[player] = nil
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
  state.pendingArrival = nil  -- no arrival if sunk
end

-- Appends deferred arrival notifications into pending (set during travel when combat interrupted arrival).
local function appendArrivalPending(state, pending)
  if state.pendingArrival then
    for _, entry in ipairs(state.pendingArrival) do
      table.insert(pending, entry)
    end
    state.pendingArrival = nil
  end
end

local function postCombatStorm(player, state, pending)
  pending = pending or {}
  if not EventEngine.stormOccurs() then return end
  Remotes.Notify:FireClient(player, "Storm, Taipan!!")
  if EventEngine.stormGoingDown() then
    Remotes.Notify:FireClient(player, "I think we're going down!!")
    if EventEngine.stormSinks(state) then
      Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
      table.insert(pending, makeCaptainNotif({ "Storm, Taipan!!", "", "We're going down!!" }, 5))
      setGameOver(state, "sunk")
      return
    end
  end
  local newPort = EventEngine.stormBlownOffCourse(state, state.destination)
  if newPort then
    state.currentPort   = newPort
    state.destination   = newPort
    state.currentPrices = PriceEngine.calculatePrices(state.basePrices, newPort)
    Remotes.Notify:FireClient(player,
      string.format("We've been blown off course to %s!", Constants.PORT_NAMES[newPort]))
    table.insert(pending, makeCaptainNotif({
      "Storm, Taipan!!",
      "",
      "We've been blown off course",
      "to " .. Constants.PORT_NAMES[newPort],
    }, 5))
  else
    Remotes.Notify:FireClient(player, "We made it!!")
    table.insert(pending, makeCaptainNotif({ "Storm, Taipan!!", "", "    We made it!!" }, 5))
  end
end

-- Shared enemy fire handler: applies one round of enemy fire, clears combat on terminal outcomes.
-- Returns true if combat ended (sunk or Li Yuen intervention).
local function applyEnemyFire(player, state, combat, pending)
  pending = pending or {}
  combatTruncateDamage(state)
  local fireResult = CombatEngine.enemyFire(state, combat)
  if fireResult.gunDestroyed then
    Remotes.Notify:FireClient(player, "The buggers hit a gun, Taipan!!")
    table.insert(pending, makeCaptainNotif({ "The buggers hit a gun, Taipan!!" }, 2))
  end
  Remotes.Notify:FireClient(player, "We've been hit, Taipan!!")
  table.insert(pending, makeCaptainNotif({ "We've been hit, Taipan!!" }, 2))
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    table.insert(pending, makeCaptainNotif({ "The buggers got us, Taipan!!! It's all over!!!" }, 5))
    setGameOver(state, "sunk")
    return true
  end
  if fireResult.liYuenIntervened then
    Remotes.Notify:FireClient(player, "Li Yuen's fleet drove them off!!")
    table.insert(pending, makeCaptainNotif({ "Li Yuen's fleet drove them off!!" }, 3))
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
  local pending = {}

  local result = CombatEngine.fight(state, combat)
  if result.noGuns then
    combat.lastCommand = 2
    Remotes.Notify:FireClient(player, "We have no guns, Taipan!!")
    table.insert(pending, makeCaptainNotif({ "We have no guns, Taipan!!" }, 2))
    local combatEnded = applyEnemyFire(player, state, combat, pending)
    if combatEnded and not state.gameOver then appendArrivalPending(state, pending) end
    state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
    return
  end

  -- Fight narration sequence
  table.insert(pending, makeCaptainNotif({ "Aye, we'll fight 'em, Taipan!" }, 1))
  table.insert(pending, makeCaptainNotif({ "We're firing on 'em, Taipan!" }, 1))

  -- Result message
  if result.sunk > 0 then
    if combat.outcome == "victory" then
      table.insert(pending, makeCaptainNotif({ "We got 'em all, Taipan!!" }, 3))
    else
      table.insert(pending, makeCaptainNotif({
        string.format("Sunk %d of the buggers, Taipan!", result.sunk),
      }, 2))
    end
    Remotes.Notify:FireClient(player, string.format("Sunk %d of the buggers, Taipan!", result.sunk))
  else
    table.insert(pending, makeCaptainNotif({ "Hit 'em, but didn't sink 'em, Taipan!" }, 2))
    Remotes.Notify:FireClient(player, "Hit 'em, but didn't sink 'em, Taipan!")
  end
  if result.fleeCount > 0 then
    table.insert(pending, makeCaptainNotif({
      string.format("%d ran away, Taipan!", result.fleeCount),
    }, 2))
    Remotes.Notify:FireClient(player, string.format("%d ran away, Taipan!", result.fleeCount))
  end

  if combat.outcome == "victory" then
    CombatEngine.applyBooty(state, combat)
    table.insert(pending, makeCaptainNotif({
      "We've captured some booty",
      string.format("It's worth %d!", combat.booty),
    }, 5))
    Remotes.Notify:FireClient(player,
      string.format("We've captured some booty worth $%d!!", combat.booty))
    state.combat = nil
    postCombatStorm(player, state, pending)
    if not state.gameOver then
      appendArrivalPending(state, pending)
      -- Re-check Li Yuen offer: booty may have given cash after the arrival-time check ran with cash=0
      if state.currentPort == Constants.HONG_KONG
          and state.liYuenProtection == 0
          and state.cash > 0
          and not state.liYuenPending then
        state.liYuenOfferCost = FinanceEngine.liYuenProtectionCost(state)
        state.liYuenPending   = true
      end
    end
    state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
    return
  end

  local combatEnded = applyEnemyFire(player, state, combat, pending)
  if combatEnded and not state.gameOver then appendArrivalPending(state, pending) end
  state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
end)

-- CombatRun: attempt to flee
Remotes.CombatRun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
  local combat = state.combat
  local pending = {}

  CombatEngine.updateRunMomentum(combat)
  local escaped = CombatEngine.attemptRun(combat)
  if escaped then
    Remotes.Notify:FireClient(player, "We got away from 'em, Taipan!!")
    table.insert(pending, makeCaptainNotif({ "We got away from 'em, Taipan!!" }, 3))
    state.combat = nil
    postCombatStorm(player, state, pending)
    if not state.gameOver then appendArrivalPending(state, pending) end
    state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
    return
  end

  Remotes.Notify:FireClient(player, "Can't lose 'em!!")
  table.insert(pending, makeCaptainNotif({ "Can't lose 'em!!" }, 2))
  local partialCount = CombatEngine.partialEscape(combat)
  if partialCount > 0 then
    Remotes.Notify:FireClient(player,
      string.format("But we escaped from %d of 'em, Taipan!", partialCount))
    table.insert(pending, makeCaptainNotif({
      string.format("But we escaped from %d of 'em, Taipan!", partialCount),
    }, 2))
  end

  local combatEnded = applyEnemyFire(player, state, combat, pending)
  if combatEnded and not state.gameOver then appendArrivalPending(state, pending) end
  state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
end)

-- CombatThrow: throw cargo, auto-attempt run
Remotes.CombatThrow.OnServerEvent:Connect(function(player, goodIndex, qty)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
  if not validGood(goodIndex) or not validQty(qty) then return end
  local combat = state.combat
  local pending = {}

  local thrown = CombatEngine.throwCargo(state, combat, goodIndex, qty)
  if thrown == 0 then
    Remotes.Notify:FireClient(player, "There's nothing there, Taipan!")
    table.insert(pending, makeCaptainNotif({ "There's nothing there, Taipan!" }, 2))
    state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
    return
  end
  Remotes.Notify:FireClient(player,
    string.format("Threw %d overboard. Let's hope we lose 'em, Taipan!", thrown))
  table.insert(pending, makeCaptainNotif({
    string.format("Threw %d overboard.", thrown),
    "Let's hope we lose 'em, Taipan!",
  }, 2))

  CombatEngine.updateRunMomentum(combat)
  local escaped = CombatEngine.attemptRun(combat)
  if escaped then
    Remotes.Notify:FireClient(player, "We got away from 'em, Taipan!!")
    table.insert(pending, makeCaptainNotif({ "We got away from 'em, Taipan!!" }, 3))
    state.combat = nil
    postCombatStorm(player, state, pending)
    if not state.gameOver then appendArrivalPending(state, pending) end
    state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
    return
  end

  Remotes.Notify:FireClient(player, "Can't lose 'em!!")
  table.insert(pending, makeCaptainNotif({ "Can't lose 'em!!" }, 2))
  local partialCount = CombatEngine.partialEscape(combat)
  if partialCount > 0 then
    Remotes.Notify:FireClient(player,
      string.format("But we escaped from %d of 'em, Taipan!", partialCount))
    table.insert(pending, makeCaptainNotif({
      string.format("But we escaped from %d of 'em, Taipan!", partialCount),
    }, 2))
  end

  local combatEnded = applyEnemyFire(player, state, combat, pending)
  if combatEnded and not state.gameOver then appendArrivalPending(state, pending) end
  state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
end)

-- Clears shipOffer when upgrade and gun sub-offers are both resolved.
local function cleanupShipOffer(state)
  if not state.shipOffer then return end
  if not state.shipOffer.upgradeOffer and not state.shipOffer.gunOffer then
    state.shipOffer = nil
  end
end

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
  state.shipOffer.repairRate = nil
  state.repairPending = false
  cleanupShipOffer(state)
  pushState(player)
end)

Remotes.DeclineRepair.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if state.shipOffer then state.shipOffer.repairRate = nil end
  state.repairPending = false
  cleanupShipOffer(state)
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
  cleanupShipOffer(state)
  pushState(player)
end)

Remotes.DeclineUpgrade.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if not state.shipOffer then return end
  state.shipOffer.upgradeOffer = nil
  cleanupShipOffer(state)
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
  cleanupShipOffer(state)
  pushState(player)
end)

Remotes.DeclineGun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if not state.shipOffer then return end
  state.shipOffer.gunOffer = nil
  cleanupShipOffer(state)
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

-- With CharacterAutoLoads=false, Roblox never auto-copies StarterGui to PlayerGui.
-- Clone it manually so the GameController LocalScript reaches the client.
Players.PlayerAdded:Connect(function(player)
  task.defer(function()
    local StarterGui = game:GetService("StarterGui")
    for _, gui in ipairs(StarterGui:GetChildren()) do
      local clone = gui:Clone()
      clone.Parent = player.PlayerGui
    end
    -- Returning players: load save and push state immediately.
    -- Client (showing InterfacePicker) receives StateUpdate with uiMode set
    -- and transitions straight to the saved game -- no picker interaction needed.
    -- Guard: only apply if ChooseStart hasn't already claimed the slot.
    task.spawn(function()
      local loaded = loadPlayer(player)
      if loaded and playerStates[player] == nil then
        playerStates[player] = loaded
        pushState(player)
      end
    end)
  end)
end)

-- Cleanup on disconnect
Players.PlayerRemoving:Connect(function(player)
  local state = playerStates[player]
  if type(state) == "table" then
    savePlayer(player, state)  -- save before removing from map
  end
  playerStates[player] = nil
  pendingModes[player] = nil
  pendingTutorialSeen[player] = nil
end)

Remotes.SetUIMode.OnServerEvent:Connect(function(player, mode)
  if mode ~= "modern" and mode ~= "apple2" then return end
  pendingModes[player] = mode
  local state = playerStates[player]
  if type(state) == "table" then
    state.uiMode = mode
    savePlayer(player, state)
    pushState(player)
  end
end)

-- Failsafe save on server shutdown (covers force-close / studio stop).
-- DataStore calls yield the coroutine; saves are sequential.
-- Max 3s backoff per player; well within Roblox's ~30s BindToClose budget.
game:BindToClose(function()
  if RunService:IsStudio() then return end
  for player, state in pairs(playerStates) do
    if type(state) == "table" then
      savePlayer(player, state)
    end
  end
end)
