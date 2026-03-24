-- Terminal.lua
-- 24-row bitmap font display using the ReplicatedStorage.Text library.
-- Uses TaipanStandardFont at TextSize=3: 40 cols x ~22 fully-visible rows.
-- Rows 23-24 may be partially clipped (CRT overscan authenticity).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Text              = require(ReplicatedStorage.Text)

local ROWS       = 24
local TEXT_SIZE  = 3
local ROW_HEIGHT = 48   -- 16 virtual px * TextSize 3
local X_OFFSET   = 30   -- left margin: sprites are center-anchored so x=0 clips the first glyph
local GREEN      = Color3.fromRGB(140, 200, 80)

local Terminal = {}

function Terminal.new(displayOrder)
  -- GetTextGUI returns a ScreenGui with TextParent frame (16:9 AspectRatioConstraint, 1920x1080 virtual)
  local gui = Text.GetTextGUI(displayOrder or 5)
  gui.Name   = "TaipanTerminal"
  gui.Parent = Players.LocalPlayer.PlayerGui

  -- Black background frame behind all text
  local bg = Instance.new("Frame")
  bg.Name               = "Background"
  bg.Size               = UDim2.fromScale(1, 1)
  bg.BackgroundColor3   = Color3.new(0, 0, 0)
  bg.BackgroundTransparency = 0
  bg.ZIndex             = 0
  bg.BorderSizePixel    = 0
  bg.Parent             = gui.TextParent

  -- Fixed pool of ROWS Text objects (one per row)
  local rows = {}
  for i = 1, ROWS do
    local t = Text.new("TaipanStandardFont", true)  -- automatic_update = true
    t.Parent    = gui.TextParent
    t.Position  = Vector2.new(X_OFFSET, (i - 1) * ROW_HEIGHT)
    t.TextSize  = TEXT_SIZE
    t.TextColor3 = GREEN
    t.ZIndex    = 1
    rows[i] = t
  end

  -- Buffer: which logical line is in which row slot
  -- buffer[row] = { text = string, color = Color3 }
  local buffer = {}
  for i = 1, ROWS do buffer[i] = { text = "", color = GREEN } end

  local function redrawAll()
    for i = 1, ROWS do
      rows[i].Text       = buffer[i].text
      rows[i].TextColor3 = buffer[i].color
    end
  end

  local term = {}

  function term.clear()
    for i = 1, ROWS do buffer[i] = { text = "", color = GREEN } end
    redrawAll()
  end

  -- Splits on \n and appends each segment; scrolls when full
  function term.print(text, color)
    color = color or GREEN
    -- Handle multi-line strings
    local segments = text:split("\n")
    for _, seg in ipairs(segments) do
      -- Scroll: shift buffer up, place new line at bottom (row ROWS-1, leaving row ROWS for input)
      for i = 1, ROWS - 2 do
        buffer[i] = buffer[i + 1]
      end
      buffer[ROWS - 1] = { text = seg, color = color }
      -- Row ROWS is the input line -- preserve it (showInputLine manages it)
    end
    redrawAll()
  end

  -- Writes text to the dedicated input row (row ROWS) without scrolling
  function term.showInputLine(text)
    buffer[ROWS] = { text = text or "", color = GREEN }
    rows[ROWS].Text = buffer[ROWS].text
    rows[ROWS].TextColor3 = GREEN
  end

  function term.setRowColor(row, color)
    if row < 1 or row > ROWS then return end
    buffer[row].color = color
    rows[row].TextColor3 = color
  end

  function term.destroy()
    for i = 1, ROWS do
      rows[i]:Destroy()
    end
    gui:Destroy()
  end

  -- Expose the gui so GlitchLayer and Apple2Interface can reference it
  term._gui = gui

  return term
end

return Terminal
