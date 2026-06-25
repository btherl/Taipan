# Design: Sound for Local (Client-Side) Events

**Date:** 2026-06-25
**Status:** Approved
**Scope:** Apple II interface only

## Problem

The game plays sound effects only for **server-driven** notifications. Every `entry.sound` assignment lives in `GameService.server.luau`; the sound flows server → `entry.sound` → `StateUpdate` → `Apple2Interface.playNextNotif()` → `SoundPlayer.play()`.

**Local scenes** — pure client-side UI rendered by `PromptEngine.luau` (validation rejections, "you're already here", etc.) — never play a sound, even though the original Apple II game did. This work wires sound into those local scenes.

## Source of Truth

The original game's sound-to-event mapping is documented in:
- `references/taipan-d3eacd0089da82292b4c4553463600fe229ee07c/sounds.h` (authoritative — instances confirmed by emulator playthrough are marked with `*`)
- `references/sounds/README.md`

The original had exactly **three** sounds — `bad_joss`, `good_joss`, `under_attack` — which are precisely the three assets we already have in `Sounds.luau` (`badjoss`, `goodjoss`, `underattack`). No new assets are required.

Per the original, **every local validation rejection played `good_joss`**. (Note: the original also played `good_joss` for the "you have only X in cash" buy/sell over-limit cases and `bad_joss` for an empty firm name, but those are out of scope — see Non-Goals.)

## Goals

Play the original sound for these local scenes. All map to `goodjoss`:

| Scene function | Trigger (`localScene`) | Original message |
|---|---|---|
| `sceneAlreadyHere` | `already_here` | "you're already here!" |
| `sceneBuyOverloadErr` | `buy_overload_err` | "ship overloaded" |
| `sceneWuBorrowErr` | `wu_borrow_err` | "won't loan you so much" |
| `sceneWuRepayErr` | `wu_repay_err` | "you have only X in cash" |
| `sceneBankDepositErr` | `bank_deposit_err` | "you have only X in cash" |
| `sceneBankWithdrawErr` | `bank_withdraw_err` | "you have only X in the bank" |
| `sceneWarehouseStepErr` | `wh_err_N` | "warehouse will only hold…" / "warehouse is full" |
| `sceneWarehouseNoCargo` | `warehouse` + no cargo on hand | "you have no cargo" |

All eight play `goodjoss`, faithful to the original.

## Non-Goals

These are explicitly **excluded** from this work:

- **`repair_amount_err`** (bad repair amount): a modern addition with no equivalent in the original game. No sound. We only add sounds the original had.
- **Buy/sell over-limit silent-clear** (`PromptEngine.luau:1127-1136`): when the player tries to buy more than they can afford or sell more than they hold, our implementation silently clears the input and re-renders the *same* scene — it shows no rejection message. The original played `good_joss` here, but since our implementation presents no distinct rejection scene, wiring it is deferred.
- **Empty firm name**: our `sceneFirmName.onType` (`PromptEngine.luau:484`) does not block an empty name — there is no rejection event to attach a sound to. (This was also the only sound in the original reconstructed from source rather than confirmed in the emulator.)
- **Server-driven notification sounds**: already handled via `entry.sound`; out of scope.
- **New sound assets / additional categories**: not needed.

## Architecture

### Why scenes declare their own sound (Approach A)

`sceneWarehouseNoCargo` is **not** reachable via a unique `localScene` string. It is a state-conditional branch under `localScene == "warehouse"` (`PromptEngine.luau:1549-1560`): the same `localScene` value renders either the normal warehouse menu (no sound) or the no-cargo error (sound), depending on whether the player holds cargo. An external "`localScene` string → sound" lookup table therefore **cannot** express it without also firing on the normal warehouse menu.

The scene function is the only place that authoritatively knows which scene it is. So each error scene **declares its own sound** on the result table it returns.

### Component changes

**`PromptEngine.luau`** — each of the eight error scene functions adds `sound = "goodjoss"` to the table it returns as its first value (the `lines`/result table, e.g. `return { rows = rows, sound = "goodjoss" }, promptDef`). This is the only change to PromptEngine: a one-line addition per scene. No change to scene logic, dispatch, or `promptDef`.

**`Apple2Interface.luau`** (`render`) — after `PromptEngine.processState` returns `lines, promptDef`:

1. Read `lines.sound`.
2. Maintain a `lastSoundedScene` variable (interface-level, alongside `localScene`).
3. If `lines.sound` is set **and** `localScene ~= lastSoundedScene`: play the sound and record `lastSoundedScene = localScene`.
4. Otherwise (no `lines.sound`): clear `lastSoundedScene = nil`.

`SoundPlayer.play` **blocks** (it polls in a `while` loop until the sound ends or a deadline), so it must be wrapped in `task.spawn` to avoid stalling render:

```lua
if lines.sound and localScene ~= lastSoundedScene then
  lastSoundedScene = localScene
  local soundName = lines.sound
  task.spawn(function() SoundPlayer.play(soundName) end)
elseif not lines.sound then
  lastSoundedScene = nil
end
```

(`SoundPlayer` is already required at `Apple2Interface.luau:13`.)

### Why the dedup guard is required

`render`/`processState` runs on **every** render, including re-renders triggered by keystrokes within a scene (amount entry, queued-command changes). Keying on `localScene` ensures the sound plays exactly **once per scene entry**:

- Re-renders keep the same `localScene`, so the `localScene ~= lastSoundedScene` check suppresses replays.
- The same error twice in a row (e.g. `bank_deposit_err` → dismiss to `bank` → trigger again) works because the intervening non-error scene clears `lastSoundedScene`, so the second entry plays again.
- The conditional `sceneWarehouseNoCargo` works because the sound comes from the scene result (set only when there is no cargo), not from the `localScene` string — the normal warehouse menu returns no `sound` and stays silent.

### Data flow

```
PromptEngine.processState
  └─ resolves scene, scene fn returns { rows=..., sound="goodjoss" }, promptDef
      └─ Apple2Interface.render reads lines.sound
          └─ if new scene entry: task.spawn(SoundPlayer.play("goodjoss"))
              └─ SoundPlayer clones Sound template, plays, destroys
```

This mirrors the existing server path's final step (`SoundPlayer.play`), just triggered locally from `render` instead of from `playNextNotif`.

## Error Handling

- Unknown sound name → `SoundPlayer.play` already `warn`s and returns without error.
- Overlapping sounds → `SoundPlayer.play` clones a fresh `Sound` per call, so overlap is harmless. In practice these local errors occur during interactive menus, not during notif playback, so no overlap is expected.

## Testing

- **No unit test**: the change is a static mapping plus UI glue; pure-logic engines are untouched.
- **Manual MCP playtest**: drive the Apple II UI into each of the eight error states and confirm the correct scene renders. Per project guidance ([[feedback_audio_verification]]), **audio confirmation is the user's responsibility** — screen capture is silent, so the user verifies the sound actually plays.

## Files Touched

- `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` — add `sound = "goodjoss"` to eight error scene return tables.
- `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` — add `lastSoundedScene` dedup + spawned `SoundPlayer.play` in `render`.
