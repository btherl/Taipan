-- StartPanel.lua
local StartPanel = {}
local AMBER = Color3.fromRGB(200, 180, 80)
local GREEN = Color3.fromRGB(140, 200, 80)
function StartPanel.new(parent, onChoose)
  local BUTTON_DEFAULT_COLOR = Color3.fromRGB(20, 20, 20)
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
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Size = UDim2.new(0.8, 0, 0, 20)
  nameLabel.Position = UDim2.new(0.1, 0, 0, 163)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = "Your firm name (optional):"
  nameLabel.TextColor3 = AMBER
  nameLabel.Font = Enum.Font.RobotoMono
  nameLabel.TextSize = 11
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.ZIndex = 30
  nameLabel.Parent = frame
  local nameBox = Instance.new("TextBox")
  nameBox.Size = UDim2.new(0.8, 0, 0, 32)
  nameBox.Position = UDim2.new(0.1, 0, 0, 183)
  nameBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
  nameBox.BorderColor3 = AMBER
  nameBox.BorderSizePixel = 1
  nameBox.Text = ""
  nameBox.PlaceholderText = "(optional)"
  nameBox.TextColor3 = GREEN
  nameBox.PlaceholderColor3 = Color3.fromRGB(80, 80, 80)
  nameBox.Font = Enum.Font.RobotoMono
  nameBox.TextSize = 13
  nameBox.ZIndex = 30
  nameBox.ClearTextOnFocus = false
  nameBox.MaxVisibleGraphemes = 22
  nameBox.Parent = frame
  local cashBtn = Instance.new("TextButton")
  cashBtn.Size = UDim2.new(0.8, 0, 0, 88)
  cashBtn.Position = UDim2.new(0.1, 0, 0, 227)
  cashBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
  cashBtn.BorderColor3 = AMBER
  cashBtn.BorderSizePixel = 1
  cashBtn.Text = "FIRM\n$400 cash · $5,000 debt · no guns"
  cashBtn.TextColor3 = GREEN
  cashBtn.Font = Enum.Font.RobotoMono
  cashBtn.TextSize = 13
  cashBtn.TextWrapped = true
  cashBtn.ZIndex = 30
  cashBtn.Parent = frame
  local gunsBtn = Instance.new("TextButton")
  gunsBtn.Size = UDim2.new(0.8, 0, 0, 88)
  gunsBtn.Position = UDim2.new(0.1, 0, 0, 327)
  gunsBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
  gunsBtn.BorderColor3 = AMBER
  gunsBtn.BorderSizePixel = 1
  gunsBtn.Text = "SHIP\n5 guns · no cash · no debt"
  gunsBtn.TextColor3 = GREEN
  gunsBtn.Font = Enum.Font.RobotoMono
  gunsBtn.TextSize = 13
  gunsBtn.TextWrapped = true
  gunsBtn.ZIndex = 30
  gunsBtn.Parent = frame
  local chosen = false
  local function choose(startChoice)
    if chosen then return end
    chosen = true
    cashBtn.Active = false
    gunsBtn.Active = false
    cashBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    gunsBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    prompt.Text = "Loading..."
    onChoose(startChoice, nameBox.Text or "")
  end
  cashBtn.Activated:Connect(function() choose("cash") end)
  gunsBtn.Activated:Connect(function() choose("guns") end)
  local panel = {}
  function panel.hide()
    frame.Visible = false
  end
  function panel.show()
    chosen = false
    cashBtn.Active = true
    gunsBtn.Active = true
    cashBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
    gunsBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
    prompt.Text = "Elder Brother Wu says:\n\"Do you have a firm, or a ship?\""
    frame.Visible = true
  end
  return panel
end
return StartPanel