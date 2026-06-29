# HANDOFF — Mobile empty firm-name soft-lock

**Date:** 2026-06-28
**Status:** RESOLVED 2026-06-29. Fixed via Option A in `KeyInput.luau` (mobile `type` submit branch). Pre-existing bug; surfaced (not caused) by the merged `mobile-firmname-canvas-shift` feature. Awaiting on-device verification (touch-only; cannot reproduce in Studio/desktop).
**Severity:** Low-medium. Reachable soft-lock on touch devices only, at the firm-name entry screen.

## Summary

On a touch device, if the player presses Return/Go on the firm-name prompt with an **empty or whitespace-only** name, the native keyboard dismisses, is never re-summoned, and the player is left on the (now lifted) terminal with no keyboard and no tap target to bring it back — a soft-lock at game start.

The lock is **pre-existing**: even before the canvas-shift feature, an empty submit dismissed the keyboard with no refocus. The merged feature did not cause it, but makes it more visually prominent — after the empty submit the canvas remains lifted to the top half (because nothing re-runs the prompt to revert it), so the player sees a half-screen terminal with empty space below and no keyboard.

## Reachable path

1. Mobile player reaches the firm-name prompt; native keyboard opens (hidden `TextBox` capture).
2. Player types nothing (or only spaces) and presses Return/Go.
3. `TextBox.FocusLost` fires with `enterPressed = true` → the **submit** branch runs (KeyInput.luau:579-586): it calls `promptDef.onType(submitted, ...)` and does **not** re-capture focus.
4. `sceneFirmName.onType` (PromptEngine.luau:490-499) sees empty/whitespace, plays `badjoss`, and returns **`nil`** — no error string, and it does **not** call `localSceneCb` (so the scene does not advance).
5. Because `onType` returned `nil`, the `if err and promptDef._onError` guard (KeyInput.luau:586) is false → `_onError` is **not** called → `setPrompt` is **not** re-invoked → `cleanup()` does **not** run → `restoreCanvas` does **not** fire (canvas stays lifted) and the keyboard is **not** re-captured.
6. Result: scene unchanged, `hiddenBox` still alive but unfocused, keyboard gone, canvas lifted. No affordance to refocus. Stuck.

Contrast: an *invalid-but-non-empty* entry on other prompts (e.g. combat-throw) returns an **error string**, which routes through `_onError` → `term.print(">> ...")` → `setPrompt(promptDef)` → `cleanup` (revert + teardown) → re-dock + fresh `CaptureFocus()`. That path self-heals. The empty firm-name case is the one that returns `nil` while staying on the prompt, so it falls through every refocus path.

## Key code locations (on `main`, commit fa451ea)

- `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`
  - Mobile `type` submit branch: **lines 578-586** (`FocusLost` `enterPressed` → `onType`, no refocus).
  - The else branch (focus lost *without* submit) DOES refocus: **lines 587-603** — this is the pattern to mirror.
- `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`
  - `sceneFirmName.onType` empty/whitespace branch returning `nil`: **lines 490-499**.

## Fix options

### Option A (recommended — minimal, general, leverages existing guard)
In the mobile `type` submit branch (KeyInput.luau:585-586), after `onType` returns, re-capture focus on the next frame **when `err` is nil**, using the same `hiddenBox.Parent` guard as the else branch:

```lua
              local err = promptDef.onType(submitted, state, actions)
              if err and promptDef._onError then
                promptDef._onError(err)
              else
                -- onType returned no error. If it advanced the scene, setPrompt ->
                -- cleanup destroyed hiddenBox and the Parent guard below no-ops. If
                -- it stayed on this prompt (e.g. empty firm name -> nil, no advance),
                -- the box survives and we must re-summon the keyboard or the player
                -- is stranded with no refocus affordance.
                task.defer(function()
                  if hiddenBox and hiddenBox.Parent then hiddenBox:CaptureFocus() end
                end)
              end
```

Why it's safe for both outcomes:
- **Valid name:** `onType` calls `localSceneCb("start_choice")` → re-render → `setPrompt` → `cleanup()` destroys `hiddenBox`. By the deferred frame `hiddenBox.Parent` is nil → guard skips. No spurious refocus.
- **Empty/whitespace:** `onType` returns nil without advancing → `hiddenBox` still parented → keyboard re-summoned. Lock fixed. (Canvas correctly stays lifted because we are still in the prompt.)
- **Combat-throw empty submit:** `onType` advances the scene (`localSceneCb(nil)` / `combatNoCommand`) → box destroyed → guard skips. No regression.

Do **not** restore text here (unlike the rotation else-branch) — an empty submit should leave the field empty; the box is already cleared at KeyInput.luau:584.

### Option B (alternative — change firm-name semantics)
Make `sceneFirmName.onType` return a short error string for empty/whitespace instead of `nil`, so it routes through the existing `_onError` → `setPrompt` → re-dock + `CaptureFocus` path. Tradeoff: prints a `>> ...` red error line, diverging from the retro-faithful "badjoss only, no message" behavior (PromptEngine.luau:492-496 cites taipan.c:758-762). If chosen, keep the `badjoss` sound and word the message tersely. Less surgical than A and only fixes firm-name, not the general "stayed-on-prompt-with-nil" class.

### Option C (broadest — tap-to-refocus affordance)
Add an invisible full-canvas tap target for mobile `type` prompts that calls `hiddenBox:CaptureFocus()` on tap, so any focus loss is recoverable. More code and a new UI element; overkill unless other refocus gaps appear. Option A covers the known case.

**Recommendation:** Option A. Smallest change, fixes the general case, no fidelity or UX change to the happy path, naturally no-ops when the prompt advanced.

## Verification (touch-only — cannot reproduce in Studio/desktop)

This is the `isMobile = UserInputService.TouchEnabled` path; it does not run in Studio Play/desktop, and TestEZ (server-side) cannot reach a StarterGui module, so there is **no automated test**. Verify on a real device:

1. New game → firm-name prompt → keyboard open.
2. Press Return/Go with the field **empty** → expect: `badjoss` plays AND the keyboard re-appears (field still empty, caret ready). Player is not stranded.
3. Repeat with **only spaces** → same expectation.
4. Regression: enter a **valid** name → advances to the start-choice screen normally, keyboard dismissed, canvas reverts to centered/full (no lingering keyboard or double-dock).
5. Regression (if touched): combat-throw amount → submit empty → advances/cancels normally, no stray keyboard.

## Resolution (2026-06-29)

Implemented **Option A**. In the mobile `type` submit branch (`KeyInput.luau`), the bare `if err and promptDef._onError then promptDef._onError(err) end` was expanded with an `else` clause that `task.defer`s a `hiddenBox:CaptureFocus()` guarded by `hiddenBox.Parent`. When `onType` advanced the scene (valid name), `cleanup()` has destroyed the box and the guard no-ops; when it stayed on the prompt (empty/whitespace -> nil), the box survives and the keyboard is re-summoned. Text is intentionally not restored (empty submit leaves the field empty). Pending real-device verification per the steps below.

## Notes

- Same-file region as the recently merged feature; expect a small, single-file diff in KeyInput.luau (Option A).
- Recorded as the second Minor in the feature's final whole-branch review (opus, 187abe6..fa451ea): "empty firm-name submit leaves canvas lifted with no keyboard." See `.superpowers/sdd/progress.md`.
