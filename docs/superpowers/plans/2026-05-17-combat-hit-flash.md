# Combat Hit Flash — Apple II Video Mode Strobe

## Original BASIC behaviour (line 5540)

When the enemy fires on the player in combat, the original Apple II Taipan! runs a
video-mode strobe before printing "We've been hit, Taipan!!".

```
5540 FOR I = 1 TO 10:
       POKE -16298,0:   ' $C056 — select LORES
       POKE -16299,0:   ' $C055 — select PAGE 2
       POKE -16297,0:   ' $C057 — select HIRES
       POKE -16300,0:   ' $C054 — select PAGE 1
       FOR J = 1 TO 10:
     NEXT J,I
```

### Sequence (one iteration)

1. LORES mode
2. PAGE 2
3. HIRES mode
4. PAGE 1
5. Inner delay loop `FOR J = 1 TO 10: NEXT J` (no-op timing)

### Outer loop

The entire 4-switch + delay sequence repeats **10 times** total.

### What the player sees

The visible framebuffer rapidly snaps between:

- **LORES page 2** (a stale/uninitialised graphics buffer — "garbage")
- **HIRES page 1** (the normal text/playfield page that combat is drawn on)

Touching the soft switch addresses is what flips the mode; the POKE value (0) is
irrelevant. The text-mode combat screen lives on page 1, so the strobe effectively
flashes "garbage video memory" over the combat display ten times — a screen-shake /
impact effect, not a real mode change into gameplay graphics.

After the strobe:

- `5542` prints "We've been hit, Taipan!!"
- `CALL 2512` plays the impact sound ML routine
- `5550` checks for a gun hit (random roll vs damage %)
- `5555` applies damage to `DM`
- `5560` rolls 1-in-20 chance Li Yuen's fleet rescues the player (normal pirates only)

## Plan: Reproduce in the Roblox port

We can't actually toggle Apple II video modes, but we can fake the visual effect by
showing pre-captured images of what those "garbage" pages actually looked like on a
real Apple II during a Taipan! combat scene.

### Steps

1. **Capture garbage page images** (user — manual, via emulator)
   - Run Taipan! in an Apple II emulator to a combat scenario.
   - At the moment of being fired upon, dump the framebuffer for:
     - LORES page 2 contents (the "garbage" buffer)
     - HIRES page 1 contents (the actual combat screen)
   - Save as PNGs (or whatever Roblox-importable image format).
   - More than one garbage capture may be desirable for variety.

2. **Upload as Roblox image assets**
   - Import into the place as `Decal`/`ImageLabel` content IDs.
   - Reference IDs in a constants module (e.g. `Constants.HIT_FLASH_FRAMES`).

3. **Wire into the Apple II interface combat panel**
   - On a "we've been hit" client signal (likely a new `Notify` variant or a flag
     on the combat state), trigger a flash sequence in the Apple II terminal
     overlay.
   - The flash: render an `ImageLabel` over the terminal cycling between the
     captured frames, matching the original cadence — 10 iterations, each frame
     held for roughly the duration of `FOR J = 1 TO 10` on a 1MHz 6502
     (negligible — milliseconds). Tune by feel; the original is *fast*.
   - Hide the overlay when the strobe completes, then let the normal "We've been
     hit" message + sound play through.

4. **Server contract**
   - Server already resolves enemy fire in `CombatEngine`. It should send a
     distinct client signal at the moment damage is applied so the client can
     play the strobe without the server caring about timing.
   - Decide whether to emit a new remote (`CombatHitFlash`) or piggyback on
     existing combat state diffs. A dedicated one-shot remote is cleaner.

5. **Modern interface**
   - Out of scope for the initial pass — Apple II interface only, per project
     focus. Could later show a simple screen-shake or flash if desired.

### Open questions

- Exactly how fast was the original strobe on a real Apple II? The inner `FOR J = 1 TO 10`
  loop is only ~a few ms of Applesoft, so the 10 outer iterations probably finished in
  well under a second. We should tune the Roblox version against video of real
  hardware rather than emulator-at-max-speed.
- Do we want one fixed pair of garbage frames, or a small pool to randomise from per
  hit so it doesn't look identical every time?
- Should the flash also pulse the CRT glitch layer that already exists
  (`GameController/Apple2/GlitchLayer.luau`)? May complement nicely.
