# BoxDrawing — Usage Reference

Module: `ReplicatedStorage.Text.BoxDrawing`

Both fonts are monospaced at `xadvance=14` pixels. All positions are `Vector2` in 1920×1080 virtual coordinates. `width` is in characters (including the corner/border chars). `textSize` scales glyph size (default 1). `zIndex` sets ImageLabel ZIndex (default 1).

---

## 1. `topString` / `newTop` — Top border of a box

```lua
-- Just the string (for use with an existing Text object):
local s = BoxDrawing.topString(20)
-- s = [187][141 x 18][189]  →  ╔══════════════════╗

-- With no left corner (plain line on left):
local s = BoxDrawing.topString(20, { noLeftCorner = true })
-- s = [141 x 20]  →  ══════════════════════

-- Create a Text object directly:
local top = BoxDrawing.newTop(Vector2.new(100, 200), 20, nil, 1.5, 5)
top.TextColor3 = Color3.fromRGB(200, 180, 80)
top.Parent = textParent
```

---

## 2. `bottomString` / `newBottom` — Bottom border of a box

```lua
local s = BoxDrawing.bottomString(20)
-- s = [156][154 x 18][158]  →  ╚══════════════════╝

-- No right corner:
local s = BoxDrawing.bottomString(20, { noRightCorner = true })

local bottom = BoxDrawing.newBottom(Vector2.new(100, 300), 20, nil, 1.5, 5)
bottom.TextColor3 = Color3.fromRGB(200, 180, 80)
bottom.Parent = textParent
```

---

## 3. `dividerString` / `newDivider` — Shared border between two stacked boxes

```lua
local s = BoxDrawing.dividerString(20)
-- s = [136][157 x 18][137]  →  ╠══════════════════╣
-- Glyph 136/137 are dual-purpose: bottom corner of upper box + top corner of lower box

local div = BoxDrawing.newDivider(Vector2.new(100, 300), 20, 1.5, 5)
div.TextColor3 = Color3.fromRGB(200, 180, 80)
div.Parent = textParent
```

---

## 4. `rowBorderString` / `newRow` — A content row with vertical bars

```lua
-- String only (just the border chars, spaces inside):
local s = BoxDrawing.rowBorderString(20)
-- s = [129][space x 18][129]  →  |                  |

-- Full row object (mixed fonts — thick bars + standard text inside):
local row = BoxDrawing.newRow(Vector2.new(100, 250), 20, 1.5, 5)
row.border.TextColor3 = Color3.fromRGB(200, 180, 80)
row.content.TextColor3 = Color3.fromRGB(200, 180, 80)
row.border.Parent = textParent
row.content.Parent = textParent
row.setContent("HONG KONG")   -- pads/truncates to fit inner width (18 chars)

-- Must call each frame:
RunService.RenderStepped:Connect(function(dt)
    row.update(dt)
end)

-- When done:
row.destroy()
```

---

## Complete box example

```lua
local X, Y = 100, 200
local W = 20
local SIZE = 1.5
local CHAR_H = math.floor(16 * SIZE)
local COLOR = Color3.fromRGB(200, 180, 80)

local top = BoxDrawing.newTop(Vector2.new(X, Y), W, nil, SIZE, 5)
local row = BoxDrawing.newRow(Vector2.new(X, Y + CHAR_H), W, SIZE, 5)
local bot = BoxDrawing.newBottom(Vector2.new(X, Y + CHAR_H*2), W, nil, SIZE, 5)

top.TextColor3 = COLOR; top.Parent = textParent
row.border.TextColor3 = COLOR; row.border.Parent = textParent
row.content.TextColor3 = COLOR; row.content.Parent = textParent
bot.TextColor3 = COLOR; bot.Parent = textParent

row.setContent("CASH: 400")

RunService.RenderStepped:Connect(function(dt)
    top:Update(dt)
    row.update(dt)
    bot:Update(dt)
end)
```
