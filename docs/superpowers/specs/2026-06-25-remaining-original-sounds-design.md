# Design: Remaining Original-Game Sounds

**Date:** 2026-06-25
**Status:** Approved
**Scope:** Apple II interface (server notifications + one local scene)

## Problem

After wiring server-notification sounds (earlier) and the eight local rejection scenes (the `2026-06-25-local-event-sounds` work), four events from the original Apple II game still play **no sound** in our port. This work closes those four gaps, faithfully to the original.

## Source of Truth

Each gap was verified directly against the original C source (`references/taipan-d3eacd0089da82292b4c4553463600fe229ee07c/taipan.c`), which records both the exact message text and the sound routine called:

| # | Event | Original message (taipan.c) | Sound routine | Sound |
|---|---|---|---|---|
| A | Wu enforcers rob you | `:2967` "N of your bodyguards have been killed by cutthroats and you have been robbed of all of your cash" (preceded by "Bad joss!!") | `under_attack_timed_getch()` (`:2972`) | `underattack` |
| B | Accept Wu bankruptcy loan | `:2877` "Very well, Taipan. Good joss!!" | `bad_joss_timed_getch()` (`:2879`) | `badjoss` |
| C | Decline loan → game over | `:2865` "Very well, Taipan, the game is over!" | `under_attack_timed_getch()` (`:2867`) | `underattack` |
| D | Empty firm name on entry | *(re-prompts; no new text)* | `bad_joss_sound()` (`:762`) | `badjoss` |

These reuse the three existing assets in `sync/ReplicatedStorage/Sounds.luau` (`badjoss`, `goodjoss`, `underattack`). No new assets.

## Explicitly Out of Scope

- **Buy/sell over-limit.** Verified against the original: `buy()` (`taipan.c:3183`) and `sell()` (`:3225`) **silently re-prompt** on an over-limit amount — no sound is played. Our current silent-clear behaviour is already faithful. (This was a mistaken entry in an earlier audit; corrected here.)
- The "you only have X in cash / in the bank" messages (`taipan.c:2780-2809`, `good_joss`) are the Wu-repay and bank limits, which were **already shipped** as local scenes (`wu_repay_err`, `bank_deposit_err`, `bank_withdraw_err`). Not re-addressed here.

## Architecture

Two mechanisms, matched to where each event lives.

### Mechanism 1 — server notification entries (gaps A, B, C)

These are server-side flow events in `GameService.server.luau`. Each handler constructs a notification entry via `makeCompradorNotif(lines, duration)` (the original shows each as a `compradores_report()`), sets `entry.sound`, and pushes it through the existing pending-messages path:

```lua
local pending = {}
-- ... build entry, entry.sound = "<name>", table.insert(pending, entry)
state.pendingMessages = pending
pushState(player)
state.pendingMessages = nil
```

`Apple2Interface.adapter.update` drains `state.pendingMessages` into the notif queue, and `playNextNotif` already plays `entry.sound` via `SoundPlayer.play`. No client change is needed for A/B/C.

**Why this also fixes a latent display bug (A):** the Apple II interface ignores `Remotes.Notify` entirely (`Apple2Interface.luau:502` — "Apple2 receives all event info via pendingMessages; ignore text notifications"). The enforcer event currently fires only `Remotes.Notify`, so in Apple II it shows **no message and no sound**. Routing it through `pendingMessages` surfaces both. The existing `Remotes.Notify` call may remain for the modern UI.

### Mechanism 2 — explicit `playSound` callback (gap D)

The empty-firm-name case **re-prompts the same scene** (no scene transition), so the scene-entry `sound` mechanism from the prior work (deduped on `localScene`) cannot fire on the re-prompt. It needs an explicit play at the moment empty input is detected.

`PromptEngine.processState` gains a 6th parameter `playSound`, forwarded only to `sceneFirmName` (the single scene that needs it). `Apple2Interface` supplies:

