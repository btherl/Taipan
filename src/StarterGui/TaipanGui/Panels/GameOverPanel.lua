-- GameOverPanel.lua
-- Full-screen overlay shown when state.gameOver = true.
-- ZIndex=20 sits above all other panels.

local GameOverPanel = {}

function GameOverPanel.new(parent, onRestart)
  -- onRestart(): fired when player clicks RESTART

  local frame = Instance.new("Frame")
  frame.Name = "GameOverPanel"
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.Position = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3 = Color3.fromRGB(30, 5, 5)
  frame.BackgroundTransparency = 0.1
  frame.BorderSizePixel = 0
  frame.ZIndex = 20
  frame.Visible = false
  frame.Parent = parent

  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.Size = UDim2.new(1, 0, 0, 80)
  title.Position = UDim2.new(0, 0, 0.3, 0)
  title.BackgroundTransparency = 1
  title.TextColor3 = Color3.fromRGB(220, 50, 50)
  title.Font = Enum.Font.RobotoMono
  title.TextSize = 42
  title.TextXAlignment = Enum.TextXAlignment.Center
  title.ZIndex = 20
  title.Text = "GAME OVER"
  title.Parent = frame

  local subtitle = Instance.new("TextLabel")
  subtitle.Name = "Subtitle"
  subtitle.Size = UDim2.new(1, -20, 0, 40)
  subtitle.Position = UDim2.new(0, 10, 0.3, 90)
  subtitle.BackgroundTransparency = 1
  subtitle.TextColor3 = Color3.fromRGB(200, 150, 150)
  subtitle.Font = Enum.Font.RobotoMono
  subtitle.TextSize = 16
  subtitle.TextXAlignment = Enum.TextXAlignment.Center
  subtitle.ZIndex = 20
  subtitle.Text = "Your ship has sunk, Taipan!"
  subtitle.Parent = frame

  local restartBtn = Instance.new("TextButton")
  restartBtn.Name = "RestartBtn"
  restartBtn.Size = UDim2.new(0.4, 0, 0, 44)
  restartBtn.Position = UDim2.new(0.3, 0, 0.3, 160)
  restartBtn.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
  restartBtn.BorderColor3 = Color3.fromRGB(150, 40, 40)
  restartBtn.TextColor3 = Color3.fromRGB(220, 100, 100)
  restartBtn.Font = Enum.Font.RobotoMono
  restartBtn.TextSize = 16
  restartBtn.ZIndex = 20
  restartBtn.Text = "RESTART"
  restartBtn.Parent = frame

  restartBtn.Activated:Connect(function()
    onRestart()
  end)

  local panel = {}

  function panel.update(state)
    if not state.gameOver then
      frame.Visible = false
      return
    end
    frame.Visible = true

    local reason = state.gameOverReason
    if reason == "retired" then
      title.Text       = "RETIRED!"
      title.TextColor3 = Color3.fromRGB(100, 220, 100)
      frame.BackgroundColor3 = Color3.fromRGB(5, 30, 5)
    elseif reason == "quit" then
      title.Text       = "FAREWELL, TAIPAN"
      title.TextColor3 = Color3.fromRGB(180, 180, 50)
      frame.BackgroundColor3 = Color3.fromRGB(20, 20, 5)
    else  -- "sunk" or nil (legacy)
      title.Text       = "GAME OVER"
      title.TextColor3 = Color3.fromRGB(220, 50, 50)
      frame.BackgroundColor3 = Color3.fromRGB(30, 5, 5)
    end

    if reason == "retired" then
      subtitle.TextColor3 = Color3.fromRGB(100, 220, 100)
    elseif reason == "quit" then
      subtitle.TextColor3 = Color3.fromRGB(200, 190, 80)
    else
      subtitle.TextColor3 = Color3.fromRGB(200, 150, 150)
    end

    if state.finalScore ~= nil then
      subtitle.Text = string.format(
        "Score: %d  |  %s", state.finalScore, state.finalRating or "")
    else
      subtitle.Text = reason == "sunk" and "Your ship has sunk, Taipan!"
                   or reason == "quit" and "You have left the trade, Taipan."
                   or "Game over."
    end
  end

  return panel
end

return GameOverPanel
