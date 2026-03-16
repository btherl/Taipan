-- BuySellPanel.lua
-- Good selector, amount input (with "A" = All shortcut), Buy and Sell buttons.
-- Fires callbacks; the GameController wires callbacks to RemoteEvents.

local Constants = require(game.ReplicatedStorage.shared.Constants)

local BuySellPanel = {}

function BuySellPanel.new(parent, onBuy, onSell, onEndTurn)
  -- onBuy(goodIndex, quantity), onSell(goodIndex, quantity), onEndTurn()

  local frame = Instance.new("Frame")
  frame.Name = "BuySellPanel"
  frame.Size = UDim2.new(1, 0, 0, 200)
  frame.Position = UDim2.new(0, 0, 0, 285)
  frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
  frame.Parent = parent

  -- Good selector buttons (1-4)
  local selectedGood = 1
  local goodButtons = {}

  for i = 1, 4 do
    local btn = Instance.new("TextButton")
    btn.Name = "GoodBtn" .. i
    btn.Size = UDim2.new(0.22, -4, 0, 28)
    btn.Position = UDim2.new((i-1)*0.25, 2, 0, 5)
    btn.BackgroundColor3 = i == 1 and Color3.fromRGB(60, 60, 20) or Color3.fromRGB(30, 30, 30)
    btn.BorderColor3 = Color3.fromRGB(100, 100, 40)
    btn.TextColor3 = Color3.fromRGB(200, 180, 80)
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = 11
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
  amountBox.Size = UDim2.new(0.5, -5, 0, 28)
  amountBox.Position = UDim2.new(0, 5, 0, 40)
  amountBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  amountBox.BorderColor3 = Color3.fromRGB(100, 100, 40)
  amountBox.TextColor3 = Color3.fromRGB(200, 180, 80)
  amountBox.Font = Enum.Font.RobotoMono
  amountBox.TextSize = 13
  amountBox.PlaceholderText = "Amount (A=All)"
  amountBox.Text = ""
  amountBox.Parent = frame

  -- "A" = All: handled in buy/sell callbacks
  local function parseAmount(state, isSell)
    local raw = amountBox.Text:upper()
    if raw == "A" then
      if isSell then
        return state and state.shipCargo[selectedGood] or 0
      else
        return state and state.holdSpace or 0
      end
    end
    return tonumber(raw) or 0
  end

  -- We hold a reference to the latest state for "All" shortcut
  local latestState = nil

  -- Buy button
  local buyBtn = Instance.new("TextButton")
  buyBtn.Name = "BuyBtn"
  buyBtn.Size = UDim2.new(0.22, -4, 0, 36)
  buyBtn.Position = UDim2.new(0, 5, 0, 75)
  buyBtn.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
  buyBtn.BorderColor3 = Color3.fromRGB(40, 120, 40)
  buyBtn.TextColor3 = Color3.fromRGB(100, 255, 100)
  buyBtn.Font = Enum.Font.RobotoMono
  buyBtn.TextSize = 14
  buyBtn.Text = "BUY"
  buyBtn.Parent = frame

  buyBtn.Activated:Connect(function()
    local qty = parseAmount(latestState, false)
    if qty > 0 then
      onBuy(selectedGood, qty)
      amountBox.Text = ""
    end
  end)

  -- Sell button
  local sellBtn = Instance.new("TextButton")
  sellBtn.Name = "SellBtn"
  sellBtn.Size = UDim2.new(0.22, -4, 0, 36)
  sellBtn.Position = UDim2.new(0.25, 0, 0, 75)
  sellBtn.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
  sellBtn.BorderColor3 = Color3.fromRGB(120, 40, 40)
  sellBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
  sellBtn.Font = Enum.Font.RobotoMono
  sellBtn.TextSize = 14
  sellBtn.Text = "SELL"
  sellBtn.Parent = frame

  sellBtn.Activated:Connect(function()
    local qty = parseAmount(latestState, true)
    if qty > 0 then
      onSell(selectedGood, qty)
      amountBox.Text = ""
    end
  end)

  -- End Turn button
  local endTurnBtn = Instance.new("TextButton")
  endTurnBtn.Name = "EndTurnBtn"
  endTurnBtn.Size = UDim2.new(0.3, -4, 0, 36)
  endTurnBtn.Position = UDim2.new(0.7, 0, 0, 75)
  endTurnBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 60)
  endTurnBtn.BorderColor3 = Color3.fromRGB(40, 40, 120)
  endTurnBtn.TextColor3 = Color3.fromRGB(100, 100, 255)
  endTurnBtn.Font = Enum.Font.RobotoMono
  endTurnBtn.TextSize = 12
  endTurnBtn.Text = "END TURN"
  endTurnBtn.Parent = frame

  endTurnBtn.Activated:Connect(function() onEndTurn() end)

  local panel = {}

  function panel.update(state)
    latestState = state
  end

  return panel
end

return BuySellPanel
