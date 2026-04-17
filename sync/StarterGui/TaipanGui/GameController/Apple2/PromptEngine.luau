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
  local neg = n < 0
  local s = tostring(math.abs(math.floor(n)))
  local result = ""
  local count = 0
  for i = #s, 1, -1 do
    if count > 0 and count % 3 == 0 then result = "," .. result end
    result = s:sub(i, i) .. result
    count = count + 1
  end
  return neg and ("$-" .. result) or ("$" .. result)
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
  local neg = n < 0
  n = math.floor(math.abs(n))
  local result
  if n < 1000000 then
    local s, r, count = tostring(n), "", 0
    for i = #s, 1, -1 do
      if count > 0 and count % 3 == 0 then r = "," .. r end
      r = s:sub(i, i) .. r
      count += 1
    end
    result = r
  else
    local II = math.floor(math.log(n) / math.log(10) + 1e-9)
    local IJ = math.floor(II / 3) * 3
    local disp = string.format("%.2f", n / (10 ^ IJ)):sub(1, 4)
    if disp:sub(-1) == "." then disp = disp:sub(1, -2) end
    local suffix = ({"Thousand","Million","Billion","Trillion"})[IJ/3] or "?"
    result = disp .. " " .. suffix
  end
  return neg and ("-" .. result) or result
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

  -- Inner helper: warehouse good row 26 chars: left 13 (good+qty) + right 13 (label/value right-justified)
  -- Format: name(7) + qty right-aligned in 6 = exactly 13 chars, supports up to 10000 with gap
  local function whInner(goodIdx, qty, rightText)
    local name = SHORT_GOOD_NAMES[goodIdx]
    local left = pad(name, 7) .. lpad(tostring(qty), 6)
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

-- Dialog with Elder Brother Wu, borrowing and repayment
-- Also used for other similar dialogs
local function sceneWuLayout(state, bodyLines)
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report", color = AMBER }
  rows[18] = { text = "", color = AMBER }
  local r = 19
  for _, l in ipairs(bodyLines) do
    rows[r] = l
    r += 1
  end
  return { rows = rows }
end

local function sceneAtPort(state, actions, localSceneCb)
  local rows = buildPortRows(state)
  local isHK     = (state.currentPort == HONG_KONG)
  local nw       = (state.cash or 0) + (state.bankBalance or 0) - (state.debt or 0)
  local canRetire = isHK and nw >= 1000000
  local prices   = state.currentPrices or {0,0,0,0}

  -- Price lines: left column 18 chars wide so right column aligns
  local p1 = tostring(math.floor(prices[1]))
  local p2 = tostring(math.floor(prices[2]))
  local p3 = tostring(math.floor(prices[3]))
  local p4 = tostring(math.floor(prices[4]))

  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Taipan, present prices per unit here are",        color = AMBER }
  rows[20] = { text = "   Spices: " .. pad(p1, 7) .. "Silk: " .. p2,   color = GREEN }
  rows[21] = { text = "   Arms: "   .. pad(p3, 9) .. "General: " .. p4, color = GREEN }
  rows[22] = { text = "",                                                color = AMBER }

  local validKeys = {"B", "S", "Q", "P"}  -- P = Settings (unlisted)
  local cursorRow, cursorPrefix
  if isHK then
    if canRetire then
      rows[23] = { text = "Shall I Buy, Sell, Visit bank, Transfer",  color = GREEN }
      rows[24] = { text = "cargo, Quit trading, or Retire?",          color = GREEN }
      table.insert(validKeys, "V")
      table.insert(validKeys, "T")
      table.insert(validKeys, "R")
      cursorRow    = 24
      cursorPrefix = "cargo, Quit trading, or Retire? "
    else
      rows[23] = { text = "Shall I Buy, Sell, Visit bank, Transfer",  color = GREEN }
      rows[24] = { text = "cargo, or Quit trading?",                  color = GREEN }
      table.insert(validKeys, "V")
      table.insert(validKeys, "T")
      cursorRow    = 24
      cursorPrefix = "cargo, or Quit trading? "
    end
  else
    rows[23] = { text = "Shall I Buy, Sell, or Quit trading?",        color = GREEN }
    cursorRow    = 23
    cursorPrefix = "Shall I Buy, Sell, or Quit trading? "
  end

  return { rows = rows }, {
    type           = "singlechar",
    keys           = validKeys,
    _inputRow      = cursorRow,
    _buildInputRow = function(s) return { text = cursorPrefix .. s, color = GREEN } end,
    onKey = function(key, _state, _actions)
      if key == "B" then
        if localSceneCb then localSceneCb("buy") end
      elseif key == "S" then
        if localSceneCb then localSceneCb("sell") end
      elseif key == "V" then
        if localSceneCb then localSceneCb("bank") end
      elseif key == "T" then
        if localSceneCb then localSceneCb("warehouse") end
      elseif key == "Q" then
        if localSceneCb then localSceneCb("travel") end
      elseif key == "R" then
        actions.retire()
      elseif key == "P" then
        if localSceneCb then localSceneCb("settings") end
      end
    end,
  }
