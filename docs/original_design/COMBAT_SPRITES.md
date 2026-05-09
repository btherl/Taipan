# Combat Sprites — Apple II Original

Analysis of enemy ship sprite rendering and damage display from `references/taipan-applesoft-annotated.txt`.

## Enemy Ship Grid

Ten enemy ship slots (indices 0–9) arranged in a 5×2 grid. Subroutine **5880** maps slot `I` to text-mode coordinates:

```
X = (I mod 5) * 8 + 1      -- column (0–4, each 8 chars wide, 1-based)
Y = INT(I / 5) * 6 + 7     -- row 7 (top row) or row 13 (bottom row)
```

Each ship occupies a 7-wide × 5-tall cell in text mode.

## Sprite Strings

| Variable | Line | Purpose |
|---|---|---|
| `SH$` | 10250 | Full ship sprite — 5 rows × 7 custom font chars |
| `SB$` | 10260 | Blank sprite — 5 rows × 7 spaces (erases a ship) |
| `DM$(0..5, 0..1)` | 10270–10290 | 6 damage fragment types × 2 zones (upper/lower) |
| `DL%(0..5, 0..1)` | 10290 DATA | Position offsets, encoded as 2-digit number: tens=X offset, units=Y offset |

`BD$`, `CD$`, `DD$` are control codes for the custom sprite renderer (`CHR$(2)`, `CHR$(3)`, `CHR$(4)`). `CG$` sets green colour.

> **Roblox port note:** The Apple II accomplished sprite rendering by swapping the character ROM mid-line via `BD$`/`CD$`/`DD$`. Our port doesn't need that machinery — the ship sprite tiles and damage fragments are already baked into `TaipanThickFont` (`sync/ReplicatedStorage/Text/Fonts/TaipanThickFont`) as glyphs at the same codepoints that the BASIC strings reference. So a ship draw is just `print("ABCDEFG", font="TaipanThickFont")` etc. at the target row. The control codes `BD$`/`CD$`/`DD$` and the colour code `CG$` have no Roblox-side equivalent and are dropped.

### Ship sprite (`SH$`)

```
BD$ + CG$ + "ABCDEFG"
           + CD$ + "HIJKLMN"
           + CD$ + "OIJKLPQ"
           + CD$ + "RSTUVWX"
           + CD$ + "YJJJJJZ" + DD$
```

A–Z etc. are indices into the custom character ROM font.

### Damage fragments (`DM$` / `DL%`)

Parsed from DATA line 10300: `cde,20,r,3,fg*,mn,50,tu,23,ij,11,vw,43,0,22,x*,z,63,kl,32,12,14,pq,52,345,34`

| Index | J=0 chars | J=0 position | J=1 chars | J=1 position |
|---|---|---|---|---|
| 0 | `cde` | X+2, Y+0 | `r` | X+0, Y+3 |
| 1 | `fg` / `mn` (2 rows) | X+5, Y+0 | `tu` | X+2, Y+3 |
| 2 | `ij` | X+1, Y+1 | `vw` | X+4, Y+3 |
| 3 | `0` | X+2, Y+2 | `x` / `z` (2 rows) | X+6, Y+3 |
| 4 | `kl` | X+3, Y+2 | `12` | X+1, Y+4 |
| 5 | `pq` | X+5, Y+2 | `345` | X+3, Y+4 |

J=0 positions cover the upper half of the sprite (Y offsets 0–2); J=1 positions cover the lower half (Y offsets 3–4).

Multi-row fragments (index 1 J=0 and index 3 J=1) use `*` as a line-break sentinel in the DATA, replaced with `CD$` during init.

## Subroutines

**5800** — Draw ship: print `SH$` at `(X, Y)`.

**5820** — Erase ship: print `SB$` at `(X, Y)` (overwrites with spaces).

**5840** — Hit animation (called each time a gun fires and hits a ship):
```
GOSUB 5880                          -- compute X, Y from slot I
POKE 2493, (Y+4)*8 - 1             -- parameters for CALL 2368
POKE 2494, X - 1
FOR J = 0 TO 1:
  IJ = FN R(6)                      -- independently random per J
  II = DL%(IJ, J)
  HTAB X + INT(II / 10)
  VTAB Y + II - INT(II/10)*10
  PRINT DM$(IJ, J)                  -- overwrite ship sprite chars
NEXT J
CALL 2368                           -- assembly sound/flash effect
```

**5860** — Sink animation: POKEs the slot's bottom-pixel-row into 2361, the slot's column into 2362, and a random speed (`FN R(FN R(192))`, where 192 is the hi-res screen height) into 2300, then `CALL 2224`. The assembly routine slides the sprite downward at the seeded speed, clipping at the slot's bottom — i.e. the ship sinks below the waterline, bottom disappearing first. There is no explosion graphic in the original; the sink-down *is* the death animation.

**5880** — Compute `(X, Y)` from slot index `I`.

## How Damage Accumulates

- Each hit prints **2 sub-fragments** (one per zone), chosen independently at random.
- The fragment characters are **permanently printed on top of `SH$`** — no restoration occurs between hits.
- There is **no tracking of which fragments have already been applied**; the same fragment can be chosen again (visually a no-op, just redraws identical characters at the same position).
- Damage accumulates visually as the sprite is progressively overwritten with fragment characters across multiple hits.
- When a ship is finally destroyed (`AM%(I,1) > AM%(I,0)`): subroutine 5860 plays the sink animation (slide-down, bottom clipped, random speed), then 5820 blanks the cell with `SB$` to clean up.

## HP / Damage Tracking (`AM%` array)

```
AM%(I, 0)  -- HP of ship in slot I (FN R(EC) + 20 on spawn; EC starts at 20, +10/year)
AM%(I, 1)  -- cumulative damage taken (0 on spawn)
```

Each gun hit adds `FN R(30) + 10` to `AM%(I,1)`. Ship is destroyed when `AM%(I,1) > AM%(I,0)`.
