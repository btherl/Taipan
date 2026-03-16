-- Constants.lua
-- All fixed game data. Edit here to tune game balance.
-- Base prices verified against BASIC source line 10200 (BASIC_ANNOTATED.md).

local Constants = {}

-- Port indices 1-7 (index 0 = "At sea", handled separately in travel logic)
Constants.PORT_NAMES = {
  "Hong Kong",   -- 1
  "Shanghai",    -- 2
  "Nagasaki",    -- 3
  "Saigon",      -- 4
  "Manila",      -- 5
  "Singapore",   -- 6
  "Batavia",     -- 7
}

Constants.HONG_KONG = 1  -- port index for HK-only events

-- Good indices 1-4
Constants.GOOD_NAMES = {
  "Opium",          -- 1
  "Silk",           -- 2
  "Arms",           -- 3
  "General Cargo",  -- 4
}

-- BASE_PRICES[port][good] — from BASIC DATA statement, line 10200
-- Columns below are port 1-7; rows are goods:
-- Opium:   11,16,15,14,12,10,13
-- Silk:    11,14,15,16,10,13,12
-- Arms:    12,16,10,11,13,14,15
-- General: 10,11,12,13,14,15,16
Constants.BASE_PRICES = {
  {11, 11, 12, 10},  -- Port 1: Hong Kong
  {16, 14, 16, 11},  -- Port 2: Shanghai
  {15, 15, 10, 12},  -- Port 3: Nagasaki
  {14, 16, 11, 13},  -- Port 4: Saigon
  {12, 10, 13, 14},  -- Port 5: Manila
  {10, 13, 14, 15},  -- Port 6: Singapore
  {13, 12, 15, 16},  -- Port 7: Batavia
}

-- Price scale per good (10^(4-goodIndex)): Opium=1000, Silk=100, Arms=10, General=1
Constants.PRICE_SCALE = {1000, 100, 10, 1}

-- Starting state
Constants.WAREHOUSE_CAPACITY = 10000
Constants.CASH_START_CASH    = 400
Constants.CASH_START_DEBT    = 5000
Constants.CASH_START_HOLD    = 60
Constants.CASH_START_GUNS    = 0
Constants.CASH_START_BP      = 10  -- pirate encounter base
Constants.GUNS_START_CASH    = 0
Constants.GUNS_START_DEBT    = 0
Constants.GUNS_START_HOLD    = 10
Constants.GUNS_START_GUNS    = 5
Constants.GUNS_START_BP      = 7   -- pirate encounter base

-- Combat scaling (starting values, incremented each January)
Constants.EC_START = 20    -- enemy base HP pool
Constants.ED_START = 0.5   -- enemy base damage

-- Financial rates (per voyage)
Constants.BANK_INTEREST_RATE = 0.005   -- 0.5% per month
Constants.DEBT_INTEREST_RATE = 0.1     -- 10% per month

return Constants
