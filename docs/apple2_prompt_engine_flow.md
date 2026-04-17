# Apple II PromptEngine Flow Reference

This document catalogs every scene in `PromptEngine.luau`, how they connect via `localScene` transitions, and how the broader Apple2Interface orchestrates them.

---

## Architecture Overview

```
Apple2Interface.luau
  ├── Terminal.luau        (24-row character grid display)
  ├── KeyInput.luau        (keyboard/touch input handling)
  ├── PromptEngine.luau    (pure logic: state + localScene -> rows + promptDef)
  └── GlitchLayer.luau     (CRT visual effects)
```

**Data flow:**
1. Server sends `StateUpdate` -> `adapter.update(state)` is called
2. `Apple2Interface.render()` calls `PromptEngine.processState(state, localScene, actions, localSceneCb)`
3. PromptEngine returns `{rows}` (display) and `promptDef` (input config)
4. Terminal renders the rows; KeyInput binds to the promptDef
5. User input triggers `promptDef.onKey/onType` which either:
   - Calls a `localSceneCb(newScene)` to re-render locally (no server round-trip)
   - Calls an `actions.*` method which fires a remote to the server

### Scene Transition Types

- **Local transitions** (`localSceneCb("scene_name")`): Immediate re-render. Used for sub-menus and multi-step dialogs.
- **Server transitions** (`actions.*()`): Fires a remote event. Server processes it, sends `StateUpdate`, which triggers `adapter.update()` and a fresh render.
- **Auto-advance** (`_autoAdvance = {seconds, nextScene}`): Timer-driven transition, cancelled if any input or re-render occurs first.
- **Notification queue**: `pendingMessages` from state are queued and displayed sequentially on rows 17-24 before the main scene renders.

### Server-Driven Scene Overrides

When `adapter.update()` detects any of these, `localScene` is reset to `nil`:

| Condition | Server-driven scene |
|---|---|
| `state.gameOver == true` | Game over / retirement |
| `state.combat ~= nil` | Combat |
| `state.liYuenPending == true` (HK) | Li Yuen demand |
| `state.repairPending == true` (HK) | Ship repair offer |
| `state.wuPending == true` (HK) | Elder Brother Wu question |
| `state.shipOffer.upgradeOffer` (HK) | Ship upgrade offer |
| `state.shipOffer.gunOffer` (HK) | Gun purchase offer |

---

## Input Types

Each scene returns a `promptDef` with one of these types:

| Type | Behavior | KeyInput handling |
|---|---|---|
| `key` | Single keypress, immediate action. Optional `anyKey=true` accepts anything. | Keypress fires `onKey(char)` immediately |
| `singlechar` | Type one char from valid set, then press Enter to confirm. Backspace clears. | Char is stored, Enter submits via `onKey(stored)` |
| `type` | Free-text entry up to `maxLength` chars, Enter submits. | Full text editing with cursor, Enter submits via `onType(text)` |
| `numeric` | Digits only, up to `maxDigits`. Left arrow = delete last. Enter submits. | Only digit keys accepted, Enter submits via `onType(text)` |

All types support `_inputRow` and `_buildInputRow(displayStr)` for in-place cursor rendering on a specific terminal row.

---

## Display Structure

### Status Screen (Rows 1-16) - `buildPortRows(state)`

Used by most scenes as the upper portion of the display.

```
Row  1: Firm: TAIPAN, Hong Kong          (centered, firm name in ThickFont)
Row  2: ┌──────────────────────────┐     (box top, 28 wide)
Row  3: │Hong Kong Warehouse      │    Date
Row  4: │Spices     0    In use:  │ 15 Jan 1860
Row  5: │Silk       0         0   │
Row  6: │Arms       0    Vacant:  │  Location
Row  7: │General    0     10000   │  Hong Kong
Row  8: ├──────────────────────────┤     (divider)
Row  9: │Hold 60       Guns 0    │    Debt
Row 10: │   Spices  0             │      0
Row 11: │   Silk    0             │
Row 12: │   Arms    0             │ Ship status
Row 13: │   General 0             │ Perfect:100
Row 14: └──────────────────────────┘     (box bottom)
Row 15: Cash:0               Bank:0
Row 16: ________________________________________
```

