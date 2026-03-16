# Taipan! Roblox Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a faithful single-player Roblox port of the classic Apple II game Taipan in 8 vertical-slice phases, each ending in a playable milestone.

**Architecture:** All game logic runs server-side (authoritative state); the client is pure UI and input, communicating via RemoteEvents. Pure 2D ScreenGui — no 3D world. Each phase produces a playable build before the next phase begins.

**Tech Stack:** Luau (Roblox), Rojo (file-based source control), TestEZ (unit tests run in Studio), Roblox Studio for integration testing.

**Reference documents:**
- Mechanics: `DESIGN_DOCUMENT.md` (v3.0) — authoritative for all formulas and probabilities
- Annotated BASIC source: `BASIC_ANNOTATED.md` — cite line numbers when verifying formulas
- Phase spec: `docs/superpowers/specs/2026-03-16-taipan-roblox-implementation-phases-design.md`

---

## Chunk 1: Phase 1 — Foundation + Trading Loop

Phase 1 goal: buy and sell goods at Hong Kong, prices fluctuate, you can go broke.

### File Structure (Phase 1)

```
Taipan/
├── default.project.json             -- Rojo project: maps src/ to Roblox services
├── .gitignore
├── src/
│   ├── ServerScriptService/
│   │   └── GameService.server.lua   -- Player state map, handles all RemoteEvents
│   ├── ReplicatedStorage/
│   │   ├── Remotes.lua              -- Creates and exposes all RemoteEvents
│   │   └── shared/
│   │       ├── Constants.lua        -- Port names, base prices, good names, config
│   │       ├── GameState.lua        -- newGame() constructor, state helpers
│   │       ├── PriceEngine.lua      -- calculatePrices(), crash/boom logic
│   │       └── Validators.lua       -- canBuy(), canSell(), holdSpaceFor()
│   └── StarterGui/
│       └── TaipanGui/
│           ├── init.client.lua      -- GameController: wires UI events to RemoteEvents
│           └── Panels/
│               ├── StatusStrip.lua  -- Cash / debt / bank one-line display
│               ├── InventoryPanel.lua -- Hold + warehouse side-by-side
│               ├── PricesPanel.lua  -- 4-good price table
│               └── BuySellPanel.lua -- Good selector, amount input, Buy/Sell buttons
└── tests/
    ├── TestRunner.server.lua        -- Discovers and runs all .spec files in Studio Play
    ├── Constants.spec.lua
    ├── GameState.spec.lua
    ├── PriceEngine.spec.lua
    └── Validators.spec.lua
```

---

### Task 1: Project Setup

**Files:**
- Create: `default.project.json`
- Create: `.gitignore`
- Create: all `src/` and `tests/` directories (empty, with `.gitkeep`)

- [ ] **Step 1: Install Rojo**

  Download Rojo from https://rojo.space and install the VS Code extension and Studio plugin. Verify with:
  ```bash
  rojo --version
  ```
  Expected: version string (0.6.x or newer)

- [ ] **Step 2: Create `default.project.json`**

  ```json
  {
    "name": "Taipan",
    "tree": {
      "$className": "DataModel",
      "ServerScriptService": {
        "$className": "ServerScriptService",
        "$path": "src/ServerScriptService",
        "Tests": {
          "$className": "Folder",
          "$path": "tests"
        }
      },
      "ReplicatedStorage": {
        "$className": "ReplicatedStorage",
        "$path": "src/ReplicatedStorage"
      },
      "StarterGui": {
        "$className": "StarterGui",
        "TaipanGui": {
          "$className": "ScreenGui",
          "$path": "src/StarterGui/TaipanGui"
        }
      }
    }
  }
  ```

- [ ] **Step 3: Create `.gitignore`**

  ```
  *.rbxl
  *.rbxlx
  .DS_Store
  Thumbs.db
  ```

- [ ] **Step 4: Create directory structure**

  ```bash
  mkdir -p src/ServerScriptService
  mkdir -p src/ReplicatedStorage/shared
  mkdir -p "src/StarterGui/TaipanGui/Panels"
  mkdir -p tests
  touch src/ServerScriptService/.gitkeep
  touch "src/StarterGui/TaipanGui/Panels/.gitkeep"
  touch tests/.gitkeep
  ```

- [ ] **Step 5: Initial commit**

  ```bash
  git add default.project.json .gitignore src/ tests/
  git commit -m "chore: scaffold Rojo project structure"
  ```

---

### Task 2: TestEZ Setup + Test Runner

**Files:**
- Create: `src/ReplicatedStorage/TestEZ.lua` (copy from TestEZ GitHub release)
- Create: `tests/TestRunner.server.lua`

- [ ] **Step 1: Install TestEZ**

  Download `TestEZ.lua` from https://github.com/Roblox/testez/releases (single-file build).
  Copy to `src/ReplicatedStorage/TestEZ.lua`.

- [ ] **Step 2: Create `tests/TestRunner.server.lua`**

  ```lua
  -- TestRunner.server.lua
  -- Run this in Studio Play mode (not Live) to execute all .spec files.
  -- Output appears in the Studio Output window.
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local ServerScriptService = game:GetService("ServerScriptService")

  local TestEZ = require(ReplicatedStorage.TestEZ)

  -- Collect all .spec modules under tests/
  -- Tests is a Folder inside ServerScriptService (mapped via default.project.json)
  local testsFolder = ServerScriptService:FindFirstChild("Tests")
    or error("Tests folder not found in ServerScriptService")
  local testModules = {}
  for _, desc in ipairs(testsFolder:GetDescendants()) do
    if desc:IsA("ModuleScript") and desc.Name:match("%.spec$") then
      table.insert(testModules, desc)
    end
  end

  local results = TestEZ.TestBootstrap:run(testModules)
  if results.failureCount > 0 then
    error(string.format("Tests failed: %d failure(s)", results.failureCount))
  end
  print(string.format("All tests passed (%d suites)", #testModules))
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add src/ReplicatedStorage/TestEZ.lua tests/TestRunner.server.lua
  git commit -m "chore: add TestEZ and test runner"
  ```

---

### Task 3: Constants Module

**Files:**
- Create: `src/ReplicatedStorage/shared/Constants.lua`
- Create: `tests/Constants.spec.lua`