end

local function sceneTravel(state, actions, localSceneCb)
  local rows = buildPortRows(state)

  rows[17] = { text = "Comprador's Report",                          color = AMBER }
  rows[18] = { text = "",                                            color = AMBER }
  rows[19] = { text = "Taipan, do you wish to go to:",              color = AMBER }
  rows[20] = { text = "1) Hong Kong, 2) Shanghai, 3) Nagasaki,",   color = GREEN }
  rows[21] = { text = "4) Saigon, 5) Manila, 6) Singapore, or",    color = GREEN }
  rows[22] = { text = "7) Batavia ?",                               color = GREEN }

  local validKeys = {}
  for i = 1, 7 do
    table.insert(validKeys, tostring(i))
  end

  return { rows = rows }, {
    type           = "singlechar",
    keys           = validKeys,
    _inputRow      = 22,
    _buildInputRow = function(s) return { text = "7) Batavia ? " .. s, color = GREEN } end,
    onKey = function(key, _state, _actions)
      local dest = tonumber(key)
      if dest then
        if dest == _state.currentPort then
          if localSceneCb then localSceneCb("already_here") end
        else
          actions.travelTo(dest)
          if localSceneCb then localSceneCb("traveling") end
        end
      end
    end,
  }
end

local function sceneAlreadyHere(state, _actions, localSceneCb)
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report",                          color = AMBER }
  rows[18] = { text = "",                                            color = AMBER }
  rows[19] = { text = "Taipan, do you wish to go to:",              color = AMBER }
  rows[20] = { text = "1) Hong Kong, 2) Shanghai, 3) Nagasaki,",   color = GREEN }
  rows[21] = { text = "4) Saigon, 5) Manila, 6) Singapore, or",    color = GREEN }
  rows[22] = { text = "7) Batavia ?",                               color = GREEN }
  rows[23] = { text = "",                                            color = AMBER }
  rows[24] = { text = "You're already here, Taipan.",               color = GREEN }
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "travel" },
    onKey        = function() if localSceneCb then localSceneCb("travel") end end,
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

local START_CHOICE_INPUT_ROW = 21
local function buildStartChoiceInputRow(s)
  return { text = "          ? " .. s, color = AMBER }
end

