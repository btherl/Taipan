# Combat Animation Sync — Design Spec

**Date:** 2026-05-13
**Scope:** Apple II interface combat-fight flow. Server: `GameService.server.luau` Fight handler. Client: `Apple2Interface.luau`.
**Problem:** On a Fight action, the server delivers `state.pendingMessages` (notif chain) and `state.combat.events` (hit/sink/flee animations) in the same state update. The client auto-drains `combat.events` the moment state arrives, so animations play in parallel with the two intro notifs ("Aye, we'll fight 'em, Taipan!" and "We're firing on 'em, Taipan!"). Flee animations are interleaved with fire animations rather than syncing with the "N ran away, Taipan!" narration that comes later.

## Goal

Tie animations to the notif they belong to, so each animation starts when its narrating message displays — with a small per-notif start delay where useful. Specifically:

| Animation | Sync target |
|---|---|
| Fire (hits + sinks + mid-fight spawns) | "We're firing on 'em, Taipan!" + 0.1 s |
| Flee | "N ran away, Taipan!" + 0 s |
| Future enemy-fire | "They're firing on us, Taipan!" — future work, will use the same substrate |
| Encounter-start spawns | Unchanged — auto-drain on state arrival |
| Run partial-escape flees | Unchanged — auto-drain on state arrival |

## Notif Schema Additions

Three new optional fields on a notif entry consumed by `playNextNotif`:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `animations` | array of `{type, slot}` | — | Events this notif owns. Enqueued into `combatAnimQueue` after the notif's row displays. |
| `animationStartDelay` | number (seconds) | `0` | Wait this long after the notif displays before enqueuing `animations`. |
| `awaitAnimations` | bool | `false` | Pause notif chain **before** displaying this entry until `combatAnimQueue` is empty and not draining. |

The existing `_animationGate` sentinel is retired (one server emit site, one client consume site). The client keeps the leading-sentinel skip loop as a tolerance for older server pushes during dev reloads.

## Server Changes (`GameService.server.luau`, Fight handler)

`CombatEngine.fight` is **unchanged** — it continues to push events to `combat.events` in chronological order (hits → sinks → mid-fight spawns → flees).

The Fight handler partitions `combat.events` at the first `flee`:

- **Fire phase** (everything before the first flee): owned by the "We're firing on 'em" notif.
- **Flee phase** (the flee events): owned by the "N ran away" notif.

Then `combat.events` is cleared so the client's state-arrival auto-drain runs on an empty list (no-op for fights).

```lua
local result = CombatEngine.fight(state, combat)

local fireEvents, fleeEvents = {}, {}
local fleePhase = false
for _, evt in ipairs(combat.events or {}) do
  if evt.type == "flee" then fleePhase = true end
  if fleePhase then table.insert(fleeEvents, evt)
  else                table.insert(fireEvents, evt) end
end
combat.events = {}

local entryFight = makeCombatNotif("Aye, we'll fight 'em, Taipan!", 1)
entryFight.sound = "underattack"
table.insert(pending, entryFight)

local entryFire = makeCombatNotif("We're firing on 'em, Taipan!", 1)
entryFire.sound               = "underattack"
entryFire.animations          = fireEvents
entryFire.animationStartDelay = 0.1
table.insert(pending, entryFire)

-- _animationGate sentinel removed; result entry now self-gates via awaitAnimations.

-- ... result-message construction unchanged ...
resultEntry.awaitAnimations = true
table.insert(pending, resultEntry)

if result.fleeCount > 0 then
  local entry = makeCombatNotif(string.format("%d ran away, Taipan!", result.fleeCount), 2)
  entry.sound      = "badjoss"
  entry.animations = fleeEvents
  table.insert(pending, entry)
end
```

The `noGuns` branch (line 708) is unchanged: it produces no `combat.events`, no animation attachment needed.

## Client Changes (`Apple2Interface.luau`)

**State-arrival auto-drain (lines 388-399): unchanged.** Run partial-escape flees and encounter-start spawns continue to animate immediately on state arrival. Fights produce empty `combat.events`, so the auto-drain is a no-op for them.

**`playNextNotif` additions:**

```lua
playNextNotif = function()
  -- existing leading _animationGate skip loop
  ...

  -- NEW: pre-display gate
  if notifQueue[1].awaitAnimations
     and (combatAnimDraining or #combatAnimQueue > 0) then
    notifWaitingForAnims = true
    return
  end

  notifGen += 1
  local myGen = notifGen
  local entry = table.remove(notifQueue, 1)
  -- ... existing rows display, isCombatNotif detection, prompt setup ...

  -- NEW: schedule animations owned by this entry
  if entry.animations and #entry.animations > 0 then
    local delay = entry.animationStartDelay or 0
    task.delay(delay, function()
      if myGen ~= notifGen then return end
      for _, evt in ipairs(entry.animations) do
        table.insert(combatAnimQueue, evt)
      end
      drainCombatEvents()
    end)
  end

  -- ... existing sound + post-sound delay block from the prior change ...
end
```

The `notifWaitingForAnims` resume path (line 123 in `drainCombatEvents`) is already wired — the new pre-display gate reuses it.

## Risks / Edges

- **`applyEnemyFire` and `combat.events`.** No code path in `applyEnemyFire` currently writes to `combat.events`. A future enemy-fire animation will use the new substrate (attach to "They're firing on us" notif).
- **Skip-before-delay race.** If the player skips the firing notif before `animationStartDelay` (0.1 s) elapses, the scheduled delayed task still enqueues the animations correctly; only stale-generation calls into `notifGen` are guarded. Animations start ~0.1 s after the notif was *displayed*, not after it was skipped — intended semantic.
- **`awaitAnimations` covers only the next entry, not the in-flight one.** The gate fires on the *next* `playNextNotif` call. The in-flight notif's `task.delay(entry.duration)` resolves, `advanceNotif` calls `playNextNotif`, which then pauses on the gate. Correct behaviour.

## Out of Scope

- `CombatEngine` changes (engine still writes to `combat.events`; server splits at handler level).
- Modern interface (doesn't consume combat notif chains).
- Run, Throw, and enemy-fire animations themselves (the latter is future work; this design provides its substrate).
- New tests — engine behaviour unchanged, client UI timing not unit-testable here.

## Verification

User-driven playtest (audio in scope, MCP can't observe):

1. **Multi-enemy fight.** Confirm: "Aye, we'll fight 'em" (sound + 1 s) → "We're firing on 'em" displays → ~0.1 s gap → fire animations begin while sound continues → animations finish → result message displays.
2. **Fight with both sinks and flees.** Verify the "N ran away" message displays in sync with flee animation, after the sunk-count result.
3. **No-guns fight.** Notif chain plays cleanly with no animations.
4. **Run with partial escape.** Flee animations still play via auto-drain. No regression.
