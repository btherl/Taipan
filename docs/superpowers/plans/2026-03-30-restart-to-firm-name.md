# Restart Returns to Firm Name Screen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After any game ending (sunk, quit, or retired), both Apple II and Modern UI return to the firm name screen so the player can rename their firm and re-pick their start type.

**Architecture:** The server's `RestartGame` handler fires a minimal "lobby" state (`startChoice=nil`) directly to the client, then nils the player slot. Existing per-handler guards (`type(state) ~= "table"`) already block all game actions when the slot is nil. Both UIs detect `startChoice==nil` and show the firm name screen — Apple II via existing PromptEngine routing (no change), Modern via a new `startPanel.show()` call.

**Tech Stack:** Roblox Luau, Rojo (file sync), Roblox Studio MCP tools for injection and playtesting.

---

## Files

| File | Change |
|---|---|
| `src/ServerScriptService/GameService.server.lua` | RestartGame handler replaced; ChooseStart guard simplified |
| `src/StarterGui/TaipanGui/Apple2Interface.lua` | One branch added to `adapter.update` |
| `src/StarterGui/TaipanGui/Panels/StartPanel.lua` | `BUTTON_DEFAULT_COLOR` constant; `hide()` → Visible=false; `show()` added |
| `src/StarterGui/TaipanGui/ModernInterface.lua` | Lobby early-return added to `adapter.update` |

**Not changed:** `PromptEngine.lua`, `GameState.lua`, `PersistenceEngine.lua`, `GameActions.lua`, all other panels.

---

## Workflow reminder

For each task:
1. Edit the `.lua` file on disk.
2. Verify local file size vs Studio file size (diff of ≤1 line is acceptable — Studio adds a trailing newline).
3. Inject the change into Studio via MCP `multi_edit` (Studio path uses dot notation — see each task).
4. Re-verify sizes.

Studio path mapping:
- `src/ServerScriptService/GameService.server.lua` → `game.ServerScriptService.GameService`
- `src/StarterGui/TaipanGui/Apple2Interface.lua` → `game.StarterGui.TaipanGui.GameController.Apple2Interface`
- `src/StarterGui/TaipanGui/Panels/StartPanel.lua` → `game.StarterGui.TaipanGui.GameController.Panels.StartPanel`
- `src/StarterGui/TaipanGui/ModernInterface.lua` → `game.StarterGui.TaipanGui.GameController.ModernInterface`

---

## Task 1: Update RestartGame and ChooseStart in GameService

**Files:**
- Modify: `src/ServerScriptService/GameService.server.lua:60-79` (ChooseStart guard)
- Modify: `src/ServerScriptService/GameService.server.lua:365-384` (RestartGame handler)

### ChooseStart guard (line 62)

Current code at line 62:
```lua
  if playerStates[player] then return end           -- already initialised (returning player) or double-fire guard
```

Replace with:
```lua
  local existing = playerStates[player]
  if type(existing) == "table" and existing.startChoice ~= nil then return end
  -- nil slot (new player or post-restart) → allowed through
```

### RestartGame handler (lines 365-384)

Current handler body:
```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.gameOver then return end
  local wasTutorialSeen = state.seenTutorial  -- preserve so tutorial doesn't replay
  local prevStartChoice = state.startChoice or "cash"  -- preserve original start choice
  local prevUIMode = state.uiMode                      -- preserve interface mode
  local newState = GameState.newGame(prevStartChoice)
  newState.currentPrices = PriceEngine.calculatePrices(newState.basePrices, newState.currentPort)
  newState.holdSpace = newState.shipCapacity
    - newState.shipCargo[1] - newState.shipCargo[2]
    - newState.shipCargo[3] - newState.shipCargo[4]
    - newState.guns * 10
  newState.seenTutorial = wasTutorialSeen
  newState.uiMode = prevUIMode
  if not wasTutorialSeen then
    newState.pendingTutorial = true  -- tutorial still pending; fires on first HK arrival
  end
  playerStates[player] = newState
  pushState(player)
end)
```