local function sceneStartChoice(_state, actions, _localSceneCb)
  local rows = {
    [8]  = { text = "Do you want to start . . .", color = AMBER },
    [9]  = { text = "", color = AMBER },
    [10] = { text = "", color = AMBER },
    [11] = { text = "  1) With cash (and a debt)", color = AMBER },
    [12] = { text = "", color = AMBER },
    [13] = { text = "", color = AMBER },
    [14] = { text = string.rep(" ", 16) .. ">> or <<", color = AMBER },
    [15] = { text = "", color = AMBER },
    [16] = { text = "", color = AMBER },
    [17] = { text = "  2) With five guns and no cash", color = AMBER },
    [18] = { text = string.rep(" ", 16) .. "(But no debt!)", color = AMBER },
    [19] = { text = "", color = AMBER },
    [20] = { text = "", color = AMBER },
    [21] = buildStartChoiceInputRow(" "),
    [22] = { text = "", color = AMBER },
    [23] = { text = "", color = AMBER },
    [24] = { text = "", color = AMBER },
  }
  return { rows = rows }, {
    type           = "singlechar",
    keys           = {"1", "2"},
    _inputRow      = START_CHOICE_INPUT_ROW,
    _buildInputRow = buildStartChoiceInputRow,
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

  local THICK      = "TaipanThickFont"
  local VERT_CHAR  = string.char(129)  -- │
  local BOT_L_CHAR = string.char(156)  -- └
  local BOT_H_CHAR = string.char(154)  -- ─

  local function row1()
    local left = pad(string.format("   %d ships attacking, Taipan!", total), col1Width)
    return { segments = {
      { text = left,       color = AMBER },
      { text = VERT_CHAR,  color = AMBER, font = THICK },
      { text = " We have", color = AMBER },
    }}
  end

  local function row2()
    local left = pad("Your orders are to:", col1Width)
    -- Right col: "│" + lpad(guns,3) + " guns" = 9 chars total
    return { segments = {
      { text = left,                               color = AMBER },
      { text = VERT_CHAR,                          color = AMBER, font = THICK },
      { text = lpad(tostring(guns), 3) .. " guns", color = AMBER },
    }}
  end

  local function row3()
    return { segments = {
      { text = string.rep(" ", col1Width),                           color = AMBER },
      { text = BOT_L_CHAR .. string.rep(BOT_H_CHAR, RIGHT_W - 1),   color = AMBER, font = THICK },
    }}
  end

  local function row4()
    local label = swLabel .. " (" .. tostring(sw) .. "%)"
    local seg = {
      { text = "Current seaworthiness: ", color = AMBER },
      { text = label, color = AMBER, inverted = swInv },
    }
    return { segments = seg }
  end

  local function row5()
    return { text = "  Ships: [" .. gridStr .. "]", color = GREEN }
  end

  local rows = {}
  rows[1] = row1()
  rows[2] = row2()
  rows[3] = row3()
  rows[4] = row4()
  rows[5] = row5()
  for r = 6, 24 do rows[r] = { text = "", color = AMBER } end

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

local function sceneRepair(state, actions, localSceneCb)
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Taipan, Mc Henry from the Hong Kong",             color = GREEN }
  rows[20] = { text = "Shipyards has arrived!  He says, 'I see",         color = GREEN }
  rows[21] = { text = "ye've a wee bit of damage to yer ship.",          color = GREEN }
  local prompt_base = "Will ye be wanting repairs?' "
  rows[22] = { text = prompt_base,                                       color = GREEN }
  rows[23] = { text = "",                                                color = AMBER }
  rows[24] = { text = "",                                                color = AMBER }
  return { rows = rows }, {
    type           = "singlechar",
    keys           = {"Y", "N"},
    _inputRow      = 22,
    _buildInputRow = function(s) return { text = prompt_base .. s, color = GREEN } end,
    onKey = function(key, _s, _a)
      if key == "Y" then
        if localSceneCb then localSceneCb("repair_amount") end
      else
        actions.declineRepair()
      end
    end,
  }
end

local function sceneRepairAmountErr(state, _actions, localSceneCb)
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Taipan, you do not have enough cash!!",           color = GREEN }
  for r = 20, 24 do rows[r] = { text = "", color = AMBER } end
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "repair_amount" },
    onKey        = function() if localSceneCb then localSceneCb("repair_amount") end end,
  }
end

local function sceneRepairAmount(state, actions, localSceneCb)
  local offer = state.shipOffer
  if not offer or not offer.repairRate then
    actions.declineRepair()
    return {}, nil
  end
  local dmgPct  = math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100)
  local maxCost = math.floor(offer.repairRate * math.ceil(state.damage or 0)) + 1
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = string.format("Och, 'tis a pity to be %d%% damaged.", dmgPct), color = GREEN }
  rows[20] = { text = "",                                                color = AMBER }
  rows[21] = { text = string.format("We can fix yer whole ship for %s,", fmtBig(maxCost)), color = GREEN }
  rows[22] = { text = "or make partial repairs if you wish.",            color = GREEN }
  local prompt_base = "How much will ye spend? "
  rows[23] = { text = prompt_base,                                       color = GREEN }
  rows[24] = { text = "",                                                color = AMBER }
  return { rows = rows }, {
    type            = "numeric",
    typePlaceholder = prompt_base,
    _inputRow       = 23,
    _buildInputRow  = function(s) return { text = prompt_base .. s, color = GREEN } end,
    maxDigits       = 9,
    onType = function(text, _s, _a)
      local amt = tonumber(text) or 0
      if amt > (state.cash or 0) then
        if localSceneCb then localSceneCb("repair_amount_err") end
        return nil
      end
      if amt > 0 then
        actions.shipRepair(math.floor(amt))
      else
        actions.declineRepair()
      end
      return nil
    end,
  }
end

local function sceneUpgrade(state, actions, _localSceneCb)
  local offer = state.shipOffer and state.shipOffer.upgradeOffer
  local cost = offer and offer.cost or 0
  local condition = (state.damage or 0) > 0 and "damaged" or "fine"
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Do you wish to trade in your " .. condition,      color = GREEN }
  rows[20] = { text = "ship for one with 50 more capacity by",           color = GREEN }
  local prompt_base = string.format("paying an additional %s, Taipan? ", fmtBig(cost))
  rows[21] = { text = prompt_base,                                       color = GREEN }
  rows[22] = { text = "",                                                color = AMBER }
  rows[23] = { text = "",                                                color = AMBER }
  rows[24] = { text = "",                                                color = AMBER }
  return { rows = rows }, {
    type           = "singlechar",
    keys           = {"Y", "N"},
    _inputRow      = 21,
    _buildInputRow = function(s) return { text = prompt_base .. s, color = GREEN } end,
    onKey = function(key, _s, _a)
      if key == "Y" then actions.acceptUpgrade()
      else actions.declineUpgrade()
      end
    end,
  }
