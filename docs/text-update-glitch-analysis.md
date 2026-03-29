# Text Rendering Glitch Analysis

## What glitches and when

When the user presses Backspace in a type prompt, the `"Amount: "` placeholder
text flashes one character-width (42 virtual px) to the right for one frame,
then snaps back to the correct position.  It does not happen when blinking or
moving the cursor left/right because those operations do not change the length
of the display string.

---

## How Text:Update() works (after the phase-swap fix)

`Text:Update(DeltaTime)` is connected to `RunService.RenderStepped` for every
Text object created with `automatic_update = true`.  It runs once per frame,
just before Roblox renders the frame to screen.

### Phase 1 — text diffing (runs first after the fix)

Runs only when `self.Text ~= self.OldText`.

```
1.  Compute difference = new_length - old_length
2a. If difference > 0 (text grew):
      append new Sprite objects to self.Sprites
2b. If difference < 0 (text shrank):
      call self.Sprites[i]:DestroySprite() for i = 1..abs(difference)
        → sets sprite.Destroyed = true
        → calls Instance:Destroy() — the ImageLabel is REMOVED from the DOM NOW
      compact self.Sprites (filter out Destroyed entries)
3.  Reconfigure every surviving sprite for the new text:
      LoadImage, AddManual (registers glyph animation), Play(glyph, true)
        → Play() calls UpdateImage() IMMEDIATELY
        → UpdateImage() reads self.Position (still the OLD position at this point)
        → writes Instance.Position to screen based on old position
4.  Calculate new sprite positions and set self.Sprites[i].Position
      (virtual coordinates only — Instance.Position is NOT updated here)
```

### Phase 2 — render (runs second after the fix)

```
5.  For every sprite in self.Sprites:
      call UpdateSprite(DeltaTime)
        → calls UpdateImage() with CURRENT self.Position
        → writes correct Instance.Position to screen
```

---

## The remaining problem: Play() writes a stale position

In step 3, `Play(glyph, true)` calls `self:UpdateImage()` immediately.
At that moment `self.Position` is still the old virtual coordinate (step 4 hasn't
run yet).  `UpdateImage()` converts that old position to a UDim2 scale and
writes it to `Instance.Position`.

Example — backspace removes "3" from "Amount: 123_":

| | Before compact | After compact, before step 4 |
|---|---|---|
| sprite[1] | "A" at x=30 (DESTROYED, gone) | — |
| sprite[2→1] | "m" at x=72 | reconfigured as "A", Play sets Instance.Position to x=72 |
| sprite[3→2] | "o" at x=114 | reconfigured as "m", Play sets to x=114 |
| … | … | … |
| sprite[12→11] | "_" at x=492 | reconfigured as "_", Play sets to x=492 |

After step 4 sets the correct `.Position` values and step 5 (UpdateSprite/UpdateImage)
runs, all `Instance.Position` values are correct.

---

## Why the phase-swap fix should work in theory

Roblox's per-frame execution order is:

```
1.  Input events (InputBegan, etc.)
2.  RenderStepped callbacks  ← Text:Update() runs here
3.  Frame is rendered to screen
```

InputBegan (step 1) sets `obj.Text` to the new shorter string.
RenderStepped (step 2) runs `Text:Update()` which:
  a. Destroys the front sprite
  b. Reconfigures all sprites (Play writes stale positions)
  c. Sets correct `.Position` values (step 4)
  d. Calls UpdateSprite → writes correct `Instance.Position` (step 5)

All of steps a–d happen within a single RenderStepped callback, before
the frame renders.  In theory, Roblox should only render the final state
(after step d) and the user should never see the intermediate stale positions
from step b.

---

## Why the glitch may still appear despite the fix

There are two possibilities:

### Possibility A: Play()'s UpdateImage() call is visible

Roblox may render `Instance.Position` changes to screen as they are set,
even within a single callback — not just at the end of the frame.  If that is
the case, the sequence within one RenderStepped is:

```
→ Step 2b: "A" ImageLabel destroyed (visually gone immediately)
→ Step 3:  Play() → UpdateImage() → surviving sprites shown at OLD positions
           (first sprite showing "A" at x=72, not x=30)
→ Step 5:  UpdateSprite → UpdateImage → correct positions
```

If Roblox composites intermediate property states within a callback, the user
sees the stale positions for however many microseconds steps 3–5 take.  This
would appear as a one-frame flash.

### Possibility B: The display string still changes length (existing workaround is incomplete)

The trailing-space patches added to `buildDisplayStr()` keep the display string
the SAME length between cursor-visible and cursor-hidden states.  But when the
user backspaces, `typeBuf` itself shrinks:

```
typeBuf = "123"  →  display = "123_" or "123 " (length 4)
         ↓ backspace
typeBuf = "12"   →  display = "12_"  or "12 "  (length 3)
```

The display string still shrinks by one character.  The sprite-destroy path
in Text:Update() still fires.  The phase-swap fix does reduce the window where
stale positions are visible, but if Possibility A is true it does not eliminate it.

---

## The reliable fix

Ensure the display string **never changes length** for the lifetime of the type
prompt.  This completely prevents sprite count changes in Text:Update().

Pad `buildDisplayStr()` in KeyInput.lua to always return exactly
`maxLength + 1` characters (the extra +1 is the cursor slot):

```lua
local function buildDisplayStr()
    local fieldLen = maxLength or #typeBuf
    -- Pad typeBuf to fieldLen+1 with spaces — string length is always constant
    local padded = typeBuf
    while #padded < fieldLen + 1 do padded = padded .. " " end
    -- cursorPos is always in range 1..fieldLen+1, always within padded
    local before = padded:sub(1, cursorPos - 1)
    local atCur  = cursorVisible and CURSOR_CHAR or padded:sub(cursorPos, cursorPos)
    local after  = padded:sub(cursorPos + 1)
    return before .. atCur .. after
end
```

With `maxLength = 8`:
- Every call returns exactly 9 characters (8 data + 1 cursor slot)
- `difference == 0` on every Text:Update() call — no sprite creation/destruction
- The sprite-destroy code path never runs → no position staling → no glitch

The full string passed to `showInputLine` would be e.g. `"Amount: 123_     "` (17 chars),
always 17 chars regardless of how many digits are typed or deleted.

---

## Summary of the phase-swap fix

The phase-swap (update before render) is still a correct improvement — it removes
the one-frame lag that existed when text was first displayed or when `Position`
was set from outside.  But it may not fully eliminate the backspace glitch if
Roblox renders intermediate property changes within a callback.

The pad-to-fixed-width approach in `buildDisplayStr()` eliminates the problem
at the source by ensuring the sprite array never changes size during input.