### Lower Section (Rows 17-24)

Content varies by scene. Typically:
- Row 17: "Comprador's Report" header
- Row 18: blank
- Rows 19-24: scene-specific prompts and messages

---

## Scene Catalog

### Priority Order in `processState()`

`processState()` evaluates conditions top-to-bottom. The first match wins:

```
1. gameOver + retired + localScene=="final_status" -> sceneFinalStatus
2. gameOver + retired                              -> sceneMillionaire
3. gameOver (other reasons)                        -> sceneGameOver
4. combat + localScene=="combat_throw_good"        -> sceneCombatThrowGood
5. combat + localScene matches combat_throw_amt_N  -> sceneCombatThrowAmount(N)
6. combat                                          -> sceneCombatLayout
7. HK + liYuenPending                              -> sceneLiYuenDemand
8. HK + repairPending + localScene variants        -> sceneRepair / sceneRepairAmount / sceneRepairAmountErr
9. HK + wuPending                                  -> sceneWuQuestion
10. HK + inWuSession + localScene variants          -> sceneWuRepay / sceneWuBorrow / sceneWuBorrowErr
11. HK + upgradeOffer                               -> sceneUpgrade
12. HK + gunOffer                                   -> sceneGun
13. localScene == "bank"                            -> sceneBank
14. localScene == "bank_withdraw"                   -> sceneWithdraw
15. localScene == "bank_deposit_err"                -> sceneBankDepositErr
16. localScene == "bank_withdraw_err"               -> sceneBankWithdrawErr
17. localScene == "warehouse"                       -> sceneWarehouseNoCargo or sceneWarehouseStep(1)
18. localScene matches wh_wait_N                    -> neutral holding screen (no prompt)
19. localScene matches wh_step_N                    -> sceneWarehouseStep(N)
20. localScene matches wh_err_N                     -> sceneWarehouseStepErr(N)
21. localScene == "buy"                             -> sceneBuySell(isBuy=true)
22. localScene == "sell"                            -> sceneBuySell(isBuy=false)
23. localScene matches buy_good_N                   -> sceneBuySellAmount(N, isBuy=true)
24. localScene matches sell_good_N                  -> sceneBuySellAmount(N, isBuy=false)
25. localScene == "travel"                          -> sceneTravel
26. localScene == "already_here"                    -> sceneAlreadyHere
27. localScene == "traveling"                       -> neutral holding screen (no prompt)
28. localScene == "settings"                        -> sceneSettings
29. localScene == "quit_confirm"                    -> sceneQuitConfirm
30. startChoice==nil, turnsElapsed==1, dest==0:
    - localScene == "start_choice"                  -> sceneStartChoice
    - else                                          -> sceneFirmName
31. (default)                                       -> sceneAtPort
```

---

## Scene Details

### Game Start Scenes

#### `sceneFirmName`
- **Display**: Boxed prompt (rows 8-17): "Taipan, What will you name your Firm:"
- **Input**: `type`, maxLength=22, cursor on row 14
- **Transitions**:
  - Enter -> `actions.setFirmName(text)` + localScene `"start_choice"`

#### `sceneStartChoice`
- **Display**: Rows 8-21: "1) With cash (and a debt)" or "2) With five guns and no cash"
- **Input**: `singlechar`, keys=["1","2"], cursor on row 21
- **Transitions**:
  - "1" -> `actions.chooseStart("cash")` (server sends StateUpdate)
  - "2" -> `actions.chooseStart("guns")` (server sends StateUpdate)

---

### Main Port Scene

#### `sceneAtPort`
- **Display**: Status screen (rows 1-16) + prices (rows 19-21) + action menu (rows 23-24)
- **Input**: `singlechar`
- **Valid keys vary by location**:
  - All ports: B (Buy), S (Sell), Q (Quit trading), P (Settings, unlisted)
  - Hong Kong adds: V (Visit bank), T (Transfer cargo)
  - Hong Kong + net worth >= $1M adds: R (Retire)
