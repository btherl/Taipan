# Tests — TestEZ unit specs

Unit tests for the pure-logic engines in `ReplicatedStorage.shared` and the Apple 2 prompt engine. Run via `TestRunner.server.luau` in Studio's **Run mode** only.

## Running

1. Open the place in Roblox Studio.
2. Click **Run** (the icon next to Play). **Not Play, not Play Here, not Live.**
3. Output appears in the Studio Output panel: `All tests passed (N)` on success, or an error count on failure.

The `IsRunMode()` guard at `TestRunner.server.luau:5` is what gates this. Run mode is unique because the server runs but no player connects — so DataStore/persistence handlers don't fire and ServerScriptService scripts execute in the same process you can inspect. **Tests will not run in Play mode** (would need a player session) **or on a published Live server** (and shouldn't).

`TestRunner` errors out (causing red text in Output) if any spec fails — use the failure count and stack traces in Output to triage.

## Spec file naming

Two patterns work because `TestEZ.TestBootstrap:run({ folder })` recurses:

- **Flat** — `Tests/<Module>.spec.luau`. The dominant pattern. Used for every shared engine plus `BoxDrawing`.
- **Sub-folder** — `Tests/<Module>/spec.luau`. Currently used only for `PromptEngine/spec.luau`. The sub-folder lets you split one module's tests across multiple files (e.g. `PromptEngine/spec_combat.luau`, `PromptEngine/spec_bank.luau`) if any spec grows unwieldy. We haven't needed that yet — the sub-folder exists in case we do.

Spec files return a function that contains `describe`/`it`/`expect` blocks (the standard TestEZ shape):

```lua
return function()
  describe("MyEngine.thing", function()
    it("does the expected thing", function()
      expect(MyEngine.thing(input)).to.equal(expected)
    end)
  end)
end
```

## Require paths

Most specs require their target from `ReplicatedStorage.shared`:

```lua
local Constants = require(game:GetService("ReplicatedStorage").shared.Constants)
```

The exception is `PromptEngine/spec.luau`, which requires from `StarterGui` because PromptEngine is a UI module:

```lua
local PromptEngine = require(game:GetService("StarterGui").TaipanGui.GameController.Apple2.PromptEngine)
```

That works because in Run mode `StarterGui` contents have already been mounted. If you add UI-side specs in future, follow the same pattern — and confirm the module doesn't yield or touch `RunService` on require, or the test will hang.

## `mockActions()` fixture

`PromptEngine/spec.luau` defines a local `mockActions()` (lines 4–21) — a stub of every `actions.<remote>` callback the prompt engine could invoke. When you add a new client-fired action to `GameActions.luau`, add a matching `<name> = function() end` entry here so existing prompt-engine tests don't crash on `attempt to call a nil value`.

The fixture is currently inlined; if a second UI spec ever needs it, factor it into a sibling helper module rather than duplicating.

## What the tests cover

Each engine's spec covers its public surface — pricing, validators, time-advance, combat resolution, etc. The PromptEngine spec covers scene dispatch (which scene returns for a given state). **The tests do not cover**:

- Server remote handlers (those need a player session — not unit-testable in Run mode).
- The Apple 2 round timer state machine in `Apple2Interface.luau` (involves `task.delay` and is hard to test deterministically).
- DataStore persistence end-to-end (skipped in Studio per the server's `IsStudio()` guard).

End-to-end coverage of UI-driven flows is via the **MCP Studio playtesting** procedure documented in the project root `CLAUDE.md`, not here.

## Adding a new spec

1. Create `Tests/<NewModule>.spec.luau`.
2. Require the module under test from its actual location (`ReplicatedStorage.shared.X` or `StarterGui...`).
3. Wrap in `return function() describe(...) end`.
4. Run in Studio Run mode and confirm the new test count appears in the success line.

If your module yields, touches `RunService`, or creates `Instance`s, it's not pure-logic — see `ReplicatedStorage/shared/CLAUDE.md` for what does and doesn't belong in a unit-testable module.
