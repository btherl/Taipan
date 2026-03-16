-- GameService.server.lua
-- Authoritative game state. All mutations happen here.
-- Clients receive state snapshots via StateUpdate RemoteEvent.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState   = require(ReplicatedStorage.shared.GameState)
local PriceEngine = require(ReplicatedStorage.shared.PriceEngine)
local Validators  = require(ReplicatedStorage.shared.Validators)
local TravelEngine = require(ReplicatedStorage.shared.TravelEngine)
local Constants   = require(ReplicatedStorage.shared.Constants)
local Remotes     = require(ReplicatedStorage.Remotes)

-- Per-player state map. Never use global state.
local playerStates: {[Player]: any} = {}

local function pushState(player)
  local state = playerStates[player]
  if state then
    Remotes.StateUpdate:FireClient(player, state)
  end
end

-- Input guards: reject malformed RemoteEvent arguments silently
local function validGood(g)
  return type(g) == "number" and g >= 1 and g <= 4 and math.floor(g) == g
end
local function validQty(q)
  return type(q) == "number" and q > 0 and math.floor(q) == q
end

-- Initialise a player's game state after they choose cash or guns start
Remotes.ChooseStart.OnServerEvent:Connect(function(player, startChoice)
  if startChoice ~= "cash" and startChoice ~= "guns" then startChoice = "cash" end
  -- Prevent re-initialisation: a second ChooseStart would wipe debt and progress
  if playerStates[player] then return end
  local state = GameState.newGame(startChoice)
  -- Calculate initial prices for Hong Kong
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  -- Recalculate holdSpace to account for guns occupying space
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2] - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  playerStates[player] = state
  pushState(player)
end)

-- Buy goods: validate, deduct cash, add to hold
Remotes.BuyGoods.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if not state then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end

  local price = state.currentPrices[goodIndex]
  if not Validators.canBuy(state, quantity, goodIndex, price) then
    pushState(player)  -- push back correct state (reject cheat)
    return
  end

  state.cash                   = state.cash - quantity * price
  state.shipCargo[goodIndex]   = state.shipCargo[goodIndex] + quantity
  state.holdSpace              = state.holdSpace - quantity
  pushState(player)
end)

-- Sell goods: validate, add cash, remove from hold
Remotes.SellGoods.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if not state then return end
  if not validGood(goodIndex) or not validQty(quantity) then return end

  if not Validators.canSell(state, quantity, goodIndex) then
    pushState(player)
    return
  end

  local price = state.currentPrices[goodIndex]
  state.cash                   = state.cash + quantity * price
  state.shipCargo[goodIndex]   = state.shipCargo[goodIndex] - quantity
  state.holdSpace              = state.holdSpace + quantity
  pushState(player)
end)

-- End Turn: recalculate prices (simulates staying in port; travel added Phase 2)
Remotes.EndTurn.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state then return end

  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  pushState(player)
end)

-- Travel to a new port: advance time, move to destination, recalculate prices
Remotes.TravelTo.OnServerEvent:Connect(function(player, destination)
  local state = playerStates[player]
  if not state then return end
  if type(destination) ~= "number" or destination < 1 or destination > 7
      or math.floor(destination) ~= destination then return end

  local err = TravelEngine.canDepart(state, destination)
  if err then
    pushState(player)
    return
  end

  TravelEngine.timeAdvance(state)
  state.destination   = destination
  state.currentPort   = destination
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, destination)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2] - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  pushState(player)
end)

-- Transfer goods from ship hold to warehouse (Hong Kong only)
Remotes.TransferToWarehouse.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if not state then return end
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

-- Transfer goods from warehouse to ship hold (Hong Kong only)
Remotes.TransferFromWarehouse.OnServerEvent:Connect(function(player, goodIndex, quantity)
  local state = playerStates[player]
  if not state then return end
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

-- Request for full state refresh (e.g. client reconnected)
Remotes.RequestStateUpdate.OnServerEvent:Connect(function(player)
  pushState(player)
end)

-- Cleanup on disconnect
Players.PlayerRemoving:Connect(function(player)
  playerStates[player] = nil
end)
