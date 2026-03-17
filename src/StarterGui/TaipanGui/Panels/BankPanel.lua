-- BankPanel.lua
-- Comprador's House: deposit and withdraw from the bank.
-- Only visible at Hong Kong.

local Constants = require(game.ReplicatedStorage.shared.Constants)

local BankPanel = {}

function BankPanel.new(parent, onDeposit, onWithdraw)
  -- onDeposit(amount), onWithdraw(amount)

  -- Layout (6px rhythm):
  --   y=3   title / balance label  22px → ends at 25
  --   y=28  amount box             44px → ends at 72
  --   y=78  action buttons         44px → ends at 122
  --   frame height = 128

  local frame = Instance.new("Frame")
  frame.Name = "BankPanel"
  frame.Size = UDim2.new(1, 0, 0, 128)
  frame.Position = UDim2.new(0, 0, 0, 1010)
  frame.BackgroundColor3 = Color3.fromRGB(10, 18, 20)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(40, 100, 110)
  frame.Visible = false
  frame.Parent = parent

  -- Title + balance label
  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.Size = UDim2.new(0.5, 0, 0, 22)
  title.Position = UDim2.new(0, 5, 0, 3)
  title.BackgroundTransparency = 1
  title.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  title.Font = Enum.Font.RobotoMono
  title.TextSize = 12
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.Text = "COMPRADOR'S HOUSE"
  title.Parent = frame

  local balanceLabel = Instance.new("TextLabel")
  balanceLabel.Name = "BalanceLabel"
  balanceLabel.Size = UDim2.new(0.45, 0, 0, 22)
  balanceLabel.Position = UDim2.new(0.52, 0, 0, 3)
  balanceLabel.BackgroundTransparency = 1
  balanceLabel.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  balanceLabel.Font = Enum.Font.RobotoMono
  balanceLabel.TextSize = 11
  balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
  balanceLabel.Text = "Balance: $0"
  balanceLabel.Parent = frame

  -- Amount input
  local amountBox = Instance.new("TextBox")
  amountBox.Name = "AmountBox"
  amountBox.Size = UDim2.new(0.5, -5, 0, 44)
  amountBox.Position = UDim2.new(0, 5, 0, 28)
  amountBox.BackgroundColor3 = Color3.fromRGB(8, 12, 14)
  amountBox.BorderColor3 = Color3.fromRGB(40, 100, 110)
  amountBox.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  amountBox.Font = Enum.Font.RobotoMono
  amountBox.TextSize = 12
  amountBox.PlaceholderText = "Amount (A=All)"
  amountBox.Text = ""
  amountBox.Parent = frame

  -- Deposit button
  local depositBtn = Instance.new("TextButton")
  depositBtn.Name = "DepositBtn"
  depositBtn.Size = UDim2.new(0.22, -4, 0, 44)
  depositBtn.Position = UDim2.new(0, 5, 0, 78)
  depositBtn.BackgroundColor3 = Color3.fromRGB(15, 40, 45)
  depositBtn.BorderColor3 = Color3.fromRGB(30, 100, 110)
  depositBtn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
  depositBtn.Font = Enum.Font.RobotoMono
  depositBtn.TextSize = 11
  depositBtn.Text = "DEPOSIT"
  depositBtn.Parent = frame

  -- Withdraw button
  local withdrawBtn = Instance.new("TextButton")
  withdrawBtn.Name = "WithdrawBtn"
  withdrawBtn.Size = UDim2.new(0.22, -4, 0, 44)
  withdrawBtn.Position = UDim2.new(0.25, 0, 0, 78)
  withdrawBtn.BackgroundColor3 = Color3.fromRGB(20, 30, 35)
  withdrawBtn.BorderColor3 = Color3.fromRGB(40, 80, 90)
  withdrawBtn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
  withdrawBtn.Font = Enum.Font.RobotoMono
  withdrawBtn.TextSize = 11
  withdrawBtn.Text = "WITHDRAW"
  withdrawBtn.Parent = frame

  -- Latest state for "A" = All shortcut
  local latestState = nil

  local function parseAmount(isDeposit)
    local raw = amountBox.Text:upper()
    if raw == "A" and latestState then
      if isDeposit then
        return latestState.cash
      else
        return latestState.bankBalance
      end
    end
    return tonumber(raw) or 0
  end

  depositBtn.Activated:Connect(function()
    local qty = parseAmount(true)
    if qty > 0 then
      onDeposit(qty)
      amountBox.Text = ""
    end
  end)

  withdrawBtn.Activated:Connect(function()
    local qty = parseAmount(false)
    if qty > 0 then
      onWithdraw(qty)
      amountBox.Text = ""
    end
  end)

  local panel = {}

  function panel.update(state)
    frame.Visible = (state.currentPort == Constants.HONG_KONG)
    balanceLabel.Text = string.format("Balance: $%d", state.bankBalance)
    latestState = state
  end

  return panel
end

return BankPanel
