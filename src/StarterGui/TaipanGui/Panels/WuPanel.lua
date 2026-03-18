-- WuPanel.lua
-- Elder Brother Wu: repay debt, borrow, Li Yuen protection offer, leave.
-- Fires automatically on HK arrival. Only visible at Hong Kong.

local Constants = require(game.ReplicatedStorage.shared.Constants)

local WuPanel = {}

function WuPanel.new(parent, onRepay, onBorrow, onLeaveWu, onBuyLiYuen)
  -- onRepay(amount), onBorrow(amount), onLeaveWu(), onBuyLiYuen()

  -- Layout (6px rhythm):
  --   y=3   title             22px → ends at 25
  --   y=28  debt label        20px → ends at 48
  --   y=54  repay row         44px → ends at 98
  --   y=104 borrow label      20px → ends at 124
  --   y=130 borrow row        44px → ends at 174
  --   y=180 li yuen row       44px → ends at 224 (conditional)
  --   y=230 leave button      44px → ends at 274
  --   frame height = 280

  local frame = Instance.new("Frame")
  frame.Name = "WuPanel"
  frame.Size = UDim2.new(1, 0, 0, 280)
  frame.Position = UDim2.new(0, 0, 0, 780)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 25)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(60, 40, 120)
  frame.Visible = false
  frame.Parent = parent

  -- Title
  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.Size = UDim2.new(1, -10, 0, 22)
  title.Position = UDim2.new(0, 5, 0, 3)
  title.BackgroundTransparency = 1
  title.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  title.Font = Enum.Font.RobotoMono
  title.TextSize = 13
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.Text = "ELDER BROTHER WU"
  title.Parent = frame

  -- Debt info label
  local debtLabel = Instance.new("TextLabel")
  debtLabel.Name = "DebtLabel"
  debtLabel.Size = UDim2.new(1, -10, 0, 20)
  debtLabel.Position = UDim2.new(0, 5, 0, 28)
  debtLabel.BackgroundTransparency = 1
  debtLabel.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  debtLabel.Font = Enum.Font.RobotoMono
  debtLabel.TextSize = 11
  debtLabel.TextXAlignment = Enum.TextXAlignment.Left
  debtLabel.Text = "Debt: $0 | Max Repay: $0"
  debtLabel.Parent = frame

  -- Repay amount box
  local repayBox = Instance.new("TextBox")
  repayBox.Name = "RepayBox"
  repayBox.Size = UDim2.new(0.5, -5, 0, 44)
  repayBox.Position = UDim2.new(0, 5, 0, 54)
  repayBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  repayBox.BorderColor3 = Color3.fromRGB(80, 60, 140)
  repayBox.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  repayBox.Font = Enum.Font.RobotoMono
  repayBox.TextSize = 12
  repayBox.PlaceholderText = "Repay (A=All)"
  repayBox.Text = ""
  repayBox.Parent = frame

  -- Repay button
  local repayBtn = Instance.new("TextButton")
  repayBtn.Name = "RepayBtn"
  repayBtn.Size = UDim2.new(0.22, -4, 0, 44)
  repayBtn.Position = UDim2.new(0.55, 0, 0, 54)
  repayBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 60)
  repayBtn.BorderColor3 = Color3.fromRGB(60, 40, 120)
  repayBtn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
  repayBtn.Font = Enum.Font.RobotoMono
  repayBtn.TextSize = 11
  repayBtn.Text = "REPAY"
  repayBtn.Parent = frame

  -- Borrow info label
  local borrowLabel = Instance.new("TextLabel")
  borrowLabel.Name = "BorrowLabel"
  borrowLabel.Size = UDim2.new(1, -10, 0, 20)
  borrowLabel.Position = UDim2.new(0, 5, 0, 104)
  borrowLabel.BackgroundTransparency = 1
  borrowLabel.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  borrowLabel.Font = Enum.Font.RobotoMono
  borrowLabel.TextSize = 11
  borrowLabel.TextXAlignment = Enum.TextXAlignment.Left
  borrowLabel.Text = "Max borrow: $0"
  borrowLabel.Parent = frame

  -- Borrow amount box
  local borrowBox = Instance.new("TextBox")
  borrowBox.Name = "BorrowBox"
  borrowBox.Size = UDim2.new(0.5, -5, 0, 44)
  borrowBox.Position = UDim2.new(0, 5, 0, 130)
  borrowBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  borrowBox.BorderColor3 = Color3.fromRGB(80, 60, 140)
  borrowBox.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  borrowBox.Font = Enum.Font.RobotoMono
  borrowBox.TextSize = 12
  borrowBox.PlaceholderText = "Borrow (A=All)"
  borrowBox.Text = ""
  borrowBox.Parent = frame

  -- Borrow button
  local borrowBtn = Instance.new("TextButton")
  borrowBtn.Name = "BorrowBtn"
  borrowBtn.Size = UDim2.new(0.22, -4, 0, 44)
  borrowBtn.Position = UDim2.new(0.55, 0, 0, 130)
  borrowBtn.BackgroundColor3 = Color3.fromRGB(30, 15, 50)
  borrowBtn.BorderColor3 = Color3.fromRGB(80, 40, 100)
  borrowBtn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
  borrowBtn.Font = Enum.Font.RobotoMono
  borrowBtn.TextSize = 11
  borrowBtn.Text = "BORROW"
  borrowBtn.Parent = frame

  -- Li Yuen protection row (hidden when no offer)
  local liYuenRow = Instance.new("Frame")
  liYuenRow.Name = "LiYuenRow"
  liYuenRow.Size = UDim2.new(1, 0, 0, 44)
  liYuenRow.Position = UDim2.new(0, 0, 0, 180)
  liYuenRow.BackgroundColor3 = Color3.fromRGB(15, 25, 15)
  liYuenRow.BorderColor3 = Color3.fromRGB(40, 80, 40)
  liYuenRow.BorderSizePixel = 1
  liYuenRow.Visible = false
  liYuenRow.Parent = frame

  local liYuenLabel = Instance.new("TextLabel")
  liYuenLabel.Name = "LiYuenLabel"
  liYuenLabel.Size = UDim2.new(0.7, -5, 1, 0)
  liYuenLabel.Position = UDim2.new(0, 5, 0, 0)
  liYuenLabel.BackgroundTransparency = 1
  liYuenLabel.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
  liYuenLabel.Font = Enum.Font.RobotoMono
  liYuenLabel.TextSize = 10
  liYuenLabel.TextXAlignment = Enum.TextXAlignment.Left
  liYuenLabel.Text = "Li Yuen asks $0 for protection"
  liYuenLabel.Parent = liYuenRow

  local buyBtn = Instance.new("TextButton")
  buyBtn.Name = "BuyBtn"
  buyBtn.Size = UDim2.new(0.22, -4, 0, 44)
  buyBtn.Position = UDim2.new(0.75, 0, 0, 0)
  buyBtn.BackgroundColor3 = Color3.fromRGB(20, 50, 20)
  buyBtn.BorderColor3 = Color3.fromRGB(40, 100, 40)
  buyBtn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
  buyBtn.Font = Enum.Font.RobotoMono
  buyBtn.TextSize = 10
  buyBtn.Text = "BUY"
  buyBtn.Parent = liYuenRow

  -- Leave Wu button
  local leaveBtn = Instance.new("TextButton")
  leaveBtn.Name = "LeaveBtn"
  leaveBtn.Size = UDim2.new(0.35, -4, 0, 44)
  leaveBtn.Position = UDim2.new(0.65, 0, 0, 230)
  leaveBtn.BackgroundColor3 = Color3.fromRGB(35, 10, 10)
  leaveBtn.BorderColor3 = Color3.fromRGB(100, 30, 30)
  leaveBtn.TextColor3 = Color3.fromRGB(220, 80, 80)   -- Red
  leaveBtn.Font = Enum.Font.RobotoMono
  leaveBtn.TextSize = 11
  leaveBtn.Text = "LEAVE WU"
  leaveBtn.Parent = frame

  -- Latest state reference for "A" = All shortcut
  local latestState = nil

  -- Parse repay amount: "A" = min(debt, cash)
  local function parseRepayAmount()
    local raw = repayBox.Text:upper()
    if raw == "A" and latestState then
      return math.min(latestState.debt, latestState.cash)
    end
    return tonumber(raw) or 0
  end

  -- Parse borrow amount: "A" = max borrow (2 * cash)
  local function parseBorrowAmount()
    local raw = borrowBox.Text:upper()
    if raw == "A" and latestState then
      return 2 * latestState.cash
    end
    return tonumber(raw) or 0
  end

  repayBtn.Activated:Connect(function()
    local qty = parseRepayAmount()
    if qty > 0 then
      onRepay(qty)
      repayBox.Text = ""
    end
  end)

  borrowBtn.Activated:Connect(function()
    local qty = parseBorrowAmount()
    if qty > 0 then
      onBorrow(qty)
      borrowBox.Text = ""
    end
  end)

  buyBtn.Activated:Connect(function()
    onBuyLiYuen()
  end)

  leaveBtn.Activated:Connect(function()
    onLeaveWu()
  end)

  local panel = {}

  function panel.update(state)
    frame.Visible = (state.currentPort == Constants.HONG_KONG)
    local maxRepay = math.min(state.debt, state.cash)
    debtLabel.Text = string.format("Debt: $%d | Max Repay: $%d", state.debt, maxRepay)
    borrowLabel.Text = string.format("Max borrow: $%d", 2 * state.cash)
    -- Enable/disable repay button
    repayBtn.Active = (state.debt > 0 and state.cash > 0)
    repayBtn.TextColor3 = repayBtn.Active
      and Color3.fromRGB(140, 200, 80)    -- Green active
      or  Color3.fromRGB(80, 80, 80)      -- Grey disabled
    -- Enable/disable borrow button
    borrowBtn.Active = (state.cash > 0)
    borrowBtn.TextColor3 = borrowBtn.Active
      and Color3.fromRGB(140, 200, 80)    -- Green active
      or  Color3.fromRGB(80, 80, 80)      -- Grey disabled
    -- Li Yuen offer row
    if state.liYuenOfferCost ~= nil then
      liYuenRow.Visible = true
      liYuenLabel.Text = string.format("Li Yuen asks $%d for protection", state.liYuenOfferCost)
    else
      liYuenRow.Visible = false
    end
    latestState = state
  end

  return panel
end

return WuPanel
