-- StatusStrip.lua
-- One-line display: Cash | Debt | Bank
-- Receives the full game state table and refreshes labels.

local StatusStrip = {}

function StatusStrip.new(parent)
  local frame = Instance.new("Frame")
  frame.Name = "StatusStrip"
  frame.Size = UDim2.new(1, 0, 0, 30)
  frame.Position = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
  frame.BorderSizePixel = 0
  frame.Parent = parent

  local layout = Instance.new("UIListLayout")
  layout.FillDirection = Enum.FillDirection.Horizontal
  layout.Padding = UDim.new(0, 10)
  layout.SortOrder = Enum.SortOrder.LayoutOrder
  layout.Parent = frame

  local function makeLabel(name)
    local lbl = Instance.new("TextLabel")
    lbl.Name = name
    lbl.Size = UDim2.new(0.33, -7, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(200, 180, 80)  -- amber terminal
    lbl.Font = Enum.Font.RobotoMono
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame
    return lbl
  end

  local cashLabel = makeLabel("CashLabel")
  cashLabel.LayoutOrder = 1
  local debtLabel = makeLabel("DebtLabel")
  debtLabel.LayoutOrder = 2
  local bankLabel = makeLabel("BankLabel")
  bankLabel.LayoutOrder = 3

  local strip = {}

  function strip.update(state)
    cashLabel.Text = string.format("Cash: $%d", state.cash)
    debtLabel.Text = string.format("Debt: $%d", state.debt)
    bankLabel.Text = string.format("Bank: $%d", state.bankBalance)
  end

  return strip
end

return StatusStrip