- [ ] **Step 1: Write the failing test**

  Create `tests/Constants.spec.lua`:
  ```lua
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Constants = require(ReplicatedStorage.shared.Constants)

  return function()
    describe("Constants", function()
      it("has 7 port names (indices 1-7)", function()
        expect(#Constants.PORT_NAMES).to.equal(7)
        expect(Constants.PORT_NAMES[1]).to.equal("Hong Kong")
        expect(Constants.PORT_NAMES[7]).to.equal("Batavia")
      end)

      it("has 4 good names", function()
        expect(#Constants.GOOD_NAMES).to.equal(4)
        expect(Constants.GOOD_NAMES[1]).to.equal("Opium")
        expect(Constants.GOOD_NAMES[4]).to.equal("General Cargo")
      end)

      it("has base price matrix [7 ports][4 goods]", function()
        expect(#Constants.BASE_PRICES).to.equal(7)
        for _, row in ipairs(Constants.BASE_PRICES) do
          expect(#row).to.equal(4)
        end
      end)

      it("has correct base price for HK Opium (11)", function()
        expect(Constants.BASE_PRICES[1][1]).to.equal(11)
      end)

      it("has correct base price for Batavia General Cargo (16)", function()
        expect(Constants.BASE_PRICES[7][4]).to.equal(16)
      end)

      it("has starting config values", function()
        expect(Constants.WAREHOUSE_CAPACITY).to.equal(10000)
        expect(Constants.CASH_START_CASH).to.equal(400)
        expect(Constants.CASH_START_DEBT).to.equal(5000)
        expect(Constants.CASH_START_HOLD).to.equal(60)
        expect(Constants.GUNS_START_HOLD).to.equal(10)
        expect(Constants.GUNS_START_GUNS).to.equal(5)
      end)
    end)
  end
  ```

- [ ] **Step 2: Run tests in Studio — confirm FAIL**

  Open Studio, start Rojo sync (`rojo serve`), enter Play mode. Check Output window.
  Expected: error `Constants is not a valid member of ReplicatedStorage.shared`

- [ ] **Step 3: Create `src/ReplicatedStorage/shared/Constants.lua`**

  ```lua
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
  -- Opium: 11,16,15,14,12,10,13
  -- Silk:  11,14,15,16,10,13,12
  -- Arms:  12,16,10,11,13,14,15
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
  Constants.GUNS_START_BP      = 7

  -- Combat scaling (starting values, incremented each January)
  Constants.EC_START = 20    -- enemy base HP pool
  Constants.ED_START = 0.5   -- enemy base damage

  -- Financial rates (per voyage)
  Constants.BANK_INTEREST_RATE = 0.005   -- 0.5% per month
  Constants.DEBT_INTEREST_RATE = 0.1     -- 10% per month

  return Constants
  ```

- [ ] **Step 4: Run tests in Studio — confirm PASS**

  Expected Output: `All tests passed (1 suites)`

- [ ] **Step 5: Commit**

  ```bash
  git add src/ReplicatedStorage/shared/Constants.lua tests/Constants.spec.lua
  git commit -m "feat: add Constants module with base price matrix and config"
  ```

---

### Task 4: GameState Module

**Files:**
- Create: `src/ReplicatedStorage/shared/GameState.lua`
- Create: `tests/GameState.spec.lua`

- [ ] **Step 1: Write the failing test**

  Create `tests/GameState.spec.lua`:
  ```lua
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local GameState = require(ReplicatedStorage.shared.GameState)
  local Constants = require(ReplicatedStorage.shared.Constants)

  return function()
    describe("GameState.newGame", function()
      it("cash start: correct opening values", function()
        local s = GameState.newGame("cash")
        expect(s.cash).to.equal(Constants.CASH_START_CASH)
        expect(s.debt).to.equal(Constants.CASH_START_DEBT)
        expect(s.shipCapacity).to.equal(Constants.CASH_START_HOLD)
        expect(s.holdSpace).to.equal(Constants.CASH_START_HOLD)
        expect(s.guns).to.equal(Constants.CASH_START_GUNS)
        expect(s.pirateBase).to.equal(Constants.CASH_START_BP)
      end)

      it("guns start: correct opening values", function()
        local s = GameState.newGame("guns")
        expect(s.cash).to.equal(Constants.GUNS_START_CASH)
        expect(s.debt).to.equal(Constants.GUNS_START_DEBT)
        expect(s.guns).to.equal(Constants.GUNS_START_GUNS)
        expect(s.shipCapacity).to.equal(Constants.GUNS_START_HOLD)
      end)

      it("starts at Hong Kong (port 1), TI=1, January 1860", function()
        local s = GameState.newGame("cash")
        expect(s.currentPort).to.equal(1)
        expect(s.month).to.equal(1)
        expect(s.year).to.equal(1860)
        expect(s.turnsElapsed).to.equal(1)
      end)

      it("has empty cargo arrays (4 goods, hold and warehouse)", function()
        local s = GameState.newGame("cash")
        expect(#s.shipCargo).to.equal(4)
        expect(#s.warehouseCargo).to.equal(4)
        for i = 1, 4 do
          expect(s.shipCargo[i]).to.equal(0)
          expect(s.warehouseCargo[i]).to.equal(0)
        end
      end)

      it("bank starts at 0", function()
        local s = GameState.newGame("cash")
        expect(s.bankBalance).to.equal(0)
      end)

      it("has empty prices array (4 goods)", function()
        local s = GameState.newGame("cash")
        expect(#s.currentPrices).to.equal(4)
      end)

      it("destination is 0 (D=0 guard for first turn)", function()
        local s = GameState.newGame("cash")
        expect(s.destination).to.equal(0)
      end)
    end)
  end
  ```

- [ ] **Step 2: Run tests — confirm FAIL**

