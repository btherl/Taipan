# GameController Module Notes

This folder holds the client-side controller that orchestrates the player UI. The split is:

| File | Role |
|---|---|
| `GameController.client.luau` (parent dir) | LocalScript entry point. Builds the `actions` table from `GameActions.luau`, picks an interface (Apple 2 / Modern) via `InterfacePicker`, and forwards `Remotes.StateUpdate` / `Remotes.Notify` to whichever interface is active. |
| `GameActions.luau` | **Source of truth for client->server action wiring.** Every `actions.<name>` is a thin `Remotes.<X>:FireServer(...)` wrapper. To add a new client-initiated action, add an entry here, not in `GameController.client.luau`. |
| `InterfacePicker.luau` | First-load screen that lets the player choose Apple 2 or Modern. Persists the choice via `actions.setUIMode`. |
| `Apple2Interface.luau` | Adapter for the retro terminal interface. Owns the `Terminal`, `KeyInput`, `PromptEngine`, and `GlitchLayer` instances; implements `{ update(state), notify(message), destroy() }`. |
| `ModernInterface.luau` | Adapter for the modern GUI; constructs the `Panels/` and routes state updates to each. |
| `Apple2/` | Apple II sub-modules (see `Apple2/CLAUDE.md` for details on the terminal, prompt engine, key input, glitch layer). |
| `Panels/` | Modern interface panels. |

## Interface contract

Both `Apple2Interface.new(screenGui, actions)` and `ModernInterface.new(...)` return an adapter table with:
- `update(state)` — called by `GameController.client` on every `Remotes.StateUpdate`.
- `notify(message)` — called on `Remotes.Notify` (Modern displays it; Apple 2 ignores text notifications and uses `state.pendingMessages` instead).
- `destroy()` — tears down the interface; called when switching modes.

## Combat input divergence

The two interfaces handle combat F/R/T differently:

- **Modern** (`Panels/CombatPanel.luau`) — pressing Fight/Run/Throw fires the corresponding remote (`actions.combatFight/Run/Throw`) **immediately**. One press = one server round.
- **Apple 2** (`Apple2Interface.luau` round timer) — F/R/T only updates a queued command; an internal tick loop fires the remote at end of phase A or B (see `Apple2/CLAUDE.md` "Round timing"). The Apple 2 stack is also the only caller of `actions.combatNoCommand`.

If you add new combat actions, wire them in `GameActions.luau`. The Modern panel can call them directly; the Apple 2 stack must route them through the round timer in `Apple2Interface.luau`.
