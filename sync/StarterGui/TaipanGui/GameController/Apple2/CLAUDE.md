# Apple2 Sub-module Notes

## Notification System (`pendingMessages`)

The server attaches a `pendingMessages` array to the state before calling `pushState`. Each entry is `{ rows = {[rowNum] = lineTable}, duration = seconds }`. The client (`Apple2Interface`) drains the queue via `playNextNotif`, which writes each entry's rows directly to the terminal via `term.showInputAt`, then auto-advances after `duration` seconds (or on any keypress).

`playNextNotif` iterates `pairs(entry.rows)` — it writes exactly the rows the entry specifies, nothing more. This means each notification builder is responsible for blanking any rows it wants cleared.

### Notification builder functions (in `GameService.server.luau`)

| Function | Rows written | Use for |
|---|---|---|
| `makeCompradorNotif(lines, dur)` | 17–24 (pre-filled, blanks unset) | Port/arrival events (Li Yuen escort, price crash, arrival) |
| `makeCaptainNotif(lines, dur)` | 17–24 (pre-filled, blanks unset) | Travel-time events (storm, robbery, pirate approach) |
| `makeCombatNotif(lines, dur)` | 4, 5, 6… (lines only, no blanking) | In-battle action results (fight/run/throw narration, enemy fire) |

`makeCombatNotif` writes the first line to row 4 (overwriting the seaworthiness display), with overflow to rows 5, 6, … for multi-line messages. Rows 17–24 are untouched, so the (blank) lower half of the combat screen stays clean.

### When to use `makeCombatNotif` vs `makeCaptainNotif`

Use `makeCombatNotif` for messages that appear while the **combat display** (rows 1–5) is on screen — i.e., inside `applyEnemyFire`, `CombatFight`, `CombatRun`, `CombatThrow`.

Use `makeCaptainNotif` for everything else that needs a full Captain's Report block — storm messages during travel, robbery, `postCombatStorm` (combat has already ended when those play), and pirate/enemy approach notices.

## Combat Screen Row Layout

```
Row 1:  "   N ships attacking, Taipan!   | We have"
Row 2:  "Your orders are to:             |  N guns"
Row 3:  └──────────────────────────────────────────
Row 4:  "Current seaworthiness: Perfect (100%)"   ← combat notifs overwrite here
Row 5:  "  Ships: [##########]"
Rows 6–24: empty
```

Row 4 is the natural slot for transient combat feedback because it's already informational (status changes each round anyway) and sits directly below the fixed header.

## Port/Status Screen Row Layout

Rows 1–16 are the port status box (warehouse, hold, cash/bank). Rows 17–24 are the Comprador's/Captain's Report area used for all non-combat notifications.

If you add a new notification context that needs to appear in a different region (e.g., overlaying the ship grid on row 5), create a new builder that populates only those rows and leave the rest to `pairs(entry.rows)` to handle correctly.
