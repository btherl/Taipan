# Apple II Mobile Input Layout — Design

**Date:** 2026-06-27
**Status:** Approved (pending implementation plan)
**Scope:** Apple II interface only. Mobile/touch on-screen input.

## Problem

On mobile, the Apple II interface's on-screen input lands on top of the terminal,
hiding the content the player needs to see:

1. **Key-button row in landscape.** The 60px button row (e.g. `B`/`S`/`Q` at port)
   is docked to the bottom of the screen. In landscape the 16:9 terminal canvas
   fills the full screen height, so the row overlaps the bottom terminal rows —
   covering roughly half of row 21 through row 24, including the price table and
   the prompt line. The player can't see what they're choosing.

2. **Native soft keyboard for numeric entry.** Buy/sell amounts, Wu repay/borrow,
   and bank deposit/withdraw use a hidden `TextBox` whose `:CaptureFocus()` summons
   the OS keyboard. Every numeric prompt echoes on terminal rows 19–23 (the very
   bottom of the canvas), which is exactly where the keyboard covers — in **both**
   orientations. The player can't see the number they're entering. The keyboard's
   size and position are OS-controlled, so we can't move it out of the way.

## Geometry (why placement is the fix)

The terminal renders in a 16:9 `AspectRatioConstraint` canvas (1920×1080 virtual),
centered in the viewport. The 40-column text occupies ~80% of the canvas width
(40 × `14*2.7` px + a 30px left margin ≈ 1542 / 1920), leaving the right ~20% empty.

- **Portrait** (taller than 16:9): the canvas is width-constrained, so it's a short
  strip centered vertically (~26% of screen height on a 9:19.5 phone), leaving a
  large empty letterbox band (~37% of height) **below** it. Ample room for a keypad.
- **Landscape** (wider than 16:9): the canvas is height-constrained, fills full
  height, side pillarbox bars ~9% each. Combined with the empty right ~20% of the
  canvas, there is a usable empty **right strip**; the bottom is fully occupied by
  the prompt rows.

Conclusion: place on-screen input in the empty space, chosen by orientation —
bottom in portrait, right strip in landscape — rather than always docking to the
bottom.

## Approach

Orientation-aware placement of all mobile on-screen input, plus a custom numeric
keypad that replaces the native keyboard so we fully control its size and position.

Alternative considered and rejected: shrink the terminal above a reserved input
band. It guarantees zero overlap but is invasive (terminal needs dynamic resize),
shrinks the text, and resizes jarringly each time a prompt opens.

All changes are contained in:
- `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau` (layout + keypad)
- `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (expose
  `maxValue` on the four capped numeric prompts)

## Components

### 1. Orientation detection & live relayout (shared, in KeyInput)

- A helper determines orientation from `workspace.CurrentCamera.ViewportSize`:
  portrait if `ViewportSize.Y >= ViewportSize.X`, else landscape.
- Whenever a mobile control container (key row or keypad) is active, a layout
  function positions it per orientation.
- A `workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")` connection
  re-runs the layout function so rotating mid-prompt re-flows the controls live.
- The connection is stored in the existing `connections` table (or torn down in
  `cleanup()`) so it is disconnected when the prompt ends.
- This composes with the existing focus-recapture fix on the firm-name TextBox
  (which re-opens the keyboard after an orientation-induced focus loss).

### 2. Key-button row — issue 1

`buildMobileButtons` becomes orientation-aware. (This automatically covers the
`singlechar` mobile path, which reuses `buildMobileButtons`.)

- **Portrait:** horizontal row docked to the bottom — unchanged from current
  behaviour.
- **Landscape:** vertical column docked to the **right edge**, sized to the empty
  right strip, clear of the prices (left columns) and the prompt rows.
- Re-lays out on `ViewportSize` change.

### 3. Numeric keypad — issue 2

Replaces the hidden `TextBox` / native-keyboard path in the `numeric` mobile branch
of `KeyInput.setPrompt` with a keypad we draw:

```
[ 7 ][ 8 ][ 9 ]
[ 4 ][ 5 ][ 6 ]
[ 1 ][ 2 ][ 3 ]
[ALL][ 0 ][ <- ]
[     OK / ENTER     ]
```

- Digit buttons append to the **existing** `typeBuf`; `<-` deletes the last digit;
  `maxDigits` is respected (digit beyond limit → beep, matching desktop).
- The keypad drives the existing `updateDisplay()` / blink logic, so the number
  still echoes on the terminal input row (23 for buy/sell, 19–20 for finance) and
  the blinking cursor still works.
- `OK / ENTER` submits via `promptDef.onType(typeBuf, state, actions)` — the same
  path Enter uses on desktop — so all existing validation is untouched
  (over-cash / over-cargo / over-balance beep-and-stay behaviour is preserved).
- Placement is orientation-aware like the key row: bottom block in portrait, right
  grid in landscape, kept clear of the prompt echo. Lives in its own
  high-`DisplayOrder` ScreenGui, like the existing `MobileKeyGui`.
- The hidden `TextBox` is no longer created for `numeric` prompts on mobile.

### 4. ALL button

- Add an optional `promptDef.maxValue` (a number) to numeric prompt definitions.
- The four capped numeric scenes in `PromptEngine.luau` set it from values they
  already compute:
  - buy → `affordable`
  - sell → `cargoAmt`
  - bank deposit → `maxDeposit`
  - bank withdraw → `maxWithdraw`
- The keypad renders the **ALL** button only when `maxValue` is present. Tapping it
  fills `typeBuf` with `tostring(maxValue)` (truncated to `maxDigits` if needed).
- Numeric prompts with no natural cap (e.g. Wu borrow, Li Yuen amount) omit
  `maxValue` and show no ALL key.

### 5. Scope / unchanged

- The `type` prompt (firm-name entry) keeps the native keyboard plus the existing
  focus-recapture fix. Revisited later, out of scope here.
- Desktop input paths (`key`, `singlechar`, `type`, `numeric`) are untouched.
- `key` / `singlechar` desktop behaviour unaffected; their mobile rows inherit the
  orientation fix via `buildMobileButtons`.

## Testing

Manual, on-device only — this is runtime UI and MCP playtesting cannot reproduce
device orientation.

- Rotate mid-entry in both orientations; confirm controls re-flow and the typed
  value/prompt remains visible.
- Buy, sell, bank deposit, bank withdraw, Wu repay/borrow: enter amounts via the
  keypad; confirm the echo on the terminal row updates.
- ALL fills the correct maximum; `<-` deletes; OK submits.
- Over-max entry still beeps and stays on the prompt (unchanged validation).
- `maxDigits` limit still beeps.
- Key-button row (B/S/Q) no longer covers the prices/prompt in landscape; still a
  bottom row in portrait.

No automated tests: the engine modules are unchanged, and the changed code is
Roblox-runtime UI.
