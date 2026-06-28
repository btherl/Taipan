# Mobile Native-Keyboard Canvas Shift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift the Apple II terminal canvas to the top of the screen while a mobile text-entry prompt is active so the native soft keyboard no longer covers the firm-name input row.

**Architecture:** Pure client UI change in one file. While a mobile `type` prompt is active, the terminal canvas frame (`TextParent`, a centered Frame with a 16:9 `UIAspectRatioConstraint`) is re-anchored to the top and capped to half-height; the aspect constraint then top-docks it in portrait and shrinks-to-top-half in landscape. A saved-then-restored closure reverts the frame when the prompt ends.

**Tech Stack:** Roblox Luau, client `LocalScript` UI (Apple II interface), Azul sync to Studio.

## Global Constraints

- Client UI only — **no** server changes, **no** changes to `GameService.server.luau`, **no** new remotes, **no** game-logic changes.
- Apple II interface only (the file `KeyInput.luau`); do not touch the Modern interface panels.
- The change applies to **all** mobile native-keyboard `type` prompts, not only firm-name (firm-name is the only such prompt today).
- Canvas height fraction is the single tunable constant `0.5` (top half of viewport).
- Behavior is a **snap** (no tween).
- The dock path is touch-only: it lives inside the existing `if isMobile then` branch (`isMobile = UserInputService.TouchEnabled`).
- Follow the CLAUDE.md script-edit workflow: (1) confirm local and Studio copies match, (2) modify local, (3) update Studio, (4) confirm they match again.
- Authoritative verification is **device-verify on a real touch device** (per the "Apple2 canvas letterbox" gotcha, vertical-layout bugs do not reproduce in Studio's letterboxed desktop viewport). TestEZ does not apply: the suite runs server-side and cannot require a `StarterGui` module, and this branch never executes without touch.

---

## File Structure

- **Modify:** `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`
  - Add one `restoreCanvas` upvalue in `KeyInput.new`'s local declarations.
  - Call `restoreCanvas` from the existing `cleanup()`.
  - Apply the dock at the top of the mobile `type` branch (the `if isMobile then` block).

No other files change.

---

## Task 1: Top-dock the terminal canvas during mobile text entry

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau` (local declarations near line 124-130; `cleanup()` at lines 155-169; mobile `type` branch at lines 512-545)

**Interfaces:**
- Consumes: `promptDef._terminal` (the Terminal instance; already referenced in this branch at line 523). `terminal._gui` is the canvas `ScreenGui` (set in `Terminal.luau:209`); `terminal._gui.TextParent` is the canvas `Frame` (created in `Text.luau:90-96`) with default `AnchorPoint (0.5,0.5)`, `Position UDim2.fromScale(0.5,0.5)`, `Size UDim2.fromScale(1,1)` and a child `UIAspectRatioConstraint` of 16:9.
- Produces: nothing consumed by other tasks (self-contained UI behavior).

- [ ] **Step 1: Confirm local and Studio copies of KeyInput match**

Per CLAUDE.md, before editing, verify the local file and the Studio copy are in sync (Azul). Read the local file and the Studio `KeyInput` script; confirm byte/size parity (a difference of 1 is allowed).

- [ ] **Step 2: Add the `restoreCanvas` upvalue**

In `KeyInput.new`, alongside the other per-instance locals (currently lines 124-130, ending with `local hiddenBox = nil`), add:

```lua
  local restoreCanvas  = nil  -- reverts the canvas top-dock applied for mobile text entry
```

- [ ] **Step 3: Call `restoreCanvas` from `cleanup()`**

In `cleanup()` (currently lines 155-169), add the restore call. Place it right after `connections = {}` so the canvas reverts on every prompt transition and on `destroy()`:

```lua
  local function cleanup()
    for _, c in ipairs(connections) do c:Disconnect() end
    connections = {}
    if restoreCanvas then restoreCanvas(); restoreCanvas = nil end
    if mobileGui then mobileGui:Destroy(); mobileGui = nil end
```

(Leave the rest of `cleanup()` unchanged.)

- [ ] **Step 4: Apply the dock at the top of the mobile `type` branch**

In the `type` branch, inside `if isMobile then` (currently begins at line 512 with the `-- Hidden TextBox triggers native on-screen keyboard` comment), insert the dock block **before** the hidden TextBox creation:

```lua
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
```

(Everything from `hiddenBox = Instance.new("TextBox")` onward is unchanged.)

- [ ] **Step 5: Sanity-check the edit reads correctly**

Re-read the modified branch. Confirm: `restoreCanvas` is declared once, set inside the dock block, and cleared in `cleanup()`; the dock block sits before `hiddenBox` creation; no stray duplicate of the `-- Hidden TextBox` comment.

- [ ] **Step 6: Update the Studio copy and confirm parity**

Per CLAUDE.md: let Azul propagate the local edit to Studio (or update the Studio copy), then confirm the local and Studio `KeyInput` copies match again (size difference of at most 1).

- [ ] **Step 7: Studio device-emulator smoke check (limited, non-authoritative)**

In Studio, enable the Device Emulator with a phone profile, then Play. Drive the Apple II flow to the firm-name prompt. If the emulator reports `UserInputService.TouchEnabled == true`, the dock path runs:

- Use `inspect_instance` (or `execute_luau` reading `Players.LocalPlayer.PlayerGui.TaipanTerminal.TextParent`) to confirm, while the firm-name prompt is active, the canvas shows `AnchorPoint = (0.5, 0)`, `Position = {0,0},{0,0}` (scale 0.5,0), `Size` scale `(1, 0.5)`.
- Submit a name (or leave the prompt) and confirm the canvas reverts to `AnchorPoint (0.5,0.5)`, `Position` scale `(0.5,0.5)`, `Size` scale `(1,1)`.

If the emulator does not set `TouchEnabled`, note that this branch cannot be exercised in Studio and rely on Step 9. Do **not** spend time forcing it — Studio's letterboxed viewport hides the vertical layout anyway.

- [ ] **Step 8: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "Top-dock terminal canvas during mobile text entry so soft keyboard does not cover firm-name input"
```

- [ ] **Step 9: Device-verify on a real touch device (authoritative)**

On a phone (live client), start a new game and reach the firm-name prompt. Confirm:
- **Portrait:** the terminal sits at the top, the keyboard is below, and the firm name is fully visible on row 14 as it is typed.
- **Landscape:** the canvas shrinks to the top half and the firm name is visible above the keyboard.
- **Rotate mid-entry:** the layout adapts without manual re-flow; the existing `FocusLost` handler re-captures focus.
- **After submit:** the canvas returns to centered/full size for the next screen.
- **Vacated lower area:** note whether it reads as black or shows an unwanted seam/color behind the keyboard. Record the result for Task 2.

---

## Task 2 (conditional): Add a full-screen black backing if the vacated area looks wrong

Only do this task if Step 9 of Task 1 shows the lower (vacated) area does **not** read as black during firm-name entry. If it already reads as black, skip this task entirely (YAGNI).

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau` (mobile `type` branch, dock block from Task 1)

**Interfaces:**
- Consumes: the `restoreCanvas` closure and dock block from Task 1.
- Produces: nothing for other tasks.

- [ ] **Step 1: Confirm local and Studio copies match** (CLAUDE.md workflow).

- [ ] **Step 2: Add a viewport-filling black frame in its own high-DisplayOrder ScreenGui**

Inside the dock block (Task 1), after computing `canvas`, create a black backing that sits *below* the terminal's DisplayOrder so the terminal still renders on top, but above the empty area. Extend `restoreCanvas` to destroy it:

```lua
          if canvas then
            -- ... (existing AnchorPoint/Position/Size dock from Task 1) ...

            -- Backing so the area vacated below the lifted canvas stays black
            -- (the canvas's own Background shrinks with it). Its own ScreenGui at a
            -- DisplayOrder just below the terminal (5) so the terminal stays on top.
            local backGui = Instance.new("ScreenGui")
            backGui.Name = "MobileTypeBacking"
            backGui.DisplayOrder = 4
            backGui.ResetOnSpawn = false
            backGui.IgnoreGuiInset = true
            backGui.Parent = screenGui.Parent
            local back = Instance.new("Frame")
            back.Size = UDim2.fromScale(1, 1)
            back.BackgroundColor3 = Color3.new(0, 0, 0)
            back.BorderSizePixel = 0
            back.Parent = backGui

            local origAnchor = canvas.AnchorPoint
            -- ... (rest of dock as in Task 1) ...
            restoreCanvas = function()
              if backGui then backGui:Destroy() end
              if canvas and canvas.Parent then
                canvas.AnchorPoint = origAnchor
                canvas.Position    = origPos
                canvas.Size        = origSize
              end
            end
          end
```

(Adjust the exact insertion so `origAnchor/origPos/origSize` are still captured before the dock writes, and `restoreCanvas` destroys `backGui` first. The terminal `ScreenGui` DisplayOrder is 5 by default — see `Terminal.new(displayOrder or 5)` — so `4` keeps the backing behind it.)

- [ ] **Step 3: Update Studio copy and confirm parity** (CLAUDE.md workflow).

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "Add black backing behind lifted canvas during mobile text entry"
```

- [ ] **Step 5: Device-verify** the vacated area now reads as black in both orientations during firm-name entry, and the terminal still renders on top.
