-- ShipGrid.lua
-- 10-slot enemy-ship sprite layer for the Apple II combat scene.
-- Sibling to Terminal and GlitchLayer.
--
-- Rendering model: each ship is composited into ONE EditableImage at native resolution
-- (7*14 x 5*16 = 98x80) by copying each TaipanThickFont glyph's pixels edge-to-edge, with no
-- gaps between glyphs. That single contiguous image is then displayed by one ImageLabel scaled
-- to the slot. Earlier we drew 35 separate glyph ImageLabels per ship; at the 2.7x scale each
-- glyph faded into the 2px transparent gutter around it in the atlas, leaving thin black seams
-- between glyphs that neither overscan nor pixelated sampling could fix without distorting the
-- shape. Compositing first removes every internal boundary, so there are no internal seams to
-- fade; only the ship's outer silhouette meets transparency, which is invisible against black.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local AssetService      = game:GetService("AssetService")
local Text              = require(ReplicatedStorage.Text)
local ShipSpriteData    = require(script.Parent.ShipSpriteData)

-- Coordinate constants must match Terminal.luau exactly so sprites land in the right cells.
local TEXT_SIZE     = 2.7
local CHAR_WIDTH    = 14 * TEXT_SIZE   -- virtual px per char
local ROW_HEIGHT    = 16 * TEXT_SIZE   -- row pitch = glyph height (matches Terminal; rows tile, no overlap)
local TOP_MARGIN    = 32               -- virtual px above row 1's centre (matches Terminal)
local X_OFFSET      = 30               -- left margin (matches Terminal)
local SCREEN_W      = 1920
local SCREEN_H      = 1080

local SHIP_W_CHARS  = 7
local SHIP_H_ROWS   = 5
local SLOT_W_PX     = SHIP_W_CHARS * CHAR_WIDTH
local SLOT_H_PX     = SHIP_H_ROWS * ROW_HEIGHT

-- Native (atlas) glyph dimensions. All TaipanThickFont ship/damage glyphs are 14x16.
local CELL_W        = 14
local CELL_H        = 16
local SHIP_PX_W     = SHIP_W_CHARS * CELL_W   -- 98: composite image width
local SHIP_PX_H     = SHIP_H_ROWS * CELL_H    -- 80: composite image height

local FG_COLOR      = Color3.fromRGB(140, 200, 80)  -- terminal green
local BG_COLOR      = Color3.fromRGB(0, 0, 0)       -- terminal black

local THICK_FONT_NAME = "TaipanThickFont"

local ShipGrid = {}

