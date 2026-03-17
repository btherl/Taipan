-- PortPanel.lua
-- Shows current port name, date, and 7 clickable port travel buttons.
-- Current port button is dimmed/disabled; others fire onTravel(destinationIndex).

local Constants = require(game.ReplicatedStorage.shared.Constants)

local PortPanel = {}

function PortPanel.new(parent, onTravel, onRetire, onQuit)
  -- parent: Frame (the root 480px frame)
  -- onTravel(destinationIndex: number): called when player clicks a port button

  -- Layout:
  --   y=4   port label / date label  28px → ends at 32
  --   y=36  port buttons             50px → ends at 86
  --   y=90  retire / quit buttons    44px → ends at 134
  --   frame height = 140

  local frame = Instance.new("Frame")
  frame.Name = "PortPanel"
  frame.Size = UDim2.new(1, 0, 0, 140)
  frame.Position = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  frame.BorderSizePixel = 1
  frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
  frame.Parent = parent

  -- Port name label
  local portLabel = Instance.new("TextLabel")
  portLabel.Name = "PortLabel"
  portLabel.Size = UDim2.new(0.6, 0, 0, 28)
  portLabel.Position = UDim2.new(0, 5, 0, 4)
  portLabel.BackgroundTransparency = 1
  portLabel.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  portLabel.Font = Enum.Font.RobotoMono
  portLabel.TextSize = 14
  portLabel.TextXAlignment = Enum.TextXAlignment.Left
  portLabel.Text = "HONG KONG"
  portLabel.Parent = frame

  -- Date label
  local dateLabel = Instance.new("TextLabel")
  dateLabel.Name = "DateLabel"
  dateLabel.Size = UDim2.new(0.35, 0, 0, 28)
  dateLabel.Position = UDim2.new(0.62, 0, 0, 4)
  dateLabel.BackgroundTransparency = 1
  dateLabel.TextColor3 = Color3.fromRGB(200, 180, 80)   -- Amber
  dateLabel.Font = Enum.Font.RobotoMono
  dateLabel.TextSize = 12
  dateLabel.TextXAlignment = Enum.TextXAlignment.Right
  dateLabel.Text = "Jan 1860"
  dateLabel.Parent = frame

  -- Port buttons (7 total) — events wired once here, never reconnected
  local portButtons = {}

  for i = 1, 7 do
    local btn = Instance.new("TextButton")
    btn.Name = "PortBtn" .. i
    btn.Size = UDim2.new(1/7, -3, 0, 50)
    btn.Position = UDim2.new((i - 1) / 7, 2, 0, 36)
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = 10
    btn.TextWrapped = true
    btn.Text = Constants.PORT_NAMES[i]:sub(1, 8)
    btn.Parent = frame
    portButtons[i] = btn

    -- Apply initial clickable style (update() will correct current port on first call)
    btn.BackgroundColor3 = Color3.fromRGB(30, 40, 20)
    btn.BorderColor3 = Color3.fromRGB(60, 90, 30)
    btn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
    btn.Active = true

    -- Wire Activated once; guard skips current port even if Active=false leaks through
    local capturedIndex = i
    btn.Activated:Connect(function()
      if btn.Active then
        onTravel(capturedIndex)
      end
    end)
  end

  -- RETIRE button (only visible at HK when netWorth >= 1M)
  local retireBtn = Instance.new("TextButton")
  retireBtn.Name             = "RetireBtn"
  retireBtn.Size             = UDim2.new(0.48, 0, 0, 44)
  retireBtn.Position         = UDim2.new(0, 2, 0, 90)
  retireBtn.BackgroundColor3 = Color3.fromRGB(20, 50, 15)
  retireBtn.BorderColor3     = Color3.fromRGB(60, 120, 40)
  retireBtn.TextColor3       = Color3.fromRGB(140, 200, 80)   -- Green
  retireBtn.Font             = Enum.Font.RobotoMono
  retireBtn.TextSize         = 12
  retireBtn.Text             = "RETIRE"
  retireBtn.Visible          = false
  retireBtn.Parent           = frame

  -- QUIT button (always visible)
  local quitBtn = Instance.new("TextButton")
  quitBtn.Name             = "QuitBtn"
  quitBtn.Size             = UDim2.new(0.48, 0, 0, 44)
  quitBtn.Position         = UDim2.new(0.5, 2, 0, 90)
  quitBtn.BackgroundColor3 = Color3.fromRGB(35, 15, 15)
  quitBtn.BorderColor3     = Color3.fromRGB(100, 40, 40)
  quitBtn.TextColor3       = Color3.fromRGB(220, 80, 80)   -- Red
  quitBtn.Font             = Enum.Font.RobotoMono
  quitBtn.TextSize         = 12
  quitBtn.Text             = "QUIT GAME"
  quitBtn.Parent           = frame

  retireBtn.Activated:Connect(onRetire)
  quitBtn.Activated:Connect(onQuit)

  local panel = {}

  function panel.update(state)
    -- Update port name label
    portLabel.Text = Constants.PORT_NAMES[state.currentPort]:upper()

    -- Update date label
    dateLabel.Text = Constants.MONTH_NAMES[state.month] .. " " .. tostring(state.year)

    -- Update each port button's visual state
    for i = 1, 7 do
      local btn = portButtons[i]
      if i == state.currentPort then
        -- Dimmed / disabled: current location
        btn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        btn.BorderColor3 = Color3.fromRGB(50, 50, 50)
        btn.TextColor3 = Color3.fromRGB(80, 80, 80)   -- Grey
        btn.Active = false
      else
        -- Clickable: travel destination
        btn.BackgroundColor3 = Color3.fromRGB(30, 40, 20)
        btn.BorderColor3 = Color3.fromRGB(60, 90, 30)
        btn.TextColor3 = Color3.fromRGB(140, 200, 80)   -- Green
        btn.Active = true
      end
    end

    local nw = (state.cash or 0) + (state.bankBalance or 0) - (state.debt or 0)
    retireBtn.Visible = (state.currentPort == 1 and nw >= 1000000 and not state.gameOver)
    quitBtn.Visible = not state.gameOver
  end

  return panel
end

return PortPanel