Replace with:
```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.gameOver then return end
  -- Push a minimal lobby state so the client shows the firm name screen.
  -- Then nil the slot: all existing handler guards (type ~= "table") block
  -- game actions during lobby, and PlayerRemoving skips the DataStore save.
  local lobbyState = {
    startChoice  = nil,
    gameOver     = false,
    turnsElapsed = 1,
    destination  = 0,
    uiMode       = state.uiMode,
    seenTutorial = state.seenTutorial,
  }
  Remotes.StateUpdate:FireClient(player, lobbyState)
  playerStates[player] = nil
end)
```

- [ ] **Step 1: Edit local file**

  Apply both changes above to `src/ServerScriptService/GameService.server.lua`.

- [ ] **Step 2: Check local line count**

  ```bash
  wc -l src/ServerScriptService/GameService.server.lua
  ```

- [ ] **Step 3: Read Studio version to confirm current content (simulation must be stopped)**

  Use `mcp__Roblox_Studio__script_read` on `game.ServerScriptService.GameService` at the relevant line ranges (lines 60–79 and 365–384) to confirm exact current text before patching.

- [ ] **Step 4: Inject ChooseStart change into Studio**

  Use `mcp__Roblox_Studio__multi_edit` on `game.ServerScriptService.GameService`:
  ```
  old_string: "  if playerStates[player] then return end           -- already initialised (returning player) or double-fire guard"
  new_string: "  local existing = playerStates[player]\n  if type(existing) == \"table\" and existing.startChoice ~= nil then return end\n  -- nil slot (new player or post-restart) → allowed through"
  ```

- [ ] **Step 5: Inject RestartGame change into Studio**

  Use `mcp__Roblox_Studio__multi_edit` (second edit in same call) replacing the full RestartGame handler body as shown above.

- [ ] **Step 6: Verify line counts match (diff ≤ 1)**

  Read Studio file final line count and compare to local.

- [ ] **Step 7: Commit**

  ```bash
  git add src/ServerScriptService/GameService.server.lua
  git commit -m "feat: RestartGame sends lobby state; ChooseStart allows nil slot"
  ```

---

## Task 2: Update Apple2Interface — reset localScene on lobby

**Files:**
- Modify: `src/StarterGui/TaipanGui/Apple2Interface.lua:85-94`

Current `adapter.update` (lines 85–94):
```lua
  function adapter.update(state)
    lastState = state

    -- Server-driven scenes clear localScene
    if isServerDriven(state) then
      localScene = nil
    end

    render(state, localScene)
  end
```

New version:
```lua
  function adapter.update(state)
    lastState = state

    -- Server-driven scenes clear localScene
    if isServerDriven(state) then
      localScene = nil
    elseif state.startChoice == nil then  -- lobby state: reset to firm name screen
      localScene = nil
    end

    render(state, localScene)
  end
```

- [ ] **Step 1: Edit local file**

  Apply the change above to `src/StarterGui/TaipanGui/Apple2Interface.lua`.

- [ ] **Step 2: Check local line count**

  ```bash
  wc -l src/StarterGui/TaipanGui/Apple2Interface.lua
  ```

- [ ] **Step 3: Read Studio version to confirm current content**

  Use `mcp__Roblox_Studio__script_read` on `game.StarterGui.TaipanGui.GameController.Apple2Interface` at lines 85–94.

- [ ] **Step 4: Inject change into Studio**

  Use `mcp__Roblox_Studio__multi_edit`:
  ```
  old_string:
  "    -- Server-driven scenes clear localScene\n    if isServerDriven(state) then\n      localScene = nil\n    end\n\n    render(state, localScene)"

  new_string:
  "    -- Server-driven scenes clear localScene\n    if isServerDriven(state) then\n      localScene = nil\n    elseif state.startChoice == nil then  -- lobby state: reset to firm name screen\n      localScene = nil\n    end\n\n    render(state, localScene)"
  ```

- [ ] **Step 5: Verify line counts match (diff ≤ 1)**

- [ ] **Step 6: Commit**

  ```bash
  git add src/StarterGui/TaipanGui/Apple2Interface.lua
  git commit -m "feat: reset localScene on lobby state in Apple2Interface"
  ```