- [ ] **Step 3: Create `src/ReplicatedStorage/shared/GameState.lua`**

  ```lua
  -- GameState.lua
  -- Constructs the canonical game state table.
  -- ALL game logic runs on the server; this module is shared so the client
  -- can interpret state updates without needing to re-derive structure.

  local Constants = require(script.Parent.Constants)

  local GameState = {}

  -- Creates a fresh game state for one player.
  -- startChoice: "cash" (default) or "guns"
  function GameState.newGame(startChoice)
    local isCash = (startChoice ~= "guns")

    local state = {
      -- Economy
      cash         = isCash and Constants.CASH_START_CASH or Constants.GUNS_START_CASH,
      bankBalance  = 0,
      debt         = isCash and Constants.CASH_START_DEBT or Constants.GUNS_START_DEBT,

      -- Ship
      shipCapacity = isCash and Constants.CASH_START_HOLD or Constants.GUNS_START_HOLD,
      holdSpace    = isCash and Constants.CASH_START_HOLD or Constants.GUNS_START_HOLD,
      damage       = 0,     -- DM: accumulated fractional damage
      guns         = isCash and Constants.CASH_START_GUNS or Constants.GUNS_START_GUNS,
      pirateBase   = isCash and Constants.CASH_START_BP   or Constants.GUNS_START_BP,

      -- Cargo: index 1=Opium, 2=Silk, 3=Arms, 4=General Cargo
      shipCargo      = {0, 0, 0, 0},   -- ST(2,J)
      warehouseCargo = {0, 0, 0, 0},   -- ST(1,J)
      warehouseUsed  = 0,               -- WS

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
      bankruptcyCount  = 0,      -- BL%: emergency loan counter

      -- Combat scaling (increase each January)
      enemyBaseHP     = Constants.EC_START,   -- EC
      enemyBaseDamage = Constants.ED_START,   -- ED
    }

    return state
  end

  return GameState
  ```

- [ ] **Step 4: Run tests — confirm PASS**

- [ ] **Step 5: Commit**

  ```bash
  git add src/ReplicatedStorage/shared/GameState.lua tests/GameState.spec.lua
  git commit -m "feat: add GameState module with newGame constructor"
  ```

---

### Task 5: PriceEngine Module

**Files:**
- Create: `src/ReplicatedStorage/shared/PriceEngine.lua`
- Create: `tests/PriceEngine.spec.lua`

- [ ] **Step 1: Write the failing test**

  Create `tests/PriceEngine.spec.lua`:
  ```lua
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local PriceEngine = require(ReplicatedStorage.shared.PriceEngine)
  local Constants   = require(ReplicatedStorage.shared.Constants)

  return function()
    describe("PriceEngine.calculatePrices", function()
      it("returns a table of 4 prices", function()
        local prices = PriceEngine.calculatePrices(Constants.BASE_PRICES, 1)
        expect(#prices).to.equal(4)
      end)

      it("Opium price is in range [BP/2*1*1000, BP/2*3*1000]", function()
        -- HK opium BP=11, so range is 11/2*1*1000=5500 to 11/2*3*1000=16500
        -- Run many times to check bounds (seed doesn't matter for range test)
        local bp = Constants.BASE_PRICES
        for _ = 1, 100 do
          local prices = PriceEngine.calculatePrices(bp, 1)
          local opiumPrice = prices[1]
          -- Allow for crash (1/5x) and boom (5-9x) events
          expect(opiumPrice).to.be.ok()  -- not nil
          expect(opiumPrice > 0).to.equal(true)
        end
      end)

      it("General Cargo price is much lower than Opium", function()
        -- General Cargo scale=1 vs Opium scale=1000
        -- Even at max BP=16, General max normal = 16/2*3*1 = 24
        -- Opium at min BP=10, min normal = 10/2*1*1000 = 5000
        local bp = Constants.BASE_PRICES
        local totalOpium, totalGeneral = 0, 0
        for _ = 1, 50 do
          local prices = PriceEngine.calculatePrices(bp, 1)
          totalOpium = totalOpium + prices[1]
          totalGeneral = totalGeneral + prices[4]
        end
        expect(totalOpium > totalGeneral * 100).to.equal(true)
      end)

      it("uses port-specific base prices (HK vs Shanghai differ)", function()
        -- Shanghai opium BP=16 vs HK BP=11 — Shanghai prices should average higher
        local bp = Constants.BASE_PRICES
        local hkTotal, shTotal = 0, 0
        for _ = 1, 200 do
          hkTotal = hkTotal + PriceEngine.calculatePrices(bp, 1)[1]
          shTotal = shTotal + PriceEngine.calculatePrices(bp, 2)[1]
        end
        -- Shanghai average should be higher (ratio ~16/11 ≈ 1.45)
        expect(shTotal > hkTotal).to.equal(true)
      end)
    end)

    describe("PriceEngine crash/boom events", function()
      it("crash produces price ~1/5 of normal", function()
        -- We can't force a crash, but we can verify the formula
        local normalPrice = PriceEngine._basePrice(11, 1, 2)  -- BP=11, good=1, rand=2
        local crashPrice  = PriceEngine._crashPrice(normalPrice)
        expect(crashPrice).to.equal(math.floor(normalPrice / 5))
      end)

      it("boom multiplies price by 5-9x", function()
        local normalPrice = PriceEngine._basePrice(11, 1, 2)
        for mult = 5, 9 do
          local boomedPrice = PriceEngine._boomPrice(normalPrice, mult)
          expect(boomedPrice).to.equal(normalPrice * mult)
        end
      end)
    end)
  end
  ```

- [ ] **Step 2: Run tests — confirm FAIL**

- [ ] **Step 3: Create `src/ReplicatedStorage/shared/PriceEngine.lua`**

  ```lua
  -- PriceEngine.lua
  -- Calculates current port prices for all 4 goods.
  -- Formula from BASIC line 2100:
  --   CP(I) = BP%(LO,I) / 2 * (FN_R(3) + 1) * 10^(4-I)
  -- Crash/boom events from BASIC lines 2410-2450:
  --   1-in-9 chance per good: crash (price/5) or boom (price*5..9)

  local Constants = require(script.Parent.Constants)

  local PriceEngine = {}

  -- Internal: base price for a single good before crash/boom
  -- bp: base price value, goodIndex: 1-4, randFactor: 1-3
  function PriceEngine._basePrice(bp, goodIndex, randFactor)
    local scale = Constants.PRICE_SCALE[goodIndex]
    return math.floor(bp / 2 * randFactor * scale)
  end

  function PriceEngine._crashPrice(price)
    return math.floor(price / 5)
  end

  function PriceEngine._boomPrice(price, multiplier)
    return price * multiplier
  end

  -- Calculates prices for all 4 goods at the given port.
  -- basePrices: the mutable base price matrix from GameState (not Constants directly,
  --             since it drifts each January)
  -- portIndex: 1-7
  -- Returns: array of 4 integer prices
  function PriceEngine.calculatePrices(basePrices, portIndex)
    local prices = {}
    for good = 1, 4 do
      local bp = basePrices[portIndex][good]
      local randFactor = math.random(1, 3)           -- FN_R(3) + 1 → range 1-3
      local price = PriceEngine._basePrice(bp, good, randFactor)

      -- Crash/boom: 1-in-9 chance (FN_R(9) = 0 triggers event)
      if math.random(0, 8) == 0 then
        -- 50/50: crash or boom
        if math.random(0, 1) == 0 then
          price = PriceEngine._crashPrice(price)
        else
          local multiplier = math.random(5, 9)       -- FN_R(5) + 5 → range 5-9
          price = PriceEngine._boomPrice(price, multiplier)
        end
      end

      prices[good] = price
    end
    return prices
  end

  -- Applies the annual January base price drift to the mutable basePrices table.
  -- Called once per in-game year. Mutates basePrices in place.
  -- From BASIC line 1020: BP%(I,J) += FN_R(2) for all ports and goods.
  function PriceEngine.applyAnnualDrift(basePrices)
    for port = 1, 7 do
      for good = 1, 4 do
        basePrices[port][good] = basePrices[port][good] + math.random(0, 1)
      end
    end
  end

  return PriceEngine
  ```

