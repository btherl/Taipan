-- Terminal.lua
-- 24-row bitmap font display using the ReplicatedStorage.Text library.
-- Uses TaipanStandardFont at TextSize=3: 40 cols x ~22 fully-visible rows.
-- Rows 23-24 may be partially clipped (CRT overscan authenticity).
--
-- Lines may be single-font: { text = string, color = Color3 }
-- or multi-font segmented:  { segments = { {text, color, font?}, ... } }
-- font defaults to "TaipanStandardFont" if omitted from a segment.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Text              = require(ReplicatedStorage.Text)

local ROWS        = 24
local TEXT_SIZE   = 3
local ROW_HEIGHT  = 48   -- 16 virtual px * TextSize 3
local X_OFFSET    = 30   -- left margin: sprites are center-anchored so x=0 clips the first glyph
local CHAR_WIDTH  = 14 * TEXT_SIZE  -- 42 virtual px per char (both fonts share xadvance=14)
local GREEN       = Color3.fromRGB(140, 200, 80)
local DEFAULT_FONT = "TaipanStandardFont"

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

  -- rowObjs[i] = array of Text objects for row i (one per font segment)
  local rowObjs = {}
  for i = 1, ROWS do
    local t = Text.new(DEFAULT_FONT, true)
    t.Parent     = gui.TextParent
    t.Position   = Vector2.new(X_OFFSET, (i - 1) * ROW_HEIGHT)
    t.TextSize   = TEXT_SIZE
    t.TextColor3 = GREEN
    t.ZIndex     = 1
    t.FontName   = DEFAULT_FONT  -- custom field for change detection
    rowObjs[i] = { t }
  end

  -- Buffer: buffer[row] = { text, color } or { segments = {{text, color, font?}, ...} }
  local buffer = {}
  for i = 1, ROWS do buffer[i] = { text = "", color = GREEN } end

  -- Sync one row's Text objects to its buffer entry
  local function syncRow(i)
    local entry = buffer[i]

    -- Normalise to segments array
    local segs
    if entry.segments then
      segs = entry.segments
    else
      segs = {{ text = entry.text or "", color = entry.color or GREEN, font = DEFAULT_FONT }}
    end

    local current = rowObjs[i]

    -- Destroy excess Text objects
    for j = #segs + 1, #current do
      current[j]:Destroy()
      current[j] = nil
    end

    -- Update each segment (creating missing Text objects as needed)
    local xPos = X_OFFSET
    for j = 1, #segs do
      local s    = segs[j]
      local font = s.font or DEFAULT_FONT

      if not current[j] then
        -- Create missing Text object
        local t = Text.new(font, true)
        t.Parent   = gui.TextParent
        t.TextSize = TEXT_SIZE
        t.ZIndex   = 1
        t.FontName = font
        current[j] = t
      elseif current[j].FontName ~= font then
        -- Font changed — replace the Text object
        current[j]:Destroy()
        local t = Text.new(font, true)
        t.Parent   = gui.TextParent
        t.TextSize = TEXT_SIZE
        t.ZIndex   = 1
        t.FontName = font
        current[j] = t
      end

      local obj = current[j]
      obj.Text       = s.text or ""
      obj.TextColor3 = s.color or GREEN
      obj.Position   = Vector2.new(xPos, (i - 1) * ROW_HEIGHT)

      xPos = xPos + #(s.text or "") * CHAR_WIDTH
    end
  end

  local function redrawAll()
    for i = 1, ROWS do
      syncRow(i)
    end
  end

  local term = {}

  function term.clear()
    for i = 1, ROWS do buffer[i] = { text = "", color = GREEN } end
    redrawAll()
  end

  -- Splits on \n and appends each segment; scrolls when full
  -- Accepts either a string (single-font) or a segmented line table
  function term.print(lineOrText, color)
    if type(lineOrText) == "table" then
      -- Segmented line: { segments = {...} }
      for i = 1, ROWS - 2 do
        buffer[i] = buffer[i + 1]
      end
      buffer[ROWS - 1] = lineOrText
    else
      -- Plain string (legacy): split on \n
      color = color or GREEN
      local parts = tostring(lineOrText):split("\n")
      for _, part in ipairs(parts) do
        for i = 1, ROWS - 2 do
          buffer[i] = buffer[i + 1]
        end
        buffer[ROWS - 1] = { text = part, color = color }
      end
    end
    redrawAll()
  end

  -- Writes text to the dedicated input row (row ROWS) without scrolling
  function term.showInputLine(text)
    buffer[ROWS] = { text = text or "", color = GREEN }
    syncRow(ROWS)
  end

  -- Writes to any row without scrolling. Accepts string or segmented table.
  function term.showInputAt(row, content)
    if row < 1 or row > ROWS then return end
    if type(content) == "table" then
      buffer[row] = content
    else
      buffer[row] = { text = content or "", color = GREEN }
    end
    syncRow(row)
  end

  -- Assigns rows directly from a keyed table (for precise-layout scenes).
  -- Unspecified rows default to empty.
  function term.setRows(rowTable)
    for i = 1, ROWS do
      buffer[i] = rowTable[i] or { text = "", color = GREEN }
    end
    redrawAll()
  end

  function term.setRowColor(row, color)
    if row < 1 or row > ROWS then return end
    if buffer[row].segments then
      for _, obj in ipairs(rowObjs[row]) do
        obj.TextColor3 = color
      end
    else
      buffer[row].color = color
      rowObjs[row][1].TextColor3 = color
    end
  end

  function term.destroy()
    for i = 1, ROWS do
      for _, obj in ipairs(rowObjs[i]) do
        obj:Destroy()
      end
    end
    gui:Destroy()
  end

  -- Expose the gui so GlitchLayer and Apple2Interface can reference it
  term._gui = gui

  return term
end

return Terminal
