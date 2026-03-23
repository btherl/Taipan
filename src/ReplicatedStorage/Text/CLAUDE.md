# CLAUDE.md -- Text: Bitmap Font Rendering Library

## Purpose

This library renders text using bitmap spritesheets, bypassing Roblox's built-in font system. Each character is an individual `ImageLabel` whose `ImageRectOffset`/`ImageRectSize` crops the correct glyph from a shared spritesheet. This gives full control over font appearance (pixel fonts, custom typefaces, etc.) at the cost of per-character Instance overhead.

## Architecture

```
Text (init.lua)          -- Facade: manages a string as a list of TextSprite objects
  |
  +-- TextSprite         -- Per-character ImageLabel with animation system + stroke
  |     +-- Signal       -- Lightweight RBXScriptSignal reimplementation (Connect/Fire/Wait/Once)
  |     +-- XMLParser    -- Parses XML spritesheet metadata (used by LoadGraphic/AddByPrefix path, NOT used by font rendering)
  |     +-- Util         -- Holds shared ScreenSize vector; has GetDataFileSize helper
  |
  +-- Unicode            -- Lua char -> integer codepoint lookup table (keys into FontData)
  +-- Fonts/
        +-- November/
              +-- FontData.lua   -- Glyph metrics table keyed by Unicode codepoint
              +-- ImageID.txt    -- Roblox asset URL for the spritesheet (StringValue in Rojo)
```

**Data flow for rendering "HELLO":**
1. `Text:Update()` splits the string into individual characters `{"H","E","L","L","O"}`.
2. For each character, it looks up `Unicode["H"]` -> `72`, then `FontData[72]` -> `{x, y, width, height, ...}`.
3. A `TextSprite` is created (or reused) per character, configured with `ImageRectOffset = (x, y)` and `ImageRectSize = (width, height)` to crop the glyph from the spritesheet.
4. Each sprite is positioned sequentially along the X axis in virtual-resolution coordinates.

## Font Format

### Spritesheet image

A single PNG containing all glyphs packed into a texture atlas. Uploaded to Roblox as a Decal/Image asset.

### ImageID.txt

A plain text file containing the Roblox asset URL, e.g.:
```
http://www.roblox.com/asset/?id=15849151180
```
Rojo maps `.txt` files as `StringValue` instances. The library reads it as `font_folder.ImageID.Value`.

### FontData.lua

A Lua module returning a table keyed by **Unicode codepoint** (integer). Each entry:

```lua
[65] = {  -- "A"
    x = 134,        -- X pixel offset in spritesheet
    y = 0,          -- Y pixel offset in spritesheet
    width = 18,     -- Glyph width in pixels
    height = 28,    -- Glyph height in pixels
    xoffset = -1,   -- Horizontal bearing (pixels to shift right from cursor)
    yoffset = 0,    -- Vertical bearing (pixels to shift down from top; halved during rendering)
    xadvance = 16,  -- How far to advance the cursor (used for space chars)
    page = 0,       -- Spritesheet page (unused; single-page only)
    chnl = 15,      -- Channel mask (unused)
}
```

This is the standard BMFont format. The `page` and `chnl` fields are present but ignored -- only single-spritesheet fonts are supported.

The November font is monospaced: every glyph has `xadvance = 16`.

## How Text Works (init.lua)

### Constructor

```lua
local textObj = Text.new(font_name, automatic_update)
```

- `font_name` (string): Must match a child folder under `Text/Fonts/` (e.g. `"November"`).
- `automatic_update` (boolean): If `true`, hooks `RunService.RenderStepped` to call `self:Update(dt)` automatically. If `false` or `nil`, the caller must call `:Update(dt)` each frame manually.

### Properties (set directly on the object)

| Property | Type | Default | Description |
|---|---|---|---|
| `Text` | string | `""` | The string to render. Changing this triggers sprite add/remove on next `Update`. |
| `Position` | Vector2 | `(0, 0)` | Top-left position in **virtual pixels** (1920x1080 space). |
| `TextSize` | number | `1` | Scale multiplier applied to glyph width/height. `1` = native spritesheet size. |
| `TextColor3` | Color3 | `(1,1,1)` white | Tint color applied to each ImageLabel's `ImageColor3`. |
| `TextCentered` | boolean | `false` | If true, text is centered horizontally around `Position.X`. |
| `Stroke` | boolean | `false` | Enables outline/stroke effect on all characters. |
| `StrokeColor3` | Color3 | `(0,0,0)` black | Color of the stroke outline. |
| `ZIndex` | number | `1` | ZIndex for all character ImageLabels. Stroke clones use `ZIndex - 1`. |
| `Parent` | Instance | `nil` | The GUI container (typically the `TextParent` Frame from `GetTextGUI`). |

### Update(DeltaTime) loop

Called each frame (either automatically or manually). Two phases:

1. **Sprite maintenance**: Iterates all existing sprites, propagates `Stroke`, `StrokeColor3`, `ImageColor3`, `Parent`, and calls `sprite:UpdateSprite(dt)`.

