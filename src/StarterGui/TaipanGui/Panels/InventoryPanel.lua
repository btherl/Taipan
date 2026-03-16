-- InventoryPanel.lua
-- Shows hold cargo (left) and warehouse cargo (right) side by side.

local Constants = require(game.ReplicatedStorage.shared.Constants)

local InventoryPanel = {}

function InventoryPanel.new(parent)
  local frame = Instance.new("Frame")
  frame.Name = "InventoryPanel"
  frame.Size = UDim2.new(1, 0, 0, 120)
  frame.Position = UDim2.new(0, 0, 0, 130)
  frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
  frame.Parent = parent

  -- Header
  local header = Instance.new("TextLabel")
  header.Size = UDim2.new(1, 0, 0, 20)
  header.Position = UDim2.new(0, 0, 0, 0)
  header.BackgroundTransparency = 1
  header.Text = "HOLD                    WAREHOUSE"
  header.TextColor3 = Color3.fromRGB(100, 200, 100)  -- green header
  header.Font = Enum.Font.RobotoMono
  header.TextSize = 13
  header.TextXAlignment = Enum.TextXAlignment.Left
  header.Parent = frame

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
    for i = 1, 4 do
      holdLabels[i].Text = string.format("%-14s %4d", Constants.GOOD_NAMES[i], state.shipCargo[i])
      wareLabels[i].Text = string.format("%-14s %4d", Constants.GOOD_NAMES[i], state.warehouseCargo[i])
    end
  end

  return panel
end

return InventoryPanel
