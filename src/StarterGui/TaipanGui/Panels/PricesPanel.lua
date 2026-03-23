-- PricesPanel.lua
-- Shows current prices for all 4 goods.

local Constants = require(game.ReplicatedStorage.shared.Constants)

local PricesPanel = {}

function PricesPanel.new(parent)
  local frame = Instance.new("Frame")
  frame.Name = "PricesPanel"
  frame.Size = UDim2.new(0.4, 0, 0, 120)
  frame.Position = UDim2.new(0, 0, 0, 285)
  frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
  frame.Parent = parent

  local header = Instance.new("TextLabel")
  header.Name = "Header"
  header.Size = UDim2.new(1, 0, 0, 20)
  header.Position = UDim2.new(0, 5, 0, 0)
  header.BackgroundTransparency = 1
  header.Text = "PRICES"
  header.TextColor3 = Color3.fromRGB(100, 200, 100)
  header.Font = Enum.Font.RobotoMono
  header.TextSize = 13
  header.TextXAlignment = Enum.TextXAlignment.Left
  header.Parent = frame

  local priceLabels = {}
  for i = 1, 4 do
    local lbl = Instance.new("TextLabel")
    lbl.Name = "Price" .. i
    lbl.Size = UDim2.new(1, -10, 0, 22)
    lbl.Position = UDim2.new(0, 5, 0, 18 + (i-1)*22)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(200, 180, 80)
    lbl.Font = Enum.Font.RobotoMono
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame
    priceLabels[i] = lbl
  end

  local panel = {}
  function panel.update(state)
    for i = 1, 4 do
      priceLabels[i].Text = string.format("%-14s $%d", Constants.GOOD_NAMES[i], state.currentPrices[i])
    end
  end
  return panel
end

return PricesPanel
