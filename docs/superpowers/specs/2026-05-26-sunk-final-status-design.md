# Sunk → Final Status Flow — Design

**Date:** 2026-05-26
**Status:** Approved
**Scope:** Apple II interface only

## Problem

When the player's ship is sunk, the game currently ends on a bare **GAME OVER**
screen ("Your ship was sunk, Taipan! / (R)estart"). The original game instead
shows the full final-status / rating screen (`final_stats()` in the C port). Two
sink paths exist:

- **Combat sink** — enemy fire destroys the ship (`applyEnemyFire`).
- **Storm sink** — a storm sends the ship down (`postCombatStorm`).

The C source confirms both call `final_stats()` then return
(`taipan.c:2567` combat, `taipan.c:2602` storm).

Additionally, on a fatal combat hit the player never sees the seaworthiness drop
to 0%: the "We've been hit" message overwrites the combat seaworthiness line
(row 4), and combat ends before the combat layout would normally redraw that
line. For a non-fatal hit the layout redraws and the updated seaworthiness is
visible; the fatal hit skips it.

## Desired Behavior

### Combat sink sequence
1. `"We've been hit, Taipan!!"` — combat view, row 4 *(existing)*
2. **NEW:** `"Current seaworthiness: Critical (0%)"` — combat view, row 4, with
   the `Critical (0%)` portion inverted; ~2s; no sound. This is the standard
   combat seaworthiness readout (matches `sceneCombatLayout` row 4), shown
   explicitly because combat ends before the layout would redraw it.
3. Status screen redraw + `"The buggers got us, Taipan!! / It's all over,
   now!!!"` — 5s, `badjoss` sound *(existing `makeStatusScreenLowerNotif`)*
4. **NEW:** `sceneFinalStatus` (net cash, ship size, years traded, score,
   rating box, "Play again? Y/N") instead of the bare GAME OVER screen.

### Storm sink sequence
1. `"We're going down!!"` — Captain's Report *(existing)*
2. **NEW:** `sceneFinalStatus` instead of the bare GAME OVER screen.

## Changes

### 1. Server — `GameService.server.luau`, `applyEnemyFire` sunk branch (~line 703)

Before the existing buggers status-screen notif, insert a combat-style notif
that paints row 4 with the seaworthiness readout:

```
rows[4] = { segments = {
  { text = "Current seaworthiness: ", color = AMBER_S },
  { text = "Critical (0%)",           color = AMBER_S, inverted = true },
}}
duration = 2   -- tunable; matches the "We've been hit" notif rhythm
-- no sound
```

A sunk ship is always 0% seaworthy, so the label is always `"Critical (0%)"` —
no threshold logic is duplicated server-side. Build this inline or via a small
helper alongside the other `make*Notif` functions.

The new notif inherits the same on-screen context as the existing "We've been
hit" combat notif (rows 1–3 and the enemy ship grid remain from the prior
combat render; only row 4 changes), so it introduces no new visual risk.

### 2. Client — `PromptEngine.luau`, `processState` (~line 1486)

Route the sunk case to the final-status screen, skipping `sceneMillionaire`:

```lua
if state.gameOver then
  if state.gameOverReason == "retired" then
    if localScene == "final_status" then
      return sceneFinalStatus(state, actions, localSceneCb)
    end
    return sceneMillionaire(state, actions, localSceneCb)
  elseif state.gameOverReason == "sunk" then
    return sceneFinalStatus(state, actions, localSceneCb)
  end
  return sceneGameOver(state, actions, localSceneCb)  -- "quit"
end
```

This makes the transition automatic: after the buggers notif drains,
`advanceNotif` finds an empty queue and re-renders `lastState`, which now
returns `sceneFinalStatus`. The "short delay" before the end screen is the
existing 5s buggers notif.

## Already Handled (no change)

- `setGameOver` already computes `finalScore` / `finalRating` for every reason,
  including `"sunk"`.
- `sceneFinalStatus` already exists; its "Play again? Y/N" prompt maps to
  `restartGame` / `quitGame`.

## Out of Scope

- The `"quit"` path is unchanged — it continues to use `sceneGameOver`.
- After this change, `sceneGameOver`'s `"sunk"` branch (and the already-dead
  `"retired"` branch) become unreachable. Optional minor cleanup; not required.

## Testing

- Adjust `sync/ServerScriptService/Tests/PromptEngine/spec.luau` to assert that
  a `gameOver` + `gameOverReason == "sunk"` state routes `processState` to the
  `sceneFinalStatus` rows (final status / rating layout), not the bare GAME OVER
  screen.
- MCP playtest the combat-sink sequence end-to-end (steps 1–4) and the
  storm-sink sequence; the user verifies visuals and audio per project
  convention.