end

local function sceneGun(state, actions, _localSceneCb)
  local offer = state.shipOffer and state.shipOffer.gunOffer
  local cost = offer and offer.cost or 0
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Do you wish to buy a ship's gun",                 color = GREEN }
  local prompt_base = string.format("for %s, Taipan? ", fmtBig(cost))
  rows[20] = { text = prompt_base,                                       color = GREEN }
  rows[21] = { text = "",                                                color = AMBER }
  rows[22] = { text = "",                                                color = AMBER }
  rows[23] = { text = "",                                                color = AMBER }
  rows[24] = { text = "",                                                color = AMBER }
  return { rows = rows }, {
    type           = "singlechar",
    keys           = {"Y", "N"},
    _inputRow      = 20,
    _buildInputRow = function(s) return { text = prompt_base .. s, color = GREEN } end,
    onKey = function(key, _s, _a)
      if key == "Y" then actions.acceptGun()
      else actions.declineGun()
      end
    end,
  }
end

local function sceneLiYuenDemand(state, actions, localSceneCb)
  local cost = state.liYuenOfferCost or 0
  -- body lines start at row 19; question+cursor on row 21
  local bodyLines = {
    { text = string.format("Li Yuen asks %s in donation", fmt(cost)), color = GREEN },
    { text = "to the temple of Tin Hau, the Sea", color = GREEN },
    { text = "Goddess.  Will you pay? ", color = GREEN },
  }
  local function buildInputRow(s)
    return { text = "Goddess.  Will you pay? " .. s, color = GREEN }
  end
  return sceneWuLayout(state, bodyLines), {
    type           = "singlechar",
    keys           = {"Y", "N"},
    _inputRow      = 21,
    _buildInputRow = buildInputRow,
    onKey = function(key, _s, _a)
      if key == "Y" then
        actions.buyLiYuen()
      else
        actions.declineLiYuen()
      end
    end,
  }
end

local function sceneWuQuestion(state, actions, localSceneCb)
  -- body lines start at row 19; question+cursor on row 20
  local bodyLines = {
    { text = "Do you have business with Elder", color = GREEN },
    { text = "Brother Wu, the moneylender? ", color = GREEN },
  }
  local function buildInputRow(s)
    return { text = "Brother Wu, the moneylender? " .. s, color = GREEN }
  end
  return sceneWuLayout(state, bodyLines), {
    type           = "singlechar",
    keys           = {"Y", "N"},
    _inputRow      = 20,
    _buildInputRow = buildInputRow,
    onKey = function(key, _s, _a)
      if key == "Y" then
        actions.confirmWu()
      else
        actions.declineWu()
      end
    end,
  }
end

local function sceneWuBorrow(state, actions, localSceneCb)
  local bodyLines = {
    { text = "How much do you wish to", color = AMBER },
  }
  return sceneWuLayout(state, bodyLines), {
    type            = "numeric",
    typePlaceholder = "borrow? ",
    _inputRow       = 20,
    _buildInputRow  = function(s) return { text = "borrow? " .. s, color = AMBER } end,
    maxDigits       = 9,
    onType = function(text, _s, _a)
      local amt = tonumber(text) or 0
      if amt > 0 and amt > 2 * (state.cash or 0) then
        if localSceneCb then localSceneCb("wu_borrow_err") end
        return nil
      end
      if amt > 0 then
        actions.wuBorrow(math.floor(amt))
      end
      actions.leaveWu()
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneWuBorrowErr(state, _actions, localSceneCb)
  return sceneWuLayout(state, {
    { text = "How much do you wish to",             color = AMBER },
    { text = "borrow?",                             color = AMBER },
    { text = "",                                    color = AMBER },
    { text = "He won't loan you so much, Taipan!", color = GREEN },
  }), {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "wu_borrow" },
    onKey        = function() if localSceneCb then localSceneCb("wu_borrow") end end,
  }
end

local function sceneWuRepayErr(state, _actions, localSceneCb)
  return sceneWuLayout(state, {
    { text = "How much do you wish to repay", color = AMBER },
    { text = "him?",                          color = AMBER },
    { text = "",                              color = AMBER },
    { text = "Taipan, you only have " .. fmtBig(state.cash or 0), color = GREEN },
    { text = "in cash.",                      color = GREEN },
  }), {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "wu_repay" },
    onKey        = function() if localSceneCb then localSceneCb("wu_repay") end end,
  }