- **Transitions**:
  - B -> localScene `"buy"`
  - S -> localScene `"sell"`
  - V -> localScene `"bank"`
  - T -> localScene `"warehouse"`
  - Q -> localScene `"travel"`
  - R -> `actions.retire()` (server-driven)
  - P -> localScene `"settings"`

---

### Buy/Sell Flow

#### `sceneBuySell` (localScene: `"buy"` or `"sell"`)
- **Display**: Status + prices + "What do you wish me to buy/sell, Taipan?"
- **Input**: `singlechar`, keys=["P","S","A","G"]
- **Good key map**: P=sPices(1), S=Silk(2), A=Arms(3), G=General(4)
- **Transitions**:
  - P/S/A/G -> localScene `"buy_good_N"` or `"sell_good_N"` (N=1-4)

#### `sceneBuySellAmount` (localScene: `"buy_good_N"` or `"sell_good_N"`)
- **Display**: Status + prices + "How much [Good] shall I buy/sell, Taipan?"
  - Buy mode also shows "You can afford [N]" in inverted text (rows 22, 24)
- **Input**: `numeric`, maxDigits=9, cursor on row 23
- **Transitions**:
  - 0 or empty -> localScene `nil` (back to port)
  - Buy: qty * price > cash -> localScene `"buy_good_N"` (re-ask, same good)
  - Buy: valid -> `actions.buyGoods(goodIdx, qty)` + localScene `nil`
  - Sell: qty > cargo -> localScene `"sell_good_N"` (re-ask, same good)
  - Sell: valid -> `actions.sellGoods(goodIdx, qty)` + localScene `nil`

---

### Travel Flow

#### `sceneTravel` (localScene: `"travel"`)
- **Display**: Status + port list 1-7
- **Input**: `singlechar`, keys=["1"-"7"]
- **Transitions**:
  - Same port as current -> localScene `"already_here"`
  - Different port -> `actions.travelTo(dest)` + localScene `"traveling"`

#### `sceneAlreadyHere` (localScene: `"already_here"`)
- **Display**: Status + port list + "You're already here, Taipan."
- **Input**: `key`, anyKey=true
- **Auto-advance**: 5 seconds -> localScene `"travel"`
- **Transitions**: Any key -> localScene `"travel"`

#### Traveling (localScene: `"traveling"`)
- **Display**: Status rows only (rows 17-24 blank). No prompt.
- **Behavior**: Inert holding screen. Server `StateUpdate` arrives and resets `localScene=nil`.

---

### Bank Flow (Hong Kong only)

#### `sceneBank` (localScene: `"bank"`)
- **Display**: Status + "How much will you deposit?"
- **Input**: `numeric`, maxDigits=9, cursor on row 19
- **Transitions**:
  - amt > cash -> localScene `"bank_deposit_err"`
  - amt > 0 -> `actions.bankDeposit(amt)` + localScene `"bank_withdraw"`
  - 0 or empty -> localScene `"bank_withdraw"`

#### `sceneWithdraw` (localScene: `"bank_withdraw"`)
- **Display**: Status + "How much will you withdraw?"
- **Input**: `numeric`, maxDigits=9, cursor on row 19
- **Transitions**:
  - amt > bankBalance -> localScene `"bank_withdraw_err"`
  - amt > 0 -> `actions.bankWithdraw(amt)` + localScene `nil` (back to port)
  - 0 or empty -> localScene `nil`

#### `sceneBankDepositErr` (localScene: `"bank_deposit_err"`)
- **Display**: Status + "Taipan, you only have [cash] in cash."
- **Input**: `key`, anyKey=true
- **Auto-advance**: 5 seconds -> localScene `"bank"`
- **Transitions**: Any key -> localScene `"bank"`

