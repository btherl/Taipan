-- KeyInput.lua
-- Handles keyboard (desktop) and virtual buttons (mobile/touch) input.
-- Calls back into Apple2Interface via promptDef callbacks.

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")  -- GetGuiInset: portrait keypad dock (see layout())

local SoundPlayer = require(ReplicatedStorage.SoundPlayer)

local isMobile = UserInputService.TouchEnabled

-- Roblox KeyCode.Name for number keys are spelled out ("One", "Two", etc.)
-- Map them to digit characters for matching against prompt key sets.
local NUMKEY_MAP = {
  One = "1", Two = "2", Three = "3", Four = "4",
  Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
  KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3", KeypadFour = "4",
  KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7", KeypadEight = "8",
  KeypadNine = "9", KeypadZero = "0",
}

-- Printable non-letter, non-digit keys: {unshifted, shifted}
local PRINTABLE_KEY_MAP = {
  Space        = {" ", " "},
  Period       = {".", ">"},
  Comma        = {",", "<"},
  Slash        = {"/", "?"},
  Semicolon    = {";", ":"},
  Quote        = {"'", '"'},
  LeftBracket  = {"[", "{"},
  RightBracket = {"]", "}"},
  Backslash    = {"\\", "|"},
  Minus        = {"-", "_"},
  Equals       = {"=", "+"},
  Grave        = {"`", "~"},
}

-- Shift+digit → punctuation (US layout)
local SHIFTED_NUM_MAP = {
  One = "!", Two = "@", Three = "#", Four = "$", Five = "%",
  Six = "^", Seven = "&", Eight = "*", Nine = "(", Zero = ")",
}

local function isShiftHeld()
  return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
      or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- Resolve a KeyCode.Name to a single printable character, or nil if not printable.
local function toPrintableChar(name)
  if NUMKEY_MAP[name] then
    return isShiftHeld() and (SHIFTED_NUM_MAP[name] or NUMKEY_MAP[name]) or NUMKEY_MAP[name]
  end
  if PRINTABLE_KEY_MAP[name] then
    local pair = PRINTABLE_KEY_MAP[name]
    return isShiftHeld() and pair[2] or pair[1]
  end
  if #name == 1 then
    -- Single-char name = letter key (A-Z); KeyCode always gives uppercase
    return name
  end
  return nil
end

-- Landscape when the viewport is wider than tall. Used to dock mobile on-screen
-- input into the empty space: bottom band in portrait, right strip in landscape.
local function isLandscape()
  local cam = Workspace.CurrentCamera
  if not cam then return false end
  local vp = cam.ViewportSize
  return vp.X > vp.Y
end

