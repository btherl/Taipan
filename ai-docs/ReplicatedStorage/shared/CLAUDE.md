# shared/ — pure-logic engines

This folder holds the game's pure-logic modules: `Constants`, `GameState`, `PriceEngine`, `Validators`, `TravelEngine`, `FinanceEngine`, `EventEngine`, `CombatEngine`, `ProgressionEngine`, `PersistenceEngine`. The per-module purpose table lives in the root `CLAUDE.md` under "Engine Modules" — don't re-document that here.

Notes specific to working in this folder:

## "Shared" is about replication, not state

The folder lives in `ReplicatedStorage`, so the **code** in here is replicated to every client (and recoverable from any decompiled Roblox client). That does **not** mean the **state** is shared — `playerStates[player]` is a server-private table in `GameService.server.luau`. Clients only ever see immutable snapshots via `Remotes.StateUpdate:FireClient`. The security boundary is the remote-handler input validation in `GameService.server.luau`, not the location of these modules.

In practice:
- Server `require`s every engine here and orchestrates them.
- Client `require`s `Constants` (port names, good names, price scale, HK index) for read-only display.
- Client should **not** `require` the mutating engines (`Travel`, `Finance`, `Combat`, etc.) — there's nothing client-side they can do with them, and pulling them in just bloats the client require graph.

## Pure-logic contract — load-bearing

Every module here must satisfy:

1. **No Roblox service calls.** No `game:GetService(...)` other than `require(...)` of sibling shared modules. No yields, no `task.wait`, no `RunService` connections, no `Instance.new`.
2. **No instance creation.** These modules return tables of values; they never produce GUI or world objects.
3. **In-place state mutation.** Engines take a `state` table and **mutate it directly**. They do not return new state. The caller (`GameService.server.luau`) holds a single `state` table per player and pushes a snapshot after each mutation. This is what makes a single `pushState(player)` after a handler reflect every change made by every engine call inside it.

Together, these constraints are what make the modules testable from `TestEZ` specs in Studio Run mode without a live game session, and what allow `PersistenceEngine` to round-trip state through `DataStoreService` cleanly.

## State schema — read root CLAUDE.md

The state table's canonical fields, derived fields, and ephemeral fields are listed in the root `CLAUDE.md` under "Game State". When adding a new field:
- Decide whether it's canonical (persisted via `PersistenceEngine`), derived (recomputed on load/arrival), or ephemeral (not persisted).
- Update both the root `CLAUDE.md` table and `PersistenceEngine` if canonical.

## BASIC fidelity

Many functions match the original Apple II BASIC line-for-line. The convention is to cite the BASIC line numbers in comments, e.g. `-- BASIC line 5060`. The annotated source is at `references/BASIC_ANNOTATED.md`. When porting new BASIC behaviour or fixing a divergence, keep the citation so future readers can verify against the original.

The `fnR(x)` helper that appears across multiple engines reproduces BASIC's `FN R(X) = INT(RND(1)*X)`:

```lua
local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end
```

It's defined per-module rather than centralised — keep it that way (cheap, makes each engine self-contained).

## What does NOT belong here

- UI rendering or anything that touches `StarterGui`/`PlayerGui` instances.
- Server-only logic that needs to yield, e.g. `DataStoreService:GetAsync` retry loops with `task.wait`. (`PersistenceEngine.luau` is the boundary case: its serialise/deserialise are pure, but the actual DataStore call with retries lives in `GameService.server.luau`.)
- Scene/flow logic for the Apple 2 prompt engine — that's in `StarterGui/.../Apple2/PromptEngine.luau`.
- Anything that needs `RunService` heartbeats — round timing, animation, etc.

If a piece of logic needs Roblox services or yields, it lives in `ServerScriptService` (server) or under `StarterGui/.../GameController/` (client) — not here.