---

## Task 3: Update StartPanel — hide/show lifecycle

**Files:**
- Modify: `src/StarterGui/TaipanGui/Panels/StartPanel.lua`

Three changes to this file:

**Change A** — Add `BUTTON_DEFAULT_COLOR` local constant just inside `StartPanel.new`, before `cashBtn` is created. This replaces the two inline `Color3.fromRGB(20, 20, 20)` literals on `cashBtn` and `gunsBtn`.

After line 5 (after `function StartPanel.new(parent, onChoose)`), add:
```lua
  local BUTTON_DEFAULT_COLOR = Color3.fromRGB(20, 20, 20)
```

Then change `cashBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)` (line 68) to:
```lua
  cashBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
```

And `gunsBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)` (line 81) to:
```lua
  gunsBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
```

**Change B** — The constructor creates the frame with `frame.Visible = true` (line 13). Change this to `frame.Visible = false` so returning players (who go straight to the game) never see a flash of the StartPanel before the first `adapter.update` call hides it. New-player and restart flows both go through `startPanel.show()`, which sets `Visible = true`.

```lua
-- line 13: change from
  frame.Visible = true
-- to
  frame.Visible = false
```

**Change C** — Replace `panel.hide()` (currently destroys frame) with Visible=false:

Current (line 105–107):
```lua
  function panel.hide()
    if frame and frame.Parent then frame:Destroy() end
  end
```

New:
```lua
  function panel.hide()
    frame.Visible = false
  end
```

**Change D** — Add `panel.show()` after `panel.hide()`:

```lua
  function panel.show()
    chosen = false
    cashBtn.Active = true
    gunsBtn.Active = true
    cashBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
    gunsBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
    prompt.Text = "Elder Brother Wu says:\n\"Do you have a firm, or a ship?\""
    frame.Visible = true
  end
```

- [ ] **Step 1: Edit local file**

  Apply changes A, B, and C to `src/StarterGui/TaipanGui/Panels/StartPanel.lua`.

- [ ] **Step 2: Check local line count**

  ```bash
  wc -l src/StarterGui/TaipanGui/Panels/StartPanel.lua
  ```

- [ ] **Step 3: Read Studio version to confirm current content**

  Use `mcp__Roblox_Studio__script_read` on `game.StarterGui.TaipanGui.GameController.Panels.StartPanel` (full file).

- [ ] **Step 4: Inject all four changes into Studio in one multi_edit call**

  Use `mcp__Roblox_Studio__multi_edit` with four edits in order:

  **Edit 1** — Add `BUTTON_DEFAULT_COLOR` constant (insert after the function declaration line):
  ```
  old_string: "  local frame = Instance.new(\"Frame\")"
  new_string: "  local BUTTON_DEFAULT_COLOR = Color3.fromRGB(20, 20, 20)\n  local frame = Instance.new(\"Frame\")"
  ```

  **Edit 2** — Change frame.Visible to false in constructor:
  ```
  old_string: "  frame.Visible = true"
  new_string: "  frame.Visible = false"
  ```
  (There is only one `frame.Visible = true` in the file — in the constructor at line 13.)

  **Edit 3** — Replace cashBtn and gunsBtn background color literals with the constant (both on separate lines — use replace_all: true or two separate edits):
  ```
  old_string: "  cashBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)"
  new_string: "  cashBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR"
  ```
  Then:
  ```
  old_string: "  gunsBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)"
  new_string: "  gunsBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR"
  ```

  **Edit 4** — Replace `panel.hide()` body and add `panel.show()`:
  ```
  old_string:
  "  function panel.hide()\n    if frame and frame.Parent then frame:Destroy() end\n  end"
  new_string:
  "  function panel.hide()\n    frame.Visible = false\n  end\n  function panel.show()\n    chosen = false\n    cashBtn.Active = true\n    gunsBtn.Active = true\n    cashBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR\n    gunsBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR\n    prompt.Text = \"Elder Brother Wu says:\\n\\\"Do you have a firm, or a ship?\\\"\"\n    frame.Visible = true\n  end"
  ```

