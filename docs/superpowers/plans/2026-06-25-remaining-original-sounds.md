# Remaining Original-Game Sounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the four remaining original Apple II sounds — Wu enforcers (underattack), bankruptcy accept (badjoss), bankruptcy decline→game-over (underattack), and empty firm name (badjoss) — faithfully to the original game.

**Architecture:** Three are server-flow events: each handler in `GameService.server.luau` builds a `makeCompradorNotif` entry with `.sound` and pushes it via the `state.pendingMessages = pending; pushState; state.pendingMessages = nil` pattern, which the Apple II `playNextNotif` path already plays. The fourth (empty firm name) is a same-scene re-prompt, so it uses an explicit `playSound(name)` callback threaded into `PromptEngine.processState` → `sceneFirmName`.

**Tech Stack:** Roblox Luau. Server (`GameService.server.luau`) + Apple II client modules. Reuses existing `badjoss`/`underattack` assets in `sync/ReplicatedStorage/Sounds.luau`. No new assets.

**Spec:** `docs/superpowers/specs/2026-06-25-remaining-original-sounds-design.md`

**Testing note:** No pure-logic (`shared/`) modules change, so there is no applicable TestEZ unit test (that suite covers `shared/` only and runs in Studio Run mode). Verification is manual via the Studio MCP tools; per project guidance, **audio confirmation is the user's responsibility** (screen capture is silent). The implementer drives the UI to each event and confirms the message renders; the user confirms the sound.

**Helper reference:** `makeCompradorNotif(lines, duration)` (`GameService.server.luau:46`) builds a "Comprador's Report" pending-messages entry from an array of plain strings. Setting `entry.sound = "<name>"` makes `playNextNotif` play it.

---

## File Structure

- **Modify:** `sync/ServerScriptService/GameService.server.luau` — gaps A, B, C: three independent remote handlers (`LeaveWu`, `AcceptBankruptcyLoan`, `DeclineBankruptcyLoan`), each gaining a sounded comprador notif pushed via `pendingMessages`.
- **Modify:** `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` — gap D: `processState` gains a 6th `playSound` param, forwarded to `sceneFirmName`, which blocks empty input and plays `badjoss`.
- **Modify:** `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` — gap D: define a `playSound` closure and pass it as the 6th argument to `processState`.

---

## Task 1: Gap A — Wu enforcers sound

The `LeaveWu` handler currently fires only `Remotes.Notify` (which the Apple II interface ignores), so the event is silent and invisible there. Route it through `pendingMessages` with the faithful "bodyguards killed" text and the `underattack` sound. The bodyguard count is pure flavour (`rand1to3` in the original), computed locally — no `FinanceEngine` change.

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau:487-497`

- [ ] **Step 1: Replace the LeaveWu handler body**

Change:
```lua
Remotes.LeaveWu.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.inWuSession then return end
  state.inWuSession = false
  if FinanceEngine.wuEnforcers(state) then
    Remotes.Notify:FireClient(player, "WU'S MEN beat you and take all your cash!")
  end
  pushState(player)
end)
```
to:
```lua
Remotes.LeaveWu.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.inWuSession then return end
  state.inWuSession = false
  local pending = {}
  if FinanceEngine.wuEnforcers(state) then
    Remotes.Notify:FireClient(player, "WU'S MEN beat you and take all your cash!")
    local braves = math.random(1, 3)
    local entry = makeCompradorNotif({
      string.format("Bad joss!!  %d of your bodyguards have", braves),
      "been killed by cutthroats and you have",
      "been robbed of all of your cash, Taipan!",
    }, 7)
    entry.sound = "underattack"
    table.insert(pending, entry)
  end
  state.pendingMessages = pending
  pushState(player)
  state.pendingMessages = nil
end)
```

- [ ] **Step 2: Sanity-check syntax**

Run: `git diff --stat sync/ServerScriptService/GameService.server.luau`
Expected: shows the one file changed. Confirm the `pending` table is always assigned (empty when no enforcers — harmless, `adapter.update` iterates an empty table).

- [ ] **Step 3: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "Sound Wu enforcer event (underattack) via pendingMessages

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Gap B — Bankruptcy accept sound

When the player accepts Wu's emergency loan, the original shows "Very well, Taipan. Good joss!!" with `bad_joss`. The handler currently pushes state with no notification.

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau:1099-1108`