#### `sceneBankWithdrawErr` (localScene: `"bank_withdraw_err"`)
- **Display**: Status + "Taipan, you only have [balance] in the bank."
- **Input**: `key`, anyKey=true
- **Auto-advance**: 5 seconds -> localScene `"bank_withdraw"`
- **Transitions**: Any key -> localScene `"bank_withdraw"`

---

### Warehouse Transfer Flow (Hong Kong only)

Transfers iterate through all 8 possible moves (4 goods x 2 directions) in order, skipping any with 0 available:

```
Step 1: Spices ship->warehouse     Step 2: Spices warehouse->ship
Step 3: Silk ship->warehouse       Step 4: Silk warehouse->ship
Step 5: Arms ship->warehouse       Step 6: Arms warehouse->ship
Step 7: General ship->warehouse    Step 8: General warehouse->ship
```

#### Entry (localScene: `"warehouse"`)
- Checks if any cargo exists in ship or warehouse
- No cargo -> `sceneWarehouseNoCargo` (anyKey/5s -> `nil`)
- Has cargo -> `sceneWarehouseStep(startN=1)`

#### `sceneWarehouseStep(startN)` (localScene: `"wh_step_N"`)
- **Logic**: `findNextStep(state, startN)` scans from step N for next non-zero transfer
- **If exhausted**: Neutral holding screen with `_autoAdvance={0, nil}` (immediate back to port)
- **Display**: Status + "How much [Good] shall I move to the warehouse/aboard ship, Taipan?"
- **Input**: `numeric`, maxDigits=9, cursor on row 20
- **Transitions**:
  - 0 or empty -> localScene `"wh_step_N+1"` (skip to next step)
  - qty > available -> localScene `"wh_err_N"` (error)
  - Valid, to warehouse -> `actions.transferTo(good, qty)` + localScene `"wh_wait_N"`
  - Valid, from warehouse -> `actions.transferFrom(good, qty)` + localScene `"wh_wait_N"`

#### `"wh_wait_N"` (waiting for server)
- **Display**: Status + blank rows 18-24. No prompt.
- **Behavior**: When `adapter.update()` receives the next `StateUpdate`, it detects `wh_wait_N` and advances to `"wh_step_N+1"` with fresh cargo counts.

#### `sceneWarehouseStepErr(stepN)` (localScene: `"wh_err_N"`)
- **Display**: Status + transfer question + "You only have [avail], Taipan."
- **Input**: `key`, anyKey=true
- **Auto-advance**: 5 seconds -> localScene `"wh_step_N"` (re-ask same step)
- **Transitions**: Any key -> localScene `"wh_step_N"`

#### `sceneWarehouseNoCargo`
- **Display**: Status + prices + "You have no cargo, Taipan."
- **Input**: `key`, anyKey=true
- **Auto-advance**: 5 seconds -> localScene `nil`
- **Transitions**: Any key -> localScene `nil`

---

### Hong Kong Arrival Sequence

When arriving at Hong Kong, the server sets various flags that are checked in priority order by `processState()`. The arrival sequence plays out as:

```
1. Li Yuen demand (if liYuenPending)
2. Repair offer (if repairPending and damage > 0)
3. Wu question (if wuPending and debt > 0 or borrowing available)
4. Wu session (repay then borrow, if inWuSession)
5. Ship upgrade offer (if shipOffer.upgradeOffer)
6. Gun offer (if shipOffer.gunOffer)
7. Main port menu (sceneAtPort)
```

Each step is server-driven: the server clears one flag and sets the next, sending StateUpdates that cascade through the sequence.

#### `sceneLiYuenDemand`
- **Display**: Wu layout + "Li Yuen asks $[cost] in donation to the temple of Tin Hau..."
- **Input**: `singlechar`, keys=["Y","N"], cursor on row 21
- **Transitions**:
  - Y -> `actions.buyLiYuen()` (server clears liYuenPending)
  - N -> `actions.declineLiYuen()` (server clears liYuenPending)

