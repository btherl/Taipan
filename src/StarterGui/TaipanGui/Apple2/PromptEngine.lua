-- PromptEngine.lua
-- Maps (state, localScene, actions, localSceneCb) -> { lines: table[], promptDef: table }
-- Pure logic: no Roblox service calls except require.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants   = require(ReplicatedStorage.shared.Constants)
local BoxDrawing  = require(ReplicatedStorage.Text.BoxDrawing)

local HONG_KONG  = Constants.HONG_KONG
local PORT_NAMES = Constants.PORT_NAMES
local MONTH_NAMES = Constants.MONTH_NAMES
local GOOD_NAMES = Constants.GOOD_NAMES

local GREEN  = Color3.fromRGB(140, 200, 80)
local AMBER  = Color3.fromRGB(200, 180, 80)
local RED    = Color3.fromRGB(220, 80, 80)
local ORANGE = Color3.fromRGB(220, 120, 60)
local DIM    = Color3.fromRGB(80, 80, 80)

local PromptEngine = {}

-- Good-name first-letter shortcut map: P=sPices(1), S=Silk(2), A=Arms(3), G=General(4)
local GOOD_KEY_MAP = { P = 1, S = 2, A = 3, G = 4 }

-- Helpers
local function pad(s, width)
  s = tostring(s)
  while #s < width do s = s .. " " end
  return s
end

local function fmt(n)
  local s = tostring(math.floor(n))
  local result = ""
  local count = 0
  for i = #s, 1, -1 do
    if count > 0 and count % 3 == 0 then result = "," .. result end
    result = s:sub(i, i) .. result
    count = count + 1
  end
  return "$" .. result
end

-- Abbreviated good names for the 26-char inner box (Constants.GOOD_NAMES[4] is "General Cargo", too long)
local SHORT_GOOD_NAMES = { "Spices", "Silk", "Arms", "General" }

-- Right-justify string to width (add spaces on left)
local function lpad(s, width)
  s = tostring(s)
  while #s < width do s = " " .. s end
  return s
end

-- Center string in `width` chars with space padding (truncates if over)
local function centerStr(s:string, width:number)
  local len = #s
  if len >= width then return s:sub(1, width) end
  local left = math.floor((width - len) / 2)
  return string.rep(" ", left) .. s .. string.rep(" ", width - len - left)
end

-- Center an arbitrary list of segments (each a table with .text and optional fields)
-- within `width` chars. Returns a new list with a leading space-segment prepended and
-- a trailing space-segment appended (omitted if the content already fills the width).
-- Each segment pair is { text=string, ...rest } where ...rest carries color/font/etc.
local function centerSeg(width, ...)
  local segs = ...
  local totalLen = 0
  for _, seg in ipairs(segs) do
    totalLen = totalLen + #seg.text
  end
  if totalLen >= width then return segs end
  local leftPad  = math.floor((width - totalLen) / 2)
  local rightPad = width - totalLen - leftPad
  local result = {}
  if leftPad > 0 then
    table.insert(result, { text = string.rep(" ", leftPad) })
  end
  for _, seg in ipairs(segs) do
    table.insert(result, seg)
  end
  if rightPad > 0 then
    table.insert(result, { text = string.rep(" ", rightPad) })
  end
  return result
end

-- Format number without $ prefix: plain comma int under 1M, "X.XX Suffix" above
local function fmtBig(n)
  n = math.floor(math.max(0, n))
  if n < 1000000 then
    local s, result, count = tostring(n), "", 0
    for i = #s, 1, -1 do
      if count > 0 and count % 3 == 0 then result = "," .. result end
      result = s:sub(i, i) .. result
      count += 1
    end
    return result
  end
  local II = math.floor(math.log(n) / math.log(10) + 1e-9)
  local IJ = math.floor(II / 3) * 3
  local disp = string.format("%.2f", n / (10 ^ IJ)):sub(1, 4)
  if disp:sub(-1) == "." then disp = disp:sub(1, -2) end
  local suffix = ({"Thousand","Million","Billion","Trillion"})[IJ/3] or "?"
  return disp .. " " .. suffix
end

-- Ship status: returns (statusText, isInverted)
-- sw = 100 - damage/shipCapacity*100 (0=destroyed, 100=perfect)
local function shipStatus(state)
  local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))
  local label = (sw >= 100 and "Perfect") or (sw >= 80 and "Prime") or
                (sw >= 60 and "Good")    or (sw >= 40 and "Fair")  or
                (sw >= 20 and "Poor")    or "Critical"
  local inverted = sw < 40
  return label .. ":" .. tostring(sw), inverted
end

local function statusLines(state)
  local lines = {}
  local portName = PORT_NAMES[state.currentPort] or "?"
  local dateStr  = MONTH_NAMES[state.month] .. " " .. tostring(state.year)
  table.insert(lines, { text = pad(portName:upper(), 28) .. dateStr, color = AMBER })
  table.insert(lines, { text = string.format("Cash:%-11s Debt:%s",
    fmt(state.cash), fmt(state.debt)), color = AMBER })
  table.insert(lines, { text = string.format("Bank:%-11s Guns:%d",
	fmt(state.bankBalance), state.guns), color = AMBER })
  local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))
  table.insert(lines, { text = string.format("Hold: %d/%d  Damage: %d%%",
    state.holdSpace or 0, state.shipCapacity or 0, 100 - sw), color = AMBER })
  return lines
end

local function priceLines(state)
  local lines = {}
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "Prices:", color = AMBER })
  local prices = state.currentPrices or {0,0,0,0}
  for i = 1, 4 do
    local name = pad(GOOD_NAMES[i] .. ":", 15)
    local price = fmt(prices[i])
    table.insert(lines, { text = " " .. name .. price, color = GREEN })
  end
  return lines
end