-- BASIC slot-coordinate formula: X = (i mod 5) * 8 + 1 (1-based char col), Y = floor(i/5) * 6 + 7 (1-based row).
-- Returns top-left pixel coordinates of slot index 1..10.
local function slotPixelTopLeft(slotIndex)
  local i = slotIndex - 1                          -- back to 0-based for the formula
  local charCol = (i % 5) * 8 + 1                  -- 1, 9, 17, 25, 33
  local rowIdx  = math.floor(i / 5) * 6 + 7        -- 7 or 13
  local x = X_OFFSET + (charCol - 1) * CHAR_WIDTH
  local y = TOP_MARGIN + (rowIdx - 1) * ROW_HEIGHT
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
  gui.IgnoreGuiInset = false   -- match Terminal so the ship grid stays aligned with the text

  local fontData, imageId = getThickFont()

  -- Atlas as an EditableImage, so we can read glyph pixels out of it. Loaded asynchronously
  -- because CreateEditableImageAsync yields and ShipGrid.new runs during interface construction.
  -- atlasImage stays nil until the load finishes; composeSlot is a no-op until then, and we
  -- recompose any already-visible slots once it's ready. Combat never starts this early.
  local atlasImage = nil

  -- Per-slot state. slotState[i] = { frame, container, inverseBackdrop, shipImage, target, damageGrid, animating, sinkTween }
  local slotState = {}

  -- Composite the slot's ship (base sprite + damage overlay) into its target EditableImage,
  -- copying each glyph's 14x16 pixels edge-to-edge so there are no gaps between glyphs.
  local function composeSlot(slot)
    local st = slotState[slot]
    if not st or not atlasImage or not st.damageGrid then return end
    local rows = ShipSpriteData.renderRows(st.damageGrid)
    local target = st.target
    for r = 1, SHIP_H_ROWS do
      local rowText = rows[r]
      for c = 1, SHIP_W_CHARS do
        local cp = string.byte(rowText, c)
        local f  = fontData[cp]
        local destPos  = Vector2.new((c - 1) * CELL_W, (r - 1) * CELL_H)
        local cellSize = Vector2.new(CELL_W, CELL_H)
        if f then
          local px = atlasImage:ReadPixelsBuffer(Vector2.new(f.x, f.y), Vector2.new(f.width, f.height))
          target:WritePixelsBuffer(destPos, Vector2.new(f.width, f.height), px)
        else
          -- Unknown glyph: clear the cell to transparent (zeroed RGBA buffer).
          target:WritePixelsBuffer(destPos, cellSize, buffer.create(CELL_W * CELL_H * 4))
        end
      end
    end
  end

  -- Build the per-slot Frame -> container -> {inverseBackdrop, shipImage} hierarchy.
  for slot = 1, 10 do
    local x, y = slotPixelTopLeft(slot)
    local frame = Instance.new("Frame")
    frame.Name = "Slot" .. slot
    frame.BackgroundTransparency = 1
    frame.Size     = UDim2.fromScale(SLOT_W_PX / SCREEN_W, SLOT_H_PX / SCREEN_H)
    frame.Position = UDim2.fromScale(x / SCREEN_W, y / SCREEN_H)
    frame.ClipsDescendants = true   -- clips the sink animation
    frame.Visible = false           -- slots start empty
    frame.Parent  = gui.TextParent

    local container = Instance.new("Frame")
    container.Name = "SpriteContainer"
    container.BackgroundTransparency = 1
    container.Size     = UDim2.fromScale(1, 1)
    container.Position = UDim2.fromScale(0, 0)
    container.Parent   = frame

    -- Inverse-video backdrop: fills the slot in foreground colour during a hit flash so the
    -- ship (re-tinted black) appears as a cut-out. ZIndex 1 keeps it below the ship image.
    local inverseBackdrop = Instance.new("Frame")
    inverseBackdrop.Name = "InverseBackdrop"
    inverseBackdrop.BackgroundColor3 = FG_COLOR
    inverseBackdrop.BackgroundTransparency = 1
    inverseBackdrop.BorderSizePixel = 0
    inverseBackdrop.ZIndex   = 1
    inverseBackdrop.Size     = UDim2.fromScale(1, 1)
    inverseBackdrop.Position = UDim2.fromScale(0, 0)
    inverseBackdrop.Parent   = container

    -- Single ImageLabel showing the composited ship, scaled to fill the slot (98x80 -> 2.7x).
    local target = AssetService:CreateEditableImage({ Size = Vector2.new(SHIP_PX_W, SHIP_PX_H) })
    local shipImage = Instance.new("ImageLabel")
    shipImage.Name = "ShipImage"
    shipImage.BackgroundTransparency = 1
    shipImage.BorderSizePixel = 0
    shipImage.ZIndex        = 2
    shipImage.Size          = UDim2.fromScale(1, 1)
    shipImage.Position      = UDim2.fromScale(0, 0)
    shipImage.ImageColor3   = FG_COLOR          -- glyphs are white in the atlas; tint to green
    shipImage.ImageContent  = Content.fromObject(target)
    shipImage.Visible       = false
    shipImage.Parent        = container

    slotState[slot] = {
      frame            = frame,
      container        = container,
      inverseBackdrop  = inverseBackdrop,
      shipImage        = shipImage,
      target           = target,
      damageGrid       = nil,
      animating        = false,
      sinkTween        = nil,
    }
  end

  -- Kick off the atlas load; recompose visible slots when it lands.
  task.spawn(function()
    local ok, result = pcall(function()
      return AssetService:CreateEditableImageAsync(Content.fromUri(imageId))
    end)
    if ok and result then
      atlasImage = result
      for slot = 1, 10 do
        local st = slotState[slot]
        if st.frame.Visible and st.damageGrid then
          composeSlot(slot)
        end
      end
    else
      warn("[ShipGrid] failed to load atlas EditableImage: " .. tostring(result))
    end
  end)

  local grid = {}
  grid._gui        = gui
  grid._slotState  = slotState
  grid._composeSlot = composeSlot

  function grid.destroy()
    gui:Destroy()
  end

  function grid.draw(slot)
    local st = slotState[slot]
    if not st then return end
    st.damageGrid = ShipSpriteData.newDamageGrid()
    st.container.Position = UDim2.fromScale(0, 0)  -- reset any prior sink offset
    st.shipImage.ImageColor3 = FG_COLOR
    st.inverseBackdrop.BackgroundTransparency = 1
    composeSlot(slot)
    st.shipImage.Visible = true
    st.frame.Visible = true
    st.animating = false
  end

  function grid.flee(slot)
    local st = slotState[slot]
    if not st then return end
    st.frame.Visible = false
    st.shipImage.Visible = false
    st.damageGrid = nil
    if st.sinkTween then st.sinkTween:Cancel(); st.sinkTween = nil end
    st.animating = false
  end

  -- Per-gun firing timing. 3 quick flashes (~0.1s total) then a 0.4s delay,
  -- giving ~0.5s per gun firing.
  local HIT_FLASH_COUNT   = 3
  local HIT_FLASH_BURST_S = 0.1
  local HIT_POST_DELAY_S  = 0.4

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
    composeSlot(slot)

    local function setInverted(inverted)
      st.inverseBackdrop.BackgroundTransparency = inverted and 0 or 1
      st.shipImage.ImageColor3 = inverted and BG_COLOR or FG_COLOR
    end

    task.spawn(function()
      local halfPeriod = HIT_FLASH_BURST_S / (HIT_FLASH_COUNT * 2)
      for _ = 1, HIT_FLASH_COUNT do
        setInverted(true)
        task.wait(halfPeriod)
        setInverted(false)
        task.wait(halfPeriod)
      end
      task.wait(HIT_POST_DELAY_S)
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
      st.shipImage.Visible = false
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