- [ ] **Step 1: Add the sounded notif to AcceptBankruptcyLoan**

Change:
```lua
Remotes.AcceptBankruptcyLoan.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if not state.bankruptcyPending then return end
  local offer = state.bankruptcyPending
  state.bankruptcyPending = nil
  state.cash = state.cash + offer.loan
  state.debt = state.debt + offer.repay
  pushState(player)
end)
```
to:
```lua
Remotes.AcceptBankruptcyLoan.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if not state.bankruptcyPending then return end
  local offer = state.bankruptcyPending
  state.bankruptcyPending = nil
  state.cash = state.cash + offer.loan
  state.debt = state.debt + offer.repay
  local entry = makeCompradorNotif({
    "Very well, Taipan.",
    "Good joss!!",
  }, 5)
  entry.sound = "badjoss"
  state.pendingMessages = { entry }
  pushState(player)
  state.pendingMessages = nil
end)
```

- [ ] **Step 2: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "Sound bankruptcy-accept (badjoss) with faithful good-joss line

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Gap C — Bankruptcy decline / game-over sound

Declining the loan ends the game. The original shows "Very well, Taipan, the game is over!" with `under_attack`. `Apple2Interface.adapter.update` drains `pendingMessages` and plays notifications *before* rendering the main scene (`Apple2Interface.luau:456-461, 490-492`), so the notif plays before the game-over screen — the same flow the combat-sink game-over uses.

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau:1110-1117`

- [ ] **Step 1: Add the sounded notif to DeclineBankruptcyLoan**

Change:
```lua
Remotes.DeclineBankruptcyLoan.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if not state.bankruptcyPending then return end
  state.bankruptcyPending = nil
  setGameOver(state, "quit")
  pushState(player)
end)
```
to:
```lua
Remotes.DeclineBankruptcyLoan.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if not state.bankruptcyPending then return end
  state.bankruptcyPending = nil
  setGameOver(state, "quit")
  local entry = makeCompradorNotif({
    "Very well, Taipan,",
    "the game is over!",
  }, 5)
  entry.sound = "underattack"
  state.pendingMessages = { entry }
  pushState(player)
  state.pendingMessages = nil
end)
```

- [ ] **Step 2: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "Sound bankruptcy-decline game-over (underattack)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Gap D — Empty firm name sound + block

Empty firm-name submission re-prompts the same scene, so the scene-entry sound mechanism can't catch it. Thread an explicit `playSound` callback through `processState` to `sceneFirmName`, which blocks empty input and plays `badjoss`. Three edits across two files.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (`processState` signature `:1493`, firm dispatch `:1606`, `sceneFirmName` `:464`)
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` (define + pass `playSound`, `:83` and `:294`)

- [ ] **Step 1: Add the `playSound` parameter to `processState`**

In `PromptEngine.luau`, change:
```lua
function PromptEngine.processState(state, localScene, actions, localSceneCb, combatSelection)
```
to:
```lua
function PromptEngine.processState(state, localScene, actions, localSceneCb, combatSelection, playSound)
```

- [ ] **Step 2: Forward `playSound` to `sceneFirmName` at the dispatch site**

In `PromptEngine.luau` (around line 1606), change:
```lua
    return sceneFirmName(state, actions, localSceneCb)
```
to:
```lua
    return sceneFirmName(state, actions, localSceneCb, playSound)
```

- [ ] **Step 3: Block empty input and play the sound in `sceneFirmName`**

In `PromptEngine.luau`, change the function signature and `onType` (around lines 464, 484-488):
```lua
local function sceneFirmName(_state, actions, localSceneCb)
```
to:
```lua
local function sceneFirmName(_state, actions, localSceneCb, playSound)
```
and change:
```lua
    onType = function(text, _s, _a)
      actions.setFirmName(text)
      if localSceneCb then localSceneCb("start_choice") end
      return nil
    end,
```
to:
```lua
    onType = function(text, _s, _a)
      if (text or ""):match("^%s*$") then
        -- Empty / whitespace-only name: re-prompt in place with bad joss,
        -- faithful to the original (taipan.c:758-762 plays bad_joss_sound()).
        if playSound then playSound("badjoss") end
        return nil
      end
      actions.setFirmName(text)
      if localSceneCb then localSceneCb("start_choice") end
      return nil
    end,
```

