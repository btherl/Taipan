-- KeyInput.lua
-- Handles keyboard (desktop) and virtual buttons (mobile/touch) input.
-- Calls back into Apple2Interface via promptDef callbacks.

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local isMobile = UserInputService.TouchEnabled

-- Roblox KeyCode.Name for number keys are spelled out ("One", "Two", etc.)
-- Map them to digit characters for matching against prompt key sets.
local NUMKEY_MAP = {
  One = "1", Two = "2", Three = "3", Four = "4",
  Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
}

local KeyInput = {}

function KeyInput.new(screenGui)
  local connections    = {}   -- active input connections
  local mobileButtons  = {}   -- active mobile TextButton instances
  local mobileFrame    = nil  -- container for mobile buttons
  local typeBuf        = ""
  local cursorPos      = 1    -- 1-based position in buffer (1 to #typeBuf+1)
  local cursorVisible  = true
  local cursorTimer    = 0
  local maxLength      = nil  -- nil = unlimited
  local typeUpdateConn = nil  -- RenderStepped for mobile TextBox mirror
  local blinkConn      = nil  -- RenderStepped for cursor blink
  local hiddenBox      = nil  -- hidden TextBox for mobile keyboard

  local CURSOR_CHAR    = "_"
  local BLINK_HALF     = 0.265  -- half of 0.53s Apple II cursor cycle

  -- Build display string with cursor baked in
  local function buildDisplayStr()
    if cursorPos > #typeBuf then
      -- Cursor is at append position (after last char)
      if cursorVisible then
        return typeBuf .. CURSOR_CHAR
      else
        return typeBuf .. " "
      end
	else
      -- Cursor is within existing text
	  local before = typeBuf:sub(1, cursorPos - 1)
	  -- We add a space to keep lengths consistent with when cursor is displayed
	  local after  = typeBuf:sub(cursorPos + 1) .. " "
      if cursorVisible then
        return before .. CURSOR_CHAR .. after
      else
        return before .. typeBuf:sub(cursorPos, cursorPos) .. after
      end
    end
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
    if mobileFrame then mobileFrame:Destroy(); mobileFrame = nil end
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

  -- Build mobile virtual key buttons for "key" mode
  local function buildMobileButtons(keys, onPress)
    mobileFrame = Instance.new("Frame")
    mobileFrame.Name = "MobileKeyRow"
    mobileFrame.Size = UDim2.new(1, 0, 0, 60)
    mobileFrame.Position = UDim2.new(0, 0, 1, -60)
    mobileFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    mobileFrame.BorderSizePixel = 0
    mobileFrame.ZIndex = 50
    mobileFrame.Parent = screenGui

    local count = #keys
    for i, key in ipairs(keys) do
      local btn = Instance.new("TextButton")
      btn.Size = UDim2.new(1 / count, -4, 1, -8)
      btn.Position = UDim2.new((i - 1) / count, 2, 0, 4)
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

      local function onPress(key)
        key = key:upper()
        if validKeys[key] then
          promptDef.onKey(key, state, actions)
        end
      end

      if isMobile then
        buildMobileButtons(promptDef.keys, onPress)
      else
        table.insert(connections,
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local name = input.KeyCode.Name  -- e.g. "F", "R", "T", "One", "Two"
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

    elseif promptDef.type == "type" then
      local placeholder = promptDef.typePlaceholder or "> "
      maxLength = promptDef.maxLength  -- nil = unlimited

      if isMobile then
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
            end
          end)
        )
      else
        -- Desktop: capture character-by-character with blinking cursor
        local terminal = promptDef._terminal
        cursorPos = 1
        resetBlink()

        local function updateDisplay()
          if terminal then terminal.showInputLine(placeholder .. buildDisplayStr()) end
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
            if input.KeyCode == Enum.KeyCode.Return then
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
              local char = input.KeyCode.Name
              if NUMKEY_MAP[char] then char = NUMKEY_MAP[char] end
              if #char == 1 then
                if cursorPos <= #typeBuf then
                  -- Overwrite mode: replace char at cursor position
                  typeBuf = typeBuf:sub(1, cursorPos - 1) .. char .. typeBuf:sub(cursorPos + 1)
                  cursorPos = cursorPos + 1
                else
                  -- Append mode: add char at end (if under maxLength)
                  if not maxLength or #typeBuf < maxLength then
                    typeBuf = typeBuf .. char
                    cursorPos = cursorPos + 1
                  end
                end
                resetBlink()
                updateDisplay()
              end
            end
          end)
        )
      end
    end
  end

  function ki.destroy()
    cleanup()
  end

  return ki
end

return KeyInput
