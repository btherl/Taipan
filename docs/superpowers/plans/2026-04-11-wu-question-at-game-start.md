# Wu Question at Game Start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set `state.wuPending = true` when a new game begins so the Apple2 interface asks the Wu question at game start, matching the behavior already present on every Hong Kong arrival.

**Architecture:** Single server-side change in the `ChooseStart` handler. The entire Wu question flow (scene routing, prompt UI, ConfirmWu/DeclineWu handlers) is already implemented and works correctly on HK arrival via TravelTo. This plan adds the one missing trigger.

**Tech Stack:** Luau, Roblox ServerScriptService, TestEZ

---

### Task 1: Add `wuPending = true` to the ChooseStart handler

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau` (around line 120)

Context: The `ChooseStart` handler creates a fresh game state and pushes it to the client. `wuPending` is already set to `true` in the `TravelTo` handler (line 270) when arriving at Hong Kong. We need the same flag set at game start.

- [ ] **Step 1: Open the file and locate the insertion point**

Read `sync/ServerScriptService/GameService.server.luau` lines 94–122. The handler ends with:

```lua
  if pendingModes[player] then
    state.uiMode = pendingModes[player]
    pendingModes[player] = nil
  end
  playerStates[player] = state
  pushState(player)
end)
```

- [ ] **Step 2: Add `state.wuPending = true` before `playerStates[player] = state`**

The modified block should read:

```lua
  if pendingModes[player] then
    state.uiMode = pendingModes[player]
    pendingModes[player] = nil
  end
  state.wuPending = true
  playerStates[player] = state
  pushState(player)
end)
```

- [ ] **Step 3: Verify no test file changes are needed**

There is no unit-testable pure-logic module changed here — this is a server handler mutation. The existing `GameState.spec.luau` and other specs are unaffected. No new test file is required.

- [ ] **Step 4: Manually verify in Roblox Studio (Apple2 interface)**

1. Open Roblox Studio with the Taipan place and ensure Azul sync has picked up the file change.
2. Click **Run** (not Play) to enter Run mode.
3. Select the Apple2 interface.
4. Enter a firm name and press Return.
5. Select "F" (Firm/cash start) or "S" (Ship/guns start).
6. Confirm the terminal shows the Wu question: `"Do you have business with Elder Brother Wu, the moneylender?"` with Y/N prompt.
7. Press **Y** — confirm the Wu borrow scene appears.
8. Restart; repeat steps 3–6, press **N** — confirm normal port scene appears.

- [ ] **Step 5: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "feat: ask Wu question at game start

Set wuPending=true in ChooseStart handler so the Apple2 interface
shows the Elder Brother Wu prompt immediately after start selection,
matching the existing behaviour on every Hong Kong arrival."
```
