-- Constants.lua
local Constants = {}

Constants.PORT_NAMES = {
  "Hong Kong","Shanghai","Nagasaki","Saigon","Manila","Singapore","Batavia",
}
Constants.HONG_KONG = 1

Constants.MONTH_NAMES = {
  "Jan","Feb","Mar","Apr","May","Jun",
  "Jul","Aug","Sep","Oct","Nov","Dec"
}

Constants.GOOD_NAMES = {
  "Opium","Silk","Arms","General Cargo",
}

Constants.BASE_PRICES = {
  {11, 11, 12, 10},
  {16, 14, 16, 11},
  {15, 15, 10, 12},
  {14, 16, 11, 13},
  {12, 10, 13, 14},
  {10, 13, 14, 15},
  {13, 12, 15, 16},
}
Constants.PRICE_SCALE = {1000, 100, 10, 1}

Constants.WAREHOUSE_CAPACITY = 10000
Constants.CASH_START_CASH    = 400
Constants.CASH_START_DEBT    = 5000
Constants.CASH_START_HOLD    = 60
Constants.CASH_START_GUNS    = 0
Constants.CASH_START_BP      = 10
Constants.GUNS_START_CASH    = 0
Constants.GUNS_START_DEBT    = 0
Constants.GUNS_START_HOLD    = 60
Constants.GUNS_START_GUNS    = 5
Constants.GUNS_START_BP      = 7

Constants.EC_START = 20
Constants.ED_START = 0.5

Constants.BANK_INTEREST_RATE = 0.005
Constants.DEBT_INTEREST_RATE = 0.1

return Constants