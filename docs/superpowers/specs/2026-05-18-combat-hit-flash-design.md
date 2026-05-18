# Combat Hit Flash — Design

## Goal

Reproduce the Apple II Taipan! enemy-fire video-mode strobe (BASIC line 5540) in
the Roblox Apple II interface. When the enemy fires on the player, the terminal
flashes through a sequence of full-screen "garbage" framebuffer images before
the "We've been hit, Taipan!!" message is rendered.

See `docs/superpowers/plans/2026-05-17-combat-hit-flash.md` for the original
BASIC analysis. This spec turns that research into an implementation design.

## Scope

### In scope (v1)
- Full-screen image overlay above the Apple II terminal that cycles through 3
  captured framebuffer images and the terminal itself, 10 iterations total.
- Server flag on the existing "We've been hit, Taipan!!" `pendingMessages`
  entry so the flash plays at the start of that notif's lifecycle.
- Three asset-ID placeholders (`rbxassetid://0`) in a new `Images.luau` module,
  to be replaced after the user uploads the captured frames.

### Out of scope (deferred)
- **Lo-res page 1 live mirror.** On real hardware lo-res page 1 reinterprets
  the current text screen's bytes as colored blocks, so it changes per scene.
  V1 uses a single captured lo-res page 1 image; a future feature will
  procedurally derive this frame from the live terminal contents.
- Modern interface — Apple II only for v1.
- Per-hit randomisation across a pool of captures.
- Coupling with the existing `GlitchLayer` (CRT glitch effects).

## Architecture

```
Server (GameService.applyEnemyFire)
  pending entry "We've been hit, Taipan!!"  +  { hitFlash = true }
              │
              ▼  pushState → pendingMessages
Client (Apple2Interface.playNextNotif)
  consume entry
  if entry.hitFlash:
      hitFlash.play(continueFn)        ◄── new branch
  else:
      continueFn()                     ◄── existing path
  continueFn:
      term.showInputAt(rows)
      ki.setPrompt(anyKey)
      SoundPlayer.play("underattack")
      task.delay(duration, advanceNotif)
```

The flash sits entirely inside the notif's lifecycle. No new RemoteEvent. No
changes to `CombatEngine`, `GlitchLayer`, or any shared logic module.

## Components

### `sync/ReplicatedStorage/Images.luau` (new)

Flat asset-ID table mirroring `Sounds.luau`:

```lua
return {
  hitFlashHiresPage2 = "rbxassetid://0",
  hitFlashLoresPage1 = "rbxassetid://0",
  hitFlashLoresPage2 = "rbxassetid://0",
}
```

Roblox treats `rbxassetid://0` as "no image" — the overlay shows transparent
until real IDs are pasted in. That is acceptable for placeholder testing.

### `sync/StarterGui/TaipanGui/GameController/Apple2/HitFlashLayer.luau` (new)

Overlay module. Public interface:

- `HitFlashLayer.new(terminalGui) → { play, destroy }`
- `play(onComplete)` — runs the strobe in a `task.spawn`, fires `onComplete()`
  when the sequence finishes.
- `destroy()` — removes the overlay frame.