end

local function sceneWuRepay(state, actions, localSceneCb)
  local bodyLines = {
    { text = "How much do you wish to repay", color = AMBER },
  }
  return sceneWuLayout(state, bodyLines), {
    type            = "numeric",
    typePlaceholder = "him? ",
    _inputRow       = 20,
    _buildInputRow  = function(s) return { text = "him? " .. s, color = AMBER } end,
    maxDigits       = 9,
    onType = function(text, s, _a)
      local amt = tonumber(text) or 0
      if amt > 0 then
        if amt > (s.cash or 0) then
          if localSceneCb then localSceneCb("wu_repay_err") end
          return nil
        end
        actions.wuRepay(math.floor(amt))
      end
      if localSceneCb then localSceneCb("wu_borrow") end
      return nil
    end,
  }
end


local function sceneBuySell(state, actions, localSceneCb, isBuy)
  local rows = buildPortRows(state)
  local prices = state.currentPrices or {0,0,0,0}
  local p1 = tostring(math.floor(prices[1]))
  local p2 = tostring(math.floor(prices[2]))
  local p3 = tostring(math.floor(prices[3]))
  local p4 = tostring(math.floor(prices[4]))

  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Taipan, present prices per unit here are",        color = AMBER }
  rows[20] = { text = "   Spices: " .. pad(p1, 7) .. "Silk: " .. p2,   color = GREEN }
  rows[21] = { text = "   Arms: "   .. pad(p3, 9) .. "General: " .. p4, color = GREEN }
  rows[22] = { text = "",                                                color = AMBER }

  local verb     = isBuy and "buy" or "sell"
  local question = "What do you wish me to " .. verb .. ", Taipan?"
  rows[23] = { text = question, color = AMBER }
  rows[24] = { text = "", color = AMBER }

  return { rows = rows }, {
    type           = "singlechar",
    keys           = {"P", "S", "A", "G"},
    _inputRow      = 23,
    _buildInputRow = function(s) return { text = question .. " " .. s, color = AMBER } end,
    onKey = function(key, _state, _actions)
      local idx = GOOD_KEY_MAP[key]
      if idx then
        if localSceneCb then localSceneCb(isBuy and ("buy_good_"..idx) or ("sell_good_"..idx)) end
      end
    end,
  }
end

