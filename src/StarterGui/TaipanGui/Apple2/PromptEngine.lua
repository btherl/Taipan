-- PromptEngine.lua
-- Maps (state, localScene, actions, localSceneCb) -> { lines: table[], promptDef: table }
-- Pure logic: no Roblox service calls except require.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.shared.Constants)

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

-- Helpers
local function pad(s, width)
  s = tostring(s)
  while #s < width do s = s .. " " end
  return s
end

local function fmt(n)
  -- Format number with commas
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

local function statusLines(state)
  local lines = {}
  local portName = PORT_NAMES[state.currentPort] or "?"
  local dateStr  = MONTH_NAMES[state.month] .. " " .. tostring(state.year)
  table.insert(lines, { text = pad(portName:upper(), 28) .. dateStr, color = AMBER })
  table.insert(lines, { text = string.format("Cash: %s  Debt: %s  Bank: %s  Guns: %d",
    fmt(state.cash), fmt(state.debt), fmt(state.bankBalance), state.guns), color = AMBER })
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
    local name = pad(GOOD_NAMES[i] .. ":", 14)
    local price = fmt(prices[i])
    table.insert(lines, { text = "  " .. name .. price, color = GREEN })
  end
  return lines
end

local function atPortMenu(state)
  -- Build the action menu based on what is available
  local isHK = (state.currentPort == HONG_KONG)
  local nw    = (state.cash or 0) + (state.bankBalance or 0) - (state.debt or 0)
  local canRetire = isHK and nw >= 1000000

  local menuParts = { "(B)uy  (S)ell  (T)ravel" }
  if isHK then
    table.insert(menuParts, "(W)arehouse  (K)Bank")
  end
  if canRetire then
    table.insert(menuParts, "(R)etire")
  end
  table.insert(menuParts, "(!)Settings  (Q)uit")

  local validKeys = {"B", "S", "T", "!", "Q"}
  if isHK then
    table.insert(validKeys, "W")
    table.insert(validKeys, "K")
  end
  if canRetire then table.insert(validKeys, "R") end

  return table.concat(menuParts, "  "), validKeys
end

-- Scene: AtPort
local function sceneAtPort(state, actions, localSceneCb)
  local lines = {}
  for _, l in ipairs(statusLines(state)) do table.insert(lines, l) end
  for _, l in ipairs(priceLines(state)) do table.insert(lines, l) end
  table.insert(lines, { text = "", color = AMBER })

  local menuStr, validKeys = atPortMenu(state)
  table.insert(lines, { text = menuStr, color = GREEN })

  local promptDef = {
    type = "key",
    keys = validKeys,
    label = menuStr,
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
        actions.quitGame()
      elseif key == "!" then
        if localSceneCb then localSceneCb("settings") end
      end
    end,
  }
  return lines, promptDef
end

-- Scene: Travel port selector
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

-- Scene: StartChoice
local function sceneStartChoice(_state, actions, _localSceneCb)
  local lines = {
    { text = "TAIPAN!",                                          color = AMBER },
    { text = "",                                                  color = AMBER },
    { text = "Elder Brother Wu says:",                           color = AMBER },
    { text = "\"Do you have a firm, or a ship?\"",               color = AMBER },
    { text = "",                                                  color = AMBER },
    { text = "[F] FIRM -- $400 cash, $5,000 debt, no guns",      color = GREEN },
    { text = "[S] SHIP -- 5 guns, no cash, no debt",             color = GREEN },
  }
  return lines, {
    type = "key",
    keys = {"F", "S"},
    label = "(F)irm  (S)hip",
    onKey = function(key, _s, _a)
      if key == "F" then actions.chooseStart("cash")
      elseif key == "S" then actions.chooseStart("guns")
      end
    end,
  }
end

-- Scene: GameOver
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

-- Scene: Settings sub-prompt
local function sceneSettings(state, actions, localSceneCb)
  local currentMode = state.uiMode or "modern"
  local lines = {
    { text = "Switch interface?", color = AMBER },
    { text = "", color = AMBER },
    { text = "[M] Modern   -- touch-friendly panels"  .. (currentMode == "modern"  and "  (current)" or ""), color = currentMode == "modern"  and DIM or GREEN },
    { text = "[A] Apple II -- keyboard terminal"      .. (currentMode == "apple2"  and "  (current)" or ""), color = currentMode == "apple2"  and DIM or GREEN },
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
        if localSceneCb then localSceneCb(nil) end  -- already current, cancel
      end
    end,
  }
end