- [ ] **Step 5: Verify line counts match (diff ≤ 1)**

- [ ] **Step 6: Commit**

  ```bash
  git add src/StarterGui/TaipanGui/Panels/StartPanel.lua
  git commit -m "feat: StartPanel hide/show lifecycle for restart flow"
  ```

---

## Task 4: Update ModernInterface — lobby early-return

**Files:**
- Modify: `src/StarterGui/TaipanGui/ModernInterface.lua:166-188`

Current `adapter.update` (lines 166–188):
```lua
  function adapter.update(state)
    startPanel.hide()  -- idempotent: destroys frame on first call, no-op thereafter
    portPanel.update(state)
    statusStrip.update(state)
    inventoryPanel.update(state)
    pricesPanel.update(state)
    buySellPanel.update(state)
    warehousePanel.update(state)
    wuPanel.update(state)
    bankPanel.update(state)
    gameOverPanel.update(state)
    combatPanel.update(state)
    shipPanel.update(state)

    latestUIMode = state.uiMode or "modern"
    local canSettings = not state.gameOver
      and state.combat == nil
      and state.shipOffer == nil
    settingsBtn.Visible = canSettings
    if not canSettings and settingsOverlay then
      settingsOverlay:Destroy(); settingsOverlay = nil
    end
  end
```

New version — add the lobby guard block at the top, and update the `startPanel.hide()` comment:
```lua
  function adapter.update(state)
    -- Lobby state: startChoice is nil (a real game always has startChoice set).
    -- Early-return here: state is incomplete, skip all panel updates.
    if state.startChoice == nil and not state.gameOver then
      if settingsOverlay then
        settingsOverlay:Destroy()
        settingsOverlay = nil
      end
      settingsBtn.Visible = false
      startPanel.show()
      return
    end

    startPanel.hide()
    portPanel.update(state)
    statusStrip.update(state)
    inventoryPanel.update(state)
    pricesPanel.update(state)
    buySellPanel.update(state)
    warehousePanel.update(state)
    wuPanel.update(state)
    bankPanel.update(state)
    gameOverPanel.update(state)
    combatPanel.update(state)
    shipPanel.update(state)

    latestUIMode = state.uiMode or "modern"
    local canSettings = not state.gameOver
      and state.combat == nil
      and state.shipOffer == nil
    settingsBtn.Visible = canSettings
    if not canSettings and settingsOverlay then
      settingsOverlay:Destroy(); settingsOverlay = nil
    end
  end
```

- [ ] **Step 1: Edit local file**

  Apply the change above to `src/StarterGui/TaipanGui/ModernInterface.lua`.

- [ ] **Step 2: Check local line count**

  ```bash
  wc -l src/StarterGui/TaipanGui/ModernInterface.lua
  ```

- [ ] **Step 3: Read Studio version to confirm current content**

  Use `mcp__Roblox_Studio__script_read` on `game.StarterGui.TaipanGui.GameController.ModernInterface` at lines 166–188.

- [ ] **Step 4: Inject change into Studio**

  Use `mcp__Roblox_Studio__multi_edit` replacing the full `adapter.update` function body.

- [ ] **Step 5: Verify line counts match (diff ≤ 1)**

- [ ] **Step 6: Commit**

  ```bash
  git add src/StarterGui/TaipanGui/ModernInterface.lua
  git commit -m "feat: ModernInterface shows StartPanel on lobby state"
  ```

---

## Task 5: MCP Playtest — Apple II restart flow

Verify the full Apple II restart-to-firm-name flow in Studio Play mode.

- [ ] **Step 1: Start Play mode**

  `mcp__Roblox_Studio__start_stop_play(true)`

- [ ] **Step 2: Screen capture — should see InterfacePicker**

- [ ] **Step 3: Select Apple II interface**

  `user_keyboard_input keyPress A`

- [ ] **Step 4: Screen capture — should see firm name box (rows 8–17, box centered)**