local function sceneBuySellAmount(state, actions, localSceneCb, goodIdx, isBuy)
  local goodName = SHORT_GOOD_NAMES[goodIdx]
  local price    = (state.currentPrices or {})[goodIdx] or 0
  local cash     = state.cash or 0
  local cargoAmt = (state.shipCargo or {})[goodIdx] or 0
  local affordable = price > 0 and math.floor(cash / price) or 0
  local verb     = isBuy and "buy" or "sell"

  local rows = buildPortRows(state)
  local prices = state.currentPrices or {0,0,0,0}
  local p1 = tostring(math.floor(prices[1]))
  local p2 = tostring(math.floor(prices[2]))
  local p3 = tostring(math.floor(prices[3]))
  local p4 = tostring(math.floor(prices[4]))

  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Taipan, present prices per unit here are",        color = AMBER }
  rows[20] = { text = "   Spices: " .. pad(p1, 7) .. "Silk: " .. p2,   color = GREEN }
  rows[21] = { text = "   Arms: "   .. pad(p3, 9) .. "General: " .. p4, color = GREEN }

  local firstLine  = "How much " .. goodName .. " shall"
  local secondLine = "I " .. verb .. ", Taipan? "

  if isBuy then
    rows[22] = { segments = {
      { text = pad(firstLine, 31),  color = AMBER },
      { text = " You can ",         color = AMBER, inverted = true },
    }}
    -- row 23 set by _buildInputRow on first update
    rows[23] = { text = secondLine, color = AMBER }
    local affordStr = centerStr(tostring(affordable), 9)
    rows[24] = { segments = {
      { text = string.rep(" ", 31), color = AMBER },
      { text = affordStr,           color = AMBER, inverted = true },
    }}
  else
    rows[22] = { text = firstLine,  color = AMBER }
    rows[23] = { text = secondLine, color = AMBER }
    rows[24] = { text = "",         color = AMBER }
  end

  local function buildAmountRow(s)
    if isBuy then
      return { segments = {
        { text = pad(secondLine .. s, 31), color = AMBER },
        { text = "  afford ",              color = AMBER, inverted = true },
      }}
    else
      return { text = secondLine .. s, color = AMBER }
    end
  end

  return { rows = rows }, {
    type            = "numeric",
    typePlaceholder = "",
    _inputRow       = 23,
    _buildInputRow  = buildAmountRow,
    maxDigits       = 9,
    onType = function(text, _s, _a)
      local qty = tonumber(text) or 0
      if qty == 0 then
        if localSceneCb then localSceneCb(nil) end
        return nil
      end
      if isBuy then
        if qty * price > cash then
          -- Exceeds available cash: stay on same scene (input already cleared)
          if localSceneCb then localSceneCb("buy_good_" .. goodIdx) end
          return nil
        end
        actions.buyGoods(goodIdx, math.floor(qty))
      else
        if qty > cargoAmt then
          -- Exceeds available cargo: stay on same scene
          if localSceneCb then localSceneCb("sell_good_" .. goodIdx) end
          return nil
        end
        actions.sellGoods(goodIdx, math.floor(qty))
      end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

-- Shared helper: rows 1-18 (status screen + Comprador header), rows 19-24 blank
local function buildBankRows(state)
  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report", color = AMBER }
  rows[18] = { text = "",                  color = AMBER }
  for r = 19, 24 do rows[r] = { text = "", color = AMBER } end
  return rows
end

local function sceneBank(state, actions, localSceneCb)
  local maxDeposit = state.cash or 0
  local rows = buildBankRows(state)
  local question = "How much will you deposit? "
  rows[19] = { text = question, color = AMBER }

  return { rows = rows }, {
    type            = "numeric",
    typePlaceholder = "",
    _inputRow       = 19,
    _buildInputRow  = function(s) return { text = question .. s, color = AMBER } end,
    maxDigits       = 9,
    onType = function(text, _s, _a)
      local amt = tonumber(text) or 0
      if amt > maxDeposit then
        if localSceneCb then localSceneCb("bank_deposit_err") end
        return nil
      end
      if amt > 0 then actions.bankDeposit(math.floor(amt)) end
      if localSceneCb then localSceneCb("bank_withdraw") end
      return nil
    end,
  }
end

local function sceneWithdraw(state, actions, localSceneCb)
  local maxWithdraw = state.bankBalance or 0
  local rows = buildBankRows(state)
  local question = "How much will you withdraw? "
  rows[19] = { text = question, color = AMBER }

  return { rows = rows }, {
    type            = "numeric",
    typePlaceholder = "",
    _inputRow       = 19,
    _buildInputRow  = function(s) return { text = question .. s, color = AMBER } end,
    maxDigits       = 9,
    onType = function(text, _s, _a)
      local amt = tonumber(text) or 0
      if amt > maxWithdraw then
        if localSceneCb then localSceneCb("bank_withdraw_err") end
        return nil
      end
      if amt > 0 then actions.bankWithdraw(math.floor(amt)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

-- Error scenes: shown for 5 seconds or until keypress, then return to their parent scene
local function sceneBankDepositErr(state, _actions, localSceneCb)
  local rows = buildBankRows(state)
  rows[21] = { text = "Taipan, you only have " .. fmtBig(state.cash or 0), color = GREEN }
  rows[22] = { text = "in cash.",                                           color = GREEN }
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "bank" },
    onKey        = function() if localSceneCb then localSceneCb("bank") end end,
  }
end

local function sceneBankWithdrawErr(state, _actions, localSceneCb)
  local rows = buildBankRows(state)
  rows[21] = { text = "Taipan, you only have " .. fmtBig(state.bankBalance or 0), color = GREEN }
  rows[22] = { text = "in the bank.",                                              color = GREEN }
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "bank_withdraw" },
    onKey        = function() if localSceneCb then localSceneCb("bank_withdraw") end end,
  }
end

-- Ordered sequence of (goodIdx, isToWarehouse) steps for transfer dialog.
-- For each good: to-warehouse first, then from-warehouse.
local TRANSFER_SEQ = {
  {1, true}, {1, false},
  {2, true}, {2, false},
  {3, true}, {3, false},
  {4, true}, {4, false},
}

