# Text — bitmap font assets and helpers

This folder is the **child tree** of the `Text` ModuleScript (defined at `sync/ReplicatedStorage/Text.luau`). At runtime, Azul mounts everything in here as children of that ModuleScript, so the runtime hierarchy is:

```
ReplicatedStorage.Text                  (ModuleScript ← Text.luau)
├── BoxDrawing                          (ModuleScript ← Text/BoxDrawing.luau)
├── Fonts                               (Folder)
│   ├── TaipanStandardFont
│   │   ├── FontData                    (ModuleScript ← Fonts/.../FontData.luau)
│   │   └── ImageID                     (StringValue, asset ID for sprite atlas)
│   └── TaipanThickFont
│       ├── FontData
│       └── ImageID
└── lib                                 (Folder of renderer internals)
    ├── Signal, TextSprite, Unicode, Util, XMLParser
```

External callers `require(ReplicatedStorage.Text)` and use the constructor `Text.new(font_name, automatic_update)`. They should not reach into `lib/` directly — that's the implementation. See `lib/CLAUDE.md` for renderer internals (sprite model, stroke emulation, inverted rendering, center-anchor quirk).

## `BoxDrawing.luau`

Helpers for drawing box/table borders using `TaipanThickFont` glyphs. The font reserves codepoints 129, 136-141, 154-158, 187, 189 for box-drawing characters (`│`, `├`, `┤`, `┬`, `─`, `└`, `┼`, `┘`, `┌`, `┐`). Three API layers, in order of "rawness":

1. **Pure string builders** — `topString`, `bottomString`, `dividerString`, `rowBorderString`. Return plain Lua strings of the codepoints. No Roblox dependencies; testable from `BoxDrawing.spec.luau`.
2. **Segmented row builders** — `boxTop`, `boxBottom`, `boxDivider`, `boxRow`. Return `{ segments = {...} }` tables compatible with `Apple2/Terminal.luau`'s row format. Segments mark `font = "TaipanThickFont"` so the terminal renders them with the thick font while content stays in the standard font.
3. **Text-object factories** — `newTop`, `newBottom`, `newDivider`, `newRow`. Construct actual `Text.new(...)` instances at given positions. `newRow` builds a two-Text composite (thick border + standard content) with `setContent(str)`, `update(dt)`, `destroy()` methods — used outside the terminal where individual sprite control is needed.

Layers 1 and 2 are pure string/table work; layer 3 wires real GUI instances. Don't conflate them — most callers want layer 2 (terminal rows) or layer 1 (tests).

## `Fonts/<FontName>/`

Each font is a folder with two children that the parent `Text.luau` reads in its constructor:

- `FontData.luau` — a ModuleScript returning a table of glyph rect descriptors keyed by codepoint: `{ [65] = { width, height, x, y, xoffset, yoffset, xadvance }, ... }`. Generated from a BMFont XML descriptor.
- `ImageID` — a `StringValue` instance (not a Luau file) whose `.Value` is the Roblox asset ID for the sprite atlas image. The runtime `Text.luau` reads `font_folder.ImageID.Value`.

To add a new font: create a folder under `Fonts/`, drop in a `FontData.luau`, add an `ImageID` StringValue with the uploaded sprite atlas asset ID, and register the folder in `sourcemap.json` so Azul mounts it. Then `Text.new("MyFontName")` will find it.

## Box-drawing glyph indirection

`BoxDrawing.luau` uses `string.char(N)` literals for the special codepoints (line 8-18). The numbers correspond directly to indices in `TaipanThickFont`'s `FontData` table — so changing a codepoint in the font requires changing the literal here too. Don't treat the numbers as portable Unicode points; they're project-specific atlas indices.

## See also

- `lib/CLAUDE.md` — bitmap renderer internals, vendored vs. custom files, stroke emulation, virtual coordinate system.
- The parent `Text.luau` at `sync/ReplicatedStorage/Text.luau` for the public constructor and `Text:Update` lifecycle.
- The project root `CLAUDE.md` for the wider "Phase 8 custom fonts (BMFont XML generator)" history.