#### `sceneRepair`
- **Display**: Status + McHenry's dialog about ship damage
- **Input**: `singlechar`, keys=["Y","N"], cursor on row 22
- **Transitions**:
  - Y -> localScene `"repair_amount"`
  - N -> `actions.declineRepair()` (server clears repairPending)

#### `sceneRepairAmount` (localScene: `"repair_amount"`)
- **Display**: Status + damage %, max repair cost, partial repair option
- **Input**: `numeric`, maxDigits=9, cursor on row 23
- **Transitions**:
  - amt > cash -> localScene `"repair_amount_err"`
  - amt > 0 -> `actions.shipRepair(amt)` (server clears repairPending)
  - 0 or empty -> `actions.declineRepair()`

#### `sceneRepairAmountErr` (localScene: `"repair_amount_err"`)
- **Display**: Status + "Taipan, you do not have enough cash!!"
- **Input**: `key`, anyKey=true
- **Auto-advance**: 5 seconds -> localScene `"repair_amount"`
- **Transitions**: Any key -> localScene `"repair_amount"`

#### `sceneWuQuestion`
- **Display**: Wu layout + "Do you have business with Elder Brother Wu, the moneylender?"
- **Input**: `singlechar`, keys=["Y","N"], cursor on row 20
- **Transitions**:
  - Y -> `actions.confirmWu()` (server sets inWuSession=true)
  - N -> `actions.declineWu()` (server clears wuPending)

#### `sceneWuRepay` (localScene: `"wu_repay"` or default when debt > 0)
- **Display**: Wu layout + "How much do you wish to repay him?"
- **Input**: `numeric`, maxDigits=9, cursor on row 20
- **Transitions**:
  - amt > 0 -> `actions.wuRepay(amt)` + localScene `"wu_borrow"`
  - 0 or empty -> localScene `"wu_borrow"`

#### `sceneWuBorrow` (localScene: `"wu_borrow"`)
- **Display**: Wu layout + "How much do you wish to borrow?"
- **Input**: `numeric`, maxDigits=9, cursor on row 20
- **Transitions**:
  - amt > 2 * cash -> localScene `"wu_borrow_err"`
  - amt > 0, valid -> `actions.wuBorrow(amt)` + `actions.leaveWu()` + localScene `nil`
  - 0 or empty -> `actions.leaveWu()` + localScene `nil`

#### `sceneWuBorrowErr` (localScene: `"wu_borrow_err"`)
- **Display**: Wu layout + "He won't loan you so much, Taipan!"
- **Input**: `key`, anyKey=true
- **Auto-advance**: 5 seconds -> localScene `"wu_borrow"`
- **Transitions**: Any key -> localScene `"wu_borrow"`

#### `sceneUpgrade`
- **Display**: Status + "Do you wish to trade in your [condition] ship for one with 50 more capacity..."
- **Input**: `singlechar`, keys=["Y","N"], cursor on row 21
- **Transitions**:
  - Y -> `actions.acceptUpgrade()` (server clears upgradeOffer)
  - N -> `actions.declineUpgrade()` (server clears upgradeOffer)

#### `sceneGun`
- **Display**: Status + "Do you wish to buy a ship's gun for [cost]?"
- **Input**: `singlechar`, keys=["Y","N"], cursor on row 20
- **Transitions**:
  - Y -> `actions.acceptGun()` (server clears gunOffer)
  - N -> `actions.declineGun()` (server clears gunOffer)

---

### Combat Scenes

