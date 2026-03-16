-- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
-- GameController: wires all UI panels to server RemoteEvents.
-- Receives state snapshots from server and distributes to panels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- Sanity check: Panels folder must exist as a child of this LocalScript's container
assert(script:FindFirstChild("Panels"),
  "TaipanGui: 'Panels' folder missing — check Studio structure")

local Remotes          = require(ReplicatedStorage.Remotes)
local StatusStrip      = require(script.Panels.StatusStrip)
local InventoryPanel   = require(script.Panels.InventoryPanel)
local PricesPanel      = require(script.Panels.PricesPanel)
local BuySellPanel     = require(script.Panels.BuySellPanel)
local PortPanel        = require(script.Panels.PortPanel)
local WarehousePanel   = require(script.Panels.WarehousePanel)

-- Build the ScreenGui root frame
local screenGui = script.Parent  -- TaipanGui is already a ScreenGui in StarterGui
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(0, 480, 1, 0)
root.Position = UDim2.new(0, 0, 0, 0)
root.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
root.BorderSizePixel = 0
root.Parent = screenGui

-- Instantiate panels
local portPanel      = PortPanel.new(root, function(dest)
  Remotes.TravelTo:FireServer(dest)
end)
local statusStrip    = StatusStrip.new(root)
local inventoryPanel = InventoryPanel.new(root)
local pricesPanel    = PricesPanel.new(root)
local buySellPanel   = BuySellPanel.new(
  root,
  function(goodIndex, qty) Remotes.BuyGoods:FireServer(goodIndex, qty) end,
  function(goodIndex, qty) Remotes.SellGoods:FireServer(goodIndex, qty) end,
  function() Remotes.EndTurn:FireServer() end
)
local warehousePanel = WarehousePanel.new(
  root,
  function(goodIndex, qty) Remotes.TransferToWarehouse:FireServer(goodIndex, qty) end,
  function(goodIndex, qty) Remotes.TransferFromWarehouse:FireServer(goodIndex, qty) end
)

-- Receive state updates from server and refresh all panels
Remotes.StateUpdate.OnClientEvent:Connect(function(state)
  portPanel.update(state)
  statusStrip.update(state)
  inventoryPanel.update(state)
  pricesPanel.update(state)
  buySellPanel.update(state)
  warehousePanel.update(state)
end)

-- Start the game (Phase 1: always cash start; start choice UI added later)
-- TODO Phase 3: replace with start-choice screen that fires "cash" or "guns"
Remotes.ChooseStart:FireServer("cash")
-- Always request state after ChooseStart: handles both new sessions (server pushes
-- after init) and reconnects (ChooseStart guard returns early, but this still gets
-- the existing state pushed back to the client)
Remotes.RequestStateUpdate:FireServer()