-- "T" pressed with no transferable cargo in either direction.
-- Preserves prices on rows 19-21 (only lines 6-8 are affected).
local function sceneWarehouseNoCargo(state, _actions, localSceneCb)
  local rows  = buildPortRows(state)
  local prices = state.currentPrices or {0,0,0,0}
  local p1 = tostring(math.floor(prices[1]))
  local p2 = tostring(math.floor(prices[2]))
  local p3 = tostring(math.floor(prices[3]))
  local p4 = tostring(math.floor(prices[4]))
  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Taipan, present prices per unit here are",        color = AMBER }
  rows[20] = { text = "   Spices: " .. pad(p1, 7) .. "Silk: " .. p2,   color = GREEN }
  rows[21] = { text = "   Arms: "   .. pad(p3, 9) .. "General: " .. p4, color = GREEN }
  rows[22] = { text = "You have no cargo, Taipan.",                      color = GREEN }
  rows[23] = { text = "",                                                color = AMBER }
  rows[24] = { text = "",                                                color = AMBER }
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, nil },
    onKey        = function() if localSceneCb then localSceneCb(nil) end end,
  }
end

-- Finds the first TRANSFER_SEQ step >= startN with something available to move.
-- Returns (stepIndex, goodIdx, isToWarehouse) or (nil, nil, nil) when done.
local function findNextStep(state, startN)
  for n = startN, #TRANSFER_SEQ do
    local step = TRANSFER_SEQ[n]
    local g, isTo = step[1], step[2]
    local avail = isTo and (state.shipCargo[g] or 0) or (state.warehouseCargo[g] or 0)
    if avail > 0 then
      return n, g, isTo
    end
  end
  return nil, nil, nil
end

-- Shows the next applicable transfer question starting from step startN.
-- Falls through to at-port when all steps are exhausted.
local function sceneWarehouseStep(state, actions, localSceneCb, startN)
  local foundN, foundG, foundIsTo = findNextStep(state, startN)
  if not foundN then
    -- All steps exhausted. Show a neutral lower section (header + blanks) and wait
    -- for the StateUpdate from the server to re-render the full port view.
    -- Falling through to sceneAtPort here would briefly flash the price menu using
    -- stale lastState cargo values before the server response arrives.
    local rows = buildPortRows(state)
    rows[17] = { text = "Comprador's Report", color = AMBER }
    for r = 18, 24 do rows[r] = { text = "", color = AMBER } end
    return { rows = rows }, { type = "key", keys = {}, _autoAdvance = { 0, nil } }
  end

  local rows      = buildPortRows(state)
  local goodName  = SHORT_GOOD_NAMES[foundG]
  local direction = foundIsTo and "to the warehouse, Taipan?" or "aboard ship, Taipan?"
  local maxAvail  = foundIsTo and (state.shipCargo[foundG] or 0) or (state.warehouseCargo[foundG] or 0)
  local firstLine  = "How much " .. goodName .. " shall I move"
  local secondLine = direction .. " "   -- trailing space precedes cursor

  rows[17] = { text = "Comprador's Report", color = AMBER }
  rows[18] = { text = "",                  color = AMBER }
  rows[19] = { text = firstLine,           color = AMBER }
  rows[20] = { text = direction,           color = AMBER }  -- overridden immediately by _buildInputRow
  rows[21] = { text = "",                  color = AMBER }
  rows[22] = { text = "",                  color = AMBER }
  rows[23] = { text = "",                  color = AMBER }
  rows[24] = { text = "",                  color = AMBER }

  return { rows = rows }, {
    type            = "numeric",
    typePlaceholder = "",
    _inputRow       = 20,
    _buildInputRow  = function(s) return { text = secondLine .. s, color = AMBER } end,
    maxDigits       = 9,
    onType = function(text, _s, _a)
      local qty = tonumber(text) or 0
      if qty == 0 then
        -- Empty/zero: skip this step
        if localSceneCb then localSceneCb("wh_step_" .. (foundN + 1)) end
        return nil
      end
      if qty > maxAvail then
        -- Too much: show error scene for this step
        if localSceneCb then localSceneCb("wh_err_" .. foundN) end
        return nil
      end
      if foundIsTo then
        actions.transferTo(foundG, math.floor(qty))
      else
        actions.transferFrom(foundG, math.floor(qty))
      end
      -- Use wh_wait_N so Apple2Interface advances to the next step only after the
      -- StateUpdate arrives with fresh cargo counts. Using stale lastState here would
      -- cause findNextStep to miss "from warehouse" steps (warehouseCargo still 0).
      if localSceneCb then localSceneCb("wh_wait_" .. foundN) end
      return nil
    end,
  }
end