- [ ] **Step 4: Run tests — confirm PASS**

- [ ] **Step 5: Commit**

  ```bash
  git add src/ReplicatedStorage/shared/PriceEngine.lua tests/PriceEngine.spec.lua
  git commit -m "feat: add PriceEngine with price calculation and crash/boom events"
  ```

---

### Task 6: Validators Module

**Files:**
- Create: `src/ReplicatedStorage/shared/Validators.lua`
- Create: `tests/Validators.spec.lua`

- [ ] **Step 1: Write the failing test**

  Create `tests/Validators.spec.lua`:
  ```lua
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Validators = require(ReplicatedStorage.shared.Validators)
  local GameState  = require(ReplicatedStorage.shared.GameState)

  return function()
    describe("Validators.canBuy", function()
      it("returns true when player can afford and has hold space", function()
        local s = GameState.newGame("cash")  -- 400 cash, 60 hold
        expect(Validators.canBuy(s, 1, 1, 100)).to.equal(true)  -- buy 1 opium at 100
      end)

      it("returns false when price exceeds cash", function()
        local s = GameState.newGame("cash")
        expect(Validators.canBuy(s, 1, 1, 1000)).to.equal(false) -- 1 opium at 1000 > 400 cash
      end)

      it("returns false when quantity exceeds hold space", function()
        local s = GameState.newGame("cash")
        s.cash = 1000000
        expect(Validators.canBuy(s, 61, 1, 1)).to.equal(false)  -- 61 units, only 60 hold
      end)
    end)

    describe("Validators.canSell", function()
      it("returns true when player has the goods", function()
        local s = GameState.newGame("cash")
        s.shipCargo[2] = 10  -- 10 silk on ship
        expect(Validators.canSell(s, 5, 2)).to.equal(true)
      end)

      it("returns false when player has fewer goods than requested", function()
        local s = GameState.newGame("cash")
        s.shipCargo[2] = 3
        expect(Validators.canSell(s, 5, 2)).to.equal(false)
      end)
    end)

    describe("Validators.holdSpaceFor", function()
      it("returns correct available hold space", function()
        local s = GameState.newGame("cash")  -- 60 hold, 0 used
        expect(Validators.holdSpaceFor(s)).to.equal(60)
      end)

      it("reduces after buying cargo", function()
        local s = GameState.newGame("cash")
        s.holdSpace = 40
        expect(Validators.holdSpaceFor(s)).to.equal(40)
      end)
    end)
  end
  ```

- [ ] **Step 2: Run tests — confirm FAIL**

- [ ] **Step 3: Create `src/ReplicatedStorage/shared/Validators.lua`**

  ```lua
  -- Validators.lua
  -- Pure functions that check whether a game action is legal.
  -- All validation must also be performed server-side before mutating state.

  local Validators = {}

  -- Can the player buy `quantity` units of `goodIndex` at `pricePerUnit`?
  function Validators.canBuy(state, quantity, goodIndex, pricePerUnit)
    local totalCost = quantity * pricePerUnit
    if totalCost > state.cash then return false end
    if quantity > state.holdSpace then return false end
    return true
  end

  -- Can the player sell `quantity` units of `goodIndex` from their ship hold?
  function Validators.canSell(state, quantity, goodIndex)
    return state.shipCargo[goodIndex] >= quantity
  end

  -- How many units of cargo can fit in the hold right now?
  function Validators.holdSpaceFor(state)
    return state.holdSpace
  end

  return Validators
  ```

- [ ] **Step 4: Run tests — confirm PASS**

- [ ] **Step 5: Commit**

  ```bash
  git add src/ReplicatedStorage/shared/Validators.lua tests/Validators.spec.lua
  git commit -m "feat: add Validators module for buy/sell/hold checks"
  ```

---

### Task 7: RemoteEvents

**Files:**
- Create: `src/ReplicatedStorage/Remotes.lua`

- [ ] **Step 1: Create `src/ReplicatedStorage/Remotes.lua`**

  ```lua
  -- Remotes.lua
  -- Single source of truth for all RemoteEvents and RemoteFunctions.
  -- Required by both server and client.

  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Remotes = {}

  local function getOrCreate(className, name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing then return existing end
    local obj = Instance.new(className)
    obj.Name = name
    obj.Parent = ReplicatedStorage
    return obj
  end

  -- Client → Server actions
  Remotes.ChooseStart    = getOrCreate("RemoteEvent", "ChooseStart")    -- "cash" or "guns"
  Remotes.BuyGoods       = getOrCreate("RemoteEvent", "BuyGoods")       -- goodIndex, quantity
  Remotes.SellGoods      = getOrCreate("RemoteEvent", "SellGoods")      -- goodIndex, quantity
  Remotes.EndTurn        = getOrCreate("RemoteEvent", "EndTurn")        -- recalculate prices

  -- Server → Client updates
  Remotes.StateUpdate    = getOrCreate("RemoteEvent", "StateUpdate")    -- full state snapshot

  -- Server → Client: request player input
  Remotes.RequestStateUpdate = getOrCreate("RemoteEvent", "RequestStateUpdate")

  return Remotes
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add src/ReplicatedStorage/Remotes.lua
  git commit -m "feat: define all RemoteEvents for Phase 1"
  ```

---

### Task 8: GameService (Server)

**Files:**
- Create: `src/ServerScriptService/GameService.server.lua`

