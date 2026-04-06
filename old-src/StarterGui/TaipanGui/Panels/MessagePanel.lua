-- MessagePanel.lua
-- Floating notification bar. Shows a message for 5 seconds then auto-hides.
-- ZIndex=10 keeps it on top of all other panels.

local MessagePanel = {}

function MessagePanel.new(parent)
  local frame = Instance.new("Frame")
  frame.Name = "MessagePanel"
  frame.Size = UDim2.new(1, 0, 0, 36)
  frame.Position = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
  frame.BackgroundTransparency = 0.3
  frame.BorderSizePixel = 0
  frame.ZIndex = 10
  frame.Visible = false
  frame.Parent = parent

  local label = Instance.new("TextLabel")
  label.Name = "MessageLabel"
  label.Size = UDim2.new(1, -10, 1, 0)
  label.Position = UDim2.new(0, 5, 0, 0)
  label.BackgroundTransparency = 1
  label.TextColor3 = Color3.fromRGB(240, 220, 140)
  label.Font = Enum.Font.RobotoMono
  label.TextSize = 13
  label.TextXAlignment = Enum.TextXAlignment.Center
  label.TextYAlignment = Enum.TextYAlignment.Center
  label.ZIndex = 10
  label.TextWrapped = true
  label.Parent = frame

  local hideTimer = nil

  local panel = {}

  function panel.show(message)
    label.Text = message
    frame.Visible = true
    -- Cancel any previous auto-hide timer
    if hideTimer then
      task.cancel(hideTimer)
    end
    hideTimer = task.delay(5, function()
      frame.Visible = false
      hideTimer = nil
    end)
  end

  return panel
end

return MessagePanel
