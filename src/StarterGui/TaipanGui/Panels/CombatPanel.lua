-- CombatPanel.lua
-- Full-screen combat overlay shown when state.combat ~= nil.
-- ZIndex=15 (below GameOverPanel at 20, above all other panels).

local CombatPanel = {}

local AMBER = Color3.fromRGB(200, 180, 80)
local RED   = Color3.fromRGB(220, 80, 80)
local GREEN = Color3.fromRGB(140, 200, 80)

local GOOD_NAMES = {"Opium", "Silk", "Arms", "General"}
local Z = 15

function CombatPanel.new(parent, onFight, onRun, onThrow)
  -- onFight()
  -- onRun()
  -- onThrow(goodIndex, qty)

  local selectedGood = 1

  -- Layout:
  --   0   header      40px
  --   40  enemy count 24px
  --   64  enemy grid  40px
  --   104 action row  52px  (8px top pad + 44px buttons)
  --   156 throw row   52px  (8px top pad + 44px buttons)
  --   208 total height
  -- Root frame is 480×208

  local frame = Instance.new("Frame")
  frame.Name = "CombatPanel"
  frame.Size = UDim2.new(0, 480, 0, 208)
  frame.Position = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3 = Color3.fromRGB(15, 5, 5)
  frame.BackgroundTransparency = 0.05
  frame.BorderSizePixel = 0
  frame.ZIndex = Z
  frame.Visible = false
  frame.Parent = parent

  -- ── 1. Header row (full width, 40px) ──────────────────────────────────────
  local header = Instance.new("Frame")
  header.Name = "Header"
  header.Size = UDim2.new(1, 0, 0, 40)
  header.Position = UDim2.new(0, 0, 0, 0)
  header.BackgroundColor3 = Color3.fromRGB(20, 5, 5)
  header.BorderSizePixel = 0
  header.ZIndex = Z
  header.Parent = frame

  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "TitleLabel"
  titleLabel.Size = UDim2.new(0.5, 0, 1, 0)
  titleLabel.Position = UDim2.new(0, 8, 0, 0)
  titleLabel.BackgroundTransparency = 1
  titleLabel.TextColor3 = RED
  titleLabel.Font = Enum.Font.RobotoMono
  titleLabel.TextSize = 24
  titleLabel.TextXAlignment = Enum.TextXAlignment.Left
  titleLabel.ZIndex = Z
  titleLabel.Text = "BATTLE!!"
  titleLabel.Parent = header

  local swLabel = Instance.new("TextLabel")
  swLabel.Name = "SeaworthinessLabel"
  swLabel.Size = UDim2.new(0.5, -8, 1, 0)
  swLabel.Position = UDim2.new(0.5, 0, 0, 0)
  swLabel.BackgroundTransparency = 1
  swLabel.TextColor3 = GREEN
  swLabel.Font = Enum.Font.RobotoMono
  swLabel.TextSize = 16
  swLabel.TextXAlignment = Enum.TextXAlignment.Right
  swLabel.ZIndex = Z
  swLabel.Text = "SW: 100%"
  swLabel.Parent = header

  -- ── 2. Enemy count label (full width, 24px) ────────────────────────────────
  local enemyCountLabel = Instance.new("TextLabel")
  enemyCountLabel.Name = "EnemyCountLabel"
  enemyCountLabel.Size = UDim2.new(1, 0, 0, 24)
  enemyCountLabel.Position = UDim2.new(0, 0, 0, 40)
  enemyCountLabel.BackgroundTransparency = 1
  enemyCountLabel.TextColor3 = AMBER
  enemyCountLabel.Font = Enum.Font.RobotoMono
  enemyCountLabel.TextSize = 14
  enemyCountLabel.TextXAlignment = Enum.TextXAlignment.Center
  enemyCountLabel.ZIndex = Z
  enemyCountLabel.Text = "Enemy ships: 0 remaining"
  enemyCountLabel.Parent = frame

  -- ── 3. Enemy grid (full width, 40px, 10 squares) ───────────────────────────
  local gridFrame = Instance.new("Frame")
  gridFrame.Name = "EnemyGrid"
  gridFrame.Size = UDim2.new(1, 0, 0, 40)
  gridFrame.Position = UDim2.new(0, 0, 0, 64)
  gridFrame.BackgroundTransparency = 1
  gridFrame.ZIndex = Z
  gridFrame.Parent = frame

  local gridSquares = {}
  for i = 1, 10 do
    local sq = Instance.new("Frame")
    sq.Name = "GridSquare" .. i
    sq.Size = UDim2.new(0, 36, 0, 36)
    -- Center 10 squares (each 36px wide) with 4px gap: total = 10*36 + 9*4 = 396px, left offset = (480-396)/2 = 42
    sq.Position = UDim2.new(0, 42 + (i - 1) * 40, 0, 2)
    sq.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    sq.BorderSizePixel = 0
    sq.ZIndex = Z
    sq.Parent = gridFrame
    gridSquares[i] = sq
  end

  -- ── 4. Action row (full width, 52px: 8px pad + 44px buttons) ──────────────
  local actionRow = Instance.new("Frame")
  actionRow.Name = "ActionRow"
  actionRow.Size = UDim2.new(1, 0, 0, 52)
  actionRow.Position = UDim2.new(0, 0, 0, 104)
  actionRow.BackgroundTransparency = 1
  actionRow.ZIndex = Z
  actionRow.Parent = frame

  -- Center two 140px buttons with a gap; total = 140+140+20 = 300; left = (480-300)/2 = 90
  local fightBtn = Instance.new("TextButton")
  fightBtn.Name = "FightBtn"
  fightBtn.Size = UDim2.new(0, 140, 0, 44)
  fightBtn.Position = UDim2.new(0, 90, 0, 8)
  fightBtn.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
  fightBtn.BorderSizePixel = 0
  fightBtn.TextColor3 = RED
  fightBtn.Font = Enum.Font.RobotoMono
  fightBtn.TextSize = 16
  fightBtn.ZIndex = Z
  fightBtn.Text = "FIGHT"
  fightBtn.Parent = actionRow

  local runBtn = Instance.new("TextButton")
  runBtn.Name = "RunBtn"
  runBtn.Size = UDim2.new(0, 140, 0, 44)
  runBtn.Position = UDim2.new(0, 250, 0, 8)
  runBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 180)
  runBtn.BorderSizePixel = 0
  runBtn.TextColor3 = Color3.fromRGB(120, 120, 220)   -- Blue
  runBtn.Font = Enum.Font.RobotoMono
  runBtn.TextSize = 16
  runBtn.ZIndex = Z
  runBtn.Text = "RUN"
  runBtn.Parent = actionRow

  -- ── 5. Throw row (full width, 52px: 8px pad + 44px buttons) ───────────────
  local throwRow = Instance.new("Frame")
  throwRow.Name = "ThrowRow"
  throwRow.Size = UDim2.new(1, 0, 0, 52)
  throwRow.Position = UDim2.new(0, 0, 0, 156)
  throwRow.BackgroundTransparency = 1
  throwRow.ZIndex = Z
  throwRow.Parent = frame

  -- Layout: 4 good buttons (4×70=280) + gap4 (4×4=16) + amount box (60) + gap (4) + throw btn (80) = 440; left = (480-440)/2 = 20
  local goodBtns = {}
  for i, name in ipairs(GOOD_NAMES) do
    local btn = Instance.new("TextButton")
    btn.Name = "GoodBtn" .. i
    btn.Size = UDim2.new(0, 70, 0, 44)
    btn.Position = UDim2.new(0, 20 + (i - 1) * 74, 0, 8)
    btn.BackgroundColor3 = Color3.fromRGB(60, 30, 10)
    btn.BorderSizePixel = 0
    btn.TextColor3 = AMBER
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = 11
    btn.ZIndex = Z
    btn.Text = name
    btn.Parent = throwRow
    goodBtns[i] = btn
  end

  local amountBox = Instance.new("TextBox")
  amountBox.Name = "AmountBox"
  amountBox.Size = UDim2.new(0, 60, 0, 44)
  amountBox.Position = UDim2.new(0, 20 + 4 * 74, 0, 8)
  amountBox.BackgroundColor3 = Color3.fromRGB(30, 20, 5)
  amountBox.BorderColor3 = Color3.fromRGB(120, 80, 20)
  amountBox.BorderSizePixel = 1
  amountBox.TextColor3 = AMBER
  amountBox.Font = Enum.Font.RobotoMono
  amountBox.TextSize = 14
  amountBox.ZIndex = Z
  amountBox.Text = "10"
  amountBox.Parent = throwRow

  local throwBtn = Instance.new("TextButton")
  throwBtn.Name = "ThrowBtn"
  throwBtn.Size = UDim2.new(0, 80, 0, 44)
  throwBtn.Position = UDim2.new(0, 20 + 4 * 74 + 64, 0, 8)
  throwBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 20)
  throwBtn.BorderSizePixel = 0
  throwBtn.TextColor3 = Color3.fromRGB(220, 120, 60)   -- Orange
  throwBtn.Font = Enum.Font.RobotoMono
  throwBtn.TextSize = 14
  throwBtn.ZIndex = Z
  throwBtn.Text = "THROW"
  throwBtn.Parent = throwRow

  -- ── Internal helpers ───────────────────────────────────────────────────────

  local function refreshGoodButtons()
    for i, btn in ipairs(goodBtns) do
      if i == selectedGood then
        btn.BackgroundColor3 = Color3.fromRGB(180, 100, 20)
        btn.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber selected
      else
        btn.BackgroundColor3 = Color3.fromRGB(60, 30, 10)
        btn.TextColor3 = AMBER
      end
    end
  end

  refreshGoodButtons()

  -- ── Wire button events ─────────────────────────────────────────────────────

  fightBtn.Activated:Connect(function()
    onFight()
  end)

  runBtn.Activated:Connect(function()
    onRun()
  end)

  throwBtn.Activated:Connect(function()
    local amount = tonumber(amountBox.Text) or 0
    onThrow(selectedGood, amount)
  end)

  for i, btn in ipairs(goodBtns) do
    local idx = i
    btn.Activated:Connect(function()
      selectedGood = idx
      refreshGoodButtons()
    end)
  end

  -- ── panel.update ───────────────────────────────────────────────────────────

  local panel = {}

  function panel.update(state)
    if not state.combat then
      frame.Visible = false
      return
    end
    frame.Visible = true

    -- Seaworthiness
    local shipCapacity = state.shipCapacity or 1
    local damage = state.damage or 0
    local sw = 100 - math.floor(damage / shipCapacity * 100)
    if sw < 0 then sw = 0 end
    swLabel.Text = "SW: " .. sw .. "%"
    if sw > 60 then
      swLabel.TextColor3 = GREEN
    elseif sw >= 30 then
      swLabel.TextColor3 = AMBER
    else
      swLabel.TextColor3 = RED
    end

    -- Enemy count
    local total = state.combat.enemyTotal or 0
    enemyCountLabel.Text = "Enemy ships: " .. total .. " remaining"

    -- Grid indicators
    local grid = state.combat.grid or {}
    for i = 1, 10 do
      local slot = grid[i]
      if slot ~= nil then
        gridSquares[i].BackgroundColor3 = GREEN
      else
        gridSquares[i].BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      end
    end
  end

  return panel
end

return CombatPanel
