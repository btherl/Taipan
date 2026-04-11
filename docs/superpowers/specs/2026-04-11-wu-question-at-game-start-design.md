# Design: Wu Question at Game Start

**Date:** 2026-04-11
**Status:** Approved

## Summary

When a new game begins (after the player selects cash+debt or guns start), the player should be asked "Do you have business with Elder Brother Wu?" — the same prompt that already fires on every Hong Kong arrival via TravelTo.

## Background

The Wu question infrastructure is fully implemented:
- `sceneWuQuestion` in `PromptEngine.luau`
- `wuQuestion` SERVER_SCENE in `Apple2Interface.luau`
- `processState` routing: `state.wuPending == true` at HK → `sceneWuQuestion`
- `ConfirmWu` / `DeclineWu` server handlers in `GameService.server.luau`
- `state.wuPending = true` already set in the `TravelTo` handler on HK arrival (line 270)

The only gap: `wuPending` is never set when a new game is created via `ChooseStart`.

## Change

**File:** `sync/ServerScriptService/GameService.server.luau`
**Location:** `ChooseStart` handler, after `GameState.newGame(startChoice, firmName)` and the derived-field calculations.

Add:
```lua
state.wuPending = true
```

## Scope

- Apple2 interface: Wu question prompt fires automatically at game start.
- Modern interface: no change — WuPanel is always visible at HK.
- `wuPending` is ephemeral (not persisted), so it only fires on the two explicit triggers: game start and HK arrival via travel.
