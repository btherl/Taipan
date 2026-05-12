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

  -- Helper: build a fresh ImageLabel for one glyph, parented to a slot container,
  -- at relative pixel pos. Sizes/positions are fractions of the slot (parent),
  -- not of the screen — Roblox UDim2.fromScale is relative to parent.
  local function makeGlyph(parent, codepoint, relX, relY)
    local frame = fontData[codepoint]
    if not frame then
      -- Missing glyph; return a blank label so we don't crash on unexpected chars.
      local blank = Instance.new("Frame")
      blank.BackgroundTransparency = 1
      blank.Size = UDim2.fromScale(CHAR_WIDTH / SLOT_W_PX, ROW_HEIGHT / SLOT_H_PX)
      blank.Position = UDim2.fromScale(relX / SLOT_W_PX, relY / SLOT_H_PX)
      blank.Parent = parent
      return blank
    end
    local img = Instance.new("ImageLabel")
    img.BackgroundTransparency = 1
    img.Image = imageId
    img.ImageRectOffset = Vector2.new(frame.x, frame.y)
    img.ImageRectSize   = Vector2.new(frame.width, frame.height)
    img.Size            = UDim2.fromScale(
      (frame.width  * TEXT_SIZE) / SLOT_W_PX,
      (frame.height * TEXT_SIZE) / SLOT_H_PX)
    img.Position        = UDim2.fromScale(relX / SLOT_W_PX, relY / SLOT_H_PX)
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

  -- Hit-flash duration (ms). Tunable.
  local HIT_FLASH_S = 0.08

  function grid.applyHit(slot, onComplete)
    local st = slotState[slot]
    if not st or not st.damageGrid then
      if onComplete then onComplete() end
      return
    end

    -- Pick two random fragments (one per zone, 0=upper, 1=lower).
    local idx0 = math.random(1, 6)
    local idx1 = math.random(1, 6)
    ShipSpriteData.applyDamageFragment(st.damageGrid, idx0, 0)
    ShipSpriteData.applyDamageFragment(st.damageGrid, idx1, 1)
    paintSlot(slot, ShipSpriteData.renderRows(st.damageGrid))

    -- Hit-flash: invert glyph colours briefly by toggling ImageColor3.
    local FLASH_COLOR = Color3.fromRGB(255, 255, 255)
    local NORMAL_COLOR = Color3.fromRGB(140, 200, 80)
    for _, g in ipairs(st.glyphs) do
      if g:IsA("ImageLabel") then g.ImageColor3 = FLASH_COLOR end
    end
    task.delay(HIT_FLASH_S, function()
      if st.glyphs then
        for _, g in ipairs(st.glyphs) do
          if g:IsA("ImageLabel") then g.ImageColor3 = NORMAL_COLOR end
        end
      end
      if onComplete then onComplete() end
    end)
  end

  -- Sink animation duration range (seconds). Random per ship; matches BASIC's R(R(192)) seed.
  local SINK_MIN_S = 0.4
  local SINK_MAX_S = 1.6

  function grid.sink(slot, onComplete)
    local st = slotState[slot]
    if not st or st.animating then
      if onComplete then onComplete() end
      return
    end
    st.animating = true

    local duration = SINK_MIN_S + math.random() * (SINK_MAX_S - SINK_MIN_S)
    -- Move container fully below the slot (clipped by ClipsDescendants on the slot frame).
    local goal = { Position = UDim2.fromScale(0, 1) }
    local info = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    local tween = TweenService:Create(st.container, info, goal)
    st.sinkTween = tween
    tween.Completed:Connect(function()
      st.frame.Visible = false
      if st.glyphs then
        for _, g in ipairs(st.glyphs) do g:Destroy() end
        st.glyphs = nil
      end
      st.damageGrid = nil
      st.animating = false
      st.sinkTween = nil
      if onComplete then onComplete() end
    end)
    tween:Play()
  end

  -- spawn is currently identical to draw; left as a separate API so a future
  -- "appear-in" flash can be added without touching call sites.
  function grid.spawn(slot)
    grid.draw(slot)
  end

  function grid.clearAll()
    for slot = 1, 10 do
      grid.flee(slot)
    end
  end

  function grid.show()
    grid._gui.Enabled = true
  end

  function grid.hide()
    grid._gui.Enabled = false
  end

  -- isAnimating: true if any slot is currently sinking (used by Apple2Interface to gate prompts).
  function grid.isAnimating()
    for slot = 1, 10 do
      if slotState[slot].animating then return true end
    end
    return false
  end

  return grid
end

return ShipGrid
