-- GameState.lua
-- Constructs the canonical game state table.
-- ALL game logic runs on the server; this module is shared so the client
-- can interpret state updates without needing to re-derive structure.

local Constants = require(script.Parent.Constants)

local GameState = {}

-- Creates a fresh game state for one player.
-- startChoice: "cash" (default) or "guns"
-- firmName: optional string, player's firm name
function GameState.newGame(startChoice, firmName)
  local isCash = (startChoice ~= "guns")

  local state = {
    -- Economy
    cash         = isCash and Constants.CASH_START_CASH or Constants.GUNS_START_CASH,
    bankBalance  = 0,
    debt         = isCash and Constants.CASH_START_DEBT or Constants.GUNS_START_DEBT,

    -- Ship
    shipCapacity = isCash and Constants.CASH_START_HOLD or Constants.GUNS_START_HOLD,
    -- holdSpace is recalculated each arrival as: shipCapacity - sum(shipCargo) - guns*10
    -- At construction, no cargo is loaded and guns are not yet deducted here
    -- (mirrors BASIC line 10150 which sets MW=SC directly)
    holdSpace    = isCash and Constants.CASH_START_HOLD or Constants.GUNS_START_HOLD,
    damage       = 0,     -- DM: may be fractional during combat; truncate only for display
    guns         = isCash and Constants.CASH_START_GUNS or Constants.GUNS_START_GUNS,
    pirateBase   = isCash and Constants.CASH_START_BP   or Constants.GUNS_START_BP,

    -- Cargo: index 1=Opium, 2=Silk, 3=Arms, 4=General Cargo
    shipCargo      = {0, 0, 0, 0},   -- ST(2,J)
    warehouseCargo = {0, 0, 0, 0},   -- ST(1,J)
    warehouseUsed  = 0,               -- WS; capacity is Constants.WAREHOUSE_CAPACITY (fixed, not per-player)

    -- Prices (set by PriceEngine each arrival)
    currentPrices  = {0, 0, 0, 0},

    -- Base price matrix (mutable — drifts each January)
    -- Deep copy from Constants so mutations don't affect the source table
    basePrices = (function()
      local copy = {}
      for p = 1, 7 do
        copy[p] = {}
        for g = 1, 4 do
          copy[p][g] = Constants.BASE_PRICES[p][g]
        end
      end
      return copy
    end)(),

    -- Time
    turnsElapsed = 1,   -- TI: starts at 1 per BASIC line 10150
    month        = 1,   -- MO
    year         = 1860,-- YE
    destination  = 0,   -- D: 0 on first turn (D=0 guard skips interest)

    -- Location
    currentPort  = 1,   -- LO: start at Hong Kong

    -- Flags
    wuWarningGiven   = false,  -- WN
    liYuenProtection = 0,      -- LI: 0 = no protection, non-zero = protected
    liYuenOfferCost  = nil,   -- set on HK arrival when LI=0 and CA>0; cost to buy Li Yuen protection
    inWuSession      = false,  -- true while at HK Wu interaction; cleared by LeaveWu
    bankruptcyCount  = 0,      -- BL (BASIC int var): emergency loan counter
    gameOver         = false,  -- true when ship sinks; client shows game over screen
    combat           = nil,    -- combat sub-table when in combat, nil otherwise
    startChoice      = startChoice,   -- ADD: raw start type for save/load round-trips
    firmName         = type(firmName) == "string" and firmName or "",
    seenTutorial     = false,         -- ADD: set true after first HK tutorial fires
    uiMode = nil,   -- nil = not yet chosen; "modern" or "apple2" once set

    -- Phase 6: progression
    gameOverReason = nil,   -- "sunk" | "quit" | "retired" (nil = game in progress)
    finalScore     = nil,   -- set at game over
    finalRating    = nil,   -- set at game over
    shipOffer      = nil,   -- set on HK arrival: { repairRate=BR, upgradeOffer={cost=X}|nil, gunOffer={cost=Y}|nil }

    -- Combat scaling (increase each January)
    enemyBaseHP     = Constants.EC_START,   -- EC
    enemyBaseDamage = Constants.ED_START,   -- ED
  }

  return state
end

return GameState
