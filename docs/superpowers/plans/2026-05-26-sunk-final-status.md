# Sunk → Final Status Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the player's ship is sunk, show a combat seaworthiness readout at 0%, then the existing "buggers got us" status screen, then route to the retirement-style final-status / rating screen instead of the bare GAME OVER screen.

**Architecture:** Two edits. (1) Server `applyEnemyFire` inserts one extra combat-style notif (row 4 = "Current seaworthiness: Critical (0%)") before the existing buggers notif. (2) Client `PromptEngine.processState` routes `gameOverReason == "sunk"` to `sceneFinalStatus` (skipping `sceneMillionaire`). All sink paths (combat + storm) already set `gameOverReason == "sunk"` and compute `finalScore`/`finalRating` via `setGameOver`, so the routing change covers both.

**Tech Stack:** Roblox Luau, TestEZ (run in Studio Run mode), Azul sync.

---

## File Structure

- `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` — client scene router; add `"sunk"` routing in `processState`. (Pure-ish: returns rows/promptDef, no Roblox service mutation, testable via TestEZ.)
- `sync/ServerScriptService/Tests/PromptEngine/spec.luau` — add a test asserting `"sunk"` routes to the final-status layout.
- `sync/ServerScriptService/GameService.server.luau` — server; insert the seaworthiness notif in `applyEnemyFire`'s sunk branch. (Not unit-tested — it calls Roblox remotes; verified via MCP playtest.)

The client routing change is implemented first (TDD with a TestEZ test, since `PromptEngine` is testable). The server notif insertion is second (verified by playtest, no unit test).

---

## Task 1: Route sunk → final status screen (client)

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (the `gameOver` block in `PromptEngine.processState`, ~line 1486)
- Test: `sync/ServerScriptService/Tests/PromptEngine/spec.luau`

- [ ] **Step 1: Write the failing test**

Add this `describe` block inside the top-level `return function() ... end` in `sync/ServerScriptService/Tests/PromptEngine/spec.luau`, immediately after the existing `describe("PromptEngine retirement flow", ...)` block (before `describe("PromptEngine sceneBank sequential", ...)`):

```lua
  describe("PromptEngine sunk flow", function()
    local function sunkState(score)
      return {
        gameOver = true, gameOverReason = "sunk",
        finalScore = score, finalRating = "Galley Hand",
        cash = 0, debt = 5000, bankBalance = 0,
        shipCapacity = 60, guns = 0, turnsElapsed = 4,
        month = 5, year = 1860,
        shipCargo = {0,0,0,0},
        warehouseCargo = {0,0,0,0}, warehouseUsed = 0,
        holdSpace = 60, currentPort = 1, damage = 60,
      }
    end

    it("sunk: routes straight to final status (inverted score row 9, Y/N keys)", function()
      -- No localScene: sunk must NOT show the millionaire screen; it goes
      -- directly to the final-status / rating layout.
      local lines, promptDef = PromptEngine.processState(
        sunkState(42), nil, mockActions(), function() end)
      expect(lines.rows).to.be.ok()
      -- Row 9 carries the inverted "Your score is N." segment (final-status marker)
      local r9 = lines.rows[9]
      expect(r9).to.be.ok()
      local hasInverted = false
      if r9.segments then
        for _, seg in ipairs(r9.segments) do
          if seg.inverted then hasInverted = true end
        end
      end
      expect(hasInverted).to.equal(true)
      -- Final-status prompt offers Y/N (Play again?)
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["Y"]).to.equal(true)
      expect(keySet["N"]).to.equal(true)
    end)
  end)
```

- [ ] **Step 2: Run the test to verify it fails**

In Roblox Studio, click **Run** (not Play). `TestRunner.server.luau` auto-discovers and runs all specs; read the Output panel.
Expected: FAIL. The current `processState` routes `"sunk"` to `sceneGameOver`, whose rows do not have an inverted segment on row 9 and whose prompt keys are `{"R"}` — so both the `hasInverted` and the `Y`/`N` key assertions fail.

(If you cannot drive Studio yourself, ask the user to click Run and paste the Output. Do not skip verifying the failure.)

- [ ] **Step 3: Add the sunk routing branch**

In `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`, find the `gameOver` block at the top of `PromptEngine.processState` (~line 1486):

```lua
  if state.gameOver then
    if state.gameOverReason == "retired" then
      if localScene == "final_status" then
        return sceneFinalStatus(state, actions, localSceneCb)
      end
      return sceneMillionaire(state, actions, localSceneCb)
    end
    return sceneGameOver(state, actions, localSceneCb)
  end
```

Replace it with:

