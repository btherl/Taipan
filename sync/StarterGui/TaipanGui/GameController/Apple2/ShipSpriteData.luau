-- ShipSpriteData.lua
-- Pure data module for combat ship sprites and damage fragments.
-- Mirrors BASIC variables SH$ (line 10250) and DM$/DL% (lines 10270-10300)
-- from references/taipan-applesoft-annotated.txt.

local ShipSpriteData = {}

-- Base 5-row x 7-col ship sprite (from BASIC SH$).
ShipSpriteData.baseSprite = {
  "ABCDEFG",
  "HIJKLMN",
  "OIJKLPQ",
  "RSTUVWX",
  "YJJJJJZ",
}

-- Damage fragments. Indexed [1..6][0..1].
-- chars: array of strings (length 1 = single-row fragment, length 2 = two-row fragment).
-- dx, dy: offset in 0-based char coords from the slot's top-left.
-- Source: BASIC line 10300:
--   DATA cde,20, r,3, fg*,mn,50, tu,23, ij,11, vw,43, 0,22, x*,z,63, kl,32, 12,14, pq,52, 345,34
-- (Decoded as 6 fragment-pairs; the offset is encoded as 2 digits "tens=dx, units=dy".)
local function frag(chars, code)
  local dx = math.floor(code / 10)
  local dy = code - dx * 10
  return { chars = chars, dx = dx, dy = dy }
end

ShipSpriteData.damageFragments = {
  [1] = { [0] = frag({ "cde" },     20), [1] = frag({ "r" },        3) },
  [2] = { [0] = frag({ "fg", "mn" }, 50), [1] = frag({ "tu" },      23) },
  [3] = { [0] = frag({ "ij" },      11), [1] = frag({ "vw" },      43) },
  [4] = { [0] = frag({ "0" },       22), [1] = frag({ "x", "z" },  63) },
  [5] = { [0] = frag({ "kl" },      32), [1] = frag({ "12" },      14) },
  [6] = { [0] = frag({ "pq" },      52), [1] = frag({ "345" },     34) },
}

-- newDamageGrid: returns a 5-row sparse map; grid[row][col] = override char, or nil.
function ShipSpriteData.newDamageGrid()
  local g = {}
  for r = 1, 5 do g[r] = {} end
  return g
end

-- applyDamageFragment: mutate grid by writing the chars of fragment[idx][zone] at its (dx, dy).
-- Rows / cols are 1-based; dx / dy are 0-based offsets.
function ShipSpriteData.applyDamageFragment(grid, idx, zone)
  local f = ShipSpriteData.damageFragments[idx][zone]
  for rowOffset, segment in ipairs(f.chars) do
    local rowIdx = f.dy + rowOffset
    if rowIdx >= 1 and rowIdx <= 5 then
      for c = 1, #segment do
        local colIdx = f.dx + c
        if colIdx >= 1 and colIdx <= 7 then
          grid[rowIdx][colIdx] = segment:sub(c, c)
        end
      end
    end
  end
end

-- renderRows: produce 5 strings of length 7, with damage cells overlaid on the base sprite.
function ShipSpriteData.renderRows(grid)
  local rows = {}
  for r = 1, 5 do
    local base = ShipSpriteData.baseSprite[r]
    local out = {}
    for c = 1, 7 do
      out[c] = grid[r][c] or base:sub(c, c)
    end
    rows[r] = table.concat(out)
  end
  return rows
end

return ShipSpriteData
