-- StartPanel.lua
-- Full-screen start-choice overlay shown before ChooseStart fires.
-- Presents two options: cash+debt start (firm) or guns start (ship).
-- Hides itself once the player makes a choice.
-- ZIndex=30 sits above all other panels (including GameOverPanel at 20).

local StartPanel = {}

local AMBER = Color3.fromRGB(200, 180, 80)
local GREEN = Color3.fromRGB(140, 200, 80)

function StartPanel.new(parent, onChoose)
  -- onChoose(startChoice): called with "cash" or "guns" when player picks

  local frame = Instance.new("Frame")
  frame.Name = "StartPanel"
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.Position = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  frame.BorderSizePixel = 0
  frame.ZIndex = 30
  frame.Visible = true
  frame.Parent = parent

  local title = Instance.new("TextLabel")
  title.Size = UDim2.new(1, -20, 0, 50)
  title.Position = UDim2.new(0, 10, 0, 30)
  title.BackgroundTransparency = 1
  title.Text = "TAIPAN!"
  title.TextColor3 = AMBER
  title.Font = Enum.Font.RobotoMono
  title.TextSize = 32
  title.TextXAlignment = Enum.TextXAlignment.Center
  title.ZIndex = 30
  title.Parent = frame

  local prompt = Instance.new("TextLabel")
  prompt.Size = UDim2.new(1, -20, 0, 60)
  prompt.Position = UDim2.new(0, 10, 0, 95)
  prompt.BackgroundTransparency = 1
  prompt.Text = "Elder Brother Wu says:\n\"Do you have a firm, or a ship?\""
  prompt.TextColor3 = AMBER
  prompt.Font = Enum.Font.RobotoMono
  prompt.TextSize = 13
  prompt.TextXAlignment = Enum.TextXAlignment.Center
  prompt.TextWrapped = true
  prompt.ZIndex = 30
  prompt.Parent = frame

  -- Cash/firm start button
  local cashBtn = Instance.new("TextButton")
  cashBtn.Size = UDim2.new(0.8, 0, 0, 88)
  cashBtn.Position = UDim2.new(0.1, 0, 0, 175)
  cashBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
  cashBtn.BorderColor3 = AMBER
  cashBtn.BorderSizePixel = 1
  cashBtn.Text = "FIRM\n$400 cash · $5,000 debt · no guns"
  cashBtn.TextColor3 = GREEN
  cashBtn.Font = Enum.Font.RobotoMono
  cashBtn.TextSize = 13
  cashBtn.TextWrapped = true
  cashBtn.ZIndex = 30
  cashBtn.Parent = frame

  -- Guns/ship start button
  local gunsBtn = Instance.new("TextButton")
  gunsBtn.Size = UDim2.new(0.8, 0, 0, 88)
  gunsBtn.Position = UDim2.new(0.1, 0, 0, 275)
  gunsBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
  gunsBtn.BorderColor3 = AMBER
  gunsBtn.BorderSizePixel = 1
  gunsBtn.Text = "SHIP\n5 guns · no cash · no debt"
  gunsBtn.TextColor3 = GREEN
  gunsBtn.Font = Enum.Font.RobotoMono
  gunsBtn.TextSize = 13
  gunsBtn.TextWrapped = true
  gunsBtn.ZIndex = 30
  gunsBtn.Parent = frame

  local chosen = false  -- guard: ignore second click / double-fire

  local function choose(startChoice)
    if chosen then return end
    chosen = true
    -- Keep frame visible (covers port buttons) until first StateUpdate arrives.
    -- Dim the buttons and show a loading message so the player knows their
    -- choice was registered while the server initialises game state.
    cashBtn.Active = false
    gunsBtn.Active = false
    cashBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    gunsBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    prompt.Text = "Loading..."
    onChoose(startChoice)
  end

  cashBtn.Activated:Connect(function() choose("cash") end)
  gunsBtn.Activated:Connect(function() choose("guns") end)

  local panel = {}

  function panel.hide()
    -- Called when StateUpdate arrives (game state loaded successfully).
    -- Destroys the frame to free memory; safe to call multiple times.
    if frame and frame.Parent then
      frame:Destroy()
    end
  end

  return panel
end

return StartPanel
