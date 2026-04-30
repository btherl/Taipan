# Bitmap Font Library — internals

This folder is the implementation of the bitmap-font text renderer used by `ReplicatedStorage.Text` (the parent module at `sync/ReplicatedStorage/Text.luau`). The lib is a mix of **custom code** and **vendored 3rd-party files**. Mods to vendored files should be avoided unless strictly necessary.

| File | Origin | Purpose |
|---|---|---|
| `TextSprite.luau` | Custom (`@Complexitify`, `@N_ckD`) | Per-glyph sprite primitive. Each glyph = one `ImageLabel` with rect-offset "animation". The workhorse of the library. |
| `Unicode.luau` | Custom | Char-to-codepoint lookup table (`Unicode["A"] = 65`). Used to index into a font's `FontData`. |
| `Util.luau` | Custom (small) | Holds the global `Util.ScreenSize` (set to `(1920, 1080)` by `Text.luau`'s init block). Also a JSON-byte-size helper. |
| `Signal.luau` | Vendored — `@stravant`'s [Simple Correct Signal](https://gist.github.com/stravant/30dd9442cc9f24a938756192daf9e718) | Standard Roblox-style Signal/Connect/Wait. Used by `TextSprite` for animation completion events. **Do not edit.** |
| `XMLParser.luau` | Vendored — MIT, [Jonathan Poelen](https://github.com/jonathanpoelen/lua-xmlparser/) | Generic XML parser for BMFont descriptor files. **Do not edit.** |

## Rendering model

A `Text` instance (parent module) holds a list of `Sprite` instances, one per glyph. Each frame, `Text:Update(dt)` flushes virtual positions to `Instance.Position`. `Sprite` itself is a thin wrapper around `ImageLabel`/`ImageButton` with rect-offset animation (used to "scroll" through sprite atlases for multi-frame glyphs even though our fonts use a single frame).

### Center anchor — important

`Sprite.new` sets `Instance.AnchorPoint = Vector2.new(0.5, 0.5)` (TextSprite.luau:79). The supplied `Position` therefore represents the **center** of the glyph cell, not the top-left. A starting position of `Vector2.new(0, y)` will clip approximately half the first glyph off the left edge of the screen. Consumers must offset by roughly `charWidth * TextSize / 2` virtual pixels — for the project's stock fonts at `TextSize = 3`, ≈ 28–32 px is sufficient (`Terminal.luau` uses `X_OFFSET = 30`).

### Stroke

Stroke is **emulated**, not native: when `Sprite.Stroke = true`, four duplicate sprites are rendered at corner offsets `(-2,-2), (2,2), (2,-2), (-2,2)` (the `StrokeOffsets` table in `TextSprite.luau:20-25`). This means:
- Stroke costs 5x the sprite count.
- Stroke is automatically suppressed in inverted mode (`Text.luau:212`) because the opaque background block makes corner offsets visually wrong.

### Inverted rendering

For inverted text, the parent `Text:Update` (Text.luau:222-228) sets `ImageColor3 = black` (tints the white glyph atlas to black) and `BackgroundColor3 = TextColor3` (the cell background fills with the would-be text colour). This is how the Apple 2 terminal achieves its inverse-video look.

## Virtual coordinate system

`Util.ScreenSize` is a single global Vector2 (default `(1920, 1080)`, mutated by `Text.luau`'s init). All `Position` and `Size` values supplied to sprites are in this virtual space. A `UIAspectRatioConstraint` on the parent frame (created by `Text.GetTextGUI`) scales the rendered output to fit the actual screen. **Don't reach for actual pixel coordinates — use the virtual resolution.**

## Where fonts live

Font assets are NOT in this folder — they live alongside, in `Text/Fonts/<FontName>/`:
- `FontData.luau` — table of glyph rects (`{ width, height, x, y, xoffset, yoffset, xadvance }` per character index).
- `ImageID` — a `StringValue` instance whose `.Value` holds the Roblox asset ID for the sprite atlas.

`Text.luau`'s constructor finds the font folder by name and reads both. The lib here is font-agnostic.

## When modifying

- **Custom files** (`TextSprite`, `Unicode`, `Util`): fair game, but read carefully — `TextSprite` is 411 lines of state machine and any change risks one-frame-flash regressions or position drift. The parent `Text:Update` has comments explaining ordering invariants (text-update before render-loop) that you must preserve.
- **Vendored files** (`Signal`, `XMLParser`): treat as read-only. If a behaviour change is unavoidable, prefer wrapping in a custom file and leave the vendored source alone.
