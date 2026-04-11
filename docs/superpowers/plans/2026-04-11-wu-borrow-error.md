# Wu Borrow Over-Limit Error Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show "He won't loan you so much, Taipan!" on row 22 when the player tries to borrow more than Wu will lend (2× current cash), with a 5-second auto-advance back to the borrow prompt (interruptible by keypress).

**Architecture:** Pure client-side change to `PromptEngine.luau`. Add a `sceneWuBorrowErr` error scene (following the identical pattern of `sceneBankDepositErr`), add an over-limit check in `sceneWuBorrow`'s `onType`, and wire the new scene into `processState`. No server changes.

**Tech Stack:** Luau, Roblox Apple2 terminal interface (PromptEngine scene system)

---

### Task 1: Add `sceneWuBorrowErr` and wire it up

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`

**Background:** `sceneWuLayout(state, bodyLines)` builds rows 1–16 from the port status display, then places each entry in `bodyLines` starting at row 19. Three body lines → rows 19, 20, 21. Four body lines → rows 19, 20, 21, 22.

The existing `sceneBankDepositErr` (around line 1149) is the pattern to follow: shows an error, uses `_autoAdvance = { 5, "parent_scene" }`, and returns to the parent scene on any keypress.

The `processState` routing for `inWuSession` is at lines 1443–1446:
```lua
if state.currentPort == HONG_KONG and state.inWuSession then
  if localScene == "wu_repay" then return sceneWuRepay(state, actions, localSceneCb) end
  return sceneWuBorrow(state, actions, localSceneCb)
end
```

The `sceneWuBorrow` function is at lines 919–944:
```lua
local function sceneWuBorrow(state, actions, localSceneCb)
  local bodyLines = {
    { text = "How much do you wish to", color = AMBER },
  }
  return sceneWuLayout(state, bodyLines), {
    type            = "numeric",
    typePlaceholder = "borrow? ",
    _inputRow       = 20,
    _buildInputRow  = function(s) return { text = "borrow? " .. s, color = AMBER } end,
    maxDigits       = 9,
    onType = function(text, _s, _a)
      local amt = tonumber(text) or 0
      if amt > 0 then
        actions.wuBorrow(math.floor(amt))
      end
      -- Transition to repay scene if they have debt or just borrowed
      if (state.debt or 0) > 0 or amt > 0 then
        if localSceneCb then localSceneCb("wu_repay") end
      else
        actions.leaveWu()
        if localSceneCb then localSceneCb(nil) end
      end
      return nil
    end,
  }
end
```

- [ ] **Step 1: Add `sceneWuBorrowErr` after `sceneWuBorrow` (after line 944)**

Insert this new function between `sceneWuBorrow` and `sceneWuRepay` (i.e. after line 944, before line 946):

```lua
local function sceneWuBorrowErr(state, _actions, localSceneCb)
  return sceneWuLayout(state, {
    { text = "How much do you wish to",             color = AMBER },
    { text = "borrow?",                             color = AMBER },
    { text = "",                                    color = AMBER },
    { text = "He won't loan you so much, Taipan!", color = GREEN },
  }), {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "wu_borrow" },
    onKey        = function() if localSceneCb then localSceneCb("wu_borrow") end end,
  }
end
```

Row layout produced:
- Row 19: "How much do you wish to"
- Row 20: "borrow?"
- Row 21: (blank)
- Row 22: "He won't loan you so much, Taipan!"

- [ ] **Step 2: Add over-limit check to `sceneWuBorrow`'s `onType` (lines 929–942)**

Replace the entire `onType` body in `sceneWuBorrow` so it reads:

```lua
    onType = function(text, _s, _a)
      local amt = tonumber(text) or 0
      if amt > 0 and amt > 2 * (state.cash or 0) then
        if localSceneCb then localSceneCb("wu_borrow_err") end
        return nil
      end
      if amt > 0 then
        actions.wuBorrow(math.floor(amt))
      end
      -- Transition to repay scene if they have debt or just borrowed
      if (state.debt or 0) > 0 or amt > 0 then
        if localSceneCb then localSceneCb("wu_repay") end
      else
        actions.leaveWu()
        if localSceneCb then localSceneCb(nil) end
      end
      return nil
    end,
```

- [ ] **Step 3: Wire `"wu_borrow_err"` into `processState` (lines 1443–1446)**

Replace the `inWuSession` routing block so it reads:

```lua
  if state.currentPort == HONG_KONG and state.inWuSession then
    if localScene == "wu_borrow_err" then return sceneWuBorrowErr(state, actions, localSceneCb) end
    if localScene == "wu_repay" then return sceneWuRepay(state, actions, localSceneCb) end
    return sceneWuBorrow(state, actions, localSceneCb)
  end
```

- [ ] **Step 4: Manually verify in Roblox Studio (Apple2 interface)**

Tests for PromptEngine run inside Roblox Studio (TestEZ). There is a spec file at `sync/ServerScriptService/Tests/PromptEngine/spec.luau` — check whether it exists and if it covers `sceneWuBorrow`; if not, skip automated testing (this feature is UI-only and cannot be unit tested without a running Roblox instance).

Manual verification:
1. Open Roblox Studio, click **Run** (not Play).
2. Select Apple2 interface, start a new game.
3. Answer **Y** to Wu question.
4. At the borrow prompt, type an amount greater than 2× your starting cash (e.g. if cash=400, type `900`) and press Enter.
5. Confirm row 22 shows "He won't loan you so much, Taipan!" in green.
6. Confirm the screen auto-returns to the borrow prompt after 5 seconds.
7. Repeat step 4, this time press any key during the 5-second wait — confirm it returns immediately.
8. Confirm that a valid borrow amount (e.g. `200` with cash=400) still works normally and transitions to the repay scene.

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "feat: show error when Wu borrow amount exceeds limit

Display 'He won't loan you so much, Taipan!' on row 22 when the
player enters more than 2x cash in the Wu borrow scene. Auto-returns
to borrow prompt after 5s (interruptible by keypress)."
```
