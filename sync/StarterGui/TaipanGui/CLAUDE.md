# TaipanGui — StarterGui mount notes

This folder maps to a `ScreenGui` named `TaipanGui` under `StarterGui`. At runtime it is cloned to `Players.LocalPlayer.PlayerGui.TaipanGui` (the path used for MCP UI playtesting).

## Bootstrap (`GameController.client.luau`)

This is a LocalScript parented to the `TaipanGui` ScreenGui. On client start it:

1. Creates a separate `Backdrop` ScreenGui at `PlayerGui.Backdrop` (full-screen black, `DisplayOrder = -10`) to hide the 3D world. PlayerGui therefore holds **two** ScreenGuis at runtime: `TaipanGui` (this folder's contents) and the runtime-created `Backdrop`.
2. Points the camera up at `(0, 1e6, 0)` so nothing leaks through transparent UI.
3. Shows `InterfacePicker` immediately — no wait for the first `StateUpdate`.
4. On selection, destroys the picker and constructs either `Apple2Interface` or `ModernInterface`, storing it as `currentAdapter`.
5. Wires `Remotes.StateUpdate` and `Remotes.Notify` to call `currentAdapter.update(state)` / `currentAdapter.notify(message)`.

The `currentAdapter` upvalue is **forward-declared** before assignment — Roblox can fire `Activated` synchronously inside `InterfacePicker.new`, so a `local currentAdapter = InterfacePicker.new(...)` would leave the callback closing over a nil. Don't refactor that pattern away.

## Programmatic UI

Nothing is authored in Studio under this folder. The `Root` frame and all child UI are created by whichever interface adapter is active. To find runtime instances during MCP playtesting, search under `Players.LocalPlayer.PlayerGui.TaipanGui.Root.<PanelName>` — they exist only in Play mode.

## Sub-folder notes

- `GameController/` — contains the adapters, the action wiring, and the Apple 2 sub-modules. See `GameController/CLAUDE.md` for the file split and the combat-input divergence between Apple 2 and Modern.
- `GameController/Apple2/` — terminal emulator and prompt engine. See `GameController/Apple2/CLAUDE.md` for the row layout, notification system, and combat round timing.

## Server-driven state

The interfaces are read-only displays. All mutations happen on the server in `ServerScriptService/GameService.server.luau`; the client only fires action remotes (wired in `GameController/GameActions.luau`) and re-renders on `StateUpdate`. Don't introduce client-side game state here.