2. **Text diffing** (only when `self.Text ~= self.OldText`):
   - Compares `string.len(self.Text)` vs `string.len(self.OldText)`.
   - If text grew: appends new `TextSprite` objects.
   - If text shrank: destroys excess sprites from the **front** of the array, then compacts by filtering out `Destroyed` sprites.
   - Reconfigures every sprite with the correct glyph from `FontData` via `AddManual` + `Play`.
   - Computes total text width, applies centering offset if `TextCentered`, then positions each sprite sequentially.

**Positioning logic**: For advancing the cursor, the code uses `width * TextSize` for visible characters and `xadvance * TextSize` for space characters. The advance for sprite `i` is based on the glyph of character `i+1` (lookahead), which means spacing is derived from the *next* character's width.

### GetTextGUI(display_order)

Static helper that creates a `ScreenGui` containing a `Frame` with a `UIAspectRatioConstraint` locked to `1920/1080`. This ensures the virtual coordinate system scales correctly on any screen size. Returns the `ScreenGui` (parent it to `PlayerGui`). Use `screenGui.TextParent` as the `Parent` for Text objects.

### Destroy()

Sets `CanUpdate = false`, destroys all sprites, disconnects the `RenderStepped` connection if present.

## How TextSprite Works (lib/TextSprite.lua)

Each `TextSprite` wraps a single `ImageLabel` instance and manages:

### Core state
- `Instance`: The `ImageLabel` Roblox GUI element.
- `Destroyed`: Boolean flag; `UpdateSprite` early-returns if true.
- `Position`, `Size`: Virtual-pixel Vector2 values.
- `Animations`: Dictionary of named animation definitions (each has `Framerate` and `Frames` array).

### Animation system

Originally designed for spritesheet animation (multiple frames at a framerate), repurposed here for single-frame font glyphs. Each "animation" has one frame containing the crop rectangle. The animation timer advances frames based on `DeltaTime` and `Framerate`. For font rendering, each glyph is a 1-frame animation so the timer is irrelevant.

Key methods:
- `LoadImage(image_id)`: Sets the spritesheet asset URL on the ImageLabel.
- `LoadGraphic(image_id, raw_xml)`: Loads a spritesheet + XML atlas (for non-font sprite usage). Uses `XMLParser` and caches parsed results.
- `AddManual(name, animation)`: Registers an animation definition by name. Font rendering uses this to set up a single-frame animation per glyph.
- `AddByPrefix(name, prefix, frame_rate)`: Extracts frames from parsed XML by name prefix (for general spritesheet animation, not font rendering).
- `Play(name, stop_all)` / `PlayLooped(name, stop_all)`: Starts playing a named animation.

### Virtual-to-screen coordinate conversion

In `UpdateImage()`, positions and sizes are converted from virtual pixels to `UDim2.fromScale`:
```lua
Instance.Size = UDim2.fromScale(
    (frame.ImageSize.X / ScreenSize.X) * Size.X,
    (frame.ImageSize.Y / ScreenSize.Y) * Size.Y
)
Instance.Position = UDim2.fromScale(
    (Position.X + (frame.Offset.X * Size.X)) / ScreenSize.X,
    (Position.Y + (frame.Offset.Y * Size.Y)) / ScreenSize.Y
)
```

### Stroke effect

When `Stroke = true`, the ImageLabel is cloned 4 times. Each clone is offset by `(-2,-2)`, `(2,2)`, `(2,-2)`, `(-2,2)` virtual pixels (scaled by `Size`), tinted with `StrokeColor3`, and placed at `ZIndex - 1`. This creates a cheap outline effect. Clones are created lazily and destroyed when stroke is disabled.

## The Unicode Table (lib/Unicode.lua)

Maps single Lua string characters to their integer Unicode codepoints, which serve as keys into `FontData`. Covers:
- ASCII printable range (space 32 through tilde 126)
- Special entries: `"backslash"` for `\` (key 92), `"__CONTROL"` (0), `"__SEPARATOR"` (29)
- Extended Unicode: curly quotes (8216-8221), bullet (8226), ellipsis (8230), angle quotes (8249-8250), fraction slash (8260)

Usage: `Unicode["A"]` returns `65`, then `FontData[65]` gives the glyph metrics for "A".

## Virtual Resolution System

The library uses a fixed virtual resolution of **1920x1080** (`SCREEN_RESOLUTION` in init.lua, `Util.ScreenSize`).

All positions and sizes are specified in this virtual coordinate space. Conversion to actual screen coordinates happens via `UDim2.fromScale(virtualX / 1920, virtualY / 1080)`, which means:
- Position `(960, 540)` = center of screen regardless of actual display size.
- A glyph 16px wide at TextSize=1 occupies `16/1920 = 0.83%` of screen width.

`GetTextGUI()` creates a container Frame with `UIAspectRatioConstraint` at ratio `1920/1080 = 16/9`. This preserves the aspect ratio so glyphs don't stretch on non-16:9 displays. The Frame is centered (`AnchorPoint = 0.5, 0.5`, `Position = 0.5, 0.5`) and fills the ScreenGui (`Size = 1, 1`), with the aspect constraint handling letterboxing.

## Usage Example

```lua
-- Client script
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Text = require(game:GetService("ReplicatedStorage").Text)