- [ ] **Step 1: Create `src/ServerScriptService/GameService.server.lua`**

  ```lua
  -- GameService.server.lua
  -- Authoritative game state. All mutations happen here.
  -- Clients receive state snapshots via StateUpdate RemoteEvent.

  local Players           = game:GetService("Players")
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local GameState   = require(ReplicatedStorage.shared.GameState)
  local PriceEngine = require(ReplicatedStorage.shared.PriceEngine)
  local Validators  = require(ReplicatedStorage.shared.Validators)
  local Remotes     = require(ReplicatedStorage.Remotes)

  -- Per-player state map. Never use global state.
  local playerStates: {[Player]: any} = {}

  local function pushState(player)
    local state = playerStates[player]
    if state then
      Remotes.StateUpdate:FireClient(player, state)
    end
  end

  -- Input guards: reject malformed RemoteEvent arguments silently
  local function validGood(g)
    return type(g) == "number" and g >= 1 and g <= 4 and math.floor(g) == g
  end
  local function validQty(q)
    return type(q) == "number" and q > 0 and math.floor(q) == q
  end

  -- Initialise a player's game state after they choose cash or guns start
  Remotes.ChooseStart.OnServerEvent:Connect(function(player, startChoice)
    if startChoice ~= "cash" and startChoice ~= "guns" then startChoice = "cash" end
    local state = GameState.newGame(startChoice)
    -- Calculate initial prices for Hong Kong
    state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
    playerStates[player] = state
    pushState(player)
  end)

  -- Buy goods: validate, deduct cash, add to hold
  Remotes.BuyGoods.OnServerEvent:Connect(function(player, goodIndex, quantity)
    local state = playerStates[player]
    if not state then return end
    if not validGood(goodIndex) or not validQty(quantity) then return end

    local price = state.currentPrices[goodIndex]
    if not Validators.canBuy(state, quantity, goodIndex, price) then
      pushState(player)  -- push back correct state (reject cheat)
      return
    end

    state.cash                   = state.cash - quantity * price
    state.shipCargo[goodIndex]   = state.shipCargo[goodIndex] + quantity
    state.holdSpace              = state.holdSpace - quantity
    pushState(player)
  end)

  -- Sell goods: validate, add cash, remove from hold
  Remotes.SellGoods.OnServerEvent:Connect(function(player, goodIndex, quantity)
    local state = playerStates[player]
    if not state then return end
    if not validGood(goodIndex) or not validQty(quantity) then return end

    if not Validators.canSell(state, quantity, goodIndex) then
      pushState(player)
      return
    end

    local price = state.currentPrices[goodIndex]
    state.cash                   = state.cash + quantity * price
    state.shipCargo[goodIndex]   = state.shipCargo[goodIndex] - quantity
    state.holdSpace              = state.holdSpace + quantity
    pushState(player)
  end)

  -- End Turn: recalculate prices (simulates staying in port; travel added Phase 2)
  Remotes.EndTurn.OnServerEvent:Connect(function(player)
    local state = playerStates[player]
    if not state then return end

    state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
    pushState(player)
  end)

  -- Request for full state refresh (e.g. client reconnected)
  Remotes.RequestStateUpdate.OnServerEvent:Connect(function(player)
    pushState(player)
  end)

  -- Cleanup on disconnect
  Players.PlayerRemoving:Connect(function(player)
    playerStates[player] = nil
  end)
  ```

- [ ] **Step 2: Manual test in Studio Play mode**

  In the Studio Output window, you should see no errors on Play. Open the Remote Events inspector and fire `ChooseStart` with `"cash"` to confirm it initialises state and fires back `StateUpdate`.

- [ ] **Step 3: Commit**

  ```bash
  git add src/ServerScriptService/GameService.server.lua
  git commit -m "feat: add GameService with buy/sell/end-turn server logic"
  ```

---

### Task 9: UI — StatusStrip + InventoryPanel

**Files:**
- Create: `src/StarterGui/TaipanGui/Panels/StatusStrip.lua`
- Create: `src/StarterGui/TaipanGui/Panels/InventoryPanel.lua`

- [ ] **Step 1: Create `StatusStrip.lua`**

  ```lua
  -- StatusStrip.lua
  -- One-line display: Cash | Debt | Bank
  -- Receives the full game state table and refreshes labels.

  local StatusStrip = {}

  function StatusStrip.new(parent)
    local frame = Instance.new("Frame")
    frame.Name = "StatusStrip"
    frame.Size = UDim2.new(1, 0, 0, 30)
    frame.Position = UDim2.new(0, 0, 0, 0)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BorderSizePixel = 0
    frame.Parent = parent

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 10)
    layout.Parent = frame

    local function makeLabel(name)
      local lbl = Instance.new("TextLabel")
      lbl.Name = name
      lbl.Size = UDim2.new(0.33, -7, 1, 0)
      lbl.BackgroundTransparency = 1
      lbl.TextColor3 = Color3.fromRGB(200, 180, 80)  -- amber terminal
      lbl.Font = Enum.Font.RobotoMono
      lbl.TextSize = 14
      lbl.TextXAlignment = Enum.TextXAlignment.Left
      lbl.Parent = frame
      return lbl
    end

    local cashLabel = makeLabel("CashLabel")
    local debtLabel = makeLabel("DebtLabel")
    local bankLabel = makeLabel("BankLabel")

    local strip = {}

    function strip.update(state)
      cashLabel.Text = string.format("Cash: $%d", state.cash)
      debtLabel.Text = string.format("Debt: $%d", state.debt)
      bankLabel.Text = string.format("Bank: $%d", state.bankBalance)
    end

    return strip
  end

  return StatusStrip
  ```

