# Design: Wu Borrow Over-Limit Error

**Date:** 2026-04-11
**Status:** Approved

## Summary

When the player is in the Wu borrow scene (Apple2 interface) and enters an amount exceeding the maximum Wu will lend (2× current cash), show the error message "He won't loan you so much, Taipan!" on row 22, then auto-return to the borrow prompt after 5 seconds (interruptible by any keypress).

## Background

The bank already has this pattern: `sceneBankDepositErr` and `sceneBankWithdrawErr` each display an error on rows 21–22, auto-advance after 5 seconds, and return to the parent scene on keypress. This feature applies the same pattern to Wu borrowing.

## Change

**File:** `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`

### 1. New `sceneWuBorrowErr` function

Add after `sceneWuBorrow` (around line 944):

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

Row layout:
- Row 19: "How much do you wish to"
- Row 20: "borrow?"
- Row 21: (blank)
- Row 22: "He won't loan you so much, Taipan!"

### 2. Validation in `sceneWuBorrow` `onType`

Before calling `actions.wuBorrow`, check if `amt > 2 * state.cash`. If so, transition to `"wu_borrow_err"` and return early:

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
  if (state.debt or 0) > 0 or amt > 0 then
    if localSceneCb then localSceneCb("wu_repay") end
  else
    actions.leaveWu()
    if localSceneCb then localSceneCb(nil) end
  end
  return nil
end,
```

### 3. Route `"wu_borrow_err"` in `processState`

Inside the `state.inWuSession` block (around line 1443), add before the existing `wu_repay` check:

```lua
if state.currentPort == HONG_KONG and state.inWuSession then
  if localScene == "wu_borrow_err" then return sceneWuBorrowErr(state, actions, localSceneCb) end
  if localScene == "wu_repay" then return sceneWuRepay(state, actions, localSceneCb) end
  return sceneWuBorrow(state, actions, localSceneCb)
end
```

## Scope

- Apple2 interface only (`PromptEngine.luau`).
- No server changes. The server's `FinanceEngine.borrow()` still validates server-side; this adds client-side feedback.
- No new remotes, no state changes.
