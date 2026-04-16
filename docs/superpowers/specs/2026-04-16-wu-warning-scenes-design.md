# Wu Warning Scenes — Design Spec

**Date:** 2026-04-16  
**Scope:** Apple II interface — Wu braves escort notification sequence

---

## Background

When a player arrives at Hong Kong with debt > $10,000 for the first time, the original
Apple II game plays a three-scene intimidation sequence before the Wu question dialog:

1. Elder Brother Wu sends braves to escort the player to his mansion (GOSUB 94 — 5 sec)
2. Wu delivers a Confucian reminder about debts (GOSUB 92 — 10 sec)
3. Wu hints at the fate of those who don't pay (GOSUB 92 — 10 sec)

The correct ordering observed in the original game is:
**Li Yuen demand → Repair offer → Escort scenes → Wu question**

In the current Luau implementation `FinanceEngine.wuWarningCheck()` fires correctly (once
per game, debt > 10,000, not on game-start turn), but the result is sent via
`Remotes.Notify:FireClient` — a channel Apple2Interface explicitly ignores. All three
scenes are silently dropped for Apple2 players. The Modern interface shows a single
custom message instead of the original three scenes.

---

## Change

**One file:** `sync/ServerScriptService/GameService.server.luau`

### New ephemeral state field: `wuEscortBraves`

At HK arrival, when `FinanceEngine.wuWarningCheck(state)` returns a braves count, store it
as `state.wuEscortBraves = N` instead of immediately firing `Remotes.Notify`. This field
is ephemeral (not persisted to DataStore — like `combat`, `shipOffer`, etc.).

The existing `Remotes.Notify:FireClient` call is **removed**. The Modern interface will
receive the escort content via the same `pendingMessages` mechanism as Apple2.

### New helper: `injectWuEscortIfReady(state, pendingTable)`

```lua
local function injectWuEscortIfReady(state, pendingTable)
  if state.wuEscortBraves
    and not state.liYuenPending
    and not state.repairPending
    and state.wuPending
  then
    local N = state.wuEscortBraves
    state.wuEscortBraves = nil
    table.insert(pendingTable, makeCompradorNotif({
      string.format("Elder Brother Wu has sent %d braves", N),
      "to escort you to the Wu mansion, Taipan.",
    }, 5))
    table.insert(pendingTable, makeCompradorNotif({
      "Elder Brother Wu reminds you of the",
      "Confucian ideal of personal worthiness,",
      "and how this applies to paying one's",
      "debts.",
    }, 10))
    table.insert(pendingTable, makeCompradorNotif({
      "He is reminded of a fabled barbarian",
      "who came to a bad end, after not caring",
      "for his obligations.",
      "",
      "He hopes no such fate awaits you, his",
      "friend, Taipan.",
    }, 10))
  end
end
```

Text sourced from `references/wu-escort-dialog.txt` (transcribed from the original game).

### Five call sites

The helper is called wherever a StateUpdate is pushed that may be the first moment both
`liYuenPending` and `repairPending` are false. Each call site builds a local `msgs` table,
calls the helper, assigns to `state.pendingMessages`, then calls `pushState`:

| Handler | Condition that makes it the right moment |
|---|---|
| `TravelTo` | No Li Yuen offer and no repair pending on arrival |
| `BuyLiYuenProtection.OnServerEvent` | Li Yuen resolved; repair already false |
| `DeclineLiYuenTribute.OnServerEvent` | Li Yuen resolved; repair already false |
| `ShipRepair.OnServerEvent` | Repair resolved; Li Yuen already false |
| `DeclineRepair.OnServerEvent` | Repair resolved; Li Yuen already false |

The condition check inside `injectWuEscortIfReady` is self-guarding — if called when
conditions are not yet met it does nothing, so calling it in all five places is safe.

---

## Behaviour

- The three notifications arrive in the `pendingMessages` of whichever StateUpdate is the
  first one where both Li Yuen and repair flags are clear and `wuPending` is true.
- Apple2Interface consumes the queue (plays all three), then renders the Wu question scene.
- Each notification is dismissible by any keypress, matching the original GOSUB abort-on-keypress.
- After all three drain, the normal Wu question dialog appears.
- `wuEscortBraves` is cleared when the notifications are injected, so they only play once
  even if multiple StateUpdates arrive.

---

## Out of Scope

- No changes to `FinanceEngine`, `Apple2Interface`, `PromptEngine`, or `KeyInput`.
- No new RemoteEvents.
- Other gap items from `apple2_flow_vs_timing_gaps.md` are separate tasks.
