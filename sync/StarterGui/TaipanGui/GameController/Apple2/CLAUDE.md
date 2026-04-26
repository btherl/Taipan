# Apple2 Sub-module Notes

## Notification System (`pendingMessages`)

The server attaches a `pendingMessages` array to the state before calling `pushState`. Each entry is `{ rows = {[rowNum] = lineTable}, duration = seconds }`. The client (`Apple2Interface`) drains the queue via `playNextNotif`, which writes each entry's rows directly to the terminal via `term.showInputAt`, then auto-advances after `duration` seconds (or on any keypress).

`playNextNotif` iterates `pairs(entry.rows)` — it writes exactly the rows the entry specifies, nothing more. This means each notification builder is responsible for blanking any rows it wants cleared.

**Combat-mode notifs** (those fired while `state.combat` is active and writing only to row 4) are treated specially: `playNextNotif` does NOT install the any-key skip prompt for them, leaving the F/R/T queue prompt active so the user can update the queued command mid-notif. The notif still auto-advances after `duration` seconds. Row 4 is also where the phase-B "Taipan, what shall we do??" message appears during a round.

### Notification builder functions (in `GameService.server.luau`)

| Function | Rows written | Use for |
|---|---|---|
| `makeCompradorNotif(lines, dur)` | 17–24 (pre-filled, blanks unset) | Port/arrival events (Li Yuen escort, price crash, arrival) |
| `makeCaptainNotif(lines, dur)` | 17–24 (pre-filled, blanks unset) | Travel-time events (storm, robbery, pirate approach) |
| `makeCombatNotif(lines, dur)` | 4 (single line only) | In-battle action results (fight/run/throw narration, enemy fire) |
| `makeLowertNotif(lines, dur)` | 17-24 (allows customized title) | Shared code used by Comprador and Captain notifications, also called directly when no title is required |

`makeCombatNotif` writes to row 4, overwriting the seaworthiness display.

### When to use `makeCombatNotif` vs `makeCaptainNotif`

Use `makeCombatNotif` for messages that appear while the **combat display** (rows 1–4) is on screen — i.e., inside `applyEnemyFire`, `CombatFight`, `CombatRun`, `CombatThrow`.

Use `makeCaptainNotif` for everything else that needs a full Captain's Report block — storm messages during travel, robbery, `postCombatStorm` (combat has already ended when those play), and pirate/enemy approach notices.

## Combat Screen Row Layout

```
Row 1:  "   N ships attacking, Taipan!   | We have"
Row 2:  "Your orders are to: Fight       |  N guns"  <- shows the queued command (Fight/Run/Throw cargo) for the next round-execute
Row 3:  "                                └────────"
Row 4:  "Current seaworthiness: Perfect (100%)"   ← combat notifs and the phase-B prompt overwrite here
Row 5:  "  Ships: [##########]"
Rows 6–24: empty
```

Row 2's selection is a **queued command**, not an immediate action. Pressing F/R/T at any time during combat updates the queue; the round timer (see "Round timing" below) reads the queued value when phase C fires. The queued display persists across rounds until the user changes it or combat ends.

Row 4 is the natural slot for transient combat feedback because it's already informational (status changes each round anyway) and sits directly below the fixed header. The phase-B "Taipan, what shall we do??" prompt is also written to row 4.

NOTE: Future work will leave rows 5-6 clear and display large ship sprites from rows 7-11 and 12-16, so this will change in future.

## Round timing

Combat is tick-driven on the Apple 2 interface. Each round runs:

- **Phase A** (2s silent wait): row 4 keeps the seaworthiness display. F/R/T keys remain live so the user can queue or change a command.
- **Phase B** (2s, only if no command was queued during phase A): row 4 shows "Taipan, what shall we do??" in amber. F/R/T keys remain live; pressing one updates the queue but does not abort the wait.
- **Phase C** (execute): the queued command fires. `Fight` -> `actions.combatFight`, `Run` -> `actions.combatRun`, `Throw cargo` -> local scene transition to `combat_throw_good`, `nil` (still no command) -> `actions.combatNoCommand` (server applies enemy fire unopposed).
- After the server responds, any pending notifs drain (combat-mode notifs leave the F/R/T prompt active per the notification system note above), then the next round starts. The throw subscenes can also resolve a round directly: pressing C in `combat_throw_good`, or submitting an empty/zero amount in `combat_throw_amt_N`, fires `combatNoCommand` and clears the queue.

`startRoundIfCombat` and `executePhaseC` in `Apple2Interface.luau` implement this. `roundGen` is bumped to invalidate in-flight phase callbacks whenever combat ends or `adapter.update` re-syncs.

## Port/Status Screen Row Layout

Rows 1–16 are the port status box (warehouse, hold, cash/bank). Rows 17–24 are the Comprador's/Captain's Report area used for all non-combat notifications.

If you add a new notification context that needs to appear in a different region (e.g., overlaying the ship grid on row 5), create a new builder that populates only those rows and leave the rest to `pairs(entry.rows)` to handle correctly.
