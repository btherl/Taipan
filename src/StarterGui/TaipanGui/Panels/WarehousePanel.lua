-- WarehousePanel.lua
-- Transfer goods between ship hold and Hong Kong warehouse.
-- Only visible when currentPort == Constants.HONG_KONG.
-- Fires callbacks; the GameController wires callbacks to RemoteEvents.

local Constants = require(game.ReplicatedStorage.shared.Constants)

local WarehousePanel = {}

function WarehousePanel.new(parent, onPut, onTake)
  -- onPut(goodIndex, quantity): transfer hold → warehouse
  -- onTake(goodIndex, quantity): transfer warehouse → hold

  -- Layout (6px rhythm):
  --   y=3   title / space label  22px → ends at 25
  --   y=28  good buttons         44px → ends at 72
  --   y=78  amount box           44px → ends at 122
  --   y=128 action buttons       44px → ends at 172
  --   frame height = 178

  local frame = Instance.new("Frame")
  frame.Name = "WarehousePanel"
  frame.Size = UDim2.new(1, 0, 0, 178)
  frame.Position = UDim2.new(0, 0, 0, 615)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(60, 60, 100)
  frame.Visible = false
  frame.Parent = parent

  -- Title
  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.Size = UDim2.new(0.5, 0, 0, 22)
  title.Position = UDim2.new(0, 5, 0, 3)
  title.BackgroundTransparency = 1
  title.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  title.Font = Enum.Font.RobotoMono
  title.TextSize = 12
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.Text = "GODOWN"
  title.Parent = frame

  -- Space label
  local spaceLabel = Instance.new("TextLabel")
  spaceLabel.Name = "SpaceLabel"
  spaceLabel.Size = UDim2.new(0.45, 0, 0, 22)
  spaceLabel.Position = UDim2.new(0.52, 0, 0, 3)
  spaceLabel.BackgroundTransparency = 1
  spaceLabel.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  spaceLabel.Font = Enum.Font.RobotoMono
  spaceLabel.TextSize = 11
  spaceLabel.TextXAlignment = Enum.TextXAlignment.Right
  spaceLabel.Text = "Used: 0 / 10000"
  spaceLabel.Parent = frame

  -- Good selector buttons (1-4)
  local selectedGood = 1
  local goodButtons = {}

  for i = 1, 4 do
    local btn = Instance.new("TextButton")
    btn.Name = "GoodBtn" .. i
    btn.Size = UDim2.new(0.22, -4, 0, 44)
    btn.Position = UDim2.new((i-1)*0.25, 2, 0, 28)
    btn.BackgroundColor3 = i == 1 and Color3.fromRGB(60, 60, 20) or Color3.fromRGB(30, 30, 30)
    btn.BorderColor3 = Color3.fromRGB(100, 100, 40)
    btn.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = 10
    btn.Text = Constants.GOOD_NAMES[i]:sub(1, 7)
    btn.Parent = frame
    goodButtons[i] = btn

    btn.Activated:Connect(function()
      selectedGood = i
      for j = 1, 4 do
        goodButtons[j].BackgroundColor3 = j == i
          and Color3.fromRGB(60, 60, 20)
          or  Color3.fromRGB(30, 30, 30)
      end
    end)
  end

  -- Amount input
  local amountBox = Instance.new("TextBox")
  amountBox.Name = "AmountBox"
  amountBox.Size = UDim2.new(0.5, -5, 0, 44)
  amountBox.Position = UDim2.new(0, 5, 0, 78)
  amountBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  amountBox.BorderColor3 = Color3.fromRGB(100, 100, 40)
  amountBox.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  amountBox.Font = Enum.Font.RobotoMono
  amountBox.TextSize = 13
  amountBox.PlaceholderText = "Amount (A=All)"
  amountBox.Text = ""
  amountBox.Parent = frame

  -- We hold a reference to the latest state for "All" shortcut
  local latestState = nil

  -- "A" = All: PUT uses shipCargo (all in hold), TAKE uses warehouseCargo (all in warehouse)
  local function parseAmount(state, isPut)
    local raw = amountBox.Text:upper()
    if raw == "A" then
      if isPut then
        return state and state.shipCargo[selectedGood] or 0
      else
        return state and state.warehouseCargo[selectedGood] or 0
      end
    end
    return tonumber(raw) or 0
  end

  -- PUT button (hold → warehouse)
  local putBtn = Instance.new("TextButton")
  putBtn.Name = "PutBtn"
  putBtn.Size = UDim2.new(0.22, -4, 0, 44)
  putBtn.Position = UDim2.new(0, 5, 0, 128)
  putBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 60)
  putBtn.BorderColor3 = Color3.fromRGB(40, 40, 120)
  putBtn.TextColor3 = Color3.fromRGB(120, 120, 220)   -- Blue
  putBtn.Font = Enum.Font.RobotoMono
  putBtn.TextSize = 12
  putBtn.Text = "PUT"
  putBtn.Parent = frame

  putBtn.Activated:Connect(function()
    local qty = parseAmount(latestState, true)
    if qty > 0 then
      onPut(selectedGood, qty)
      amountBox.Text = ""
    end
  end)

  -- TAKE button (warehouse → hold)
  local takeBtn = Instance.new("TextButton")
  takeBtn.Name = "TakeBtn"
  takeBtn.Size = UDim2.new(0.22, -4, 0, 44)
  takeBtn.Position = UDim2.new(0.25, 0, 0, 128)
  takeBtn.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
  takeBtn.BorderColor3 = Color3.fromRGB(120, 40, 40)
  takeBtn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
  takeBtn.Font = Enum.Font.RobotoMono
  takeBtn.TextSize = 12
  takeBtn.Text = "TAKE"
  takeBtn.Parent = frame

  takeBtn.Activated:Connect(function()
    local qty = parseAmount(latestState, false)
    if qty > 0 then
      onTake(selectedGood, qty)
      amountBox.Text = ""
    end
  end)

  local panel = {}

  function panel.update(state)
    frame.Visible = (state.currentPort == Constants.HONG_KONG)
    spaceLabel.Text = "Used: " .. state.warehouseUsed .. " / " .. Constants.WAREHOUSE_CAPACITY
    latestState = state
  end

  return panel
end

return WarehousePanel