#### `sceneCombatLayout`
- **Display** (rows 1-5):
  - Row 1: "[N] ships attacking, Taipan!" + "| We have"
  - Row 2: "Your orders are to:" + "|  N guns"
  - Row 3: (spacer) + box bottom corner
  - Row 4: "Current seaworthiness: [label] ([pct]%)" (inverted if < 40%)
  - Row 5: "Ships: [##########]" (# = alive, . = empty)
  - Rows 6-24: blank
- **Input**: `key`, keys=["F","R","T"]
- **Transitions**:
  - F -> `actions.combatFight()` (server resolves fight round, sends StateUpdate)
  - R -> `actions.combatRun()` (server resolves run attempt)
  - T -> localScene `"combat_throw_good"`

#### `sceneCombatThrowGood` (localScene: `"combat_throw_good"`)
- **Display**: "Throw which cargo overboard?" + list of goods with quantities + "[C] Cancel"
- **Input**: `key`, keys=["1","2","3","4","P","S","A","G","C"]
- **Transitions**:
  - C -> localScene `nil` (back to combat layout)
  - Good key with 0 quantity -> localScene `"combat_throw_good"` (re-ask)
  - Good key with cargo -> localScene `"combat_throw_amt_N"`

#### `sceneCombatThrowAmount` (localScene: `"combat_throw_amt_N"`)
- **Display**: "Throw [Good] (max [qty], A=all):"
- **Input**: `type`, maxLength=8
- **Transitions**:
  - Empty -> localScene `"combat_throw_good"` (back to good selection)
  - "A" -> `actions.combatThrow(goodIdx, maxQty)` + localScene `nil`
  - Valid qty -> `actions.combatThrow(goodIdx, qty)` + localScene `nil`
  - qty > max -> error message "Only [N] available"
  - 0 -> localScene `"combat_throw_good"`

---

### Game Over / Retirement Scenes

#### `sceneGameOver` (non-retirement)
- **Display**: "GAME OVER" + reason text + "(R)estart"
- **Input**: `key`, keys=["R"]
- **Transitions**: R -> `actions.restartGame()`

#### `sceneMillionaire` (retirement step 1)
- **Display**: Large inverted "Y o u ' r e   a   M I L L I O N A I R E !" (rows 19-24)
- **Input**: `key`, anyKey=true
- **Transitions**: Any key -> localScene `"final_status"`

#### `sceneFinalStatus` (retirement step 2, localScene: `"final_status"`)
- **Display** (full 24 rows):
  - Row 1: "Your final status:"
  - Row 3: Net cash
  - Row 5: Ship size + guns
  - Row 7: Trading duration (years + months)
  - Row 9: Score (inverted)
  - Row 13-20: Rating table (achieved rating inverted)
  - Row 22: "Play again? (Y/N)"
- **Input**: `key`, keys=["Y","N"]
- **Transitions**:
  - Y -> `actions.restartGame()`
  - N -> `actions.quitGame()`

---

### Utility Scenes

#### `sceneSettings` (localScene: `"settings"`)
- **Display**: "Switch interface?" + [M] Modern, [A] Apple II, [C] Cancel
- **Input**: `key`, keys=["M","A","C"]
- **Transitions**:
  - M (if not already modern) -> `actions.setUIMode("modern")` (destroys Apple2, switches to Modern)
  - A (if already apple2) -> localScene `nil` (no change)
  - C -> localScene `nil`

#### `sceneQuitConfirm` (localScene: `"quit_confirm"`)
- **Display**: "Quit game? (Y/N)"
- **Input**: `key`, keys=["Y","N"]
- **Transitions**:
  - Y -> `actions.quitGame()`
  - N -> localScene `nil`

---

## Notification System

Notifications are **not handled by PromptEngine**. They flow through a separate pipeline:

1. Server builds entries via `makeCaptainNotif(lines, duration)` or `makeCompradorNotif(lines, duration)` in `GameService.server.luau`
2. Entries are attached to `state.pendingMessages` as `{ rows = {[17]...[24]}, duration = N }`
3. `adapter.update()` drains `pendingMessages` into `notifQueue`
4. `playNextNotif()` writes notification rows to rows 17-24 and sets an anyKey prompt
5. Each notification can be dismissed by keypress or auto-advances after its `duration`
6. When the queue empties, `localScene` is reset to `nil` and the main scene renders

**Note:** `Remotes.Notify` (the text-only channel used by Modern UI) is explicitly ignored by the Apple2 adapter (`Apple2Interface.luau` line 186-188). Only `pendingMessages` entries are displayed.

### Report Types

- **Captain's Report** — header on row 17, used for combat narration and storm events
- **Comprador's Report** — header on row 17, used for financial events, arrival info, and trade events

### Combat Notifications (Captain's Report)

| Event | Message | Duration |
|---|---|---|
| Hostile encounter | "Taipan!! [N] hostile ships approaching!!" | 2.5s |
| Li Yuen protection active | "Good joss!! Li Yuen's fleet let us be!!" | 2.5s |
| Li Yuen encounter | "Taipan!! Li Yuen's fleet!! [N] ships!!" | 2.5s |
| No guns to fight | "We have no guns, Taipan!!" | 1s |
| Firing on enemies | "We're firing on 'em, Taipan!" | 1s |
| Sunk enemies | "Sunk [N] of the buggers, Taipan!" | 1s |
| Hit but no sink | "Hit 'em, but didn't sink 'em, Taipan!" | 1s |
| Enemy ships flee | "[N] ran away, Taipan!" | 1s |
| Victory + booty | "We got 'em all, Taipan!!" / "We've captured some booty worth $[N]!!" | 3s |
| Run — escaped | "We got away from 'em, Taipan!!" | 2.5s |
| Run — failed | "Can't lose 'em!!" | 1s |
| Run — partial escape | "But we escaped from [N] of 'em, Taipan!" | 1s |
| Throw — nothing | "There's nothing there, Taipan!" | 1s |
| Throw — success | "Threw [N] overboard. Let's hope we lose 'em, Taipan!" | 1s |
| Enemy hits ship | "We've been hit, Taipan!!" | 1s |
| Enemy destroys gun | "The buggers hit a gun, Taipan!!" | 1s |
| Ship sinks (combat) | "The buggers got us, Taipan!!!" | 1s |
| Li Yuen intervention | "Li Yuen's fleet drove them off!!" | 2.5s |

### Storm Notifications (Captain's Report)

| Event | Message | Duration |
|---|---|---|
| Storm encountered | "Storm, Taipan!!" | 5s |
| Severe storm | "I think we're going down!!" | 5s |
| Ship sinks (storm) | "We're going down, Taipan!!" | 5s |
| Storm survived | "We made it!!" | 5s |
| Blown off course | "We've been blown off course to [PORT]!" | 5s |

### Sea/Arrival Events (Comprador's Report)

| Event | Message | Duration |
|---|---|---|
| Arrive at port | "Arriving at [PORT]..." | 2.5s |
| Price change | "Taipan!! The price of [GOOD] has [risen/dropped] to [N]!!" | 5s |
| Li Yuen warning | "Li Yuen wishes you to reconsider!..." | 5s |

### Wu/Finance Notifications (Comprador's Report)

| Event | Message | Duration |
|---|---|---|
| Wu escort scene 1 | "Elder Brother Wu has sent [N] braves to escort you..." | 5s |
| Wu escort scene 2 | "Elder Brother Wu reminds you of the Confucian ideal..." | 10s |
| Wu escort scene 3 | "He is reminded of a fabled barbarian..." | 10s |

---

## Helper Functions

| Function | Purpose |
|---|---|
| `pad(s, width)` | Right-pad string with spaces |
| `lpad(s, width)` | Left-pad string with spaces |
| `fmt(n)` | Format number with $ prefix and commas (e.g. "$1,234") |
| `fmtBig(n)` | Format number without $: commas under 1M, "X.XX Suffix" above |
| `centerStr(s, width)` | Center a string in a fixed-width field |
| `centerSeg(width, segs)` | Center a list of segments (rich text) in a field |
| `shipStatus(state)` | Returns "Label:pct" string and inverted flag |
| `buildPortRows(state)` | Builds the 16-row status screen |
| `sceneWuLayout(state, bodyLines)` | Status screen + "Comprador's Report" + body lines starting at row 19 |
| `buildBankRows(state)` | Status screen + "Comprador's Report" + blank rows 19-24 |

---

## Complete Scene Graph

```
sceneFirmName
  └─> sceneStartChoice
       ├─ "1" ──> [SERVER: StateUpdate] ──> sceneAtPort
       └─ "2" ──> [SERVER: StateUpdate] ──> sceneAtPort

sceneAtPort
  ├─ B ──> sceneBuySell(buy)
  │         └─ P/S/A/G ──> sceneBuySellAmount(buy)
  │                          ├─ valid ──> [SERVER] ──> sceneAtPort
  │                          ├─ over budget ──> sceneBuySellAmount (re-ask)
  │                          └─ 0/empty ──> sceneAtPort
  ├─ S ──> sceneBuySell(sell)
  │         └─ P/S/A/G ──> sceneBuySellAmount(sell)
  │                          ├─ valid ──> [SERVER] ──> sceneAtPort
  │                          ├─ over cargo ──> sceneBuySellAmount (re-ask)
  │                          └─ 0/empty ──> sceneAtPort
  ├─ V ──> sceneBank
  │         ├─ deposit ──> sceneWithdraw
  │         │               ├─ withdraw ──> [SERVER] ──> sceneAtPort
  │         │               ├─ over balance ──> sceneBankWithdrawErr ──> sceneWithdraw
  │         │               └─ 0/empty ──> sceneAtPort
  │         └─ over cash ──> sceneBankDepositErr ──> sceneBank
  ├─ T ──> sceneWarehouseStep(1)
  │         ├─ transfer ──> [SERVER: wh_wait] ──> sceneWarehouseStep(N+1) ──> ...
  │         ├─ 0/empty ──> sceneWarehouseStep(N+1)
  │         ├─ over avail ──> sceneWarehouseStepErr ──> sceneWarehouseStep(N)
  │         └─ all exhausted ──> sceneAtPort
  ├─ Q ──> sceneTravel
  │         ├─ same port ──> sceneAlreadyHere ──> sceneTravel
  │         └─ diff port ──> [SERVER: traveling] ──> ...arrival sequence...
  ├─ R ──> [SERVER: retire] ──> sceneMillionaire ──> sceneFinalStatus
  └─ P ──> sceneSettings ──> sceneAtPort (or mode switch)

[ARRIVAL AT HONG KONG]
  sceneLiYuenDemand (if pending)
    └─> [SERVER] ──>
  sceneRepair (if pending)
    └─ Y ──> sceneRepairAmount
    │          ├─ over cash ──> sceneRepairAmountErr ──> sceneRepairAmount
    │          └─ valid/0 ──> [SERVER] ──>
    └─ N ──> [SERVER] ──>
  sceneWuQuestion (if pending)
    └─ Y ──> [SERVER: inWuSession] ──>
    │   sceneWuRepay (if debt > 0)
    │     └─> sceneWuBorrow
    │           ├─ over limit ──> sceneWuBorrowErr ──> sceneWuBorrow
    │           └─ valid/0 ──> [SERVER: leaveWu] ──>
    └─ N ──> [SERVER] ──>
  sceneUpgrade (if offered)
    └─> [SERVER] ──>
  sceneGun (if offered)
    └─> [SERVER] ──>
  sceneAtPort

[COMBAT]
  sceneCombatLayout
    ├─ F ──> [SERVER: fight round] ──> sceneCombatLayout (or combat ends)
    ├─ R ──> [SERVER: run attempt] ──> sceneCombatLayout (or escape)
    └─ T ──> sceneCombatThrowGood
              ├─ C ──> sceneCombatLayout
              └─ good ──> sceneCombatThrowAmount
                           ├─ valid ──> [SERVER] ──> sceneCombatLayout
                           └─ empty/0 ──> sceneCombatThrowGood

[GAME OVER]
  sceneGameOver (sunk/quit)
    └─ R ──> [SERVER: restartGame]
  sceneMillionaire (retired)
    └─ anykey ──> sceneFinalStatus
                   ├─ Y ──> [SERVER: restartGame]
                   └─ N ──> [SERVER: quitGame]
```