-- Error: entered more than available.  Shows question + error line, anyKey/5s re-asks.
local function sceneWarehouseStepErr(state, actions, localSceneCb, stepN)
  local step = TRANSFER_SEQ[stepN]
  if not step then
    return sceneAtPort(state, actions, localSceneCb)
  end
  local g, isTo   = step[1], step[2]
  local avail     = isTo and (state.shipCargo[g] or 0) or (state.warehouseCargo[g] or 0)
  local goodName  = SHORT_GOOD_NAMES[g]
  local direction = isTo and "to the warehouse, Taipan?" or "aboard ship, Taipan?"

  local rows = buildPortRows(state)
  rows[17] = { text = "Comprador's Report",                         color = AMBER }
  rows[18] = { text = "",                                           color = AMBER }
  rows[19] = { text = "How much " .. goodName .. " shall I move",  color = AMBER }
  rows[20] = { text = direction,                                    color = AMBER }
  rows[21] = { text = "",                                           color = AMBER }
  rows[22] = { text = "You only have " .. tostring(avail) .. ", Taipan.", color = GREEN }
  rows[23] = { text = "",                                           color = AMBER }
  rows[24] = { text = "",                                           color = AMBER }

  local retScene = "wh_step_" .. stepN
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, retScene },
    onKey        = function() if localSceneCb then localSceneCb(retScene) end end,
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
  if state.currentPort == HONG_KONG and state.liYuenPending then
    return sceneLiYuenDemand(state, actions, localSceneCb)
  end
  if state.currentPort == HONG_KONG and state.repairPending then
    if localScene == "repair_amount_err" then
      return sceneRepairAmountErr(state, actions, localSceneCb)
    end
    if localScene == "repair_amount" then
      return sceneRepairAmount(state, actions, localSceneCb)
    end
    return sceneRepair(state, actions, localSceneCb)
  end
  if state.currentPort == HONG_KONG and state.wuPending then
    return sceneWuQuestion(state, actions, localSceneCb)
  end
  if state.currentPort == HONG_KONG and state.inWuSession then
    if localScene == "wu_borrow_err" then return sceneWuBorrowErr(state, actions, localSceneCb) end
    if localScene == "wu_repay_err" then return sceneWuRepayErr(state, actions, localSceneCb) end
    if localScene == "wu_borrow" then return sceneWuBorrow(state, actions, localSceneCb) end
    if localScene == "wu_repay" or (localScene == nil and (state.debt or 0) > 0) then
      return sceneWuRepay(state, actions, localSceneCb)
    end
    return sceneWuBorrow(state, actions, localSceneCb)
  end
  if state.currentPort == HONG_KONG and state.shipOffer and state.shipOffer.upgradeOffer then
    return sceneUpgrade(state, actions, localSceneCb)
  end
  if state.currentPort == HONG_KONG and state.shipOffer and state.shipOffer.gunOffer then
    return sceneGun(state, actions, localSceneCb)
  end
  if localScene == "bank"             then return sceneBank(state, actions, localSceneCb) end
  if localScene == "bank_withdraw"    then return sceneWithdraw(state, actions, localSceneCb) end
  if localScene == "bank_deposit_err" then return sceneBankDepositErr(state, actions, localSceneCb) end
  if localScene == "bank_withdraw_err" then return sceneBankWithdrawErr(state, actions, localSceneCb) end
  if localScene == "warehouse" then
    local hasCargo = false
    for g = 1, 4 do
      if (state.shipCargo and state.shipCargo[g] or 0) > 0 or
         (state.warehouseCargo and state.warehouseCargo[g] or 0) > 0 then
        hasCargo = true; break
      end
    end
    if not hasCargo then
      return sceneWarehouseNoCargo(state, actions, localSceneCb)
    end
    return sceneWarehouseStep(state, actions, localSceneCb, 1)
  end
  if localScene and localScene:match("^wh_wait_(%d+)$") then
    -- Neutral holding screen while waiting for StateUpdate after a transfer action.
    -- Apple2Interface.adapter.update advances this to wh_step_N+1 with fresh cargo.
    local rows = buildPortRows(state)
    rows[17] = { text = "Comprador's Report", color = AMBER }
    for r = 18, 24 do rows[r] = { text = "", color = AMBER } end
    return { rows = rows }, nil
  end
  if localScene and localScene:match("^wh_step_(%d+)$") then
    local n = tonumber(localScene:match("(%d+)"))
    return sceneWarehouseStep(state, actions, localSceneCb, n)
  end
  if localScene and localScene:match("^wh_err_(%d+)$") then
    local n = tonumber(localScene:match("(%d+)"))
    return sceneWarehouseStepErr(state, actions, localSceneCb, n)
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
  if localScene == "already_here" then return sceneAlreadyHere(state, actions, localSceneCb) end
  if localScene == "traveling"   then
    -- Inert waiting scene: hold display until server notification arrives
    local rows = buildPortRows(state)
    for r = 17, 24 do rows[r] = { text = "", color = AMBER } end
    return { rows = rows }, nil
  end
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