-- Scene: Combat
local function sceneCombat(state, actions, _localSceneCb)
  local combat = state.combat
  local total   = combat and combat.enemyTotal or 0
  local grid    = combat and combat.grid or {}
  local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))

  -- Render enemy grid as ASCII: # = ship present, . = empty slot
  local gridStr = ""
  for i = 1, 10 do
    gridStr = gridStr .. (grid[i] ~= nil and "#" or ".")
  end

  local lines = {
    { text = string.format("BATTLE!!%sSW: %d%%", string.rep(" ", 22), sw),
      color = RED },
    { text = string.format("Enemy ships: %d remaining", total), color = AMBER },
    { text = "[" .. gridStr .. "]", color = GREEN },
    { text = "", color = AMBER },
    { text = "(F)ight  (R)un  (T)hrow cargo overboard", color = GREEN },
  }

  -- Include current cargo for throw context
  for i = 1, 4 do
    if (state.shipCargo[i] or 0) > 0 then
      table.insert(lines, { text = string.format("  %s: %d units", GOOD_NAMES[i], state.shipCargo[i]), color = AMBER })
    end
  end

  return lines, {
    type = "key",
    keys = {"F", "R", "T"},
    label = "(F)ight  (R)un  (T)hrow",
    onKey = function(key, _s, _a)
      if key == "F" then actions.combatFight()
      elseif key == "R" then actions.combatRun()
      elseif key == "T" then
        -- Default throw: General Cargo, 10 units
        -- TODO: replace with a two-step type prompt in a later iteration
        actions.combatThrow(4, 10)
      end
    end,
  }
end

-- Scene: ShipOffers (HK only)
local function sceneShipOffers(state, actions, localSceneCb)
  local offer = state.shipOffer
  local lines = {
    { text = "[ HONG KONG -- SHIP OFFERS ]", color = AMBER },
    { text = "", color = AMBER },
  }
  local keys = {"D"}  -- D = Done always available

  if offer and offer.upgradeOffer then
    table.insert(lines, { text = string.format("Upgrade ship (+50 tons) for %s", fmt(offer.upgradeOffer.cost)), color = GREEN })
    table.insert(lines, { text = "(U)pgrade  (N)o thanks", color = GREEN })
    table.insert(keys, "U")
    table.insert(keys, "N")
  end
  if offer and offer.gunOffer then
    table.insert(lines, { text = "", color = AMBER })
    table.insert(lines, { text = string.format("Buy a cannon for %s (needs 10 tons hold)", fmt(offer.gunOffer.cost)), color = GREEN })
    table.insert(lines, { text = "(G)un  (X) No cannon", color = GREEN })
    table.insert(keys, "G")
    table.insert(keys, "X")
  end
  if offer and offer.repairRate and (state.damage or 0) > 0 then
    local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))
    table.insert(lines, { text = "", color = AMBER })
    table.insert(lines, { text = string.format("Repair: %s/unit  SW: %d%%  Damage: %d",
      fmt(offer.repairRate), sw, math.floor(state.damage or 0)), color = AMBER })
    table.insert(lines, { text = "Enter repair amount (A=all): type number + Enter", color = GREEN })
    table.insert(keys, "R")  -- R enters repair type-mode (handled in onKey)
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
        -- Enter repair amount -- localSceneCb switches to "repair" sub-scene
        if localSceneCb then localSceneCb("repair") end
      end
    end,
  }
end

-- Scene: WuSession (automatic on HK arrival)
local function sceneWuSession(state, actions, localSceneCb)
  local maxRepay  = math.min(state.debt or 0, state.cash or 0)
  local maxBorrow = 2 * (state.cash or 0)
  local lines = {
    { text = "ELDER BROTHER WU",                    color = AMBER },
    { text = string.format("Debt: %s  Max repay: %s", fmt(state.debt), fmt(maxRepay)), color = AMBER },
    { text = string.format("Max borrow: %s",          fmt(maxBorrow)),                  color = AMBER },
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

-- Sub-scenes: BuySell
local function sceneBuySell(state, actions, localSceneCb, isBuy)
  local verb = isBuy and "buy" or "sell"
  local lines = {}
  for _, l in ipairs(statusLines(state)) do table.insert(lines, l) end
  for _, l in ipairs(priceLines(state)) do table.insert(lines, l) end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = string.format("Which good to %s? (1-4) or C to cancel", verb), color = GREEN })
  for i = 1, 4 do
    local available = isBuy and (state.holdSpace or 0) or (state.shipCargo[i] or 0)
    table.insert(lines, { text = string.format("  [%d] %s (avail: %d)", i, GOOD_NAMES[i], available), color = AMBER })
  end

  return lines, {
    type = "key",
    keys = {"1","2","3","4","C"},
    label = "1-4 to select good, C to cancel",
    onKey = function(key, _s, _a)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      else
        local idx = tonumber(key)
        if idx and idx >= 1 and idx <= 4 then
          if localSceneCb then localSceneCb(isBuy and ("buy_good_"..idx) or ("sell_good_"..idx)) end
        end
      end
    end,
  }
end

