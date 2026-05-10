-- ShipGrid.lua
-- 10-slot enemy-ship sprite layer for the Apple II combat scene.
-- Sibling to Terminal and GlitchLayer; uses TaipanThickFont glyphs as ImageLabels.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Text              = require(ReplicatedStorage.Text)
local ShipSpriteData    = require(script.Parent.ShipSpriteData)

-- Coordinate constants must match Terminal.luau exactly so sprites land in the right cells.
local TEXT_SIZE     = 3
local CHAR_WIDTH    = 14 * TEXT_SIZE   -- 42 virtual px
local ROW_HEIGHT    = 16 * TEXT_SIZE   -- 48 virtual px
local X_OFFSET      = 30               -- left margin (matches Terminal)
local SCREEN_W      = 1920
local SCREEN_H      = 1080

local SHIP_W_CHARS  = 7
local SHIP_H_ROWS   = 5
local SLOT_W_PX     = SHIP_W_CHARS * CHAR_WIDTH
local SLOT_H_PX     = SHIP_H_ROWS * ROW_HEIGHT

local THICK_FONT_NAME = "TaipanThickFont"

local ShipGrid = {}

-- BASIC slot-coordinate formula: X = (i mod 5) * 8 + 1 (1-based char col), Y = floor(i/5) * 6 + 7 (1-based row).
-- Returns top-left pixel coordinates of slot index 1..10.
local function slotPixelTopLeft(slotIndex)
  local i = slotIndex - 1                          -- back to 0-based for the formula
  local charCol = (i % 5) * 8 + 1                  -- 1, 9, 17, 25, 33
  local rowIdx  = math.floor(i / 5) * 6 + 7        -- 7 or 13
  local x = X_OFFSET + (charCol - 1) * CHAR_WIDTH
  local y = (rowIdx - 1) * ROW_HEIGHT
  return x, y
end

-- Lazily resolve the TaipanThickFont folder + atlas asset once.
local function getThickFont()
  local fontFolder = ReplicatedStorage.Text.Fonts:FindFirstChild(THICK_FONT_NAME)
  assert(fontFolder, "TaipanThickFont not found in ReplicatedStorage.Text.Fonts")
  local fontData = require(fontFolder.FontData)
  local imageId  = fontFolder.ImageID.Value
  return fontData, imageId
end

function ShipGrid.new(displayOrder)
  local gui = Text.GetTextGUI(displayOrder or 6)   -- > Terminal's 5 so sprites overlay
  gui.Name   = "TaipanShipGrid"
  gui.Parent = Players.LocalPlayer.PlayerGui

  local fontData, imageId = getThickFont()

  -- Per-slot state. slotState[i] = { frame, container, glyphs, damageGrid, animating, sinkTween }
  local slotState = {}

  -- Helper: build a fresh ImageLabel for one glyph, parented to a Frame, at relative pixel pos.
  local function makeGlyph(parent, codepoint, relX, relY)
    local frame = fontData[codepoint]
    if not frame then
      -- Missing glyph; return a blank label so we don't crash on unexpected chars.
      local blank = Instance.new("Frame")
      blank.BackgroundTransparency = 1
      blank.Size = UDim2.fromScale(CHAR_WIDTH / SCREEN_W, ROW_HEIGHT / SCREEN_H)
      blank.Position = UDim2.fromScale(relX / SCREEN_W, relY / SCREEN_H)
      blank.Parent = parent
      return blank
    end
    local img = Instance.new("ImageLabel")
    img.BackgroundTransparency = 1
    img.Image = imageId
    img.ImageRectOffset = Vector2.new(frame.x, frame.y)
    img.ImageRectSize   = Vector2.new(frame.width, frame.height)
    img.Size            = UDim2.fromScale(
      (frame.width  * TEXT_SIZE) / SCREEN_W,
      (frame.height * TEXT_SIZE) / SCREEN_H)
    img.Position        = UDim2.fromScale(relX / SCREEN_W, relY / SCREEN_H)
    img.ImageColor3     = Color3.fromRGB(140, 200, 80)  -- terminal green
    img.Parent          = parent
    return img
  end

  -- Build (or rebuild) the 35 glyph ImageLabels for a slot from a damage-overlaid render.
  local function paintSlot(slot, rows)
    local st = slotState[slot]
    -- Clear existing glyphs
    if st.glyphs then
      for _, g in ipairs(st.glyphs) do g:Destroy() end
    end
    st.glyphs = {}
    for r = 1, SHIP_H_ROWS do
      local rowText = rows[r]
      for c = 1, SHIP_W_CHARS do
        local ch = rowText:sub(c, c)
        local cp = string.byte(ch)
        local relX = (c - 1) * CHAR_WIDTH
        local relY = (r - 1) * ROW_HEIGHT
        local g = makeGlyph(st.container, cp, relX, relY)
        table.insert(st.glyphs, g)
      end
    end
  end

  -- Build the per-slot Frame + container hierarchy.
  for slot = 1, 10 do
    local x, y = slotPixelTopLeft(slot)
    local frame = Instance.new("Frame")
    frame.Name = "Slot" .. slot
    frame.BackgroundTransparency = 1
    frame.Size     = UDim2.fromScale(SLOT_W_PX / SCREEN_W, SLOT_H_PX / SCREEN_H)
    frame.Position = UDim2.fromScale(x / SCREEN_W, y / SCREEN_H)
    frame.ClipsDescendants = true
    frame.Visible = false   -- slots start empty
    frame.Parent  = gui.TextParent

    local container = Instance.new("Frame")
    container.Name = "SpriteContainer"
    container.BackgroundTransparency = 1
    container.Size     = UDim2.fromScale(1, 1)
    container.Position = UDim2.fromScale(0, 0)
    container.Parent   = frame

    slotState[slot] = {
      frame      = frame,
      container  = container,
      glyphs     = nil,
      damageGrid = nil,
      animating  = false,
      sinkTween  = nil,
    }
  end

  local grid = {}
  grid._gui       = gui
  grid._slotState = slotState
  grid._paintSlot = paintSlot

  function grid.destroy()
    gui:Destroy()
  end

  function grid.draw(slot)
    local st = slotState[slot]
    if not st then return end
    st.damageGrid = ShipSpriteData.newDamageGrid()
    st.container.Position = UDim2.fromScale(0, 0)  -- reset any prior sink offset
    paintSlot(slot, ShipSpriteData.renderRows(st.damageGrid))
    st.frame.Visible = true
    st.animating = false
  end

  function grid.flee(slot)
    local st = slotState[slot]
    if not st then return end
    st.frame.Visible = false
    st.damageGrid = nil
    if st.glyphs then
      for _, g in ipairs(st.glyphs) do g:Destroy() end
      st.glyphs = nil
    end
    if st.sinkTween then st.sinkTween:Cancel(); st.sinkTween = nil end
    st.animating = false
  end

  return grid
end

return ShipGrid