-- Create the GUI container
local screenGui = Text.GetTextGUI(5) -- DisplayOrder = 5
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local textParent = screenGui:FindFirstChild("TextParent")

-- Create a text object (automatic_update = false, we update manually)
local label = Text.new("November", false)
label.Parent = textParent
label.Position = Vector2.new(960, 100)  -- Virtual coords (centered top)
label.TextSize = 2                       -- 2x native glyph size
label.TextColor3 = Color3.fromRGB(200, 180, 80)  -- Amber
label.TextCentered = true
label.Stroke = true
label.StrokeColor3 = Color3.fromRGB(0, 0, 0)
label.ZIndex = 5

-- Set text and update each frame
label.Text = "TAIPAN!"

RunService.RenderStepped:Connect(function(dt)
    label:Update(dt)
end)

-- Later, change text dynamically:
label.Text = "HONG KONG"  -- Sprites will be added/removed on next Update

-- Cleanup:
-- label:Destroy()
```

## Adding a New Font

1. Create folder: `Text/Fonts/MyFont/`

2. Create `ImageID.txt` containing the Roblox asset URL for your spritesheet:
   ```
   http://www.roblox.com/asset/?id=YOUR_ASSET_ID
   ```
   Upload the spritesheet PNG to Roblox as a Decal, then use the image asset ID.

3. Create `FontData.lua` returning a table keyed by Unicode codepoints:
   ```lua
   return {
       [32] = {x = 0, y = 0, width = 1, height = 1, xoffset = 0, yoffset = 0, xadvance = 8, page = 0, chnl = 15},
       [33] = {x = 10, y = 0, width = 6, height = 16, xoffset = 1, yoffset = 0, xadvance = 8, page = 0, chnl = 15},
       -- ... one entry per glyph
   }
   ```
   You can generate this from BMFont (AngelCode Bitmap Font Generator) XML output, converting the XML `<char>` elements into Lua table entries. The codepoint integer keys must match the values in `Unicode.lua`.

4. Use it: `Text.new("MyFont", false)`

## Limitations and Gotchas

- **Single spritesheet per font**: The `page` field in FontData is ignored. All glyphs must fit on one texture atlas.

- **No kerning pairs**: Characters are spaced based on individual glyph `width` (or `xadvance` for spaces). There is no kerning table support.

- **Space uses xadvance, not width**: The space character (codepoint 32) has `width = 3, height = 1` (essentially invisible). Its spacing comes from `xadvance` (16 in November). The code explicitly checks `if text[i] == " "` to use `xadvance` instead of `width`.

- **Cursor advance uses next-character lookahead**: The positioning loop at line 211-221 advances the cursor by the *next* character's width (`text[i+1]`), not the current character's. For the last character it falls back to its own width. This is an unusual approach and may produce slightly off spacing for variable-width fonts.

- **Shrinking text destroys from front**: When the string gets shorter, sprites at indices `1..difference` are destroyed, then the array is compacted. This means the *first* N sprites are removed, not the last N. The sprites are then all reconfigured anyway, so the visual result is correct, but it is less efficient than removing from the tail.

- **`automatic_update = false` requires manual `:Update(dt)`**: The caller must call `textObj:Update(dt)` every frame from `RenderStepped`. If you forget, no text will appear or update. The `true` option hooks `RenderStepped` internally but creates one connection per Text object.

- **`Destroyed` flag on TextSprite**: `UpdateSprite` checks `self.Destroyed` and early-returns. Once a sprite is destroyed, it cannot be reused. The parent `Text` object filters destroyed sprites out of the array during text shrink.

- **`CanUpdate` flag on Text**: Set to `false` by `Destroy()`. The `Update` method early-returns if this is false.

- **yoffset is halved**: In `Text:Update()` line 182, the glyph's `yoffset` is divided by 2 when creating the animation frame: `Offset = Vector2.new(frame.xoffset, (frame.yoffset / 2))`. This is a deliberate adjustment, likely to compensate for the font metrics being generated at a different reference size.

- **No newline support**: The library does not handle `\n` or multi-line text. All characters are laid out on a single horizontal line.

- **XMLParser is unused for font rendering**: The XMLParser module and `LoadGraphic`/`AddByPrefix` methods exist for general spritesheet animation. Font rendering uses `LoadImage` + `AddManual` exclusively. The XMLParser is only relevant if TextSprite is used for non-font animated sprites.

- **No text measurement API**: There is no method to measure the pixel width of a string without rendering it. You would need to manually sum `FontData[Unicode[char]].width` (or `xadvance` for spaces) times `TextSize`.
