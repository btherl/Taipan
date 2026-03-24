-- InterfacePicker.lua
-- Phase 1: interface choice (modern/apple2), stores pendingMode.
-- Phase 2: start choice (cash/guns), fires chooseStart.
-- adapter.update() fires setUIMode(pendingMode) after ChooseStart state arrives.
local UserInputService = game:GetService("UserInputService")

local AMBER = Color3.fromRGB(200, 180, 80)
local GREEN = Color3.fromRGB(140, 200, 80)
local DIM   = Color3.fromRGB(120, 120, 120)

local InterfacePicker = {}

function InterfacePicker.new(screenGui, actions)
  local frame = Instance.new("Frame")
  frame.Name = "InterfacePicker"
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  frame.BorderSizePixel = 0
  frame.ZIndex = 30
  frame.Parent = screenGui

  local conn        = nil
  local phase       = 1
  local chosen      = false
  local pendingMode = nil   -- set in Phase 1, consumed by update()

  local function clearChildren()
    for _, child in ipairs(frame:GetChildren()) do child:Destroy() end
  end

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

  local function makeBtn(label, desc, yPos, onClick)
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
    btn.Activated:Connect(onClick)
    return btn
  end

  local function showPhase2()
    clearChildren()
    if conn then conn:Disconnect(); conn = nil end
    chosen = false

    lbl("TAIPAN!", 40, 60)
    lbl("Elder Brother Wu asks:", 110, 24)
    lbl('"Shall I buy a ship for you? Or will you trade in your Clipper?"', 140, 24)

    makeBtn("[C] Buy a Cargo Hold",    "$400 cash, large debt, no guns",  220, function()
      if chosen then return end; chosen = true
      actions.chooseStart("cash")
    end)
    makeBtn("[G] Trade in my Clipper", "No cash, no debt, 5 guns",        300, function()
      if chosen then return end; chosen = true
      actions.chooseStart("guns")
    end)

    conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
      if gameProcessed then return end
      if input.KeyCode == Enum.KeyCode.C then
        if chosen then return end; chosen = true; actions.chooseStart("cash")
      elseif input.KeyCode == Enum.KeyCode.G then
        if chosen then return end; chosen = true; actions.chooseStart("guns")
      end
    end)
  end

  local function showPhase1()
    clearChildren()
    if conn then conn:Disconnect(); conn = nil end
    chosen = false

    lbl("TAIPAN!", 40, 60)
    lbl("Choose your interface style:", 120, 28)

    makeBtn("[M] Modern",   "touch-friendly panels",             190, function()
      if chosen then return end; chosen = true
      pendingMode = "modern"; phase = 2; showPhase2()
    end)
    makeBtn("[A] Apple II", "keyboard terminal, authentic style", 270, function()
      if chosen then return end; chosen = true
      pendingMode = "apple2"; phase = 2; showPhase2()
    end)

    lbl("(You can change this later from Settings at any port)", 355, 24, DIM)

    conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
      if gameProcessed then return end
      if input.KeyCode == Enum.KeyCode.M then
        if chosen then return end; chosen = true
        pendingMode = "modern"; phase = 2; showPhase2()
      elseif input.KeyCode == Enum.KeyCode.A then
        if chosen then return end; chosen = true
        pendingMode = "apple2"; phase = 2; showPhase2()
      end
    end)
  end

  showPhase1()

  local adapter = {}

  function adapter.update(_state)
    -- Called when StateUpdate arrives with uiMode=nil (after ChooseStart fired).
    -- Fire SetUIMode to complete the selection; bootstrapper handles the rest.
    if phase == 2 and pendingMode then
      actions.setUIMode(pendingMode)
      pendingMode = nil
    end
  end

  function adapter.notify(_msg)  end

  function adapter.destroy()
    if conn then conn:Disconnect() end
    frame:Destroy()
  end

  return adapter
end

return InterfacePicker