local function atPortMenu(state)
  local isHK = (state.currentPort == HONG_KONG)
  local nw    = (state.cash or 0) + (state.bankBalance or 0) - (state.debt or 0)
  local canRetire = isHK and nw >= 1000000
  local menuLines = { "(B)uy  (S)ell  (T)ravel" }
  if isHK then
    table.insert(menuLines, "(W)arehouse  (K)Bank")
  end
  local line3Parts = {}
  if canRetire then
    table.insert(line3Parts, "(R)etire")
  end
  table.insert(line3Parts, "(P)Settings  (Q)uit")
  table.insert(menuLines, table.concat(line3Parts, "  "))
  local validKeys = {"B", "S", "T", "P", "Q"}
  if isHK then
    table.insert(validKeys, "W")
    table.insert(validKeys, "K")
  end
  if canRetire then table.insert(validKeys, "R") end
  return menuLines, validKeys
end

local function buildPortRows(state)
  local rows = {}
  local VERT  = string.char(129)
  local THICK = "TaipanThickFont"
  local BOX_W   = 28  -- Width of Warehouse box and Hold box, on status screen
  local INNER_W = 26  -- Inside width of boxes
  local RIGHT_W = 12

  -- Derived values
  local firmName      = state.firmName or "TAIPAN"
  local portName      = PORT_NAMES[state.currentPort] or "Hong Kong"
  local monthName     = MONTH_NAMES[state.month] or "Jan"
  local yearStr       = tostring(state.year or 1860)
  local wh            = state.warehouseCargo or {0,0,0,0}
  local warehouseUsed = state.warehouseUsed or 0
  local vacant        = Constants.WAREHOUSE_CAPACITY - warehouseUsed
  local sc            = state.shipCargo or {0,0,0,0}
  local holdSpace     = state.holdSpace or 0
  local overloaded    = holdSpace < 0

  -- Inner helper: warehouse good row 26 chars: left 12 (good+qty) + right 14 (label/value right-justified)
  local function whInner(goodIdx, qty, rightText)
    local name = SHORT_GOOD_NAMES[goodIdx]
    local left = pad("   " .. pad(name, 7) .. " " .. tostring(qty), 13):sub(1, 13)
    local right = lpad(tostring(rightText), 13)
    return (left .. right):sub(1, INNER_W)
  end

  -- Inner helper: hold good row 26 chars: good+qty, rest spaces
  local function holdInner(goodIdx, qty)
    return pad("   " .. pad(SHORT_GOOD_NAMES[goodIdx], 7) .. " " .. tostring(qty), INNER_W):sub(1, INNER_W)
  end

  -- Build a segmented row: │inner│ + right-column segments
  local function boxRowSegs(innerText, rightSegs)
    local segs = {
      { text = VERT,                                       color = AMBER, font = THICK },
      { text = pad(innerText, INNER_W):sub(1, INNER_W),   color = AMBER },
      { text = VERT,                                       color = AMBER, font = THICK },
    }
    for _, s in ipairs(rightSegs) do table.insert(segs, s) end
    return { segments = segs }
  end

  -- Row 1: firm name centered over 40 cols
  local firmSeg = {
    {text = "Firm: ", color = AMBER},
    {text = firmName, color = AMBER, font = "TaipanThickFont"},
    {text = ", Hong Kong", color = AMBER}
  }
  local firmSegCentered = centerSeg(40, firmSeg)
  rows[1] = { segments = firmSegCentered }

  -- Row 2: box top border (28 wide), no right content
  rows[2] = { segments = {{ text = BoxDrawing.topString(BOX_W), color = AMBER, font = THICK }}}

  -- Row 3: warehouse header + "Date" label
  rows[3] = boxRowSegs("Hong Kong Warehouse", {{ text = "    Date    ", color = AMBER }})

  -- Row 4: Spices in warehouse + date (with inverted month)
  -- Right col: " 15 " + INVERTED(monthName) + " " + yearStr = 4+3+1+4 = 12 chars
  rows[4] = boxRowSegs(
    whInner(1, wh[1], "In use:"),
    {
      { text = " 15 ",    color = AMBER },
      { text = monthName, color = AMBER, inverted = true },
      { text = " " .. yearStr, color = AMBER },
    }
  )

  -- Row 5: Silk in warehouse + warehouse used value (right col empty)
  rows[5] = boxRowSegs(
    whInner(2, wh[2], pad(warehouseUsed, 6)),
    {{ text = string.rep(" ", RIGHT_W), color = AMBER }}
  )

  -- Row 6: Arms in warehouse + "Location" label
  rows[6] = boxRowSegs(
    whInner(3, wh[3], "Vacant:"),
    {{ text = "  Location  ", color = AMBER }}
  )

  -- Row 7: General in warehouse + inverted location name
  -- Location centered in 8 chars (matching "Location" label width) if <=8; left-aligned if longer
  local locDisp = (#portName <= 8) and centerStr(portName, 8) or portName
  rows[7] = boxRowSegs(
    whInner(4, wh[4], pad(vacant, 6)),
    {
      { text = "  ",     color = AMBER },
      { text = locDisp,  color = AMBER, inverted = true },
      { text = string.rep(" ", math.max(0, RIGHT_W - 2 - #locDisp)), color = AMBER },
    }
  )

  -- Row 8: box divider (├──...──┤), no right content
  rows[8] = { segments = {{ text = BoxDrawing.dividerString(BOX_W), color = AMBER, font = THICK }}}

  -- Row 9: Hold/Guns header + "Debt" label
  -- If overloaded, "Overload" shown inverted instead of holdSpace number
  if not overloaded then
    local gunsStr = "Guns " .. tostring(state.guns or 0)
	local holdStr = "Hold " .. tostring(holdSpace)
	local holdPadStr = pad(holdStr, 15)
	local gunPadStr = pad(gunsStr, 11)
    local inner9  = holdPadStr .. gunsStr
    rows[9] = boxRowSegs(inner9, {{ text = "    Debt    ", color = AMBER }})
  else
	local gunsStr = "Guns " .. tostring(state.guns or 0)
	local gunPadStr = pad(gunsStr, 11)
    rows[9] = { segments = {
      { text = VERT,                          color = AMBER, font = THICK },
      { text = "Hold ",                       color = AMBER },
      { text = "Overload",                    color = AMBER, inverted = true },
      { text = string.rep(" ", 2),            color = AMBER },
      { text = gunPadStr,                     color = AMBER },
      { text = VERT,                          color = AMBER, font = THICK },
      { text = "    Debt    ",                color = AMBER },
    }}
  end

  -- Row 10: Spices in hold + inverted debt value (centered in 12-char right col)
  local debtStr = fmtBig(state.debt or 0)
  local dPad    = math.floor((RIGHT_W - #debtStr) / 2)
  rows[10] = boxRowSegs(holdInner(1, sc[1]), {
    { text = string.rep(" ", dPad),                               color = AMBER },
    { text = debtStr,                                              color = AMBER, inverted = true },
    { text = string.rep(" ", math.max(0, RIGHT_W - dPad - #debtStr)), color = AMBER },
  })

  -- Row 11: Silk in hold, right col empty
  rows[11] = boxRowSegs(holdInner(2, sc[2]), {{ text = string.rep(" ", RIGHT_W), color = AMBER }})

  -- Row 12: Arms in hold + "Ship status" label
  rows[12] = boxRowSegs(holdInner(3, sc[3]), {{ text = " Ship status", color = AMBER }})

  -- Row 13: General in hold + ship status (inverted when sw < 40, full 11-char block)
  local statusText, statusInv = shipStatus(state)
  local statusDisp = centerStr(statusText, 11)
  rows[13] = boxRowSegs(holdInner(4, sc[4]), {
    { text = " ",        color = AMBER },
    { text = statusDisp, color = AMBER, inverted = statusInv },
  })

  -- Row 14: box bottom border (└──...──┘), no right content
  rows[14] = { segments = {{ text = BoxDrawing.bottomString(BOX_W), color = AMBER, font = THICK }}}

  -- Row 15: Cash and Bank (right-aligned)
  local cashStr = "Cash:" .. fmtBig(state.cash or 0)
  local bankStr = "Bank:" .. fmtBig(state.bankBalance or 0)
  local cashPadStr = pad(cashStr, 20)
  local bankPadStr = pad(bankStr, 20)
  rows[15] = { text = cashPadStr .. bankPadStr, color = AMBER }

  -- Row 16: separator line
  rows[16] = { text = string.rep("_", 40), color = AMBER }

  return rows
end

local function sceneAtPort(state, actions, localSceneCb)
  local rows = buildPortRows(state)
  rows[17] = { text = "", color = AMBER }
  local menuLines, validKeys = atPortMenu(state)
  for i, ml in ipairs(menuLines) do
    rows[17 + i] = { text = ml, color = GREEN }
  end
  local promptDef = {
    type = "key",
    keys = validKeys,
    label = menuLines[#menuLines],
    onKey = function(key, _state, _actions)
      if key == "B" or key == "S" then
        if localSceneCb then localSceneCb(key == "B" and "buy" or "sell") end
      elseif key == "W" then
        if localSceneCb then localSceneCb("warehouse") end
      elseif key == "K" then
        if localSceneCb then localSceneCb("bank") end
      elseif key == "T" then
        if localSceneCb then localSceneCb("travel") end
      elseif key == "R" then
        actions.retire()
      elseif key == "Q" then
        if localSceneCb then localSceneCb("quit_confirm") end
      elseif key == "P" then
        if localSceneCb then localSceneCb("settings") end
      end
    end,
  }
  return { rows = rows }, promptDef
end

local function sceneTravel(state, actions, localSceneCb)
  local lines = {}
  for _, l in ipairs(statusLines(state)) do table.insert(lines, l) end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "Sail to which port?", color = AMBER })
  local validKeys = {"C"}
  for i = 1, 7 do
    if i ~= state.currentPort then
      table.insert(lines, { text = string.format("  [%d] %s", i, PORT_NAMES[i]), color = GREEN })
      table.insert(validKeys, tostring(i))
    end
  end
  table.insert(lines, { text = "  [C] Cancel", color = DIM })
  return lines, {
    type = "key",
    keys = validKeys,
    label = "Select port number or C to cancel",
    onKey = function(key, _state, _actions)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      else
        local dest = tonumber(key)
        if dest and dest >= 1 and dest <= 7 and dest ~= state.currentPort then
          actions.travelTo(dest)
          if localSceneCb then localSceneCb(nil) end
        end
      end
    end,
  }
end

local FIRM_INPUT_ROW = 14

local function buildFirmInputRow(displayStr)
  return { segments = {
    { text = string.char(129), color = AMBER, font = "TaipanThickFont" },
    { text = "     Firm: ",   color = AMBER },
    { text = displayStr,      color = AMBER, font = "TaipanThickFont" },
    { text = "    ",          color = AMBER },
    { text = string.char(129), color = AMBER, font = "TaipanThickFont" },
  }}
end

local function sceneFirmName(_state, actions, localSceneCb)
  local initDisplay = "_" .. string.rep(" ", 22)
  local rows = {
    [8]  = BoxDrawing.boxTop(40, AMBER),
    [9]  = BoxDrawing.boxRow(40, "", AMBER),
    [10] = BoxDrawing.boxRow(40, "     Taipan,", AMBER),
    [11] = BoxDrawing.boxRow(40, "", AMBER),
    [12] = BoxDrawing.boxRow(40, " What will you name your", AMBER),
    [13] = BoxDrawing.boxRow(40, "", AMBER),
    [14] = buildFirmInputRow(initDisplay),
    [15] = BoxDrawing.boxRow(40, "           ----------------------", AMBER),
    [16] = BoxDrawing.boxRow(40, "", AMBER),
    [17] = BoxDrawing.boxBottom(40, AMBER),
  }
  return { rows = rows }, {
    type            = "type",
    typePlaceholder = "",
    maxLength       = 22,
    _inputRow       = FIRM_INPUT_ROW,
    _buildInputRow  = buildFirmInputRow,
    onType = function(text, _s, _a)
      actions.setFirmName(text)
      if localSceneCb then localSceneCb("start_choice") end
      return nil
    end,
  }
end

local function sceneStartChoice(_state, actions, _localSceneCb)
  local lines = {
    { text = "Do you want to start . . .", color = AMBER },
	{ text = "", color = AMBER },
	{ text = "", color = AMBER },
	{ text = "  1) With cash (and a debt)", color = AMBER },
	{ text = "", color = AMBER },
	{ text = "", color = AMBER },
	{ text = string.rep(" ", 16) .. ">> or <<", color = AMBER},
	{ text = "", color = AMBER },
	{ text = "", color = AMBER },
	{ text = "  2) With five guns and no cash", color = AMBER },
	{ text = string.rep(" ", 16) .. "(But no debt!)", color = AMBER},
	{ text = "", color = AMBER },
	{ text = "", color = AMBER },
	{ text = string.rep(" ", 10) .. "?", color = AMBER},
  }
  return lines, {
    type = "key",
    keys = {"1", "2"},
    label = "Debt or Cash",
    onKey = function(key, _s, _a)
      if key == "1" then actions.chooseStart("cash")
      elseif key == "2" then actions.chooseStart("guns")
      end
    end,
  }
end

local function sceneGameOver(state, actions, _localSceneCb)
  local reason = state.gameOverReason or "unknown"
  local lines = {
    { text = "GAME OVER", color = RED },
    { text = "",          color = AMBER },
  }
  if reason == "sunk" then
    table.insert(lines, { text = "Your ship was sunk, Taipan!", color = RED })
  elseif reason == "retired" then
    table.insert(lines, { text = "You have retired, Taipan!", color = GREEN })
    if state.finalScore then
      table.insert(lines, { text = string.format("Final score: %d (%s)",
        state.finalScore, state.finalRating or ""), color = AMBER })
    end
  elseif reason == "quit" then
    table.insert(lines, { text = "You quit, Taipan!", color = AMBER })
  end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "(R)estart", color = GREEN })
  return lines, {
    type = "key",
    keys = {"R"},
    label = "(R)estart",
    onKey = function(_key, _s, _a) actions.restartGame() end,
  }
end

local function sceneSettings(state, actions, localSceneCb)
  local currentMode = state.uiMode or "modern"
  local lines = {
    { text = "Switch interface?", color = AMBER },
    { text = "", color = AMBER },
    { text = "[M] Modern   -- touch panels" .. (currentMode == "modern"  and " *" or ""), color = currentMode == "modern"  and DIM or GREEN },
    { text = "[A] Apple II -- terminal"     .. (currentMode == "apple2"  and " *" or ""), color = currentMode == "apple2"  and DIM or GREEN },
    { text = "(* = current mode)", color = DIM },
    { text = "[C] Cancel",                             color = AMBER },
  }
  return lines, {
    type = "key",
    keys = {"M", "A", "C"},
    label = "(M)odern  (A)pple II  (C)ancel",
    onKey = function(key, _s, _a)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      elseif key == "M" and currentMode ~= "modern" then
        actions.setUIMode("modern")
      elseif key == "A" and currentMode ~= "apple2" then
        actions.setUIMode("apple2")
      else
        if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
end

local function sceneQuitConfirm(_state, actions, localSceneCb)
  local lines = {
    { text = "Quit game? (Y/N)", color = AMBER },
  }
  return lines, {
    type = "key",
    keys = {"Y", "N"},
    label = "Quit game? (Y/N)",
    onKey = function(key, _s, _a)
      if key == "Y" then
        actions.quitGame()
      elseif key == "N" then
        if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
end

local function sceneCombatLayout(state, actions, localSceneCb)
  local combat  = state.combat or {}
  local total   = combat.enemyTotal or 0
  local grid    = combat.grid or {}
  local guns    = state.guns or 0
  local sw      = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))
  local swLabel = (sw >= 100 and "Perfect") or (sw >= 80 and "Prime") or
                  (sw >= 60 and "Good")    or (sw >= 40 and "Fair")  or
                  (sw >= 20 and "Poor")    or "Critical"
  local swInv   = sw < 40

  -- 10-slot ship grid: # = alive, . = empty
  local gridStr = ""
  for i = 1, 10 do
    gridStr = gridStr .. (grid[i] ~= nil and "#" or ".")
  end

  -- Col 32 onward (9 chars): "| We have" / "|  N guns" / "+--------"
  local RIGHT_W   = 9
  local col1Width = 40 - RIGHT_W  -- 31 chars for left column

  local function row17()
    local left = pad(string.format("   %d ships attacking, Taipan!", total), col1Width)
    return { text = left .. "| We have", color = AMBER }
  end

  local function row18()
    local left = pad("Your orders are to:", col1Width)
    -- Right col: "|" + lpad(guns,3) + " guns" = 9 chars total
    return { text = left .. "|" .. lpad(tostring(guns), 3) .. " guns", color = AMBER }
  end

  local function row19()
    return { text = string.rep(" ", col1Width) .. "+--------", color = AMBER }
  end

  local function row20()
    local label = swLabel .. " (" .. tostring(sw) .. "%)"
    local seg = {
      { text = "Current seaworthiness: ", color = AMBER },
      { text = label, color = AMBER, inverted = swInv },
    }
    return { segments = seg }
  end

  local function row21()
    return { text = "  Ships: [" .. gridStr .. "]", color = GREEN }
  end

  local rows = {}
  rows[17] = row17()
  rows[18] = row18()
  rows[19] = row19()
  rows[20] = row20()
  rows[21] = row21()
  for r = 22, 24 do rows[r] = { text = "", color = AMBER } end

  -- Also populate the status screen (rows 1-16)
  local statusRows = buildPortRows(state)
  for r = 1, 16 do
    rows[r] = statusRows[r]
  end

  local promptDef = {
    type = "key",
    keys = { "F", "R", "T" },
    label = "(F)ight  (R)un  (T)hrow",
    onKey = function(key, _state, _actions)
      if key == "F" then actions.combatFight()
      elseif key == "R" then actions.combatRun()
      elseif key == "T" then
        if localSceneCb then localSceneCb("combat_throw_good") end
      end
    end,
  }
  return { rows = rows }, promptDef
end

local function sceneCombatThrowGood(state, actions, localSceneCb)
  local lines = {
    { text = "Throw which cargo overboard?", color = AMBER },
  }
  for i = 1, 4 do
    if (state.shipCargo[i] or 0) > 0 then
      table.insert(lines, { text = string.format("  [%d] %s: %d units", i, GOOD_NAMES[i], state.shipCargo[i]), color = AMBER })
    end
  end
  table.insert(lines, { text = "  [C] Cancel", color = DIM })
  return lines, {
    type = "key",
    keys = {"1","2","3","4","P","S","A","G","C"},
    label = "sPices Silk Arms General Cancel",
    onKey = function(key, _s, _a)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      else
        local idx = GOOD_KEY_MAP[key] or tonumber(key)
        if idx and idx >= 1 and idx <= 4 then
          if (state.shipCargo[idx] or 0) <= 0 then
            if localSceneCb then localSceneCb("combat_throw_good") end
          else
            if localSceneCb then localSceneCb("combat_throw_amt_" .. idx) end
          end
        end
      end
    end,
  }
end

local function sceneCombatThrowAmount(state, actions, localSceneCb, goodIdx)
  local goodName = GOOD_NAMES[goodIdx]
  local maxQty   = state.shipCargo[goodIdx] or 0
  local lines = {
    { text = string.format("Throw %s (max %d, A=all):", goodName, maxQty), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount: ",
    maxLength = 8,
    onType = function(text, _s, _a)
      if text == "" then
        if localSceneCb then localSceneCb("combat_throw_good") end
        return nil
      end
      local qty
      if text:upper() == "A" then qty = maxQty
      else qty = tonumber(text) end
      if not qty or qty < 0 then return "Enter a positive number or A for all" end
      if qty == 0 then
        if localSceneCb then localSceneCb("combat_throw_good") end
        return nil
      end
      if qty > maxQty then return string.format("Only %d available", maxQty) end
      actions.combatThrow(goodIdx, math.floor(qty))
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneShipOffers(state, actions, localSceneCb)
  local offer = state.shipOffer
  local lines = {
    { text = "[ HONG KONG -- SHIP OFFERS ]", color = AMBER },
    { text = "", color = AMBER },
  }
  local keys = {"D"}
  if offer and offer.upgradeOffer then
    table.insert(lines, { text = string.format("Upgrade ship (+50 tons) for %s", fmt(offer.upgradeOffer.cost)), color = GREEN })
    table.insert(lines, { text = "(U)pgrade  (N)o thanks", color = GREEN })
    table.insert(keys, "U")
    table.insert(keys, "N")
  end
  if offer and offer.gunOffer then
    table.insert(lines, { text = "", color = AMBER })
    table.insert(lines, { text = string.format("Buy cannon for %s (-10 hold)", fmt(offer.gunOffer.cost)), color = GREEN })
    table.insert(lines, { text = "(G)un  (X) No cannon", color = GREEN })
    table.insert(keys, "G")
    table.insert(keys, "X")
  end
  if offer and offer.repairRate and (state.damage or 0) > 0 then
    local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))
    table.insert(lines, { text = "", color = AMBER })
    table.insert(lines, { text = string.format("Repair: %s/pt  SW:%d%%  Dmg:%d",
      fmt(offer.repairRate), sw, math.floor(state.damage or 0)), color = AMBER })
    table.insert(lines, { text = "(R)epair -- enter amount, A=all", color = GREEN })
    table.insert(keys, "R")
  end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "(D)one", color = AMBER })
  return lines, {
    type = "key",
    keys = keys,
    label = "Select option or D to finish",
    onKey = function(key, _s, _a)
      if key == "U" then actions.acceptUpgrade()
      elseif key == "N" then actions.declineUpgrade()
      elseif key == "G" then actions.acceptGun()
      elseif key == "X" then actions.declineGun()
      elseif key == "D" then actions.shipPanelDone()
      elseif key == "R" then
        if localSceneCb then localSceneCb("repair") end
      end
    end,
  }
end

local function sceneWuSession(state, actions, localSceneCb)
  local maxRepay  = math.min(state.debt or 0, state.cash or 0)
  local maxBorrow = 2 * (state.cash or 0)
  local lines = {
    { text = "ELDER BROTHER WU",                    color = AMBER },
    { text = string.format("Debt:%-13s Repay:%s", fmt(state.debt), fmt(maxRepay)), color = AMBER },
    { text = string.format("Borrow max:%s", fmt(maxBorrow)), color = AMBER },
    { text = "",                                     color = AMBER },
  }
  if state.liYuenOfferCost then
    table.insert(lines, { text = string.format("Li Yuen asks %s for protection", fmt(state.liYuenOfferCost)), color = GREEN })
    table.insert(lines, { text = "(L)i Yuen", color = GREEN })
  end
  table.insert(lines, { text = "(P)ay debt  (B)orrow  (Q)Leave Wu", color = GREEN })
  local keys = {"P", "B", "Q"}
  if state.liYuenOfferCost then table.insert(keys, "L") end
  return lines, {
    type = "key",
    keys = keys,
    label = "(P)ay  (B)orrow  (Q)Leave  (L)iYuen",
    onKey = function(key, _s, _a)
      if key == "P" then
        if localSceneCb then localSceneCb("wu_repay") end
      elseif key == "B" then
        if localSceneCb then localSceneCb("wu_borrow") end
      elseif key == "Q" then
        actions.leaveWu()
      elseif key == "L" then
        actions.buyLiYuen()
      end
    end,
  }
end

local function sceneBuySell(state, actions, localSceneCb, isBuy)
  local verb = isBuy and "buy" or "sell"
  local lines = {}
  for _, l in ipairs(statusLines(state)) do table.insert(lines, l) end
  for _, l in ipairs(priceLines(state)) do table.insert(lines, l) end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = string.format("Which good to %s?", verb), color = GREEN })
  table.insert(lines, { text = " sPices Silk Arms General", color = GREEN })
  for i = 1, 4 do
    local available
    if isBuy then
      if state.currentPort == HONG_KONG then
        local p = (state.currentPrices or {})[i] or 0
        available = math.floor((state.cash or 0) / math.max(1, p))
      else
        available = state.holdSpace or 0
      end
    else
      available = state.shipCargo[i] or 0
    end
    table.insert(lines, { text = string.format("  [%d] %s (avail: %d)", i, GOOD_NAMES[i], available), color = AMBER })
  end
  table.insert(lines, { text = "  [C] Cancel", color = DIM })
  return lines, {
    type = "key",
    keys = {"1","2","3","4","P","S","A","G","C"},
    label = "sPices Silk Arms General Cancel",
    onKey = function(key, _s, _a)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      else
        local idx = GOOD_KEY_MAP[key] or tonumber(key)
        if idx and idx >= 1 and idx <= 4 then
          local price = (state.currentPrices or {})[idx] or 0
          local maxQty
          if isBuy then
            local affordable = math.floor((state.cash or 0) / math.max(1, price))
            if state.currentPort == HONG_KONG then
              maxQty = affordable
            else
              maxQty = math.min(affordable, state.holdSpace or 0)
            end
          else
            maxQty = state.shipCargo[idx] or 0
          end
          if maxQty <= 0 then
            if localSceneCb then localSceneCb(isBuy and "buy" or "sell") end
          else
            if localSceneCb then localSceneCb(isBuy and ("buy_good_"..idx) or ("sell_good_"..idx)) end
          end
        end
      end
    end,
  }
end

local function sceneBuySellAmount(state, actions, localSceneCb, goodIdx, isBuy)
  local goodName  = GOOD_NAMES[goodIdx]
  local price     = (state.currentPrices or {})[goodIdx] or 0
  local maxQty
  if isBuy then
    local affordable = math.floor((state.cash or 0) / math.max(1, price))
    if state.currentPort == HONG_KONG then
      maxQty = affordable
    else
      maxQty = math.min(affordable, state.holdSpace or 0)
    end
  else
    maxQty = state.shipCargo[goodIdx] or 0
  end
  local verb = isBuy and "buy" or "sell"
  local lines = {
    { text = string.format("%s %s at %s", verb:upper(), goodName, fmt(price)), color = AMBER },
    { text = string.format("Max %d, A=all.", maxQty), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount: ",
    maxLength = 8,
    onType = function(text, _s, _a)
      if text == "" then
        if localSceneCb then localSceneCb(isBuy and "buy" or "sell") end
        return nil
      end
      local qty
      if text:upper() == "A" then qty = maxQty
      else qty = tonumber(text) end
      if not qty or qty < 0 then return "Enter a number or A for all" end
      if qty == 0 then
        if localSceneCb then localSceneCb(isBuy and "buy" or "sell") end
        return nil
      end
      if qty > maxQty then return string.format("You can only %s %d units", verb, maxQty) end
      if isBuy then actions.buyGoods(goodIdx, math.floor(qty))
      else           actions.sellGoods(goodIdx, math.floor(qty)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneBank(state, actions, localSceneCb)
  local lines = {
    { text = "BANK OF HONG KONG",                        color = AMBER },
    { text = string.format("Balance: %s  Cash: %s", fmt(state.bankBalance), fmt(state.cash)), color = AMBER },
    { text = "",                                          color = AMBER },
    { text = "(D)eposit  (W)ithdraw  (C)ancel",          color = GREEN },
  }
  return lines, {
    type = "key",
    keys = {"D", "W", "C"},
    label = "(D)eposit  (W)ithdraw  (C)ancel",
    onKey = function(key, _s, _a)
      if key == "D" then
        if (state.cash or 0) <= 0 then
          if localSceneCb then localSceneCb("bank") end
        else
          if localSceneCb then localSceneCb("bank_deposit") end
        end
      elseif key == "W" then
        if (state.bankBalance or 0) <= 0 then
          if localSceneCb then localSceneCb("bank") end
        else
          if localSceneCb then localSceneCb("bank_withdraw") end
        end
      elseif key == "C" then
        if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
end

local function sceneBankAmount(state, actions, localSceneCb, isDeposit)
  local maxAmt = isDeposit and (state.cash or 0) or (state.bankBalance or 0)
  local verb = isDeposit and "deposit" or "withdraw"
  local lines = {
    { text = string.format("%s (max %s, A=all):", verb:upper(), fmt(maxAmt)), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount: ",
    maxLength = 8,
    onType = function(text, _s, _a)
      if text == "" then
        if localSceneCb then localSceneCb("bank") end
        return nil
      end
      local amt
      if text:upper() == "A" then amt = maxAmt
      else amt = tonumber(text) end
      if not amt or amt < 0 then return "Enter a positive amount or A for all" end
      if amt == 0 then
        if localSceneCb then localSceneCb("bank") end
        return nil
      end
      if amt > maxAmt then return string.format("Max %s is %s", verb, fmt(maxAmt)) end
      if isDeposit then actions.bankDeposit(math.floor(amt))
      else              actions.bankWithdraw(math.floor(amt)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneWarehouse(state, actions, localSceneCb)
  local lines = {
    { text = "HONG KONG WAREHOUSE",                             color = AMBER },
    { text = string.format("Warehouse used: %d / %d",
        state.warehouseUsed or 0, Constants.WAREHOUSE_CAPACITY), color = AMBER },
    { text = "",                                                  color = AMBER },
  }
  for i = 1, 4 do
    table.insert(lines, { text = string.format(" %-14s Ship:%-5d WH:%d",
      GOOD_NAMES[i], state.shipCargo[i] or 0, state.warehouseCargo[i] or 0), color = AMBER })
  end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "(T)o WH  (F)rom WH  (C)ancel", color = GREEN })
  return lines, {
    type = "key",
    keys = {"T", "F", "C"},
    label = "(T)o warehouse  (F)rom warehouse  (C)ancel",
    onKey = function(key, _s, _a)
      if key == "T" then if localSceneCb then localSceneCb("wh_to") end
      elseif key == "F" then if localSceneCb then localSceneCb("wh_from") end
      elseif key == "C" then if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
end

local function sceneWarehouseGood(state, actions, localSceneCb, isToWarehouse)
  local direction = isToWarehouse and "TO warehouse" or "FROM warehouse"
  local lines = {
    { text = string.format("Transfer %s -- which good?", direction), color = AMBER },
    { text = " sPices Silk Arms General", color = GREEN },
  }
  for i = 1, 4 do
    local avail = isToWarehouse and (state.shipCargo[i] or 0) or (state.warehouseCargo[i] or 0)
    table.insert(lines, { text = string.format("  [%d] %s (%d avail)", i, GOOD_NAMES[i], avail), color = AMBER })
  end
  table.insert(lines, { text = "  [C] Cancel", color = DIM })
  return lines, {
    type = "key",
    keys = {"1","2","3","4","P","S","A","G","C"},
    label = "sPices Silk Arms General Cancel",
    onKey = function(key, _s, _a)
      if key == "C" then if localSceneCb then localSceneCb(nil) end
      else
        local idx = GOOD_KEY_MAP[key] or tonumber(key)
        if idx then
          if localSceneCb then localSceneCb(isToWarehouse and ("wh_to_"..idx) or ("wh_from_"..idx)) end
        end
      end
    end,
  }
end

local function sceneWarehouseAmount(state, actions, localSceneCb, goodIdx, isToWarehouse)
  local goodName = GOOD_NAMES[goodIdx]
  local maxAmt   = isToWarehouse and (state.shipCargo[goodIdx] or 0)
                                  or (state.warehouseCargo[goodIdx] or 0)
  local dir = isToWarehouse and "to WH" or "from WH"
  local lines = {
    { text = string.format("%s %s (max %d, A=all):", goodName, dir, maxAmt), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount: ",
    maxLength = 8,
    onType = function(text, _s, _a)
      if text == "" then
        if localSceneCb then localSceneCb(isToWarehouse and "wh_to" or "wh_from") end
        return nil
      end
      local qty
      if text:upper() == "A" then qty = maxAmt
      else qty = tonumber(text) end
      if not qty or qty < 0 then return "Enter a positive amount or A" end
      if qty == 0 then
        if localSceneCb then localSceneCb(isToWarehouse and "wh_to" or "wh_from") end
        return nil
      end
      if qty > maxAmt then return string.format("Only %d available", maxAmt) end
      if isToWarehouse then actions.transferTo(goodIdx, math.floor(qty))
      else                  actions.transferFrom(goodIdx, math.floor(qty)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneWuAmount(state, actions, localSceneCb, isRepay)
  local maxAmt = isRepay
    and math.min(state.debt or 0, state.cash or 0)
    or  2 * (state.cash or 0)
  local verb = isRepay and "repay" or "borrow"
  local lines = {
    { text = string.format("%s (max %s, A=all):", verb:upper(), fmt(maxAmt)), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount: ",
    maxLength = 8,
    onType = function(text, _s, _a)
      if text == "" then
        if localSceneCb then localSceneCb(nil) end
        return nil
      end
      local amt
      if text:upper() == "A" then amt = maxAmt
      else amt = tonumber(text) end
      if not amt or amt < 0 then return "Enter a positive amount or A" end
      if amt == 0 then
        if localSceneCb then localSceneCb(nil) end
        return nil
      end
      if amt > maxAmt then return string.format("Max is %s", fmt(maxAmt)) end
      if isRepay then actions.wuRepay(math.floor(amt))
      else            actions.wuBorrow(math.floor(amt)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneRepairAmount(state, actions, localSceneCb)
  local offer = state.shipOffer
  if not offer or not offer.repairRate then
    if localSceneCb then localSceneCb(nil) end
    return {}, nil
  end
  local maxCost = offer.repairRate * math.ceil(state.damage or 0) + 1
  local lines = {
    { text = string.format("Repair: %s/pt  Full: %s",
        fmt(offer.repairRate), fmt(maxCost)), color = AMBER },
    { text = "Cash to spend (A=all):", color = GREEN },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount: ",
    maxLength = 8,
    onType = function(text, _s, _a)
      if text == "" then
        if localSceneCb then localSceneCb(nil) end
        return nil
      end
      local amt
      if text:upper() == "A" then amt = maxCost
      else amt = tonumber(text) end
      if not amt or amt < 0 then return "Enter a positive amount or A" end
      if amt == 0 then
        if localSceneCb then localSceneCb(nil) end
        return nil
      end
      actions.shipRepair(math.floor(amt))
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneMillionaire(_state, _actions, localSceneCb)
  local INV_W  = 25   -- inverted block width
  local LEFT   = math.floor((40 - INV_W) / 2)  -- centering offset

  local function invRow(text)
    local inner = centerStr(text, INV_W)
    return { segments = {
      { text = string.rep(" ", LEFT), color = AMBER },
      { text = inner,                 color = AMBER, inverted = true },
    }}
  end

  local rows = {}
  for r = 1, 18 do rows[r] = { text = "", color = AMBER } end
  rows[19] = invRow("")
  rows[20] = invRow("Y o u ' r e    a")
  rows[21] = invRow("")
  rows[22] = invRow("M I L L I O N A I R E !")
  rows[23] = invRow("")
  rows[24] = invRow("")

  return { rows = rows }, {
    type   = "key",
    keys   = {},
    anyKey = true,
    onKey  = function()
      if localSceneCb then localSceneCb("final_status") end
    end,
  }
end

local RATING_TABLE = {
  { label = "Ma Tsu",        text = "|Ma Tsu         50,000 and over |" },
  { label = "Master Taipan", text = "|Master Taipan   8,000 to 49,999|" },
  { label = "Taipan",        text = "|Taipan          1,000 to  7,999|" },
  { label = "Compradore",    text = "|Compradore        500 to    999|" },
  { label = "Galley Hand",   text = "|Galley Hand       less than 500|" },
}

local function sceneFinalStatus(state, actions, _localSceneCb)
  local score      = state.finalScore  or 0
  local rating     = state.finalRating or "Galley Hand"
  local netCash    = (state.cash or 0) + (state.bankBalance or 0) - (state.debt or 0)
  local yearsTotal = math.floor((state.turnsElapsed or 0) / 12)
  local monthsRem  = (state.turnsElapsed or 0) % 12

  local rows = {}
  rows[1]  = { text = "Your final status:", color = AMBER }
  rows[2]  = { text = "", color = AMBER }
  rows[3]  = { text = "Net Cash: " .. fmtBig(netCash), color = AMBER }
  rows[4]  = { text = "", color = AMBER }
  rows[5]  = { text = string.format("Ship size: %d units with %d guns",
                 state.shipCapacity or 0, state.guns or 0), color = AMBER }
  rows[6]  = { text = "", color = AMBER }
  rows[7]  = { text = string.format("You traded for %d year%s and %d month%s",
                 yearsTotal, yearsTotal == 1 and "" or "s",
                 monthsRem,  monthsRem  == 1 and "" or "s"), color = AMBER }
  rows[8]  = { text = "", color = AMBER }
  rows[9]  = { segments = {
    { text = string.format("Your score is %d.", score), color = AMBER, inverted = true },
  }}
  rows[10] = { text = "", color = AMBER }
  rows[11] = { text = "", color = AMBER }
  rows[12] = { text = "", color = AMBER }
  rows[13] = { text = "Your Rating:", color = AMBER }
  rows[14] = { text = "+-------------------------------+", color = AMBER }
  for i, entry in ipairs(RATING_TABLE) do
    local isAchieved = (entry.label == rating)
    rows[14 + i] = isAchieved
      and { segments = {{ text = entry.text, color = AMBER, inverted = true }}}
      or  { text = entry.text, color = AMBER }
  end
  rows[20] = { text = "+-------------------------------+", color = AMBER }
  rows[21] = { text = "", color = AMBER }
  rows[22] = { text = "Play again? (Y/N)", color = GREEN }
  rows[23] = { text = "", color = AMBER }
  rows[24] = { text = "", color = AMBER }

  return { rows = rows }, {
    type = "key",
    keys = { "Y", "N" },
    label = "Play again? (Y/N)",
    onKey = function(key, _s, _a)
      if key == "Y" then actions.restartGame()
      elseif key == "N" then actions.quitGame()
      end
    end,
  }
end

function PromptEngine.processState(state, localScene, actions, localSceneCb)
  if state.gameOver then
    if state.gameOverReason == "retired" then
      if localScene == "final_status" then
        return sceneFinalStatus(state, actions, localSceneCb)
      end
      return sceneMillionaire(state, actions, localSceneCb)
    end
    return sceneGameOver(state, actions, localSceneCb)
  end
  if state.combat ~= nil then
    if localScene == "combat_throw_good" then
      return sceneCombatThrowGood(state, actions, localSceneCb)
    end
    if localScene and localScene:match("^combat_throw_amt_(%d)$") then
      local idx = tonumber(localScene:match("(%d)$"))
      return sceneCombatThrowAmount(state, actions, localSceneCb, idx)
    end
    return sceneCombatLayout(state, actions, localSceneCb)
  end
  if state.shipOffer ~= nil then
    if localScene == "repair" then
      return sceneRepairAmount(state, actions, localSceneCb)
    end
    return sceneShipOffers(state, actions, localSceneCb)
  end
  if state.currentPort == HONG_KONG and state.inWuSession then
    if localScene == "wu_repay" then return sceneWuAmount(state, actions, localSceneCb, true) end
    if localScene == "wu_borrow" then return sceneWuAmount(state, actions, localSceneCb, false) end
    return sceneWuSession(state, actions, localSceneCb)
  end
  if localScene == "bank"         then return sceneBank(state, actions, localSceneCb) end
  if localScene == "bank_deposit"  then return sceneBankAmount(state, actions, localSceneCb, true) end
  if localScene == "bank_withdraw" then return sceneBankAmount(state, actions, localSceneCb, false) end
  if localScene == "warehouse"    then return sceneWarehouse(state, actions, localSceneCb) end
  if localScene == "wh_to"        then return sceneWarehouseGood(state, actions, localSceneCb, true) end
  if localScene == "wh_from"      then return sceneWarehouseGood(state, actions, localSceneCb, false) end
  if localScene and localScene:match("^wh_to_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneWarehouseAmount(state, actions, localSceneCb, idx, true)
  end
  if localScene and localScene:match("^wh_from_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneWarehouseAmount(state, actions, localSceneCb, idx, false)
  end
  if localScene == "buy"  then return sceneBuySell(state, actions, localSceneCb, true) end
  if localScene == "sell" then return sceneBuySell(state, actions, localSceneCb, false) end
  if localScene and localScene:match("^buy_good_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneBuySellAmount(state, actions, localSceneCb, idx, true)
  end
  if localScene and localScene:match("^sell_good_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneBuySellAmount(state, actions, localSceneCb, idx, false)
  end
  if localScene == "travel"       then return sceneTravel(state, actions, localSceneCb) end
  if localScene == "settings"     then return sceneSettings(state, actions, localSceneCb) end
  if localScene == "quit_confirm" then return sceneQuitConfirm(state, actions, localSceneCb) end
  if state.startChoice == nil and (state.turnsElapsed or 1) == 1 and (state.destination or 0) == 0 then
    if localScene == "start_choice" then
      return sceneStartChoice(state, actions, localSceneCb)
    end
    return sceneFirmName(state, actions, localSceneCb)
  end
  return sceneAtPort(state, actions, localSceneCb)
end

return PromptEngine