- [ ] **Step 2: Create `InventoryPanel.lua`**

  ```lua
  -- InventoryPanel.lua
  -- Shows hold cargo (left) and warehouse cargo (right) side by side.

  local Constants = require(game.ReplicatedStorage.shared.Constants)

  local InventoryPanel = {}

  function InventoryPanel.new(parent)
    local frame = Instance.new("Frame")
    frame.Name = "InventoryPanel"
    frame.Size = UDim2.new(1, 0, 0, 120)
    frame.Position = UDim2.new(0, 0, 0, 35)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.BorderSizePixel = 1
    frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
    frame.Parent = parent

    -- Header
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 20)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BackgroundTransparency = 1
    header.Text = "HOLD                    WAREHOUSE"
    header.TextColor3 = Color3.fromRGB(100, 200, 100)  -- green header
    header.Font = Enum.Font.RobotoMono
    header.TextSize = 13
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = frame

    local holdLabels = {}
    local wareLabels = {}

    for i = 1, 4 do
      local holdLbl = Instance.new("TextLabel")
      holdLbl.Size = UDim2.new(0.5, -5, 0, 22)
      holdLbl.Position = UDim2.new(0, 5, 0, 18 + (i-1)*22)
      holdLbl.BackgroundTransparency = 1
      holdLbl.TextColor3 = Color3.fromRGB(200, 180, 80)
      holdLbl.Font = Enum.Font.RobotoMono
      holdLbl.TextSize = 13
      holdLbl.TextXAlignment = Enum.TextXAlignment.Left
      holdLbl.Parent = frame
      holdLabels[i] = holdLbl

      local wareLbl = Instance.new("TextLabel")
      wareLbl.Size = UDim2.new(0.5, -5, 0, 22)
      wareLbl.Position = UDim2.new(0.5, 0, 0, 18 + (i-1)*22)
      wareLbl.BackgroundTransparency = 1
      wareLbl.TextColor3 = Color3.fromRGB(200, 180, 80)
      wareLbl.Font = Enum.Font.RobotoMono
      wareLbl.TextSize = 13
      wareLbl.TextXAlignment = Enum.TextXAlignment.Left
      wareLbl.Parent = frame
      wareLabels[i] = wareLbl
    end

    local panel = {}

    function panel.update(state)
      for i = 1, 4 do
        holdLabels[i].Text = string.format("%-14s %4d", Constants.GOOD_NAMES[i], state.shipCargo[i])
        wareLabels[i].Text = string.format("%-14s %4d", Constants.GOOD_NAMES[i], state.warehouseCargo[i])
      end
    end

    return panel
  end

  return InventoryPanel
  ```

- [ ] **Step 3: Manual visual test in Studio**

  Play the game, call `ChooseStart` — confirm status strip shows correct cash/debt/bank.

- [ ] **Step 4: Commit**

  ```bash
  git add "src/StarterGui/TaipanGui/Panels/StatusStrip.lua"
  git add "src/StarterGui/TaipanGui/Panels/InventoryPanel.lua"
  git commit -m "feat: add StatusStrip and InventoryPanel UI panels"
  ```

---

### Task 10: UI — PricesPanel + BuySellPanel

**Files:**
- Create: `src/StarterGui/TaipanGui/Panels/PricesPanel.lua`
- Create: `src/StarterGui/TaipanGui/Panels/BuySellPanel.lua`

- [ ] **Step 1: Create `PricesPanel.lua`**

  ```lua
  -- PricesPanel.lua
  -- Shows current prices for all 4 goods.

  local Constants = require(game.ReplicatedStorage.shared.Constants)

  local PricesPanel = {}

  function PricesPanel.new(parent)
    local frame = Instance.new("Frame")
    frame.Name = "PricesPanel"
    frame.Size = UDim2.new(0.4, 0, 0, 120)
    frame.Position = UDim2.new(0, 0, 0, 160)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.BorderSizePixel = 1
    frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
    frame.Parent = parent

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 20)
    header.Position = UDim2.new(0, 5, 0, 0)
    header.BackgroundTransparency = 1
    header.Text = "PRICES"
    header.TextColor3 = Color3.fromRGB(100, 200, 100)
    header.Font = Enum.Font.RobotoMono
    header.TextSize = 13
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = frame

    local priceLabels = {}
    for i = 1, 4 do
      local lbl = Instance.new("TextLabel")
      lbl.Size = UDim2.new(1, -10, 0, 22)
      lbl.Position = UDim2.new(0, 5, 0, 18 + (i-1)*22)
      lbl.BackgroundTransparency = 1
      lbl.TextColor3 = Color3.fromRGB(200, 180, 80)
      lbl.Font = Enum.Font.RobotoMono
      lbl.TextSize = 13
      lbl.TextXAlignment = Enum.TextXAlignment.Left
      lbl.Parent = frame
      priceLabels[i] = lbl
    end

    local panel = {}

    function panel.update(state)
      for i = 1, 4 do
        priceLabels[i].Text = string.format(
          "%-14s $%d", Constants.GOOD_NAMES[i], state.currentPrices[i]
        )
      end
    end

    return panel
  end

  return PricesPanel
  ```

