# Apple II Mobile Input Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Place Apple II on-screen mobile input in the empty letterbox/pillarbox space by orientation, and replace the native soft keyboard for numeric prompts with a custom keypad, so terminal content is never hidden.

**Architecture:** All work is in two files. `KeyInput.luau` gains an orientation helper, makes the existing mobile key-button row orientation-aware, and adds a custom numeric keypad that drives the existing `typeBuf`/`updateDisplay` machinery instead of a hidden `TextBox`. `PromptEngine.luau` exposes a `maxValue` field on the four capped numeric prompts so the keypad's ALL button knows the maximum.

**Tech Stack:** Roblox Luau, ScreenGui/Frame/TextButton, `workspace.CurrentCamera.ViewportSize` for orientation. Synced to Studio via Azul.

## Global Constraints

- Apple II interface only. Do not touch the Modern interface panels.
- Pure-logic engine modules in `shared/` are NOT touched. Changes are runtime UI only.
- Colour palette: amber labels `Color3.fromRGB(200,180,80)`, green positive `Color3.fromRGB(140,200,80)`, button border amber `Color3.fromRGB(100,100,40)`, button fill `Color3.fromRGB(30,30,30)`, panel bg `Color3.fromRGB(10,10,10)`.
- Font: `Enum.Font.RobotoMono` throughout.
- Mobile input UI lives in its own ScreenGui with `DisplayOrder = 100` (above the terminal's DisplayOrder 5), matching the existing `MobileKeyGui` pattern.
- Desktop input paths (`key`, `singlechar`, `type`, `numeric` non-mobile branches) MUST remain unchanged.
- The `type` prompt (firm-name) keeps its native keyboard + focus-recapture fix — out of scope.
- No automated tests: `UserInputService.TouchEnabled` is false in Studio, so the mobile branches don't run there, and TestEZ only covers `shared/` logic. Verification is diff/syntax review by the implementer plus on-device checks by the user.

---

## Verification Note (read before starting)

This plan changes Roblox runtime UI that only executes on a touch device. The implementer CANNOT fully verify it. For each task:
- The implementer verifies: the diff matches the plan, Luau is syntactically valid, and no desktop code path changed.
- The user verifies on-device (rotation, taps). Each task lists the exact on-device checks to hand back to the user.

Do not claim a task "works" — claim it is "implemented; awaiting on-device verification."

---

## Task 0: Commit the already-verified focus-recapture fix

The working tree already contains a verified fix in `KeyInput.luau`: the mobile
`type` and `numeric` `FocusLost` handlers re-capture focus when focus is lost
without Enter (orientation change). The user has confirmed this works. Commit it
on its own before layering new work on top.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau` (already edited in working tree)

- [ ] **Step 1: Confirm the working-tree change is the focus-recapture fix only**

Run: `git diff --stat`
Expected: only `KeyInput.luau` modified.

Run: `git diff sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`
Expected: two added `else` branches in the mobile `type` and `numeric` `FocusLost`
handlers, each calling `task.defer(function() if hiddenBox and hiddenBox.Parent then hiddenBox:CaptureFocus() end end)`.

- [ ] **Step 2: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "Re-capture mobile keyboard focus after orientation change

Rotating the device drops TextBox focus and closes the soft keyboard.
Re-capture focus on a non-Enter FocusLost while the prompt is active.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 1: Orientation helper + orientation-aware key-button row

Fixes issue 1 (B/S/Q row covers prices in landscape). Add an orientation helper
and rewrite `buildMobileButtons` to dock to the bottom in portrait and the right
edge in landscape, re-flowing live on rotation. This also fixes the `singlechar`
mobile path, which reuses `buildMobileButtons`.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`

**Interfaces:**
- Consumes: existing `screenGui`, `connections`, `mobileGui`, `mobileFrame`,
  `mobileButtons` locals inside `KeyInput.new`; existing `cleanup()` which already
  destroys `mobileGui` and disconnects everything in `connections`.
- Produces: module-level `isLandscape()` helper used by Task 2; an
  orientation-aware `buildMobileButtons(keys, onPress)` with identical call sites.

- [ ] **Step 1: Add the Workspace service and `isLandscape` helper**

At the top of the file, alongside the other `game:GetService` calls (after the
`local UserInputService = ...` block, near line 5-8), add:

```lua
local Workspace = game:GetService("Workspace")
```

Then, just above `local KeyInput = {}` (currently line 67), add the helper:

```lua
-- Landscape when the viewport is wider than tall. Used to dock mobile on-screen
-- input into the empty space: bottom band in portrait, right strip in landscape.
local function isLandscape()
  local cam = Workspace.CurrentCamera
  if not cam then return false end
  local vp = cam.ViewportSize
  return vp.X > vp.Y
end
```

- [ ] **Step 2: Replace `buildMobileButtons` with the orientation-aware version**

Replace the entire current `buildMobileButtons` function (currently lines 137-177)
with:

```lua
  -- Build mobile virtual key buttons for "key"/"singlechar" mode.
  -- Portrait: a horizontal row docked to the bottom (in the bottom letterbox band).
  -- Landscape: a vertical column docked to the right edge (in the empty right
  -- strip), so it never covers the prices/prompt on the left. Re-lays out on
  -- ViewportSize change so rotating mid-prompt re-flows the buttons.
  local function buildMobileButtons(keys, onPress)
    -- Across separate ScreenGuis, draw order and input are governed by
    -- DisplayOrder, not ZIndex; the terminal (DisplayOrder 5) is opaque, so the
    -- button row must live in its own higher-DisplayOrder ScreenGui or the
    -- terminal occludes it and absorbs every tap. (screenGui.Parent is PlayerGui.)
    mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "MobileKeyGui"
    mobileGui.DisplayOrder = 100
    mobileGui.ResetOnSpawn = false
    mobileGui.IgnoreGuiInset = true
    mobileGui.Parent = screenGui.Parent

    mobileFrame = Instance.new("Frame")
    mobileFrame.Name = "MobileKeyRow"
    mobileFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    mobileFrame.BorderSizePixel = 0
    mobileFrame.ZIndex = 50
    mobileFrame.Parent = mobileGui

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

    layout()
    table.insert(connections,
      Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
  end
```

- [ ] **Step 3: Verify the diff and syntax**

Run: `git diff sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`
Expected: only the service line, the `isLandscape` helper, and the
`buildMobileButtons` body changed. The two call sites of `buildMobileButtons`
(in the `key` branch and the `singlechar` branch) are unchanged. No desktop
(`InputBegan`) code changed.

Confirm balanced `end`s by eye: the function opens with `local function buildMobileButtons` and closes with a single `end` after the `table.insert(connections, ...)` line.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "Dock mobile key row to the right strip in landscape

Portrait keeps the bottom row; landscape moves it to the empty right
edge so it no longer covers the price table and prompt. Re-flows live
on orientation change.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand on-device checks to the user**

Ask the user to verify on their phone:
- Portrait: B/S/Q at port still appear as a bottom row.
- Landscape: B/S/Q appear as a column on the right; the price table and prompt
  on rows 21-24 are fully visible.
- Rotating while the prompt is showing re-flows the buttons between row and column.

---

## Task 2: Custom numeric keypad (replaces native keyboard)

Fixes issue 2. Replace the hidden-`TextBox` mobile path in the `numeric` branch
with a custom keypad that drives the existing `typeBuf`/`updateDisplay`. ALL is
added in Task 3; this task builds the keypad with digits, delete, and OK, plus an
inert ALL slot toggled by a flag.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`

**Interfaces:**
- Consumes: `isLandscape()` (Task 1); `screenGui`, `connections`, `mobileGui`,
  `mobileFrame`, `mobileButtons`, `typeBuf`, `cursorPos`, `maxLength`,
  `resetBlink`, `beep` locals; and the `numeric` branch locals `terminal`,
  `placeholder`, `updateDisplay`.
- Produces: `buildMobileKeypad(hasAll, onKey)` helper; new mobile behaviour for
  the `numeric` prompt. `onKey` receives a token string: `"0".."9"`, `"DEL"`,
  `"ALL"`, or `"OK"`.

- [ ] **Step 1: Add the `buildMobileKeypad` helper**

Immediately after the `buildMobileButtons` function (from Task 1), add:

```lua
  -- Build a custom numeric keypad for "numeric" prompts on mobile, replacing the
  -- native soft keyboard so we control size/placement. Portrait: a block docked
  -- to the bottom band. Landscape: a block docked to the right strip. onKey is
  -- called with "0".."9", "DEL", "ALL", or "OK". ALL is shown only when hasAll.
  local function buildMobileKeypad(hasAll, onKey)
    mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "MobileKeypadGui"
    mobileGui.DisplayOrder = 100
    mobileGui.ResetOnSpawn = false
    mobileGui.IgnoreGuiInset = true
    mobileGui.Parent = screenGui.Parent

    mobileFrame = Instance.new("Frame")
    mobileFrame.Name = "MobileKeypad"
    mobileFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    mobileFrame.BorderSizePixel = 0
    mobileFrame.ZIndex = 50
    mobileFrame.Parent = mobileGui

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
        local w = 240
        mobileFrame.Size = UDim2.new(0, w, 1, 0)
        mobileFrame.Position = UDim2.new(1, -w, 0, 0)
      else
        local h = 320
        mobileFrame.Size = UDim2.new(1, 0, 0, h)
        mobileFrame.Position = UDim2.new(0, 0, 1, -h)
      end
      for _, cell in ipairs(cells) do
        cell.btn.Size = UDim2.new(1 / COLS, -6, ROWFRAC, -6)
        cell.btn.Position = UDim2.new((cell.col - 1) / COLS, 3, (cell.row - 1) * ROWFRAC, 3)
      end
      okBtn.Size = UDim2.new(1, -6, ROWFRAC, -6)
      okBtn.Position = UDim2.new(0, 3, 4 * ROWFRAC, 3)
    end

    layout()
    table.insert(connections,
      Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
  end
```

- [ ] **Step 2: Replace the `numeric` mobile branch**

In the `numeric` prompt branch, find the `if isMobile then ... else` block that
currently creates the hidden `TextBox` (currently lines 480-503, starting
`if isMobile then` and ending just before `else` at line 503 which begins the
desktop `InputBegan` handler). Replace ONLY the mobile half (the lines from
`if isMobile then` through the line before `else`) with:

```lua
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
        end)
      else
```

Note: the `else` at the end above is the SAME `else` that begins the existing
desktop `InputBegan` handler — keep that handler unchanged. The net effect is the
hidden `TextBox`, its `RenderStepped` mirror, and its `FocusLost` connection are
gone from the `numeric` branch; the desktop branch is untouched.

- [ ] **Step 3: Verify the diff and syntax**

Run: `git diff sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`
Expected changes only:
- New `buildMobileKeypad` function added after `buildMobileButtons`.
- The `numeric` branch mobile half replaced (hidden `TextBox` removed; keypad
  added). The desktop `InputBegan` handler below it is unchanged.
- The `type` branch (firm-name) hidden `TextBox` is UNCHANGED.

Confirm by eye that `buildMobileKeypad` has balanced `end`s and the `numeric`
branch still closes with its existing `end`s.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "Replace native keyboard with custom keypad for numeric prompts

Mobile numeric entry now uses an on-screen keypad we position in the
empty space (bottom in portrait, right strip in landscape), driving the
existing typeBuf/echo. The prompt number is no longer hidden by the OS
keyboard. ALL button is inert until maxValue is wired up.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand on-device checks to the user**

Ask the user to verify on their phone (ALL not yet functional — that's Task 3):
- Buy and sell a good: a keypad appears (not the OS keyboard); digits build up the
  number shown on the prompt row; `<-` deletes; OK submits.
- Bank deposit/withdraw and Wu repay/borrow: same keypad behaviour.
- Entering more than 9 digits beeps and is rejected.
- Entering an amount over the limit (e.g. buy more than affordable) still beeps and
  stays on the prompt.
- Rotate mid-entry: keypad moves between bottom (portrait) and right (landscape);
  the typed number stays visible.

---

## Task 3: Wire up the ALL button (maxValue)

Expose `maxValue` on the four capped numeric prompts so the keypad's ALL button
fills the maximum. Uncapped prompts (Wu borrow/repay, Li Yuen) omit it and show no
ALL key.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`

**Interfaces:**
- Consumes: the keypad's `hasAll`/ALL handling (Task 2), which reads
  `promptDef.maxValue` (a number).
- Produces: `maxValue` set on the buy/sell amount prompt and the bank
  deposit/withdraw prompts.

- [ ] **Step 1: Add `maxValue` to the buy/sell amount prompt**

In `sceneBuySellAmount` (the prompt def returned near line 1129), add a `maxValue`
field. `affordable` (cash/price) and `cargoAmt` (held qty) are already in scope.
Locate the returned options table that begins `type = "numeric"` with
`_inputRow = 23` and add the field after `maxDigits = 9,`:

```lua
    maxDigits       = 9,
    maxValue        = isBuy and affordable or cargoAmt,
```

- [ ] **Step 2: Add `maxValue` to the bank deposit prompt**

In `sceneBank` (returned options near line 1180, `_inputRow = 19`,
`question = "How much will you deposit? "`), `maxDeposit` is in scope. Add after
`maxDigits = 9,`:

```lua
    maxDigits       = 9,
    maxValue        = maxDeposit,
```

- [ ] **Step 3: Add `maxValue` to the bank withdraw prompt**

In `sceneWithdraw` (returned options near line 1205, `_inputRow = 19`,
`question = "How much will you withdraw? "`), `maxWithdraw` is in scope. Add after
`maxDigits = 9,`:

```lua
    maxDigits       = 9,
    maxValue        = maxWithdraw,
```

- [ ] **Step 4: Verify the diff**

Run: `git diff sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`
Expected: exactly three added `maxValue = ...` lines, one each in
`sceneBuySellAmount`, `sceneBank`, `sceneWithdraw`. No other numeric prompts
(Wu borrow at `_inputRow = 20`, Wu repay, Li Yuen) gain `maxValue` — they correctly
keep no ALL key.

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "Expose maxValue for keypad ALL on capped numeric prompts

Buy=affordable, sell=cargo held, deposit=cash, withdraw=balance. The
keypad shows an ALL key that fills this maximum; uncapped prompts (Wu
borrow, Li Yuen) omit it.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 6: Hand on-device checks to the user**

Ask the user to verify on their phone:
- Buy: ALL fills the affordable amount; sell: ALL fills the quantity held.
- Bank deposit: ALL fills cash; withdraw: ALL fills bank balance.
- Wu borrow/repay and Li Yuen amount prompts show NO ALL key.

---

## Self-Review

**Spec coverage:**
- Orientation detection & live relayout → Task 1 (`isLandscape`, ViewportSize
  connection reused in Task 2).
- Key-button row landscape fix → Task 1.
- Numeric keypad replacing native keyboard → Task 2.
- ALL button + maxValue from buy/sell/deposit/withdraw → Tasks 2 (handling) + 3
  (wiring).
- `type` prompt unchanged / focus-recapture preserved → Task 0 commits it; Tasks
  1-3 don't touch the `type` branch.
- Desktop unchanged → enforced in every task's verify step.
- Testing = manual on-device → each task ends with a user hand-off step.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the inert
ALL slot in Task 2 is explicitly made functional in Task 3 (not a placeholder, a
sequenced dependency).

**Type consistency:** `isLandscape()` defined in Task 1, used in Task 2.
`buildMobileKeypad(hasAll, onKey)` token set `"0".."9"/"DEL"/"ALL"/"OK"` matches
the handler in Task 2 Step 2. `promptDef.maxValue` is a number in Task 3 and read
as `type(...) == "number"` / `math.floor(...)` in Task 2 — consistent.
