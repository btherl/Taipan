# ServerScriptService — the server

This folder holds the authoritative game server. There's effectively one file that matters: `GameService.server.luau` (~1000 lines, Roblox classifies it as a `Script` not a ModuleScript). The `Tests/` folder is unrelated to runtime — it's the TestEZ harness, see `Tests/CLAUDE.md`.

The "all mutations happen here" discipline that the project root `CLAUDE.md` describes is enforced by this single file. Treat it as the only legitimate writer to player state.

## File layout (top to bottom)

1. **Service requires + shared module imports** (lines 1–18). Pulls in everything from `ReplicatedStorage.shared` plus `Remotes`.
2. **Notification builders** (lines 20–86). Helpers that construct entries for `state.pendingMessages`. **Use these — do not hand-build row tables**. Builders:
   - `makeLowerNotif(title, lines, duration)` — fills rows 17–24 with a titled report block.
   - `makeCaptainNotif(lines, duration)` — wraps `makeLowerNotif` with title `"  Captain's Report"`.
   - `makeCompradorNotif(lines, duration)` — wraps with title `"Comprador's Report"`.
   - `makeCombatNotif(line, duration)` — single-line entry on row 4 only.
   - `makeStatusScreenLowerNotif(title, lines, duration)` — like `makeLowerNotif` but also redraws the lines 1–16 port status screen on the client first. Use for combat-end messages (booty / escape / sunk) that follow the BASIC convention of returning to the status screen before reporting.
   The choice between Captain/Comprador/Combat is enforced by `Apple2/CLAUDE.md` — read it before adding a new notification site.
3. **DataStore + persistence helpers** (lines 88–113). `savePlayer` / `loadPlayer` skip when `RunService:IsStudio()` is true, so persistence only fires on real Roblox servers. Wraps `PersistenceEngine.dataStoreRetry` for exponential backoff.
4. **`playerStates`, `pendingModes`, `pendingTutorialSeen` tables** (lines 95–97). Server-private state. Never exposed to clients except via snapshot.
5. **`pushState(player)`** (line 115). The single broadcast point. Guards `type(state) == "table"` to handle the boolean sentinel during DataStore load.
6. **Input validators** (`validGood`, `validQty`, etc., line 122+). Use these at the top of every remote handler.
7. **Remote handlers** (line 129+, the bulk of the file). One handler per `Remotes.X.OnServerEvent`.

## Critical patterns

### `pushState` discipline

Every remote handler ends with `pushState(player)`. Never mutate state without pushing — clients silently drift. Even on validation failure, push (so the client's optimistic UI re-syncs to truth).

### Sentinel for async load

When `ChooseStart` fires for a player whose data is being loaded, the slot may temporarily hold the boolean `true` (or `false`) instead of a state table. Every handler opens with:

```lua
local state = playerStates[player]
if type(state) ~= "table" then return end
```

This silently drops requests that arrive during the load yield. Don't replace this guard with `if not state` — the boolean sentinel would pass that check.

### `state.pendingMessages` pattern

To deliver a sequence of row-4 / row-17–24 messages to the client, build a `pending = {}` array of notif entries, then:

```lua
state.pendingMessages = pending
pushState(player)
state.pendingMessages = nil
```

The set/push/clear dance is intentional — `pendingMessages` is **ephemeral** (not persisted), and clearing after push prevents the same messages from replaying on a later state read. `PersistenceEngine.serialize` strips it anyway, but defensive clearing is the convention.

### Combat post-action helpers

Combat handlers (`CombatFight`, `CombatRun`, `CombatThrow`, `CombatNoCommand`) follow a fixed shape:

1. Validate state and combat exist.
2. Call the combat-engine action (`CombatEngine.fight` / `attemptRun` / `throwCargo`) which mutates `state.combat` and returns whatever was computed.
3. Push action narration into `pending` via `makeCombatNotif`.
4. If combat hasn't ended, call `applyEnemyFire(player, state, combat, pending)` — signature is **player-first**, despite reading like an internal helper.
5. After enemy fire, check `combatEnded` outcome. If victory/fled/Li Yuen-saved/sunk, call `appendArrivalPending` to splice in any post-combat travel events.
6. `state.pendingMessages = pending; pushState; clear`.

`applyEnemyFire` itself handles `combat.outcome = "sunk"` and `combat.outcome = "liYuen"` and pushes its own `makeCombatNotif`s into `pending`. Don't duplicate that logic in callers.

### `IsStudio()` skips persistence

DataStore reads/writes are silently skipped when `RunService:IsStudio()` returns true. **This is intentional** — playtesting in Studio shouldn't pollute the production DataStore. If you need to test persistence specifically, run in Roblox's Team Test or a published place. Don't remove the guard.

## What does NOT belong here

- Pure logic — put it in `ReplicatedStorage/shared/` (engines, validators, BASIC ports). The server is the orchestrator, not the calculator.
- Client UI logic — `StarterGui/TaipanGui/GameController/`.
- Long-lived per-player coroutines for combat ticking, etc. — combat is currently client-driven on Apple 2 (see `StarterGui/.../GameController/CLAUDE.md`). The server is reactive: one round per remote call.
- Tests — `Tests/`.

If `GameService.server.luau` ever splits, the natural seams are: connection lifecycle (`PlayerAdded`/`PlayerRemoving` + DataStore), the remote-handler bank (one per Remote), and the notif builders (could move to a `shared/Notifications.luau` if needed). It hasn't split yet because the file is still readable as a single artifact.