-- Fraction of the terminal's 16:9 canvas width occupied by the 40-column text
-- (column 40's right edge). The terminal text lives in a 1920x1080 virtual canvas
-- (Terminal.luau: X_OFFSET=30, CHAR_WIDTH=14*2.7=37.8, 40 cols), so the text ends
-- at (30 + 40*37.8)/1920 of the canvas width. Used to dock landscape controls just
-- right of the text instead of a fixed width from the screen edge — the canvas is
-- centred, so on wide screens (extra pillarbox) a fixed dock would overlap the
-- rightmost columns.
local TEXT_RIGHT_FRAC = (30 + 40 * (14 * 2.7)) / 1920  -- = 0.803125

-- Screen-space X just right of the terminal text (plus an 8px margin), and the
-- width from there to the right edge, for docking a landscape control strip. The
-- canvas is height-constrained in landscape, so its width = viewport height*16/9;
-- using full viewport height (ignoring the topbar inset) slightly over-estimates,
-- leaving a small safe gap rather than overlapping. minW guarantees a usable strip.
local function rightStrip(minW)
  local vp = Workspace.CurrentCamera.ViewportSize
  local canvasW = vp.Y * (16 / 9)
  local leftX = vp.X / 2 + (TEXT_RIGHT_FRAC - 0.5) * canvasW + 8
  if vp.X - leftX < minW then leftX = vp.X - minW end
  if leftX < 0 then leftX = 0 end
  return leftX, vp.X - leftX
end

local KeyInput = {}

-- Bare modifier presses produce no character and must never beep.
local MODIFIER_KEYS = {
  LeftShift = true, RightShift = true,
  LeftControl = true, RightControl = true,
  LeftAlt = true, RightAlt = true,
  CapsLock = true, LeftMeta = true, RightMeta = true,
  Unknown = true,
}

-- Play the Apple II input-rejection beep, unless this prompt opts out.
local function beep(promptDef)
  if promptDef and promptDef.noBeep then return end
  task.spawn(function() SoundPlayer.play("beep") end)
end

function KeyInput.new(screenGui)
  local connections    = {}   -- active input connections
  local mobileButtons  = {}   -- active mobile TextButton instances
  local mobileFrame    = nil  -- container for mobile buttons
  local mobileGui      = nil  -- dedicated high-DisplayOrder ScreenGui for the button row
  local typeBuf        = ""
  local cursorPos      = 1    -- 1-based position in buffer (1 to #typeBuf+1)
  local cursorVisible  = true
  local cursorTimer    = 0
  local maxLength      = nil  -- nil = unlimited
  local typeUpdateConn = nil  -- RenderStepped for mobile TextBox mirror
  local blinkConn      = nil  -- RenderStepped for cursor blink
  local hiddenBox      = nil  -- hidden TextBox for mobile keyboard
  local restoreCanvas  = nil  -- reverts the canvas top-dock applied for mobile text entry

  local CURSOR_CHAR    = "_"
  local BLINK_HALF     = 0.265  -- half of 0.53s Apple II cursor cycle

  -- Build display string with cursor baked in.
  -- Always returns exactly (fieldLen + 1) characters so Text:Update() never
  -- sees a length change — prevents sprite destroy/create and position staling.
  local function buildDisplayStr()
    local fieldLen = maxLength or #typeBuf
    local padded = typeBuf
    while #padded < fieldLen + 1 do padded = padded .. " " end
    local before = padded:sub(1, cursorPos - 1)
    local atCur  = cursorVisible and CURSOR_CHAR or padded:sub(cursorPos, cursorPos)
    local after  = padded:sub(cursorPos + 1)
    return before .. atCur .. after
  end

  -- Reset cursor blink to visible (call on any keypress)
  local function resetBlink()
    cursorTimer = 0
    cursorVisible = true
  end

  -- Clean up all active listeners and mobile UI
  local function cleanup()
    for _, c in ipairs(connections) do c:Disconnect() end
    connections = {}
    if restoreCanvas then restoreCanvas(); restoreCanvas = nil end
    if mobileGui then mobileGui:Destroy(); mobileGui = nil end
    mobileFrame = nil
    mobileButtons = {}
    if typeUpdateConn then typeUpdateConn:Disconnect(); typeUpdateConn = nil end
    if blinkConn then blinkConn:Disconnect(); blinkConn = nil end
    if hiddenBox then hiddenBox:Destroy(); hiddenBox = nil end
    typeBuf = ""
    cursorPos = 1
    cursorVisible = true
    cursorTimer = 0
    maxLength = nil
  end

  -- Create the mobile input container (its own high-DisplayOrder ScreenGui plus a
  -- backing Frame) and assign the shared mobileGui/mobileFrame upvalues. Across
  -- separate ScreenGuis, draw order and input are governed by DisplayOrder, not
  -- ZIndex; the terminal (DisplayOrder 5) is opaque, so mobile input must live in
  -- its own higher-DisplayOrder ScreenGui or the terminal occludes it and absorbs
  -- every tap. (screenGui.Parent is the LocalPlayer's PlayerGui.)
  local function makeMobileContainer(guiName, frameName)
    mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = guiName
    mobileGui.DisplayOrder = 100
    mobileGui.ResetOnSpawn = false
    mobileGui.IgnoreGuiInset = true
    mobileGui.Parent = screenGui.Parent

    mobileFrame = Instance.new("Frame")
    mobileFrame.Name = frameName
    mobileFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    mobileFrame.BorderSizePixel = 0
    mobileFrame.ZIndex = 50
    mobileFrame.Parent = mobileGui
  end

  -- Run layout once and re-run it on every viewport (orientation) change so the
  -- mobile controls re-flow live. The connection is tracked in `connections`, so
  -- cleanup() disconnects it when the prompt ends.
  local function bindLayout(layout)
    layout()
    table.insert(connections,
      Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
  end

  -- Build mobile virtual key buttons for "key"/"singlechar" mode.
  -- Portrait: a horizontal row docked to the bottom (in the bottom letterbox band).
  -- Landscape: a vertical column docked to the right edge (in the empty right
  -- strip), so it never covers the prices/prompt on the left. Re-lays out on
  -- ViewportSize change so rotating mid-prompt re-flows the buttons.
  local function buildMobileButtons(keys, onPress)
    makeMobileContainer("MobileKeyGui", "MobileKeyRow")

    local count = #keys
    for i, key in ipairs(keys) do
      local btn = Instance.new("TextButton")
      btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
      btn.BorderColor3 = Color3.fromRGB(100, 100, 40)
      btn.TextColor3 = Color3.fromRGB(200, 180, 80)
      btn.Font = Enum.Font.RobotoMono
      btn.TextSize = 18
      btn.ZIndex = 50
      btn.Text = key
      btn.Parent = mobileFrame
      btn.Activated:Connect(function() onPress(key) end)
      table.insert(mobileButtons, btn)
    end

    local function layout()
      if isLandscape() then
        -- Vertical column on the right edge.
        local w = 110
        mobileFrame.Size = UDim2.new(0, w, 1, 0)
        mobileFrame.Position = UDim2.new(1, -w, 0, 0)
        for i, btn in ipairs(mobileButtons) do
          btn.Size = UDim2.new(1, -8, 1 / count, -8)
          btn.Position = UDim2.new(0, 4, (i - 1) / count, 4)
        end
      else
        -- Horizontal row along the bottom.
        mobileFrame.Size = UDim2.new(1, 0, 0, 60)
        mobileFrame.Position = UDim2.new(0, 0, 1, -60)
        for i, btn in ipairs(mobileButtons) do
          btn.Size = UDim2.new(1 / count, -4, 1, -8)
          btn.Position = UDim2.new((i - 1) / count, 2, 0, 4)
        end
      end
    end

    bindLayout(layout)
  end

  -- Build a custom numeric keypad for "numeric" prompts on mobile, replacing the
  -- native soft keyboard so we control size/placement. Portrait: a block docked
  -- to the bottom band. Landscape: a block docked to the right strip. onKey is
  -- called with "0".."9", "DEL", "ALL", or "OK". ALL is shown only when hasAll.
  local function buildMobileKeypad(hasAll, onKey, term)
    makeMobileContainer("MobileKeypadGui", "MobileKeypad")

    -- The terminal's 16:9 text canvas (centred, with letterbox bands). Used to
    -- dock the keypad below the actual rendered text bottom in portrait, rather
    -- than a fixed band height that would cover the lowest rows on tall screens.
    local canvas = term and term._gui and term._gui:FindFirstChild("TextParent")

    -- 4 digit/util rows of 3 cells; bottom-left is ALL (or blank), bottom-right
    -- is delete. A full-width OK occupies a 5th visual row.
    local grid = {
      { "7", "8", "9" },
      { "4", "5", "6" },
      { "1", "2", "3" },
      { hasAll and "ALL" or "", "0", "DEL" },
    }
    local COLS = 3
    local cells = {}  -- { btn = TextButton, row = n, col = n }

    for r, rowLabels in ipairs(grid) do
      for c, label in ipairs(rowLabels) do
        if label ~= "" then
          local btn = Instance.new("TextButton")
          btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
          btn.BorderColor3 = Color3.fromRGB(100, 100, 40)
          btn.TextColor3 = Color3.fromRGB(200, 180, 80)
          btn.Font = Enum.Font.RobotoMono
          btn.TextSize = 22
          btn.ZIndex = 50
          btn.Text = (label == "DEL") and "<-" or label
          btn.Parent = mobileFrame
          local token = label  -- "ALL"/"DEL"/digit; label is the token directly
          btn.Activated:Connect(function() onKey(token) end)
          table.insert(mobileButtons, btn)
          table.insert(cells, { btn = btn, row = r, col = c })
        end
      end
    end

    local okBtn = Instance.new("TextButton")
    okBtn.Name = "OK"
    okBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 30)
    okBtn.BorderColor3 = Color3.fromRGB(100, 140, 60)
    okBtn.TextColor3 = Color3.fromRGB(140, 200, 80)
    okBtn.Font = Enum.Font.RobotoMono
    okBtn.TextSize = 22
    okBtn.ZIndex = 50
    okBtn.Text = "OK"
    okBtn.Parent = mobileFrame
    okBtn.Activated:Connect(function() onKey("OK") end)
    table.insert(mobileButtons, okBtn)

    local ROWFRAC = 1 / 5  -- 4 digit rows + 1 OK row
    local function layout()
      if isLandscape() then
        -- Dock to the empty strip right of the text, not a fixed width from the
        -- screen edge (which overlaps the rightmost columns on wide screens).
        local leftX, w = rightStrip(170)
        mobileFrame.Size = UDim2.new(0, w, 1, 0)
        mobileFrame.Position = UDim2.new(0, leftX, 0, 0)
      else
        -- Dock below the terminal text so it doesn't cover the bottom rows. The
        -- canvas is centred with a large bottom letterbox band in portrait; read
        -- its actual rendered bottom rather than guessing a fixed band height.
        --
        -- Coordinate-space correction: the terminal canvas gui is
        -- IgnoreGuiInset=false, so canvas.AbsolutePosition.Y is measured from the
        -- topbar-inset origin; this keypad gui (MobileKeypadGui) is
        -- IgnoreGuiInset=true, so a frame offset Y is true-screen. They do NOT
        -- share an origin — add the inset to lift the canvas bottom into the
        -- keypad's space, else the keypad lands ~inset px too high and covers the
        -- lowest text rows (confirmed on S23 Ultra: inset=58 swallowed rows 20-24).
        local vpY = Workspace.CurrentCamera.ViewportSize.Y
        local insetY = GuiService:GetGuiInset().Y
        local topY
        if canvas and canvas.AbsoluteSize.Y > 0 then
          topY = canvas.AbsolutePosition.Y + canvas.AbsoluteSize.Y + insetY + 6
        else
          topY = vpY - 320  -- fallback: fixed bottom band
        end
        -- Guarantee a usable keypad height. On near-square screens (rare) this can
        -- push the top up over the lowest text rows; a tappable keypad wins.
        local minH = 240
        if vpY - topY < minH then topY = vpY - minH end
        if topY < 0 then topY = 0 end
        mobileFrame.Size = UDim2.new(1, 0, 0, vpY - topY)
        mobileFrame.Position = UDim2.new(0, 0, 0, topY)
      end
      for _, cell in ipairs(cells) do
        cell.btn.Size = UDim2.new(1 / COLS, -6, ROWFRAC, -6)
        cell.btn.Position = UDim2.new((cell.col - 1) / COLS, 3, (cell.row - 1) * ROWFRAC, 3)
      end
      okBtn.Size = UDim2.new(1, -6, ROWFRAC, -6)
      okBtn.Position = UDim2.new(0, 3, 4 * ROWFRAC, 3)
    end

    bindLayout(layout)
    -- Re-flow when the canvas resizes (e.g. orientation change updates its bottom
    -- edge) so the portrait dock tracks the text; AbsoluteSize is current here,
    -- unlike when reading it during the ViewportSize signal.
    if canvas then
      table.insert(connections,
        canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
    end
  end

  local ki = {}

  -- Called by Apple2Interface whenever the active promptDef changes
  function ki.setPrompt(promptDef, state, actions)
    cleanup()
    if not promptDef then return end

    if promptDef.type == "key" then
      -- Build a set of valid keys (uppercase) for fast lookup
      local validKeys = {}
      for _, k in ipairs(promptDef.keys) do
        validKeys[k:upper()] = true
      end
      local acceptAny = promptDef.anyKey == true   -- NEW

      local function onPress(key)
        key = key:upper()
        if acceptAny or validKeys[key] then         -- NEW: acceptAny path
          promptDef.onKey(key, state, actions)
        else
          beep(promptDef)
        end
      end

      if isMobile then
        if acceptAny then                            -- NEW: "OK" button for any-key
          buildMobileButtons({"OK"}, onPress)
        else
          buildMobileButtons(promptDef.keys, onPress)
        end
      else
        table.insert(connections,
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local name = input.KeyCode.Name  -- e.g. "F", "R", "T", "One", "Two"
            if MODIFIER_KEYS[name] then return end  -- never beep on bare modifiers
            -- Map common keys to their character
            local char = name
            if #name == 1 then char = name:upper()
            elseif NUMKEY_MAP[name] then char = NUMKEY_MAP[name]
            elseif name == "Exclamation" then char = "!"
            elseif name == "Escape" then char = "C"   -- Escape acts as Cancel
            end
            onPress(char)
          end)
        )
      end

      -- Optional blinking cursor for key prompts (Apple II style single-char input)
      local terminal = promptDef._terminal
      local buildRow = promptDef._buildInputRow
      if terminal and buildRow and promptDef._inputRow then
        local function updateCursor()
          local cursorChar = cursorVisible and CURSOR_CHAR or " "
          terminal.showInputAt(promptDef._inputRow, buildRow(cursorChar))
        end
        resetBlink()
        updateCursor()
        blinkConn = RunService.RenderStepped:Connect(function(dt)
          cursorTimer += dt
          if cursorTimer >= BLINK_HALF then
            cursorVisible = not cursorVisible
            cursorTimer = 0
            updateCursor()
          end
        end)
      end

    elseif promptDef.type == "singlechar" then
      -- Single-character input with Enter to submit.
      -- Valid chars display; invalid chars or backspace clear the buffer.
      -- A new valid char replaces the current one.
      local validKeySet = {}
      for _, k in ipairs(promptDef.keys) do validKeySet[k:upper()] = true end

      local terminal = promptDef._terminal
      local buildRow = promptDef._buildInputRow
      local stored   = ""  -- "" or one accepted char

      local function updateDisplay()
        if terminal and buildRow and promptDef._inputRow then
          local cursorChar = cursorVisible and CURSOR_CHAR or " "
          -- Always pass exactly 2 chars so the row length stays constant
          local suffix = stored ~= "" and (stored .. cursorChar) or (cursorChar .. " ")
          terminal.showInputAt(promptDef._inputRow, buildRow(suffix))
        end
      end

      resetBlink()
      updateDisplay()
      blinkConn = RunService.RenderStepped:Connect(function(dt)
        cursorTimer += dt
        if cursorTimer >= BLINK_HALF then
          cursorVisible = not cursorVisible
          cursorTimer = 0
          updateDisplay()
        end
      end)

      if isMobile then
        -- Mobile: a tap on a virtual key fires immediately (no Enter/confirm
        -- step). Behaviourally identical to the "key" type on touch. Reuses the
        -- validKeySet built above and the shared buildMobileButtons helper.
        local function onPress(key)
          key = key:upper()
          if validKeySet[key] then
            promptDef.onKey(key, state, actions)
          end
        end
        buildMobileButtons(promptDef.keys, onPress)
      else
        table.insert(connections,
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local name = input.KeyCode.Name

            if name == "Return" or name == "KeypadEnter" then
              if stored ~= "" then
                promptDef.onKey(stored, state, actions)
              end
              return
            end

            if name == "BackSpace" then
              stored = ""
              resetBlink()
              updateDisplay()
              return
            end

            if MODIFIER_KEYS[name] then return end  -- never beep on bare modifiers

            local char = name
            if #name == 1 then char = name:upper()
            elseif NUMKEY_MAP[name] then char = NUMKEY_MAP[name]
            end

            if validKeySet[char] then
              stored = char
            else
              stored = ""
              beep(promptDef)
            end
            resetBlink()
            updateDisplay()
          end)
        )
      end

    elseif promptDef.type == "type" then
      local placeholder = promptDef.typePlaceholder or "> "
      maxLength = promptDef.maxLength  -- nil = unlimited

      if isMobile then
        -- Lift the terminal canvas into the top half of the screen so the native
        -- soft keyboard (drawn by the OS along the bottom) does not cover the
        -- input row. The canvas Frame has a 16:9 UIAspectRatioConstraint, so
        -- capping it to a top-anchored half-height box top-docks it in portrait
        -- (already short) and shrinks it to the top half in landscape. The scale
        -- values re-fit automatically on orientation change, so no manual
        -- re-flow is needed. cleanup() calls restoreCanvas to revert.
        do
          local term   = promptDef._terminal
          local canvas = term and term._gui and term._gui:FindFirstChild("TextParent")
          if canvas then
            local origAnchor = canvas.AnchorPoint
            local origPos    = canvas.Position
            local origSize   = canvas.Size
            canvas.AnchorPoint = Vector2.new(0.5, 0)
            canvas.Position    = UDim2.fromScale(0.5, 0)
            canvas.Size        = UDim2.fromScale(1, 0.5)
            restoreCanvas = function()
              if canvas and canvas.Parent then
                canvas.AnchorPoint = origAnchor
                canvas.Position    = origPos
                canvas.Size        = origSize
              end
            end
          end
        end

        -- Hidden TextBox triggers native on-screen keyboard
        hiddenBox = Instance.new("TextBox")
        hiddenBox.Size = UDim2.new(0, 1, 0, 1)
        hiddenBox.Position = UDim2.new(0, -10, 0, -10)
        hiddenBox.BackgroundTransparency = 1
        hiddenBox.Text = ""
        hiddenBox.Parent = screenGui
        hiddenBox:CaptureFocus()

        -- Mirror TextBox content to terminal each frame
        local terminal = promptDef._terminal  -- Apple2Interface sets this
        typeUpdateConn = RunService.RenderStepped:Connect(function()
          if terminal then terminal.showInputLine(placeholder .. hiddenBox.Text) end
        end)

        table.insert(connections,
          hiddenBox.FocusLost:Connect(function(enterPressed)
            if enterPressed then
              local submitted = hiddenBox.Text
              hiddenBox.Text = ""
              local err = promptDef.onType(submitted, state, actions)
              if err and promptDef._onError then promptDef._onError(err) end
            else
              -- Focus lost without submitting (e.g. orientation change drops
              -- TextBox focus and closes the soft keyboard). Re-capture focus on
              -- the next frame while this prompt is still active. The Parent
              -- guard prevents re-summoning after cleanup() destroys the box.
              task.defer(function()
                if hiddenBox and hiddenBox.Parent then hiddenBox:CaptureFocus() end
              end)
            end
          end)
        )
      else
        -- Desktop: capture character-by-character with blinking cursor
        local terminal = promptDef._terminal
        cursorPos = 1
        resetBlink()

        local function updateDisplay()
          if terminal then
            local displayStr = buildDisplayStr()
            local buildRow = promptDef._buildInputRow
            if buildRow and promptDef._inputRow then
              terminal.showInputAt(promptDef._inputRow, buildRow(displayStr))
            else
              terminal.showInputLine(placeholder .. displayStr)
            end
          end
        end

        updateDisplay()

        -- Cursor blink timer
        blinkConn = RunService.RenderStepped:Connect(function(dt)
          cursorTimer = cursorTimer + dt
          if cursorTimer >= BLINK_HALF then
            cursorVisible = not cursorVisible
            cursorTimer = 0
            updateDisplay()
          end
        end)

        table.insert(connections,
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
              local submitted = typeBuf
              typeBuf = ""
              cursorPos = 1
              resetBlink()
              if terminal then terminal.showInputLine(placeholder) end
              local err = promptDef.onType(submitted, state, actions)
              if err and promptDef._onError then promptDef._onError(err) end
            elseif input.KeyCode == Enum.KeyCode.Escape then
              typeBuf = ""
              cursorPos = 1
              resetBlink()
              if terminal then terminal.showInputLine(placeholder) end
              local err = promptDef.onType("", state, actions)
              if err and promptDef._onError then promptDef._onError(err) end
            elseif input.KeyCode == Enum.KeyCode.Left then
              if cursorPos > 1 then cursorPos = cursorPos - 1 end
              resetBlink()
              updateDisplay()
            elseif input.KeyCode == Enum.KeyCode.Right then
              if cursorPos <= #typeBuf then cursorPos = cursorPos + 1 end
              resetBlink()
              updateDisplay()
            elseif input.KeyCode == Enum.KeyCode.Backspace then
              if cursorPos > 1 then
                typeBuf = typeBuf:sub(1, cursorPos - 2) .. typeBuf:sub(cursorPos)
                cursorPos = cursorPos - 1
              end
              resetBlink()
              updateDisplay()
            else
              if MODIFIER_KEYS[input.KeyCode.Name] then return end  -- never beep on bare modifiers
              local char = toPrintableChar(input.KeyCode.Name)
              if char then
                if cursorPos <= #typeBuf then
                  -- Overwrite mode: replace char at cursor position
                  typeBuf = typeBuf:sub(1, cursorPos - 1) .. char .. typeBuf:sub(cursorPos + 1)
                  cursorPos = cursorPos + 1
                  resetBlink()
                  updateDisplay()
                else
                  -- Append mode: add char at end (if under maxLength)
                  if not maxLength or #typeBuf < maxLength then
                    typeBuf = typeBuf .. char
                    cursorPos = cursorPos + 1
                    resetBlink()
                    updateDisplay()
                  else
                    beep(promptDef)  -- buffer already at max length
                  end
                end
              else
                beep(promptDef)  -- non-printable key
              end
            end
          end)
        )
      end

    elseif promptDef.type == "numeric" then
      local placeholder = promptDef.typePlaceholder or "> "
      maxLength = promptDef.maxDigits   -- reuse maxLength variable for buildDisplayStr

      local terminal = promptDef._terminal
      cursorPos = #typeBuf + 1
      resetBlink()

      local function updateDisplay()
        if terminal then
          local displayStr = buildDisplayStr()
          if promptDef._buildInputRow and promptDef._inputRow then
            terminal.showInputAt(promptDef._inputRow, promptDef._buildInputRow(displayStr))
          else
            terminal.showInputLine(placeholder .. displayStr)
          end
        end
      end

      updateDisplay()

      blinkConn = RunService.RenderStepped:Connect(function(dt)
        cursorTimer = cursorTimer + dt
        if cursorTimer >= BLINK_HALF then
          cursorVisible = not cursorVisible
          cursorTimer = 0
          updateDisplay()
        end
      end)

      if isMobile then
        -- Custom keypad drives typeBuf directly and reuses updateDisplay()/blink,
        -- so the number still echoes on the terminal input row. No native keyboard.
        local hasAll = type(promptDef.maxValue) == "number"
        buildMobileKeypad(hasAll, function(token)
          if token == "OK" then
            local submitted = typeBuf
            typeBuf = ""
            cursorPos = 1
            resetBlink()
            if terminal then terminal.showInputLine(placeholder) end
            local err = promptDef.onType(submitted, state, actions)
            if err and promptDef._onError then promptDef._onError(err) end
          elseif token == "DEL" then
            if #typeBuf > 0 then
              typeBuf = typeBuf:sub(1, -2)
              cursorPos = #typeBuf + 1
            else
              beep(promptDef)
            end
            resetBlink()
            updateDisplay()
          elseif token == "ALL" then
            local v = tostring(math.floor(promptDef.maxValue))
            if maxLength and #v > maxLength then v = v:sub(1, maxLength) end
            typeBuf = v
            cursorPos = #typeBuf + 1
            resetBlink()
            updateDisplay()
          else
            -- digit token "0".."9"
            if not maxLength or #typeBuf < maxLength then
              typeBuf = typeBuf .. token
              cursorPos = #typeBuf + 1
              resetBlink()
              updateDisplay()
            else
              beep(promptDef)  -- buffer already at max digits
            end
          end
        end, terminal)
      else
        table.insert(connections,
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
              local submitted = typeBuf
              typeBuf = ""
              cursorPos = 1
              resetBlink()
              if terminal then terminal.showInputLine(placeholder) end
              local err = promptDef.onType(submitted, state, actions)
              if err and promptDef._onError then promptDef._onError(err) end
            elseif input.KeyCode == Enum.KeyCode.Escape then
              typeBuf = ""
              cursorPos = 1
              resetBlink()
              if terminal then terminal.showInputLine(placeholder) end
              local err = promptDef.onType("", state, actions)
              if err and promptDef._onError then promptDef._onError(err) end
            elseif input.KeyCode == Enum.KeyCode.Left
                or input.KeyCode == Enum.KeyCode.Backspace then
              -- Left arrow deletes the last digit (Apple II). Backspace mirrors it
              -- for usability (spec Decision 1). Beep when there is nothing to delete.
              if #typeBuf > 0 then
                typeBuf = typeBuf:sub(1, -2)
                cursorPos = #typeBuf + 1
              else
                beep(promptDef)
              end
              resetBlink()
              updateDisplay()
            else
              if MODIFIER_KEYS[input.KeyCode.Name] then return end  -- never beep on bare modifiers
              -- Accept digit keys only. Backspace is handled with Left above.
              local char = input.KeyCode.Name
              if NUMKEY_MAP[char] then char = NUMKEY_MAP[char] end
              if #char == 1 and char:match("%d") then
                if not maxLength or #typeBuf < maxLength then
                  typeBuf = typeBuf .. char
                  cursorPos = #typeBuf + 1
                  resetBlink()
                  updateDisplay()
                else
                  beep(promptDef)  -- buffer already at max digits
                end
              else
                beep(promptDef)  -- non-digit key
              end
            end
          end)
        )
      end
    end  -- if promptDef.type == "key" / "type" / "numeric"
  end

  function ki.destroy()
    cleanup()
  end

  return ki
end

return KeyInput