```lua
local function playSound(name)
  task.spawn(function() SoundPlayer.play(name) end)  -- play() blocks; must spawn
end
```

passed as the 6th argument to `processState`. (`SoundPlayer` is already required at `Apple2Interface.luau:13`.)

## Component Detail

### A — Wu enforcers (`GameService.server.luau:493`)

Current:
```lua
if FinanceEngine.wuEnforcers(state) then
  Remotes.Notify:FireClient(player, "WU'S MEN beat you and take all your cash!")
end
pushState(player)
```

New behaviour: when `wuEnforcers(state)` returns true, build a comprador notif with the faithful text and `sound = "underattack"`, and push it via `pendingMessages`. The bodyguard count `N` is pure flavour (`rand1to3` in the original, no mechanical effect), so the handler computes `math.random(1, 3)` locally — no `FinanceEngine` change required. The modern `Remotes.Notify` line may be kept for the modern UI.

Faithful message lines (comprador notif):
```
Bad joss!!  N of your bodyguards have
been killed by cutthroats and you have
been robbed of all of your cash, Taipan!
```

### B — Accept bankruptcy loan (`GameService.server.luau:1099-1108`)

After `state.cash`/`state.debt` are adjusted, push a comprador notif before/with the state update:
```
Very well, Taipan.
Good joss!!
```
with `entry.sound = "badjoss"`, via the `pendingMessages` pattern.

### C — Decline bankruptcy loan → game over (`GameService.server.luau:1110-1117`)

Before/with `setGameOver(state, "quit")`, push a comprador notif:
```
Very well, Taipan,
the game is over!
```
with `entry.sound = "underattack"`. Order the push so the notif drains before the game-over screen renders, following the combat-sink precedent (`GameService:705-710` builds the sink notif, then `setGameOver`, then pushes with `pendingMessages`). The existing `"quit"` game-over reason is retained.

### D — Empty firm name (`PromptEngine.luau` + `Apple2Interface.luau`)

1. `PromptEngine.processState(state, localScene, actions, localSceneCb, combatSelection)` → add a 6th param `playSound`. At the firm-name dispatch (`:1606`), pass it through: `return sceneFirmName(state, actions, localSceneCb, playSound)`.
2. `sceneFirmName(_state, actions, localSceneCb, playSound)` `onType`:
   ```lua
   onType = function(text, _s, _a)
     if (text or ""):match("^%s*$") then       -- empty / whitespace-only
       if playSound then playSound("badjoss") end
       return nil                                -- re-prompt in place, no advance
     end
     actions.setFirmName(text)
     if localSceneCb then localSceneCb("start_choice") end
     return nil
   end
   ```
   `KeyInput.luau:364-370` already calls `onType(submitted)` on Return with an empty buffer (desktop and mobile hidden-box paths both route through `onType`), and re-shows the input line, so returning without advancing yields the original's re-prompt.
3. `Apple2Interface` passes the `playSound` closure (above) as the 6th argument wherever it calls `PromptEngine.processState`.

## Error Handling

- `SoundPlayer.play` already `warn`s on an unknown name and returns; all sounds wrapped in `task.spawn` so nothing blocks render or the server handler.
- Overlapping sounds are harmless (`SoundPlayer.play` clones a fresh `Sound` per call).

## Testing

- **No unit tests:** no pure-logic (`shared/`) module changes — this is server-handler and client-UI glue.
- **Manual MCP playtest** of all four triggers, confirming the message renders in the Apple II interface. Per project guidance ([[feedback_audio_verification]]), **audio confirmation is the user's responsibility** — the implementer drives the UI to each event; the user confirms the sound plays.

## Files Touched

- `sync/ServerScriptService/GameService.server.luau` — gaps A, B, C: build sounded comprador notif entries via `pendingMessages` in the enforcer and two bankruptcy handlers.
- `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` — gap D: `processState` 6th param + `sceneFirmName` empty-input block + sound.
- `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` — gap D: define and pass the `playSound` closure to `processState`.
