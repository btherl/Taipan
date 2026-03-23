-- InventoryPanel.lua
-- Shows hold cargo (left) and warehouse cargo (right) side by side.

local Constants = require(game.ReplicatedStorage.shared.Constants)

local InventoryPanel = {}

function InventoryPanel.new(parent)
  local frame = Instance.new("Frame")
  frame.Name = "InventoryPanel"
  frame.Size = UDim2.new(1, 0, 0, 120)
  frame.Position = UDim2.new(0, 0, 0, 160)
  frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
  frame.Parent = parent

  local holdHeader = Instance.new("TextLabel")
  holdHeader.Name = "HoldHeader"
  holdHeader.Size = UDim2.new(0.5, -5, 0, 20)
  holdHeader.Position = UDim2.new(0, 5, 0, 0)
  holdHeader.BackgroundTransparency = 1
  holdHeader.TextColor3 = Color3.fromRGB(100, 200, 100)
  holdHeader.Font = Enum.Font.RobotoMono
  holdHeader.TextSize = 13
  holdHeader.TextXAlignment = Enum.TextXAlignment.Left
  holdHeader.Parent = frame
  local wareHeader = Instance.new("TextLabel")
  wareHeader.Name = "WareHeader"
  wareHeader.Size = UDim2.new(0.5, -5, 0, 20)
  wareHeader.Position = UDim2.new(0.5, 0, 0, 0)
  wareHeader.BackgroundTransparency = 1
  wareHeader.TextColor3 = Color3.fromRGB(100, 200, 100)
  wareHeader.Font = Enum.Font.RobotoMono
  wareHeader.TextSize = 13
  wareHeader.TextXAlignment = Enum.TextXAlignment.Left
  wareHeader.Parent = frame

  local holdLabels = {}
  local wareLabels = {}

  for i = 1, 4 do
    local holdLbl = Instance.new("TextLabel")
    holdLbl.Size = UDim2.new(0.5, -5, 0, 22)
    holdLbl.Position = UDim2.new(0, 5, 0, 18 + (i-1)*22)
    holdLbl.BackgroundTransparency = 1
    holdLbl.TextColor3 = Color3.fromRGB(200, 180, 80)
    holdLbl.Font = Enum.Font.RobotoMono
    holdLbl.TextSize = 13
    holdLbl.TextXAlignment = Enum.TextXAlignment.Left
    holdLbl.Parent = frame
    holdLabels[i] = holdLbl

    local wareLbl = Instance.new("TextLabel")
    wareLbl.Size = UDim2.new(0.5, -5, 0, 22)
    wareLbl.Position = UDim2.new(0.5, 0, 0, 18 + (i-1)*22)
    wareLbl.BackgroundTransparency = 1
    wareLbl.TextColor3 = Color3.fromRGB(200, 180, 80)
    wareLbl.Font = Enum.Font.RobotoMono
    wareLbl.TextSize = 13
    wareLbl.TextXAlignment = Enum.TextXAlignment.Left
    wareLbl.Parent = frame
    wareLabels[i] = wareLbl
  end

  local panel = {}
  function panel.update(state)
    holdHeader.Text = string.format("HOLD [%d free]", state.holdSpace)
    wareHeader.Text = string.format("WAREHOUSE [%d/%d]", state.warehouseUsed, Constants.WAREHOUSE_CAPACITY)
    for i = 1, 4 do
      holdLabels[i].Text = string.format("%-14s %4d", Constants.GOOD_NAMES[i], state.shipCargo[i])
      wareLabels[i].Text = string.format("%-14s %4d", Constants.GOOD_NAMES[i], state.warehouseCargo[i])
    end
  end
  return panel
end

return InventoryPanel
