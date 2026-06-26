# Design: Apple II Input Beeps

**Date:** 2026-06-26
**Status:** Approved
**Scope:** Apple II interface only

## Problem

The original Apple II Taipan! plays a plain system beep when the player enters
invalid input. Our research (`references/original-apple2-beeps.md`) found the BASIC
source only invokes the beep (`CALL 2524`) at two *submit-time* semantic rejections —
buy-can't-afford and sell-more-than-held. But emulator testing revealed a second,
larger class of beeps that never appears in the BASIC: the keyboard-read routine
(`CALL 2680`, the input ML routine) beeps internally on every invalid keystroke. That
is why those beeps are invisible in the BASIC listing — they live inside the input
routine, not in game logic.

Our game currently plays **no** beep for any of this. When the player types an
over-limit amount, our buy/sell handler silently clears the input and re-prompts
(faithful to the original's re-prompt, but missing the beep). Invalid keystrokes at
menus and during amount entry are silently ignored. This work adds the beep across
both layers.

This supersedes a deferred Non-Goal from `2026-06-25-local-event-sounds-design.md`,
which postponed the buy/sell over-limit case and incorrectly stated it played
`good_joss`. It played the beep (`CALL 2524`). That spec's stale note will be
corrected as part of this work.

## Source of Truth

- `references/original-apple2-beeps.md` — the `CALL 2524` catalog (submit-level beeps).
- Emulator observation (recorded by the user) — the keyboard-routine beep behavior,
  which is not derivable from the BASIC source:
  - **Single-character inputs** (menus, good selection): invalid key clears any
    pending entry and beeps; a valid key displays with no sound, even when repeated.
  - **Multi-character inputs** (amount entry): beep on an invalid character, and on
    entering a digit once max length is reached. Left-arrow deletes the most recent
    character, or beeps if the buffer is empty.
  - **Port selection**: beeps on invalid input.
  - **Combat**: the fight/throw/run main loop has its own special handling and does
    **not** beep on invalid key. The throw sub-prompts (which goods, how much) *do*
    beep like ordinary inputs.

## The Sound

`beep` is already registered in `sync/ReplicatedStorage/Sounds.luau`
(`rbxassetid://110935510356277`). `SoundPlayer` auto-creates a template for it, so it
is playable via `SoundPlayer.play("beep")`. No new assets.

## Architecture

Two beep layers, both using the `beep` sound.

### Layer 1 — input-routine beeps (`KeyInput.luau`)

This is the main work and the new center of gravity. `KeyInput` is the single place
all keyboard input flows through, so the beep belongs here — faithful to the original,
where the beep lived in the shared input routine rather than in any one prompt.

- `KeyInput` requires `SoundPlayer` and plays the beep with
  `task.spawn(function() SoundPlayer.play("beep") end)` — `SoundPlayer.play` blocks
  (it polls until the sound ends or a deadline), so it must be spawned, exactly as
  `Apple2Interface.luau:85` already does.
- A `promptDef.noBeep == true` flag suppresses all Layer-1 beeps for that prompt.
- Only the **desktop** (physical keyboard) paths beep. Mobile virtual buttons expose
  only valid keys, and the mobile numeric box filters non-digits, so invalid input is
  largely impossible there — no mobile changes.
- **Modifier-only keypresses never beep.** Shift / Ctrl / Alt / Caps Lock / Super
  produce no character; beeping on them would be jarring and unfaithful. They are the
  sole exception — every other rejected keypress beeps.

### Layer 2 — submit-level over-limit beep (`PromptEngine.luau`)

Distinct from Layer 1: the player can type affordable-looking digits (no character-
level rejection), press Return, and only then fail the affordability/quantity check.
This is the original `CALL 2524` submit beep.

- `sceneBuySellAmount` gains a `playSound` parameter (matching `sceneFirmName`'s
  existing convention, `PromptEngine.luau:464`).
- The buy branch (`qty * price > cash`) and sell branch (`qty > cargoAmt`) call
  `playSound("beep")` before re-prompting. The existing silent-clear / re-prompt
  behavior is otherwise unchanged (no message, no scene change — faithful to the
  original, which just beeps and re-asks).
- The two dispatch sites (`PromptEngine.luau:1596`, `:1600`) pass `playSound` through.
- `playSound` is already constructed in `Apple2Interface` (`:85`) and already passed
  into `PromptEngine.processState` (`:317`). No `Apple2Interface` change is needed for
  Layer 2.

## Beep Rules per Input Type (desktop)

`KeyInput` has four prompt types. Each gains beeps at its rejection points. Unless a
prompt sets `noBeep = true`, these apply.

### `key` (immediate-fire menus: port-sail, Wu menu, yes/no, combat main loop)

- **Beep:** any rejected key — one not in the valid set — including navigation keys
  (arrows, etc.), which are genuine invalid-input attempts at a menu.
- **No beep:** a valid key (fires `onKey` immediately, no Enter); modifier-only keys.
- No buffer / no Enter step, so there is no "clear previous entry" concept here.

### `singlechar` (buy/sell good selection P/S/A/G, and similar)

- **Beep:** an invalid character. The existing behavior of clearing the stored char
  on invalid input is retained; the beep is added alongside it.
- **No beep:** a valid character (displays; replacing/repeating a valid char is
  silent); modifier-only keys; Backspace (clears the stored char — a valid edit).

### `numeric` (all amount entry: buy/sell, bank, Wu, warehouse)

- **Beep:** a non-digit character key; a digit pressed when the buffer is already at
  `maxDigits`; **Left-arrow or Backspace pressed on an empty buffer.**
- **No beep:** a valid digit; Left-arrow or Backspace with content (deletes the last
  digit).
- **Decision 1:** Backspace now mirrors Left-arrow (delete last digit, or beep on
  empty). Previously Backspace was silently ignored (`KeyInput.luau:497`). This is a
  minor, deliberate usability deviation — the original had only the left-arrow delete
  key, but modern users press Backspace expecting deletion.

### `type` (free text — combat throw amount; firm name is `noBeep`)

- **Beep:** a non-printable character (`toPrintableChar` returns nil); a character
  entered when the buffer is at `maxLength` (append path, `KeyInput.luau:403`).
- **No beep:** the existing cursor / overwrite / Backspace editing model is left
  unchanged. We add the two core rejection beeps only; we do not add boundary beeps to
  the richer `type` editing model.

## `noBeep = true` Scenes (exactly two)

1. **`sceneCombatLayout`** (`PromptEngine.luau:646`, `type = "key"`) — the
   fight/throw/run main combat loop. It already has special round orchestration
   (`roundPhase` / `queuedCommand` in `Apple2Interface`); per the original it does not
   beep on invalid key.
2. **`sceneFirmName`** (`PromptEngine.luau:479`, `type = "type"`) — **Decision 2:** the
   firm-naming dialog is a customized scene (and is itself buggy in the original); it
   takes no input beeps.

Every other prompt beeps, including the two combat throw sub-prompts
(`sceneCombatThrowGood` `:673`, `sceneCombatThrowAmount` `:702`).

**Firm-name interaction:** `noBeep` suppresses only the new Layer-1 input beep. The
existing `playSound("badjoss")` on an empty-name *submit* (`PromptEngine.luau:491`,
faithful to `taipan.c`) is a separate sound on a separate event and is unchanged.

## Component Changes

- **`sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`**
  - Require `SoundPlayer`; add a local `beep()` helper that spawns
    `SoundPlayer.play("beep")`, gated on `not promptDef.noBeep`.
  - `key` path: beep when a character-producing key is rejected (skip modifiers).
  - `singlechar` path: beep on invalid character (keep the existing clear).
  - `numeric` path: beep on non-digit, on digit at `maxDigits`, and on
    Left-arrow/Backspace with an empty buffer; route Backspace through the same delete
    logic as Left-arrow.
  - `type` path: beep on non-printable char and on char at `maxLength`.
- **`sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`**
  - `sceneBuySellAmount`: add the `playSound` parameter; call `playSound("beep")` in
    the buy and sell over-limit branches; pass `playSound` at the two dispatch sites.
  - `sceneCombatLayout` and `sceneFirmName`: add `noBeep = true` to their promptDefs.
- **`docs/superpowers/specs/2026-06-25-local-event-sounds-design.md`**
  - Correct the stale note that buy/sell over-limit played `good_joss`; it played the
    beep (`CALL 2524`), now implemented here.

## Error Handling

- Unknown sound name → `SoundPlayer.play` already `warn`s and returns; no error.
- Rapid/overlapping beeps → `SoundPlayer.play` clones a fresh `Sound` per call, and the
  beep is ~0.1s, so overlap is harmless.

## Testing

- **No unit test:** the change is client-side UI input glue; no pure-logic engine
  module is touched.
- **Manual MCP playtest:** drive each input type into a rejection (invalid menu key,
  non-digit in an amount field, digit past max length, Left/Backspace on an empty
  amount, invalid key in combat throw selection) and confirm the prompt behaves
  correctly; confirm the combat main loop and firm-name dialog stay silent. Per
  project guidance ([[feedback_audio_verification]]), **audio confirmation is the
  user's responsibility** — screen capture is silent, so the user verifies the beep
  actually plays (and is correctly absent in the two `noBeep` scenes).

## Files Touched

- `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`
- `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`
- `docs/superpowers/specs/2026-06-25-local-event-sounds-design.md` (one-line correction)
