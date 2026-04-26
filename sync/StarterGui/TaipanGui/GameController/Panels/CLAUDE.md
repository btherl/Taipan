# Modern UI Panels

Each `*.luau` file here is a single panel module for the Modern interface. They are constructed by `ModernInterface.luau`, never required directly by `GameController.client.luau`. Layout positions, ZIndex layering, touch-target sizes, the colour palette, and the `.update(state)` contract are documented in the root `CLAUDE.md`'s "GUI System" and "Coding Conventions" sections — don't re-document those here.

Notes specific to working in this folder:

## Constructor signature

```
PanelName.new(parent, ...callbacks) -> { update(state), [show(message)], [destroy()] }
```

- `parent` is the `Root` Frame built by `ModernInterface`. Every panel parents its top-level `Instance.new("Frame")` to it.
- Callbacks are passed positionally and forward to `actions.<remote>`. Wiring lives in `ModernInterface.luau:67-71`-style blocks; if you add a new panel callback, both the panel constructor and the wiring block need updating.
- `update(state)` is required on every panel. `show(message)` exists only on `MessagePanel`. `destroy()` is rare; most panels live for the session.

## `latestState` capture pattern

Buttons handle clicks asynchronously and need access to the most recent state — particularly for "A = all" amount resolution. The convention is:

```lua
local latestState = nil
-- ...build buttons with closures that read latestState...
function panel.update(state)
  latestState = state
  -- update labels/visibility from state
end
```

The `latestState` upvalue is captured by every `Activated` connection so a click after the most recent `StateUpdate` resolves "A" against fresh data. Keep this pattern when adding amount-input panels.

## HK-only visibility

`WarehousePanel`, `WuPanel`, `BankPanel`, and `ShipPanel` are constructed unconditionally but **self-hide** based on state inside their own `update`. The convention is:

```lua
function panel.update(state)
  frame.Visible = state.currentPort == Constants.HONG_KONG and ...other guards...
  if not frame.Visible then return end
  -- update child elements
end
```

`ModernInterface.luau` doesn't gate construction by port. If you add a new HK-only panel, follow the same pattern — don't try to destroy/recreate panels on travel.

## Overlay panels

`MessagePanel`, `ShipPanel`, `CombatPanel`, `GameOverPanel`, `StartPanel` are overlays with explicit ZIndex (see root `CLAUDE.md`). They sit absolutely over the column. Their `update` typically toggles `frame.Visible` based on a state field (`state.combat`, `state.shipOffer`, `state.gameOver`, etc.) rather than always-on.

## Combat panel divergence vs Apple 2

`CombatPanel.luau` fires `actions.combatFight()`, `actions.combatRun()`, `actions.combatThrow(g, q)` **immediately** on button press. The Apple 2 stack uses a tick-driven round timer (see `Apple2/CLAUDE.md` "Round timing") — the Modern panel does **not** participate in that timer and never fires `actions.combatNoCommand`. If you change combat behaviour, decide explicitly whether the change applies to one interface or both, and remember the project's stated focus on Apple 2 (see root `CLAUDE.md`).

## Touch targets

Per root convention, interactive buttons are minimum 44px tall (mobile-friendly). The four-good selector in `BuySellPanel` uses `UDim2.new(0.22, -4, 0, 44)` — copy that sizing for new panels.
