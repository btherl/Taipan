# Combat Sprites — Apple II Interface

**Status:** Proposed
**Date:** 2026-05-09
**Scope:** Apple II combat interface only. Modern interface is out of scope.

Implements the enemy-ship sprite grid, damage overlay, hit-flash, ship-flee blank, and ship-sink animation in the Apple II combat scene. Faithful to the BASIC original (`references/taipan-applesoft-annotated.txt` lines 5320–5895, 5800–5895), with one tightening for Roblox: damage fragments are picked client-side per hit and never persisted.

## Background

`docs/original_design/COMBAT_SPRITES.md` analyses the BASIC sprite system. Key facts carried into this design:

- 10-slot ship grid, 5×2 layout. Slot `i` (0-based in BASIC, 1-based in our port) sits at column `(i mod 5) * 8 + 1`, row `floor(i / 5) * 6 + 7` — i.e. top row at display row 7, bottom row at display row 13.
- Each ship occupies 7 chars wide × 5 rows tall.
- BASIC ship sprite is `"ABCDEFG\nHIJKLMN\nOIJKLPQ\nRSTUVWX\nYJJJJJZ"` printed in the custom-ROM character set.
- Damage = on each gun hit, two random fragments (one upper, one lower) are printed on top of the sprite. Cumulative; never tracked or restored. Fragments come from a fixed table of 6 fragment-pairs (`DM$` / `DL%` in BASIC line 10300).
- Sink = BASIC sub 5860 calls assembly routine 2224 with a random speed seed. The ship slides down with the bottom clipped at the slot edge until gone. There is no explosion graphic.
- Hit-flash = BASIC sub 5840 calls assembly routine 2368. Brief slot-local effect; precise rendering not specified, treated as a tunable visual.
- Roblox port equivalence: the sprite tile glyphs (uppercase A–Z and the lowercase + digit fragment chars) are already baked into `TaipanThickFont` at the codepoints the BASIC strings reference, so drawing reduces to printing those strings in `TaipanThickFont`. The control codes `BD$` / `CD$` / `DD$` and the colour code `CG$` are dropped.

## Requirements

In scope:

1. Draw a fresh ship sprite at any of the 10 slots when combat begins or a replacement spawns.
2. Apply visible damage to a slot when our gun hits the ship there: a brief hit-flash followed by two damage-fragment overwrites (cumulative).
3. Blank a slot instantly when the ship at that slot flees (run-attempt success, partial-escape, or post-fight enemy flee).
4. Animate a ship sinking when destroyed: the sprite slides down inside its slot, the bottom is clipped at the slot edge, the slot ends blank. Speed is randomised per ship.
5. Replace the existing `"  Ships: [#.##.....#]"` placeholder on row 5 of the combat scene with the real sprite grid.
6. Block player input (Fight / Run / Throw prompt) while animations are playing.

Out of scope:

- Explosion graphic (the user has noted reusable explosion code is wanted *elsewhere later* — separate spec).
- Modern-interface combat visuals.
- Persisting damage-fragment state across reconnects (matches BASIC; visuals reset on resync).
- Sound effects for hits/sinks (`Add sounds` work is independent).
- Tuning of timing constants beyond reasonable defaults.

## Architecture

