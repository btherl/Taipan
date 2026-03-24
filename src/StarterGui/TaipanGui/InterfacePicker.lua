-- InterfacePicker.lua
-- Shown when state.uiMode == nil (new player, no preference saved).
-- Implements the adapter contract: update() and notify() are no-ops.
local UserInputService = game:GetService("UserInputService")

local AMBER = Color3.fromRGB(200, 180, 80)
local GREEN = Color3.fromRGB(140, 200, 80)

local InterfacePicker = {}

function InterfacePicker.new(screenGui, actions)
  local frame = Instance.new("Frame")
  frame.Name = "InterfacePicker"
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  frame.BorderSizePixel = 0
  frame.ZIndex = 30
  frame.Parent = screenGui

  local function lbl(text, yPos, size, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.8, 0, 0, size)
    l.Position = UDim2.new(0.1, 0, 0, yPos)
    l.BackgroundTransparency = 1
    l.TextColor3 = color or AMBER
    l.Font = Enum.Font.RobotoMono
    l.TextSize = size > 40 and 28 or 14
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.TextWrapped = true
    l.ZIndex = 30
    l.Text = text
    l.Parent = frame
    return l
  end

  lbl("TAIPAN!", 40, 60)
  lbl("Choose your interface:", 120, 28)

  local chosen = false
  local conn   -- keyboard connection

  local function pick(mode)
    if chosen then return end
    chosen = true
    if conn then conn:Disconnect() end
    actions.setUIMode(mode)
    -- Bootstrapper will detect state.uiMode change and call destroy() + instantiate real adapter
  end

  local function makeBtn(label, desc, yPos, mode)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.8, 0, 0, 70)
    btn.Position = UDim2.new(0.1, 0, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    btn.BorderColor3 = AMBER
    btn.BorderSizePixel = 1
    btn.TextColor3 = GREEN
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = 13
    btn.TextWrapped = true
    btn.ZIndex = 30
    btn.Text = label .. "\n" .. desc
    btn.Parent = frame
    btn.Activated:Connect(function() pick(mode) end)
  end

  makeBtn("[M] Modern",   "touch-friendly panels",             170, "modern")
  makeBtn("[A] Apple II", "keyboard terminal, authentic style", 260, "apple2")

  lbl("(You can change this later from the Settings option at port)", 350, 28, Color3.fromRGB(120, 120, 120))

  -- Keyboard shortcut: M or A
  conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.M then pick("modern")
    elseif input.KeyCode == Enum.KeyCode.A then pick("apple2")
    end
  end)

  local adapter = {}
  function adapter.update(_state)  end   -- no-op
  function adapter.notify(_msg)    end   -- no-op
  function adapter.destroy()
    if conn then conn:Disconnect() end
    frame:Destroy()
  end
  return adapter
end

return InterfacePicker