Internals: one `ImageLabel` parented to `terminalGui.TextParent`:
- `Size = UDim2.fromScale(1, 1)` (inherits the 16:9 letterboxing from the
  terminal's `AspectRatioConstraint`)
- `BackgroundTransparency = 1`
- `ZIndex = 50` (above terminal text at 1, below `GlitchLayer` at 100)
- `Visible = false` initially
- `ScaleType = Enum.ScaleType.Stretch` (default)

Strobe sequence per iteration (4 frames):

| Phase | Image                         | Duration |
|-------|-------------------------------|----------|
| 1     | `hitFlashLoresPage1`          | `FRAME_MS` |
| 2     | `hitFlashLoresPage2`          | `FRAME_MS` |
| 3     | `hitFlashHiresPage2`          | `FRAME_MS` |
| 4     | (overlay hidden — terminal)   | `FRAME_MS` |

Repeats 10 times. `FRAME_MS = 16` (≈one 60 Hz CRT frame). Total ≈640 ms.
After the final iteration the overlay is hidden and `onComplete` fires.

This mirrors the BASIC sequence (`LORES → PAGE2 → HIRES → PAGE1`, repeated
10×): in each iteration, the user sees lo-res page 1, then lo-res page 2,
then hi-res page 2, then the underlying "hi-res page 1" (which in our port
is just the terminal showing through).

### `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` (modified)

Three changes:

1. Construct the layer alongside `GlitchLayer`:
   ```lua
   local hitFlash = HitFlashLayer.new(term._gui)
   ```

2. In `playNextNotif`, gate the existing row-write + sound + advance logic
   behind `entry.hitFlash`. When set, run the strobe first and continue in
   the completion callback. Use the existing `myGen` guard so the post-flash
   logic bails if the notif has been invalidated.

3. Call `hitFlash.destroy()` in `adapter.destroy()`.

### `sync/ServerScriptService/GameService.server.luau` (modified)

One-line addition in `applyEnemyFire` (currently line ~693):

```lua
local entryHit = makeCombatNotif("We've been hit, Taipan!!", 2)
entryHit.sound = "underattack"
entryHit.hitFlash = true                    -- NEW
table.insert(pending, entryHit)
```

The follow-up entries ("buggers hit a gun", "buggers got us", "Li Yuen's
fleet drove them off") do NOT set `hitFlash`; only the primary impact notif
plays the strobe.

## Data flow

1. `CombatEngine.enemyFire` mutates `state.combat`.
2. `GameService.applyEnemyFire` builds `pending` entries; the first entry
   (`entryHit`) gets `hitFlash = true`.
3. `pushState(player)` ships `state.pendingMessages` to the client.
4. `Apple2Interface.update` drains `pendingMessages` into `notifQueue`.
5. `playNextNotif` pops the entry, sees `hitFlash`, runs `hitFlash.play(...)`.
6. Strobe runs for ~640 ms over the terminal.
7. Completion callback writes row 4 ("We've been hit, Taipan!!"), starts the
   `underattack` sound, schedules `advanceNotif` after `entry.duration` (2s).
8. Subsequent notifs (gun destroyed, sunk, etc.) play normally with no flash.

## Edge cases

| Case | Behaviour |
|------|-----------|
| Sinking hit (`fireResult.sunk`) | Flash plays normally on the impact notif. The game-over status screen is a separate notif appended after it. |
| Combat ends mid-flash | `hitFlash.play` reads no game state. The 640 ms strobe finishes; the existing `myGen` guard in `playNextNotif` discards the post-flash sound/advance if the notif is stale. |
| `GlitchLayer` active during a hit | Both render simultaneously; glitch sits on top (ZIndex 100 vs 50). Reads as extra CRT interference — acceptable. |
| Placeholder asset IDs (`rbxassetid://0`) | Roblox renders nothing for those frames; the overlay is effectively hidden during phases 1–3, terminal shows through during phase 4. Visible cadence still works for layout testing; visual fidelity requires the real captures. |
| `Apple2Interface.destroy()` mid-flash | `hitFlash.destroy()` removes the frame; any in-flight `task.delay` calls become no-ops because the `ImageLabel` is gone (writes to `Image` on a destroyed instance are safe). |

## Testing

- **No TestEZ spec required.** The server change is a single boolean flag
  with no logic; the client change is presentational.
- **Visual verification (manual, user-driven):**
  1. Studio Play mode → Apple II interface → start a game.
  2. Travel until pirates attack.
  3. Take enemy fire (Fight with no guns, or wait out a round).
  4. Observe the 10-iteration strobe immediately before "We've been hit,
     Taipan!!" appears on row 4.
  5. Audio (`underattack` sound) starts AFTER the strobe completes.
- Per project memory (`feedback_audio_verification`): audio verification
  remains the user's responsibility — MCP screen captures are silent.

## File summary

| File | Action |
|------|--------|
| `sync/ReplicatedStorage/Images.luau` | NEW — 3 placeholder asset IDs |
| `sync/StarterGui/TaipanGui/GameController/Apple2/HitFlashLayer.luau` | NEW — overlay module |
| `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` | MODIFY — construct layer, gate notif on `hitFlash`, destroy on teardown |
| `sync/ServerScriptService/GameService.server.luau` | MODIFY — one line in `applyEnemyFire` |
| `sourcemap.json` | MODIFY — register the two new files |

## Future work (not in v1)

- Replace the static `hitFlashLoresPage1` image with a procedural render of
  the terminal's current text reinterpreted as lo-res color blocks. This is
  what the real Apple II shows in that phase and is the main fidelity gap.
- Add a small pool of alternate `hitFlash*` captures and pick randomly per
  hit, so repeated combat does not look identical.
- Wire a matching effect into the Modern interface (simpler screen-shake
  or flash).
- Consider pulsing `GlitchLayer` during the flash for added impact.
