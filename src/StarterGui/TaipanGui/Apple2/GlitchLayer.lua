-- GlitchLayer.lua
-- Stub overlay for future CRT glitch effects (scan lines, phosphor bloom, etc.).
-- The frame exists so Apple2Interface can hand it to a future implementation
-- without structural changes.

local GlitchLayer = {}

function GlitchLayer.new(terminalGui)
  -- terminalGui is the ScreenGui returned by Text.GetTextGUI()
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