A new module `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau` is introduced as a sibling layer to `Terminal` and `GlitchLayer`. It owns 10 slot Frames in a `ScreenGui` (or shared `TextParent` frame, matching `Terminal`'s parenting), positioned at the BASIC grid coordinates, each with `ClipsDescendants = true` so a sinking ship clips at the slot's bottom edge.

Each slot Frame contains a single Text object (`TaipanThickFont`, `TextSize = 3`, green) holding the 5-line sprite string. Damage is applied by mutating individual characters in that string and re-rendering. Sinking tweens the Text object's `Position.Y` downward inside the clipping Frame.

`ShipGrid` is created once by `Apple2Interface` when the Apple II interface is mounted (alongside `Terminal` and `GlitchLayer`) and destroyed when the interface is torn down. While the player is *not* in combat, the layer is hidden via `Visible = false`. While in combat, the layer is shown and `Apple2Interface` drives it from `state.combat.events` and `state.combat.grid` snapshots. `PromptEngine.sceneCombatLayout` no longer renders the `"  Ships: [...]"` placeholder; instead, `Apple2Interface` calls into `ShipGrid` after the scene draws. The sprite area (1-based display rows 7–11 for the top sprite row and 13–17 for the bottom) is left blank by the scene compositor so sprites overlay cleanly.

Parenting matches `Terminal`'s pattern: `ShipGrid` creates its own `ScreenGui` via `Text.GetTextGUI(displayOrder)` and parents it to `Players.LocalPlayer.PlayerGui`, with a `displayOrder` greater than `Terminal`'s so sprites render on top of any leftover text in those rows.

## Server side

### CombatEngine event timeline

`CombatEngine.fight()` returns `{sunk, fleeCount, events}`. The `events` list is built in chronological order during the gun loop:

```lua
{ type = "hit",   slot = 3 }   -- gun hit, ship survived
{ type = "sink",  slot = 3 }   -- gun hit, ship destroyed (emitted right after the hit)
{ type = "spawn", slot = 7 }   -- replacement appeared (emitted after the sink that emptied the screen)
{ type = "flee",  slot = 9 }   -- ship fled (post-fight enemy-flee pass)
```

`CombatEngine.partialEscape()` and `CombatEngine.attemptRun()` likewise return / mutate an events list with `flee` entries for vacated slots. `CombatEngine` does not generate damage-fragment indices; those are picked client-side.

### Engine semantics — preserved from BASIC

The existing `fight()` spawn rule is preserved: replacements only spawn when `enemyOnScreen == 0` mid-loop and `enemyWaiting > 0`. Surplus guns in the same round may then fire on the freshly-spawned ships, matching BASIC line 5330's behaviour. The events list reflects this naturally — `spawn` events appear chronologically right after the `sink` that emptied the screen, before the next gun's events.

### State plumbing

`GameService` attaches the events list to `state.combat.events` before `pushState`. The field is ephemeral: the next state push (the one after the player's next action) clears it. `PersistenceEngine` does not serialise `events` (it's already a non-canonical field).

## Client side

### ShipGrid module

Public API (`Apple2/ShipGrid.luau`):

```lua
local grid = ShipGrid.new(parent)
grid.draw(slot)               -- show fresh ship at slot 1..10 (no damage)
grid.applyHit(slot)           -- play hit-flash + overlay 2 random damage fragments
grid.flee(slot)               -- blank the slot instantly
grid.sink(slot, onComplete)   -- slide-down + clip + blank, then fire callback
grid.spawn(slot)              -- like draw(); reserved for a possible appear-in effect later
grid.clearAll()               -- erase all 10 slots (combat ended)
grid.destroy()                -- tear down all GUI elements
```

Per-slot internal state:

- `frame: Frame` — clipping container at the slot's pixel coordinates (7 chars × 5 rows worth of pixels).
- `text: TextSprite` — the 5-line Text object holding the sprite glyphs; mutable per character.
- `damageGrid: {[row]={[col]=char}}` — sparse map of which cells have been overwritten with damage chars; consulted on every redraw so accumulated damage persists across hits within a combat session.
- `animating: bool` — guard against double-trigger.

### Damage application

Faithful to BASIC line 5840 / `DM$` / `DL%`:

- For `J = 0, 1` (upper, lower zone), pick `IJ = math.random(0, 5)`.
- Look up the fragment's char string and offset from a port of the BASIC tables (lives at the top of `ShipGrid.luau` as a local constant).
- Write the chars into `damageGrid[slot]` at the offset (handling the multi-row `*` sentinel for fragments 1-J=0 and 3-J=1).
- Re-render the slot's text from `damageGrid[slot]` overlaid on the base sprite.

### Hit-flash

BASIC `CALL 2368` interpretation: brief inverse-video flash on the slot's Text object (`Inverted = true` for ~80 ms, then back to `false`). Tunable; the contract is "a short visual indication that this slot was just hit, regardless of whether it's also about to sink".

### Sink animation

BASIC `CALL 2224` interpretation: tween `text.Position.Y` from 0 to `slotPixelHeight` (so the ship slides past the frame's bottom edge). Duration randomised in `0.4 s .. 1.6 s` (echoing the BASIC double-`R(192)` randomisation). `ClipsDescendants = true` on the slot frame produces the bottom-disappearing-first effect for free. After the tween, the slot is blanked, `damageGrid[slot]` is cleared, and `onComplete` fires.

### Animator (in Apple2Interface)

A module-local `combatAnimator = {queue, playing, current}` table. On every `StateUpdate` while `state.combat ~= nil`:

1. If `state.combat.events` is present, append them to the queue.
2. Drain the queue **sequentially**: one event at a time, each waiting for its animation `onComplete` before pulling the next.

While the queue is non-empty, `roundPhase` (existing field) is set so the Fight/Run/Throw prompt is hidden. When the queue drains, `startRoundIfCombat()` (existing function) renders the next prompt.

### Initial render & resyncs

- First combat StateUpdate (no events, fresh fight): `ShipGrid` reads `combat.grid[1..10]` from the snapshot and calls `draw(slot)` for each populated slot synchronously, no animation.
- Reconnect / resync mid-combat: same path — ships re-appear instantly with no accumulated damage chars (matches BASIC).

### Combat exit

When `state.combat` transitions from non-nil to `nil`, `ShipGrid.clearAll()` runs and the layer's `Visible` is set `false`. The module instance and its GUI elements remain in memory for the next combat — only `Apple2Interface` teardown destroys them.

## Data flow summary

```
Player presses F           server                       client
─────────────────────────  ───────────────────────────  ──────────────────────────────
combatFight ─────────────► CombatEngine.fight()
                           ─ build events list
                           ─ enemyFire() (after fight,
                             unless outcome decided)
                           state.combat.events = [...]
                           pushState ─────────────────► StateUpdate handler
                                                        ShipGrid: enqueue events
                                                        animator: drain sequentially
                                                          ─ hit  → applyHit (~80 ms)
                                                          ─ sink → sink     (~0.4-1.6 s)
                                                          ─ spawn→ draw     (instant)
                                                          ─ flee → flee     (instant)
                                                        when drained →
                                                        roundPhase cleared,
                                                        Fight/Run/Throw shown
```

## Animation timing (defaults)

| Event | Duration | Notes |
|---|---|---|
| Hit-flash | 80 ms | inverse-video tick |
| Damage-fragment overlay | 0 ms | painted with the hit-flash, no separate delay |
| Sink | 400-1600 ms random | tween Y, easing linear |
| Spawn appear-in | 0 ms | instant draw; can add a flash later |
| Flee | 0 ms | instant blank |
| Inter-event gap | 50 ms | small breathing room between sequential events |

All values tunable during implementation. The plan does not lock in exact timings — they are the recommendation.

## Testing

### Unit tests (TestEZ)

Extensions to `CombatEngine.spec.luau`:

- `fight()` returns events in chronological order; 3-gun / 5-ship scenario produces hit events in firing order.
- A killing shot emits `sink` immediately after its `hit` for the same slot.
- When a sink empties the screen and `enemyWaiting > 0`, `spawn` events appear right after the triggering `sink`, before the next gun's events.
- When a sink empties the screen and `enemyWaiting == 0`, no `spawn` events emit.
- `attemptRun()` failure → `partialEscape()` events contain only `flee` entries for vacated slots.
- Post-fight enemy-flee pass: `flee` events appear after all hit/sink/spawn events of the same `fight()` invocation.
- Empty-screen reconcile case: `fight()` with `onScreenCount == 0` emits no events.

### MCP playtest verification

Validates the GUI behaviour that unit tests can't reach:

- Combat encounter starts → all spawned ships render at the correct slot coordinates.
- Gun fire → hit-flash plays, damage-fragment chars appear and accumulate across multiple hits.
- Killing shot → slot slides downward, clips at slot bottom, ends blank.
- Successful run → all slots blank instantly.
- Sink-triggered respawn → spawn events render after the triggering sink; new ships appear at fresh slots; remaining guns fire on them in the same round.
- Input gating: Fight/Run/Throw prompt is hidden until the animation queue drains.

### Out of scope for tests

- Damage-fragment RNG distribution (visual flair only).
- Pixel-precise sink timing (random per ship, intentional).

## File-level changes

| File | Change |
|---|---|
| `sync/ReplicatedStorage/shared/CombatEngine.luau` | `fight()` / `partialEscape()` / `attemptRun()` build and return an `events` list. Engine semantics unchanged otherwise. |
| `sync/ServerScriptService/GameService.server.luau` | Attach events to `state.combat.events`; clear on the next non-combat-action push. |
| `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau` | **NEW** — slot frames, draw / applyHit / flee / sink / spawn / clearAll / destroy, damage-fragment table, hit-flash + sink-tween primitives. |
| `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` | Instantiate `ShipGrid`, drain `state.combat.events` through the animator, gate prompts via `roundPhase`. |
| `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` | Remove `"  Ships: [#.##.....#]"` placeholder from row 5 of `sceneCombatLayout`; leave display rows 7–17 blank for the sprite overlay. |
| `sync/ServerScriptService/Tests/CombatEngine.spec.luau` | New describe block for the events list (cases listed above). |
| `docs/original_design/COMBAT_SPRITES.md` | Already updated as part of this brainstorm (Roblox-port note + sink-not-explosion correction). |
| `customfonts/CLAUDE.md` | Optional follow-up: tighten the "we may simply use large sprites" wording to confirm font glyphs are the chosen path for ship sprites. |

## Open questions

- Exact codepoint mapping in `TaipanThickFont` for the damage fragment characters (lowercase + digits 0–5). Confirmed at implementation time by reading the font atlas; if any mismatch, font data file is updated rather than the design.
- Easing curve for the sink tween. Default linear; consider `Sine`-out if linear feels too mechanical.
- Whether `spawn` should have a brief appear-in flash. Default no; revisit after first playtest.
