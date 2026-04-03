-- GlitchLayer.lua
-- Stub overlay for future CRT glitch effects.
local GlitchLayer = {}

function GlitchLayer.new(terminalGui)
  local frame = Instance.new("Frame")
  frame.Name = "GlitchLayer"
  frame.Size = UDim2.fromScale(1, 1)
  frame.BackgroundTransparency = 1
  frame.ZIndex = 100
  frame.Visible = false
  frame.Parent = terminalGui.TextParent
  return {
    enable  = function() frame.Visible = true end,
    disable = function() frame.Visible = false end,
    destroy = function() frame:Destroy() end,
  }
end

return GlitchLayer