- [ ] **Step 5: Type name and press Enter**

  `user_keyboard_input keyPress T`, `A`, `I`, `P`, `A`, `N` then `Return`

- [ ] **Step 6: Select cash start**

  `user_keyboard_input keyPress One`

- [ ] **Step 7: Screen capture — should see port screen (HONG KONG, Jan 1860)**

- [ ] **Step 8: Force game-over by firing QuitGame**

  Via `execute_luau`:
  ```lua
  local Remotes = require(game:GetService("ReplicatedStorage").Remotes)
  Remotes.QuitGame:FireServer()
  ```

- [ ] **Step 9: Screen capture — should see game-over scene (score + rating + restart prompt)**

- [ ] **Step 10: Press R to restart**

  `user_keyboard_input keyPress R`

- [ ] **Step 11: Screen capture — should see firm name box again (not port screen, not start choice)**

  Expected: centered box with "Taipan," / "What will you name your" / "Firm: _____________________"

- [ ] **Step 12: Type new name and complete the flow**

  Type `W`, `U`, then `Return`, then `Two` (guns start this time).

- [ ] **Step 13: Screen capture — should see port screen with guns=5, cash=0**

- [ ] **Step 14: Verify state via execute_luau**

  ```lua
  local Remotes = require(game:GetService("ReplicatedStorage").Remotes)
  local state = nil
  Remotes.StateUpdate.OnClientEvent:Connect(function(s) state = s end)
  Remotes.RequestStateUpdate:FireServer()
  task.wait(0.3)
  return "firmName=" .. tostring(state and state.firmName)
    .. " startChoice=" .. tostring(state and state.startChoice)
    .. " guns=" .. tostring(state and state.guns)
  ```

  Expected: `firmName=WU startChoice=guns guns=5`

- [ ] **Step 15: Stop Play mode**

  `mcp__Roblox_Studio__start_stop_play(false)`

---

## Task 6: MCP Playtest — Modern UI restart flow

Verify the full Modern UI restart-to-firm-name flow.

- [ ] **Step 1: Start Play mode**

- [ ] **Step 2: Screen capture — InterfacePicker visible**

- [ ] **Step 3: Click Modern button**

  Use `user_mouse_input` on the [M] Modern button (inspect via `search_game_tree` + `inspect_instance` to get coordinates if needed).

- [ ] **Step 4: Screen capture — should see StartPanel (FIRM / SHIP buttons) with firm name TextBox above**

- [ ] **Step 5: Type firm name "Matheson" in the TextBox, click FIRM button**

- [ ] **Step 6: Screen capture — should see Modern port panels (Hong Kong)**

- [ ] **Step 7: Force game-over**

  ```lua
  local Remotes = require(game:GetService("ReplicatedStorage").Remotes)
  Remotes.QuitGame:FireServer()
  ```

- [ ] **Step 8: Screen capture — should see GameOverPanel**

- [ ] **Step 9: Click RESTART button on GameOverPanel**

- [ ] **Step 10: Screen capture — should see StartPanel again (firm name TextBox visible, "Matheson" pre-filled, FIRM/SHIP buttons active)**

- [ ] **Step 11: Clear name box, type "Dent", click SHIP button**

- [ ] **Step 12: Screen capture — should see Modern port panels (guns=5, cash=0)**

- [ ] **Step 13: Verify state**

  ```lua
  local Remotes = require(game:GetService("ReplicatedStorage").Remotes)
  local state = nil
  Remotes.StateUpdate.OnClientEvent:Connect(function(s) state = s end)
  Remotes.RequestStateUpdate:FireServer()
  task.wait(0.3)
  return "firmName=" .. tostring(state and state.firmName)
    .. " guns=" .. tostring(state and state.guns)
  ```

  Expected: `firmName=Dent guns=5`

- [ ] **Step 14: Stop Play mode**

---

## Task 7: Final commit

- [ ] **Step 1: Confirm all four files are committed**

  ```bash
  git log --oneline -6
  ```

  Should show four feature commits from Tasks 1–4 plus the spec/plan commits.

- [ ] **Step 2: Done ✓**
