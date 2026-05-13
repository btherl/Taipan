# Notif Sound Timing — Design Spec

**Date:** 2026-05-13
**Scope:** Apple II interface only (`sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau`).
**Problem:** Server-driven notif entries play their sound via `task.spawn` while `task.delay(entry.duration)` starts at the same instant. Result: messages with audio cues advance before the cue is heard.

## Goal

Reorder the notif sequence so the per-entry `duration` is a **post-sound dwell**: display the message, play the sound to completion, *then* start the delay before advancing to the next entry.

## Behavioural Contract

| Entry condition | Sequence |
|---|---|
| No sound | Display rows → `task.delay(entry.duration)` → advance. **Unchanged.** |
| With sound, no keypress | Display rows → `SoundPlayer.play` (blocks) → `task.delay(entry.duration)` → advance. |
| With sound, keypress during sound | Buffered. Sound finishes naturally → advance immediately (skip post-sound delay). |
| With sound, keypress after sound | Advances immediately (current "anyKey" behaviour). |
| Combat-mode notif (`isCombatNotif`) | No anyKey prompt; F/R/T queued command stays active. Sound still blocks; post-sound delay still runs. |

Rationale for "skip delay only, not sound": preserves the Apple II audio-cue experience while keeping the UI responsive to player input.

## Scope

- **Touched:** `Apple2Interface.luau`, function `playNextNotif`, tail block (currently lines ~200-211).
- **Unchanged:** `GameService.server.luau` (entry schema `{rows, duration, sound, includeStatusScreen, _animationGate}` stays as-is). `SoundPlayer.luau` (already blocks correctly via internal polling). Modern interface (doesn't consume `entry.sound`).

## Implementation

Replace the sound/delay tail of `playNextNotif` with a single spawned task that owns both the play-blocking and the post-sound `task.delay`. Two locals coordinate with the keypress handler:

```lua
local soundPlaying = entry.sound ~= nil
local skipDelayRequested = false

if not isCombatNotif then
  ki.setPrompt({
    type   = "key", keys = {}, anyKey = true,
    onKey  = function()
      if soundPlaying then
        skipDelayRequested = true
      else
        advanceNotif(myGen)
      end
    end,
  }, lastState, actions)
end

task.spawn(function()
  if entry.sound then
    SoundPlayer.play(entry.sound)  -- blocks until Ended (or fallback deadline)
    soundPlaying = false
    if myGen ~= notifGen then return end       -- queue invalidated mid-sound; bail
    if skipDelayRequested then
      advanceNotif(myGen)
      return
    end
  end
  task.delay(entry.duration, function() advanceNotif(myGen) end)
end)
```

### Notes

- `SoundPlayer.play` already blocks via a 50 ms polling loop with a `TimeLength + 0.2 s` deadline (5 s fallback when `TimeLength <= 0`). No changes there.
- `advanceNotif` self-guards on stale `gen` (`if gen ~= notifGen then return end` at line 140), so the inner `myGen ~= notifGen` check is belt-and-braces — it avoids scheduling a wasted `task.delay` when the queue is invalidated mid-sound.
- Unknown sound names: `SoundPlayer.play` warns and returns immediately; flow falls through to the delay branch as if there were no sound.

## Risks

- **Stuck sound asset.** If a `SoundId` hasn't preloaded, `Sound.TimeLength` is `0` and `SoundPlayer.play` falls back to a 5 s wait. Today this is masked by `task.spawn`; under this design the notif chain freezes for up to 5 s. **Pre-existing bug, surfaced but not fixed here.** Mitigation deferred — a preload pass at game start would address it cleanly.
- **Unskippable audio.** Long sounds become unskippable by design. Matches the Apple II UX rule chosen during brainstorming; flagged so a future tweak isn't surprising.

## Out of Scope

- Server changes.
- `SoundPlayer.luau` changes.
- Modern interface.
- Asset preloading / readiness work.
- Per-entry `waitForSound` flag (rejected as YAGNI — the project will not have non-blocking sounds).

## Verification

No unit test — this is client-side UI with real timing. Verify via MCP playtest:

1. Enter Play mode; pick Apple II interface; start a game.
2. Trigger a sounded notif end-to-end. Examples:
   - Travel to Hong Kong with cargo to trigger Li Yuen `goodjoss` (line 305 in `GameService.server.luau`).
   - Force a storm `underattack` notif (line 355).
   - Trigger opium seizure `badjoss` (line 294).
3. Observe sequence: rows appear → sound audible → no advance until sound ends → dwell matches `entry.duration` → next notif.
4. Press a key mid-sound. Confirm sound is not cut, then notif advances immediately on sound-end without waiting for `entry.duration`.