- [ ] **Step 4: Define the `playSound` closure in Apple2Interface**

In `Apple2Interface.luau`, find (around line 83, added by prior sound work):
```lua
  local lastSoundedScene = nil  -- localScene value whose sound we last played; dedups re-renders
  local GREEN      = Color3.fromRGB(140, 200, 80)
```
Change to:
```lua
  local lastSoundedScene = nil  -- localScene value whose sound we last played; dedups re-renders
  local function playSound(name)  -- explicit one-shot local sound (same-scene re-prompts)
    task.spawn(function() SoundPlayer.play(name) end)  -- play() blocks; must spawn
  end
  local GREEN      = Color3.fromRGB(140, 200, 80)
```

- [ ] **Step 5: Pass `playSound` as the 6th argument to `processState`**

In `Apple2Interface.luau`, the `processState` call (starting line 294) ends with the combat-selection table then a closing `)`. Change:
```lua
      {
        current = queuedCommand,
        set = function(newAction)
          queuedCommand = newAction
          render(lastState, localScene)
        end,
      }
    )
```
to:
```lua
      {
        current = queuedCommand,
        set = function(newAction)
          queuedCommand = newAction
          render(lastState, localScene)
        end,
      },
      playSound
    )
```

- [ ] **Step 6: Verify scope and syntax**

Read the edited `processState` call in `Apple2Interface.luau` and confirm `playSound` is defined (Step 4) above its use (Step 5) within the same `Apple2Interface.new` closure, and that `SoundPlayer` is in scope (required at line 13). Confirm `processState`'s 5th argument (the combat-selection table) is unchanged and `playSound` is strictly the 6th.

- [ ] **Step 7: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau
git commit -m "Block empty firm name and play badjoss (playSound callback)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Manual verification of all four gaps

No automated test applies (see Testing note). Drive each event in the Apple II interface via the Studio MCP tools, confirm the message renders, and have the user confirm the sound.

**Setup:** `start_stop_play(true)`, select the Apple II interface, choose a start, reach the relevant state.

- [ ] **Step 1: Drive each trigger and screen-capture the result**

| # | How to trigger | Expected message | Sound |
|---|---|---|---|
| D | At firm-name entry, press Enter with the name blank | Re-prompts in place (no advance) | badjoss |
| A | Owe Wu a large debt (`debt > 20000`), have cash, leave the Wu session; repeat until the 1-in-5 enforcer event fires | "Bad joss!! N of your bodyguards have been killed by cutthroats and you have been robbed of all of your cash, Taipan!" | underattack |
| B | Reach bankruptcy (debt overwhelming, low cash) so Wu offers an emergency loan; accept it | "Very well, Taipan. Good joss!!" | badjoss |
| C | Same bankruptcy offer; decline it | "Very well, Taipan, the game is over!" then game-over screen | underattack |

For A/B/C, the message must now appear **in the Apple II interface** (previously A showed nothing there). For testing convenience, the enforcer odds/threshold and bankruptcy state can be forced by firing the relevant remotes with a constructed state, or by adjusting debt/cash via normal play.

- [ ] **Step 2: Exit play mode**

`start_stop_play(false)`.

- [ ] **Step 3: Ask the user to confirm audio**

Explicitly ask the user to confirm each of the four sounds played, since audio cannot be verified from screen capture.

---

## Self-Review Notes

- **Spec coverage:** Task 1 = gap A, Task 2 = gap B, Task 3 = gap C, Task 4 = gap D (all three edits: `processState` param, dispatch forward, `sceneFirmName` block+sound, plus the Apple2Interface closure + 6th arg). Task 5 covers the spec's manual-testing section. The spec's out-of-scope items (buy/sell over-limit; already-shipped "you only have X") have no task, as intended.
- **Message text** matches the spec/`taipan.c` citations: A "bodyguards… cutthroats… all of your cash" (underattack), B "Very well, Taipan. / Good joss!!" (badjoss), C "Very well, Taipan, / the game is over!" (underattack).
- **Type consistency:** `playSound(name)` signature is identical in PromptEngine's param, the dispatch call, `sceneFirmName`'s param, and the Apple2Interface closure. `makeCompradorNotif(lines, duration)` then `entry.sound = "<name>"` is used uniformly for A/B/C. The `pendingMessages` push/clear pattern is identical across the three handlers.