- [ ] **Step 2: Create `BuySellPanel.lua`**

  ```lua
  -- BuySellPanel.lua
  -- Good selector, amount input (with "A" = All shortcut), Buy and Sell buttons.
  -- Fires callbacks; the GameController wires callbacks to RemoteEvents.

  local Constants = require(game.ReplicatedStorage.shared.Constants)

  local BuySellPanel = {}

  function BuySellPanel.new(parent, onBuy, onSell, onEndTurn)
    -- onBuy(goodIndex, quantity), onSell(goodIndex, quantity), onEndTurn()

    local frame = Instance.new("Frame")
    frame.Name = "BuySellPanel"
    frame.Size = UDim2.new(1, 0, 0, 200)
    frame.Position = UDim2.new(0, 0, 0, 285)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.BorderSizePixel = 1
    frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
    frame.Parent = parent

    -- Good selector buttons (1-4)
    local selectedGood = 1
    local goodButtons = {}

    for i = 1, 4 do
      local btn = Instance.new("TextButton")
      btn.Size = UDim2.new(0.22, -4, 0, 28)
      btn.Position = UDim2.new((i-1)*0.25, 2, 0, 5)
      btn.BackgroundColor3 = i == 1 and Color3.fromRGB(60, 60, 20) or Color3.fromRGB(30, 30, 30)
      btn.BorderColor3 = Color3.fromRGB(100, 100, 40)
      btn.TextColor3 = Color3.fromRGB(200, 180, 80)
      btn.Font = Enum.Font.RobotoMono
      btn.TextSize = 11
      btn.Text = Constants.GOOD_NAMES[i]:sub(1, 7)
      btn.Parent = frame
      goodButtons[i] = btn

      btn.Activated:Connect(function()
        selectedGood = i
        for j = 1, 4 do
          goodButtons[j].BackgroundColor3 = j == i
            and Color3.fromRGB(60, 60, 20)
            or  Color3.fromRGB(30, 30, 30)
        end
      end)
    end

    -- Amount input
    local amountBox = Instance.new("TextBox")
    amountBox.Size = UDim2.new(0.5, -5, 0, 28)
    amountBox.Position = UDim2.new(0, 5, 0, 40)
    amountBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    amountBox.BorderColor3 = Color3.fromRGB(100, 100, 40)
    amountBox.TextColor3 = Color3.fromRGB(200, 180, 80)
    amountBox.Font = Enum.Font.RobotoMono
    amountBox.TextSize = 13
    amountBox.PlaceholderText = "Amount (A=All)"
    amountBox.Text = ""
    amountBox.Parent = frame

    -- "A" = All: handled in buy/sell callbacks
    local function parseAmount(state, isSell)
      local raw = amountBox.Text:upper()
      if raw == "A" then
        if isSell then
          return state and state.shipCargo[selectedGood] or 0
        else
          return state and state.holdSpace or 0
        end
      end
      return tonumber(raw) or 0
    end

    -- We hold a reference to the latest state for "All" shortcut
    local latestState = nil

    -- Buy button
    local buyBtn = Instance.new("TextButton")
    buyBtn.Size = UDim2.new(0.22, -4, 0, 36)
    buyBtn.Position = UDim2.new(0, 5, 0, 75)
    buyBtn.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
    buyBtn.BorderColor3 = Color3.fromRGB(40, 120, 40)
    buyBtn.TextColor3 = Color3.fromRGB(100, 255, 100)
    buyBtn.Font = Enum.Font.RobotoMono
    buyBtn.TextSize = 14
    buyBtn.Text = "BUY"
    buyBtn.Parent = frame

    buyBtn.Activated:Connect(function()
      local qty = parseAmount(latestState, false)
      if qty > 0 then
        onBuy(selectedGood, qty)
        amountBox.Text = ""
      end
    end)

    -- Sell button
    local sellBtn = Instance.new("TextButton")
    sellBtn.Size = UDim2.new(0.22, -4, 0, 36)
    sellBtn.Position = UDim2.new(0.25, 0, 0, 75)
    sellBtn.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
    sellBtn.BorderColor3 = Color3.fromRGB(120, 40, 40)
    sellBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
    sellBtn.Font = Enum.Font.RobotoMono
    sellBtn.TextSize = 14
    sellBtn.Text = "SELL"
    sellBtn.Parent = frame

    sellBtn.Activated:Connect(function()
      local qty = parseAmount(latestState, true)
      if qty > 0 then
        onSell(selectedGood, qty)
        amountBox.Text = ""
      end
    end)

    -- End Turn button
    local endTurnBtn = Instance.new("TextButton")
    endTurnBtn.Size = UDim2.new(0.3, -4, 0, 36)
    endTurnBtn.Position = UDim2.new(0.7, 0, 0, 75)
    endTurnBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 60)
    endTurnBtn.BorderColor3 = Color3.fromRGB(40, 40, 120)
    endTurnBtn.TextColor3 = Color3.fromRGB(100, 100, 255)
    endTurnBtn.Font = Enum.Font.RobotoMono
    endTurnBtn.TextSize = 12
    endTurnBtn.Text = "END TURN"
    endTurnBtn.Parent = frame

    endTurnBtn.Activated:Connect(onEndTurn)

    local panel = {}

    function panel.update(state)
      latestState = state
    end

    return panel
  end

  return BuySellPanel
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add "src/StarterGui/TaipanGui/Panels/PricesPanel.lua"
  git add "src/StarterGui/TaipanGui/Panels/BuySellPanel.lua"
  git commit -m "feat: add PricesPanel and BuySellPanel UI panels"
  ```

---

### Task 11: GameController (Client) + Integration

**Files:**
- Create: `src/StarterGui/TaipanGui/init.client.lua`

- [ ] **Step 1: Create `src/StarterGui/TaipanGui/init.client.lua`**

  ```lua
  -- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
  -- GameController: wires all UI panels to server RemoteEvents.
  -- Receives state snapshots from server and distributes to panels.

  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Players           = game:GetService("Players")

  local Remotes        = require(ReplicatedStorage.Remotes)
  local StatusStrip    = require(script.Panels.StatusStrip)
  local InventoryPanel = require(script.Panels.InventoryPanel)
  local PricesPanel    = require(script.Panels.PricesPanel)
  local BuySellPanel   = require(script.Panels.BuySellPanel)

  -- Build the ScreenGui
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "TaipanGui"
  screenGui.ResetOnSpawn = false
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.Parent = Players.LocalPlayer.PlayerGui

  local root = Instance.new("Frame")
  root.Size = UDim2.new(0, 480, 1, 0)
  root.Position = UDim2.new(0, 0, 0, 0)
  root.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  root.BorderSizePixel = 0
  root.Parent = screenGui

  -- Instantiate panels
  local statusStrip    = StatusStrip.new(root)
  local inventoryPanel = InventoryPanel.new(root)
  local pricesPanel    = PricesPanel.new(root)
  local buySellPanel   = BuySellPanel.new(
    root,
    function(goodIndex, qty) Remotes.BuyGoods:FireServer(goodIndex, qty) end,
    function(goodIndex, qty) Remotes.SellGoods:FireServer(goodIndex, qty) end,
    function() Remotes.EndTurn:FireServer() end
  )

  -- Receive state updates from server and refresh all panels
  Remotes.StateUpdate.OnClientEvent:Connect(function(state)
    statusStrip.update(state)
    inventoryPanel.update(state)
    pricesPanel.update(state)
    buySellPanel.update(state)
  end)

  -- Start the game (Phase 1: always cash start; start choice UI added later)
  Remotes.ChooseStart:FireServer("cash")

  -- Handle reconnection
  Remotes.RequestStateUpdate:FireServer()
  ```

- [ ] **Step 2: Manual integration test in Studio**

  - Play the game
  - Verify: status strip shows 400 cash / 5000 debt / 0 bank
  - Verify: inventory shows 0 for all goods (hold + warehouse)
  - Verify: prices panel shows 4 prices
  - Buy 1 Opium: confirm cash decreases, inventory updates
  - Sell 1 Opium: confirm cash increases, inventory updates
  - End Turn: confirm prices change
  - Type "A" in amount box, click Buy: confirm it buys max affordable quantity
  - Try to buy more than hold space allows: confirm it is rejected

- [ ] **Step 4: Commit**

  ```bash
  git add "src/StarterGui/TaipanGui/init.client.lua"
  git commit -m "feat: add GameController and wire all Phase 1 UI panels"
  ```

---

### Phase 1 Milestone Test

- [ ] Buy opium cheap at Hong Kong
- [ ] Click End Turn multiple times until a crash/boom price event visibly occurs
- [ ] Sell opium at profit and confirm cash increases correctly
- [ ] Fill hold completely (buy until "A" = 0 available)
- [ ] Attempt to buy 1 more unit — confirm rejected (hold full)
- [ ] Confirm amber-on-black terminal aesthetic is consistent across all panels