local function sceneBuySellAmount(state, actions, localSceneCb, goodIdx, isBuy)
  local goodName  = GOOD_NAMES[goodIdx]
  local price     = (state.currentPrices or {})[goodIdx] or 0
  local maxQty    = isBuy
    and math.min(math.floor((state.cash or 0) / math.max(1, price)), state.holdSpace or 0)
    or  (state.shipCargo[goodIdx] or 0)
  local verb = isBuy and "buy" or "sell"

  local lines = {
    { text = string.format("%s %s at %s each (max %d, A=all)", verb:upper(), goodName, fmt(price), maxQty), color = AMBER },
    { text = "Amount: ", color = GREEN },
  }

  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local qty
      if text:upper() == "A" then qty = maxQty
      else qty = tonumber(text) end
      if not qty or qty <= 0 then return "Please enter a positive number or A for all" end
      if qty > maxQty then return string.format("You can only %s %d units", verb, maxQty) end
      if isBuy then actions.buyGoods(goodIdx, math.floor(qty))
      else           actions.sellGoods(goodIdx, math.floor(qty)) end
      if localSceneCb then localSceneCb(nil) end  -- cleared on success; StateUpdate will re-render
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
        if localSceneCb then localSceneCb("bank_deposit") end
      elseif key == "W" then
        if localSceneCb then localSceneCb("bank_withdraw") end
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
    { text = string.format("%s amount (max %s, A=all):", verb:upper(), fmt(maxAmt)), color = AMBER },
    { text = "Amount: ", color = GREEN },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local amt
      if text:upper() == "A" then amt = maxAmt
      else amt = tonumber(text) end
      if not amt or amt <= 0 then return "Enter a positive amount or A for all" end
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
    table.insert(lines, { text = string.format("  %s -- Ship: %d  Warehouse: %d",
      GOOD_NAMES[i], state.shipCargo[i] or 0, state.warehouseCargo[i] or 0), color = AMBER })
  end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "(T)ransfer to warehouse  (F)rom warehouse  (C)ancel", color = GREEN })

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
  }
  for i = 1, 4 do
    local avail = isToWarehouse and (state.shipCargo[i] or 0) or (state.warehouseCargo[i] or 0)
    table.insert(lines, { text = string.format("  [%d] %s (%d avail)", i, GOOD_NAMES[i], avail), color = AMBER })
  end
  table.insert(lines, { text = "  [C] Cancel", color = DIM })

  return lines, {
    type = "key",
    keys = {"1","2","3","4","C"},
    label = "1-4 to select, C cancel",
    onKey = function(key, _s, _a)
      if key == "C" then if localSceneCb then localSceneCb(nil) end
      else
        local idx = tonumber(key)
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
  local direction = isToWarehouse and "to warehouse" or "from warehouse"
  local lines = {
    { text = string.format("Transfer %s %s (max %d, A=all):", goodName, direction, maxAmt), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local qty
      if text:upper() == "A" then qty = maxAmt
      else qty = tonumber(text) end
      if not qty or qty <= 0 then return "Enter a positive amount or A" end
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
    { text = string.format("Amount to %s (max %s, A=all):", verb, fmt(maxAmt)), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local amt
      if text:upper() == "A" then amt = maxAmt
      else amt = tonumber(text) end
      if not amt or amt <= 0 then return "Enter a positive amount or A" end
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
    { text = string.format("Repair: %s/unit. Max cost to fully repair: %s",
        fmt(offer.repairRate), fmt(maxCost)), color = AMBER },
    { text = "Cash to spend (A=max):", color = GREEN },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=max): ",
    onType = function(text, _s, _a)
      local amt
      if text:upper() == "A" then amt = maxCost
      else amt = tonumber(text) end
      if not amt or amt <= 0 then return "Enter a positive amount or A" end
      actions.shipRepair(math.floor(amt))
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

-- Main entry point
function PromptEngine.processState(state, localScene, actions, localSceneCb)
  -- Determine scene (priority order)
  if state.gameOver then
    return sceneGameOver(state, actions, localSceneCb)
  end
  if state.combat ~= nil then
    return sceneCombat(state, actions, localSceneCb)
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
  -- Sub-scenes
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
  if localScene == "travel"   then return sceneTravel(state, actions, localSceneCb) end
  if localScene == "settings" then return sceneSettings(state, actions, localSceneCb) end
  -- StartChoice: only when startChoice not yet made (InterfacePicker handles this
  -- before Apple2Interface is created, so state.startChoice is always set on arrival)
  if state.startChoice == nil and (state.turnsElapsed or 1) == 1 and (state.destination or 0) == 0 then
    return sceneStartChoice(state, actions, localSceneCb)
  end
  -- Default: AtPort
  return sceneAtPort(state, actions, localSceneCb)
end

return PromptEngine