```lua
  if state.gameOver then
    if state.gameOverReason == "retired" then
      if localScene == "final_status" then
        return sceneFinalStatus(state, actions, localSceneCb)
      end
      return sceneMillionaire(state, actions, localSceneCb)
    elseif state.gameOverReason == "sunk" then
      -- Faithful to the original (taipan.c:2567 combat, :2602 storm): after the
      -- "buggers got us" status screen, sinking goes straight to final_stats().
      -- Skip sceneMillionaire (that screen is retirement-only).
      return sceneFinalStatus(state, actions, localSceneCb)
    end
    return sceneGameOver(state, actions, localSceneCb)  -- "quit"
  end
```

- [ ] **Step 4: Run the test to verify it passes**

In Studio, click **Run** again and read the Output panel.
Expected: PASS — the new "sunk flow" test passes, and all pre-existing PromptEngine tests still pass (the retirement and combat-layout tests are unaffected).

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau sync/ServerScriptService/Tests/PromptEngine/spec.luau
git commit -m "Route sunk game-over to final-status screen"
```

Commit message footer (append to the commit):

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

---

## Task 2: Show "Critical (0%)" seaworthiness before the buggers message (server)

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau` (`applyEnemyFire`, sunk branch, ~line 703)

No unit test: this code fires Roblox remotes and is verified by MCP playtest in Task 3.

- [ ] **Step 1: Insert the seaworthiness notif in the sunk branch**

In `sync/ServerScriptService/GameService.server.luau`, find the sunk branch inside `applyEnemyFire` (~line 703):

```lua
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    local entry = makeStatusScreenLowerNotif(
      "", { "The buggers got us, Taipan!!", "It's all over, now!!!" }, 5)
    entry.sound = "badjoss"
    table.insert(pending, entry)
    setGameOver(state, "sunk")
    return true
  end
```

Replace it with (adds the seaworthiness notif *before* the buggers notif):

```lua
  if fireResult.sunk then
    -- Standard combat seaworthiness readout at 0%, shown on row 4 the way a
    -- non-fatal hit would after the layout redraws. A sunk ship is always 0%
    -- seaworthy, so the label is always "Critical (0%)" (matches the combat
    -- layout's row 4). No sound; ~2s so the player registers it before the
    -- "buggers got us" status screen.
    local swEntry = { rows = { [4] = { segments = {
      { text = "Current seaworthiness: ", color = AMBER_S },
      { text = "Critical (0%)",           color = AMBER_S, inverted = true },
    }}}, duration = 2 }
    table.insert(pending, swEntry)

    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    local entry = makeStatusScreenLowerNotif(
      "", { "The buggers got us, Taipan!!", "It's all over, now!!!" }, 5)
    entry.sound = "badjoss"
    table.insert(pending, entry)
    setGameOver(state, "sunk")
    return true
  end
```

- [ ] **Step 2: Verify Azul synced the change to Studio**

After saving, confirm the local file and the Studio copy of `GameService` match (per the project's update-script workflow: check sizes match, difference of 1 allowed). The Azul sync is automatic; just confirm it propagated before playtesting.

- [ ] **Step 3: MCP playtest the combat-sink sequence**

Drive the game to a sinking via the Apple II interface. Recommended fast path: start a game, then fire `RequestStateUpdate` / use `execute_luau` only for inspection — but to force a sink reliably you may set up a combat and repeatedly Run while taking enemy fire. Observe via `screen_capture` that the sequence is:

1. "We've been hit, Taipan!!" on the combat view (row 4).
2. "Current seaworthiness: Critical (0%)" on the combat view (row 4), ~2s.
3. Status screen redraw + "The buggers got us, Taipan!! / It's all over, now!!!".
4. Final-status / rating screen with "Play again?" (Y/N).

Expected: all four steps appear in order; step 2 is the newly added one. The user verifies visuals and audio (per project convention — do not rely on screen capture for sound).

- [ ] **Step 4: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "Show Critical (0%) seaworthiness before sunk status screen"
```

Commit message footer (append to the commit):

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

---

## Self-Review Notes

- **Spec coverage:**
  - Combat sink step 2 (seaworthiness "Critical (0%)") → Task 2.
  - Combat sink step 4 / storm sink step 2 (route to `sceneFinalStatus`) → Task 1 (covers both, since both set `gameOverReason == "sunk"`).
  - Existing steps (hit message, buggers status screen, `setGameOver` computing score/rating) → unchanged, no task needed.
  - Out-of-scope items (`"quit"` path, dead-branch cleanup) → intentionally not implemented.
  - Testing requirement (PromptEngine spec for sunk routing) → Task 1; MCP playtest → Task 2 Step 3.
- **Placeholder scan:** none — all code blocks are complete and concrete.
- **Type consistency:** `AMBER_S` is the existing server color constant (`GameService.server.luau:21`). Notif entries use the established `{ rows = {...}, duration = N }` shape with optional `.sound`; row segments use `{ text, color, inverted }` matching `sceneCombatLayout`'s row 4 and the status-screen segment rows. `processState` signature `(state, localScene, actions, localSceneCb, combatSelection)` is unchanged.