---

## Chunk 2: Phases 2–4 (Travel + Finance + Events)

*Full bite-sized plans for Phases 2–4 to be written as separate plan documents when Phase 1 is complete. Summaries below are sufficient to understand scope.*

### Phase 2: Travel + All Ports + Time

**New files:**
- `src/ReplicatedStorage/shared/TravelEngine.lua` — departure/arrival flow, D=0 guard, time advance
- `src/ServerScriptService/GameService.server.lua` — extend with `TravelTo` RemoteEvent handler
- `src/StarterGui/TaipanGui/Panels/PortPanel.lua` — port name display + destination selector
- `tests/TravelEngine.spec.lua`

**Key tasks:**
1. Add `TravelTo` RemoteEvent; server validates destination is different from current port
2. Implement time advance: TI++, MO++, year rollover, 0.5% bank interest, 10% debt compound
3. D=0 guard: skip interest/debt on first turn
4. January annual event: call `PriceEngine.applyAnnualDrift`, increment EC/ED
5. Menu options: non-HK shows Buy/Sell/Quit/Travel; HK adds Transfer + Visit Wu (greyed out)
6. Warehouse transfer UI: bidirectional per-good transfers, MW recalculation
7. Overload check: block departure when holdSpace < 0

### Phase 3: Financial System

**New files:**
- `src/ReplicatedStorage/shared/FinanceEngine.lua` — Wu visit flow, bank logic, Li Yuen logic
- `src/StarterGui/TaipanGui/Panels/WuPanel.lua` — Wu dialog UI
- `src/StarterGui/TaipanGui/Panels/BankPanel.lua` — bank deposit/withdraw UI
- `tests/FinanceEngine.spec.lua`

**Key tasks:**
1. Bank deposit/withdraw (HK only), "A" shortcut
2. Wu visit full flow: debt repayment skip condition (`DW=0 OR cash=0`), borrow up to `2×cash`, bankruptcy emergency loan with `BL%` counter
3. Wu warning at 10k debt (fires once only, `WN` flag)
4. Wu enforcers: `DW > 20000`, 1-in-5 after Wu visit
5. Li Yuen protection offer, cost formula for `TI<=12` and `TI>12`
6. Li Yuen protection lapse: `LI = LI AND FN_R(20)` each arrival
7. Li Yuen warning message: 3-in-4 chance when unprotected outside HK

### Phase 4: Random Events + Storm

**New files:**
- `src/ReplicatedStorage/shared/EventEngine.lua` — all random arrival events
- `tests/EventEngine.spec.lua`

**Key tasks:**
1. Opium seizure: check `shipCargo[1] > 0`, not HK, 1-in-18; confiscate, restore holdSpace, deduct fine
2. Cargo theft: check warehouse total > 0, 1-in-50; reduce each `warehouseCargo[J]` to `FN_R(J/1.8)`, update `warehouseUsed`
3. Cash robbery: `cash > 25000`, 1-in-20; lose `FN_R(cash/1.4)`
4. Storm: 1-in-10; sink check; blown off course 1-in-3 (not 2-in-3!)
5. Game over screen on ship sunk
6. Enforce arrival event ordering exactly per spec section 2.10

---

## Chunk 3: Phases 5–8 (Combat, Progression, Polish, Publish)

*Full bite-sized plans to be written as separate plan documents per phase.*

### Phase 5: Combat

**New files:**
- `src/ReplicatedStorage/shared/CombatEngine.lua` — all combat resolution logic
- `src/StarterGui/TaipanGui/Panels/CombatPanel.lua` — 10-slot enemy grid + action buttons
- `tests/CombatEngine.spec.lua`

**Key tasks:**
1. Pirate encounter triggers (generic BP check, Li Yuen 1-in-4/1-in-12)
2. AM% 10-slot grid initialisation and spawn-on-vacancy algorithm
3. Fight: random slot retry, `FN_R(30)+10` damage per gun
4. Run: momentum system (`OK`, `IK`), success check `FN_R(OK) > FN_R(SN)`, failed run partial escape, throw cargo auto-runs
5. Enemy fire: `DM += FN_R(ED*I*F1) + I/2`, gun destruction check
6. Li Yuen intervention 1-in-20
7. Post-combat chaining: victory/run → storm check, Li Yuen saved → Li Yuen re-check
8. Combat display: truncation for in-combat seaworthiness (line 5160), rounding for status screen (line 313)

### Phase 6: Ship Progression + Score + Retirement

**Key tasks:**
1. Ship repair: cost `BR` formula, `INT(W/BR + 0.5)` rounding, "All" = `BR*DM+1`
2. Ship upgrade offer 1-in-4, gun purchase offer 1-in-3
3. Score formula `INT((CA+BA-DW)/100/TI^1.1)` and rating thresholds
4. Retirement option `R` at 1M net worth in HK (`OK=16`)
5. Full game over screen for all endings

### Phase 7: Persistence + Polish

**Key tasks:**
1. DataStore save/load with `dataStoreRetry()` (3 attempts, exponential backoff)
2. `game:BindToClose()` failsafe alongside `Players.PlayerRemoving`
3. Save on port departure (dirty flag), respect rate limits
4. Schema `version` field for future migrations
5. Per-player state maps verified throughout (no global state)
6. Replace any RemoteFunction with RemoteEvent request/response
7. Mobile: all buttons ≥ 44dp, portrait layout test
8. Amber/green terminal colour palette pass
9. First-play onboarding text (Wu, Li Yuen, warehouse)
10. `TextService:FilterStringAsync` on all visible strings

### Phase 8: Publishing Prep

**Key tasks:**
1. Full formula audit against `BASIC_ANNOTATED.md`
2. Edge case checklist (guns start, DM fractional, D=0 guard, overload, BL% late-game, TI=13 Li Yuen formula switch)
3. Roblox content policy check on "Opium" — rename if required
4. Game icon, description, ≥3 thumbnails
5. Smoke-test live (not just Studio) on desktop + mobile
6. Publish

---

## Notes for Future Phase Plans

When writing the plan for each subsequent phase:
1. Re-read the phase's spec section before writing tasks
2. Verify every formula against `BASIC_ANNOTATED.md` (cite line numbers)
3. Write tests before implementation (TDD)
4. Each phase plan saves to `docs/superpowers/plans/2026-03-16-taipan-phase-N.md`
