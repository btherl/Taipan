# Mobile Native-Keyboard Canvas Shift — Design

**Date:** 2026-06-28
**Status:** Approved, ready for implementation plan
**Scope:** Apple II interface, client UI only (no server / no game logic changes)

## Problem

When the player enters their Firm Name at game start (Apple II interface), the
mobile native soft keyboard slides up from the bottom of the screen and covers
the terminal input row (row 14 of 24), so the player cannot see the name as they
type it.

This was the last unresolved case of the "mobile on-screen inputs overlapping
the game screen" class of bugs. All other cases were already fixed — notably the
**numeric** prompts, which avoid the problem entirely by replacing the native
keyboard with a custom on-screen keypad docked into the safe area
(`buildMobileKeypad` in `KeyInput.luau`).

The firm-name prompt is the only Apple II input that still summons the **native**
keyboard: it is a `type` prompt, and on mobile the `type` branch
(`KeyInput.luau:512`) spawns a hidden 1x1 `TextBox`, calls `:CaptureFocus()` to
raise the OS keyboard, and mirrors the typed text onto terminal row 14.

## Decision

Keep the native keyboard (it gives free autocorrect, caps, and symbol entry —
the right UX for a name field). Instead of relocating the echo, **move the entire
terminal canvas up** while a mobile text-entry prompt is active, so the whole
game screen occupies the top portion of the viewport and the keyboard has room
beneath it.

Apply this to **all** mobile native-keyboard `type` prompts, not just firm-name,
so any future text field benefits. (Firm-name is the only such prompt today.)

## Mechanism

The terminal canvas (`TextParent`, created in `Text.luau:92-99`) is a Frame
anchored at center with a 16:9 `UIAspectRatioConstraint`:

| Property | Normal value |
|---|---|
| `AnchorPoint` | `(0.5, 0.5)` |
| `Position` | `UDim2.fromScale(0.5, 0.5)` |
| `Size` | `UDim2.fromScale(1, 1)` |

While a mobile `type` prompt is active, change it to top-docked, half-height:

| Property | Active value |
|---|---|
| `AnchorPoint` | `(0.5, 0)` |
| `Position` | `UDim2.fromScale(0.5, 0)` |
| `Size` | `UDim2.fromScale(1, 0.5)` |

The aspect-ratio constraint fits the largest 16:9 rectangle inside the resulting
box, which handles **both orientations with one change**:

- **Portrait:** the canvas is already width-constrained (height = width x 9/16,
  roughly 25% of a tall phone screen), so the half-height box does not shrink it
  further — it simply snaps to the top. Row 14 lands high and stays clear of the
  keyboard.
- **Landscape:** the canvas is normally height-constrained (fills full height).
  The half-height box forces the constraint to shrink the canvas to the top half
  and center it horizontally, clearing the keyboard.

Because these are **scale** values, Roblox recomputes the layout automatically on
orientation change — no manual re-flow is needed (unlike the numeric keypad,
which positions real `TextButton` instances and must re-flow on
`ViewportSize` change).

We do **not** need to know the keyboard's height (Roblox exposes no API for it).
Top-docking simply vacates the bottom of the screen; as long as the canvas fits
above the keyboard, the input is visible. The `0.5` height fraction is a single
tunable constant.

## Implementation Location

`KeyInput.luau`, the mobile `type` branch (`KeyInput.luau:512`, inside
`ki.setPrompt`).

- On entry: resolve the canvas via `terminal._gui.TextParent` (the `type` branch
  already has `terminal = promptDef._terminal`). Save the three original property
  values, then apply the docked values.
- Store a small `restoreCanvas()` closure (an upvalue) that writes the saved
  values back.
- Call `restoreCanvas()` from the existing `cleanup()` so the canvas reverts on
  prompt end, submit, or focus loss. `cleanup()` already runs on every
  `setPrompt` transition and on `destroy()`.

No new remotes, no server changes, no game-logic changes.

## Explicitly Out of Scope / Deferred

- **Tween on the shift.** Start with a snap (simplest). A short (~0.15s) tween can
  be added later if the snap feels abrupt.
- **Black background below the vacated canvas.** The full-screen `Background`
  frame is a child of `TextParent`, so it shrinks with the canvas; the vacated
  lower area shows whatever is behind the terminal gui. At firm-name time that is
  the game-start screen. Treat "does the lower area still read as black?" as a
  **device-verify** check. Only if it looks wrong do we add a separate
  viewport-filling black frame — not built speculatively.

## Verification

- Live-client check (per the "Apple2 canvas letterbox" gotcha — vertical layout
  bugs do not reproduce in Studio's letterboxed viewport):
  - Portrait: firm name visible above the keyboard as typed.
  - Landscape: canvas shrinks to top half, firm name visible above the keyboard.
  - Rotate mid-entry: layout adapts without manual re-flow; focus is re-captured
    (existing `FocusLost` handler).
  - Canvas returns to centered/full size after submit.
  - Lower (vacated) area reads as black, or note that the extra background frame
    is needed.
