# Apple II Input Beeps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play the `beep` sound on rejected keyboard input across the Apple II interface, faithful to the original game's input-routine beep and its buy/sell over-limit beep.

**Architecture:** Two layers, both using the already-registered `beep` sound. Layer 1 lives in `KeyInput.luau` (the single point all keyboard input flows through) and beeps on character-level rejection for each prompt type, gated by a per-prompt `noBeep` flag. Layer 2 lives in `PromptEngine.luau`'s `sceneBuySellAmount` and beeps on the submit-time over-limit rejection via the existing `playSound` callback.

**Tech Stack:** Roblox Luau; Azul file sync; `ReplicatedStorage.SoundPlayer`.

## Global Constraints

- **Apple II interface only.** Do not touch the Modern interface or any `shared/` logic module.
- **Sound name is `beep`** — already registered in `sync/ReplicatedStorage/Sounds.luau` (`rbxassetid://110935510356277`). No new assets.
- **`SoundPlayer.play` blocks** (polls until the sound ends / a deadline). Every call must be wrapped in `task.spawn`.
- **Desktop only.** Only the physical-keyboard (`UserInputService.InputBegan`) paths change. Do **not** modify any mobile path (virtual buttons / hidden `TextBox`): invalid input is essentially impossible there.
- **Modifier-only keys never beep:** `LeftShift, RightShift, LeftControl, RightControl, LeftAlt, RightAlt, CapsLock, LeftMeta, RightMeta, Unknown`.
- **Two `noBeep` scenes only:** `sceneCombatLayout` (combat fight/throw/run loop) and `sceneFirmName`. Every other prompt beeps, including the two combat throw sub-prompts.
- **Editing models unchanged** except the one deliberate deviation (Decision 1): in `numeric`, Backspace now mirrors Left-arrow.

## Testing Approach (read before starting)

These two files (`KeyInput.luau`, `PromptEngine.luau`) are client-side UI input glue that depends on Roblox services (`UserInputService`, `RunService`) and prompt callbacks. The project has **no unit-test harness for client modules** — TestEZ specs cover only the pure `shared/` logic engines, none of which change here. This matches the precedent in `2026-06-25-local-event-sounds-design.md` ("No unit test").

Therefore each task's verification is **(a)** a code-level read-back confirming the exact edit, and **(b)** deferred audio verification, consolidated into the final manual playtest task. Per project guidance ([[feedback_audio_verification]]), **the user** confirms the beep audibly plays — screen capture is silent, so an implementing agent cannot self-verify audio. Do not attempt MCP playtests for audio confirmation; leave that to Task 8 / the user.

---

### Task 1: KeyInput beep infrastructure + `key`-type beep

Adds the `SoundPlayer` require, the modifier-key set, the `beep()` helper, and wires the beep into the `key` prompt type (immediate-fire menus, e.g. port-sail, Wu menu, combat main loop).

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`

**Interfaces:**
- Produces: a module-level `beep(promptDef)` helper — plays `beep` via `task.spawn(SoundPlayer.play("beep"))` unless `promptDef.noBeep` is truthy. Consumed by Tasks 2–4.
- Produces: a module-level `MODIFIER_KEYS` set (`KeyCode.Name` → `true`). Consumed by Tasks 3–4.

- [ ] **Step 1: Add the `ReplicatedStorage` + `SoundPlayer` requires**

In the services block at the top (currently lines 5–7), add `ReplicatedStorage` and the `SoundPlayer` require. After:

```lua
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundPlayer = require(ReplicatedStorage.SoundPlayer)
```

- [ ] **Step 2: Add `MODIFIER_KEYS` and the `beep()` helper**

Immediately after `local KeyInput = {}` (currently line 61), add:

```lua
-- Bare modifier presses produce no character and must never beep.
local MODIFIER_KEYS = {
  LeftShift = true, RightShift = true,
  LeftControl = true, RightControl = true,
  LeftAlt = true, RightAlt = true,
  CapsLock = true, LeftMeta = true, RightMeta = true,
  Unknown = true,
}

-- Play the Apple II input-rejection beep, unless this prompt opts out.
local function beep(promptDef)
  if promptDef and promptDef.noBeep then return end
  task.spawn(function() SoundPlayer.play("beep") end)
end
```

- [ ] **Step 3: Beep on a rejected key in the `key` path**

In the `key` branch, the `onPress` closure (currently lines 173–178) only fires `onKey` for valid keys and silently drops the rest. Add an `else` beep. Replace:

```lua
      local function onPress(key)
        key = key:upper()
        if acceptAny or validKeys[key] then         -- NEW: acceptAny path
          promptDef.onKey(key, state, actions)
        end
      end
```

with:

```lua
      local function onPress(key)
        key = key:upper()
        if acceptAny or validKeys[key] then         -- NEW: acceptAny path
          promptDef.onKey(key, state, actions)
        else
          beep(promptDef)
        end
      end
```

(Mobile virtual buttons only ever pass valid keys, so this `else` is reached only on the desktop path — no spurious mobile beep.)

- [ ] **Step 4: Guard the desktop `key` listener against bare modifiers**

In the desktop `InputBegan` handler of the `key` branch (currently lines 188–199), return early for modifier keys so pressing Shift/Ctrl/etc. at a menu does not beep. Replace:

```lua
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local name = input.KeyCode.Name  -- e.g. "F", "R", "T", "One", "Two"
            -- Map common keys to their character
            local char = name
```

with:

```lua
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local name = input.KeyCode.Name  -- e.g. "F", "R", "T", "One", "Two"
            if MODIFIER_KEYS[name] then return end  -- never beep on bare modifiers
            -- Map common keys to their character
            local char = name
```

- [ ] **Step 5: Verify the edit**

Re-read `KeyInput.luau` lines 1–10, 61–80, and the `key` branch (~165–202). Confirm: requires present; `MODIFIER_KEYS` and `beep` defined once at module level; `onPress` has the `else beep(promptDef)`; the modifier guard precedes char mapping. Confirm no mobile path was touched.

- [ ] **Step 6: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "$(printf 'Add input beep helper and key-type rejection beep\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 2: `singlechar`-type beep

Beep on an invalid character at single-character prompts (e.g. buy/sell good selection P/S/A/G). The existing behavior of clearing the stored char on invalid input is kept; the beep is added alongside it.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`

**Interfaces:**
- Consumes: `beep(promptDef)`, `MODIFIER_KEYS` (Task 1).

- [ ] **Step 1: Guard the `singlechar` listener against bare modifiers**

In the desktop `singlechar` `InputBegan` handler, the `Return` and `BackSpace` cases are handled first (currently lines 271–283), then the key is mapped to a char. Add a modifier guard between the `BackSpace` block and the char mapping. Replace:

```lua
            if name == "BackSpace" then
              stored = ""
              resetBlink()
              updateDisplay()
              return
            end

            local char = name
```

with:

```lua
            if name == "BackSpace" then
              stored = ""
              resetBlink()
              updateDisplay()
              return
            end

            if MODIFIER_KEYS[name] then return end  -- never beep on bare modifiers

            local char = name
```

- [ ] **Step 2: Beep when the stored char is cleared by invalid input**

In the same handler, the validity check (currently lines 290–294) clears `stored` on an invalid char. Add the beep to the `else`. Replace:

```lua
            if validKeySet[char] then
              stored = char
            else
              stored = ""
            end
            resetBlink()
            updateDisplay()
```

with:

```lua
            if validKeySet[char] then
              stored = char
            else
              stored = ""
              beep(promptDef)
            end
            resetBlink()
            updateDisplay()
```

- [ ] **Step 3: Verify the edit**

Re-read the `singlechar` branch (~223–299). Confirm a valid char still stores silently (no beep), an invalid char clears **and** beeps, `BackSpace` still clears with no beep, and bare modifiers return before the beep. Mobile path untouched.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "$(printf 'Beep on invalid char in singlechar prompts\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 3: `numeric`-type beep (and Backspace = Left-arrow)

Beep on non-digit keys, on a digit past max length, and on Left-arrow/Backspace with an empty buffer. Route Backspace through the same delete logic as Left-arrow (spec Decision 1). Covers all amount fields (buy/sell, bank, Wu, warehouse).

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`

**Interfaces:**
- Consumes: `beep(promptDef)`, `MODIFIER_KEYS` (Task 1).

- [ ] **Step 1: Make Left-arrow and Backspace share delete logic; beep on empty**

In the desktop `numeric` `InputBegan` handler, replace the `Left` branch (currently lines 488–495):

```lua
            elseif input.KeyCode == Enum.KeyCode.Left then
              -- Left arrow: delete last digit (Apple II behaviour)
              if #typeBuf > 0 then
                typeBuf = typeBuf:sub(1, -2)
                cursorPos = #typeBuf + 1
              end
              resetBlink()
              updateDisplay()
```

with:

```lua
            elseif input.KeyCode == Enum.KeyCode.Left
                or input.KeyCode == Enum.KeyCode.Backspace then
              -- Left arrow deletes the last digit (Apple II). Backspace mirrors it
              -- for usability (spec Decision 1). Beep when there is nothing to delete.
              if #typeBuf > 0 then
                typeBuf = typeBuf:sub(1, -2)
                cursorPos = #typeBuf + 1
              else
                beep(promptDef)
              end
              resetBlink()
              updateDisplay()
```

- [ ] **Step 2: Beep on non-digit keys and on a digit past max length**

In the same handler, replace the final `else` branch (currently lines 496–508):

```lua
            else
              -- Accept digit keys only; Backspace is silently ignored
              local char = input.KeyCode.Name
              if NUMKEY_MAP[char] then char = NUMKEY_MAP[char] end
              if #char == 1 and char:match("%d") then
                if not maxLength or #typeBuf < maxLength then
                  typeBuf = typeBuf .. char
                  cursorPos = #typeBuf + 1
                end
                resetBlink()
                updateDisplay()
              end
            end
```

with:

```lua
            else
              if MODIFIER_KEYS[input.KeyCode.Name] then return end  -- never beep on bare modifiers
              -- Accept digit keys only. Backspace is handled with Left above.
              local char = input.KeyCode.Name
              if NUMKEY_MAP[char] then char = NUMKEY_MAP[char] end
              if #char == 1 and char:match("%d") then
                if not maxLength or #typeBuf < maxLength then
                  typeBuf = typeBuf .. char
                  cursorPos = #typeBuf + 1
                  resetBlink()
                  updateDisplay()
                else
                  beep(promptDef)  -- buffer already at max digits
                end
              else
                beep(promptDef)  -- non-digit key
              end
            end
```

- [ ] **Step 3: Verify the edit**

Re-read the `numeric` branch (~416–511). Confirm: a digit under max appends silently; a digit at max beeps; a non-digit (including arrows other than Left, and unmapped keys) beeps; Left **or** Backspace deletes when there is content, beeps when empty; bare modifiers return silently. Mobile path untouched.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "$(printf 'Beep on numeric input rejection; Backspace mirrors Left-arrow\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 4: `type`-type beep

Beep on a non-printable character and on a character entered at max length, in free-text fields. The richer cursor/overwrite/Backspace editing model is left unchanged (no boundary beeps). The only beeping `type` scene at runtime is the combat throw amount; the firm-name scene opts out via `noBeep` (Task 6).

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau`

**Interfaces:**
- Consumes: `beep(promptDef)`, `MODIFIER_KEYS` (Task 1).

- [ ] **Step 1: Beep on non-printable char and on char at max length**

In the desktop `type` `InputBegan` handler, replace the final `else` branch (currently lines 394–411):

```lua
            else
              local char = toPrintableChar(input.KeyCode.Name)
              if char then
                if cursorPos <= #typeBuf then
                  -- Overwrite mode: replace char at cursor position
                  typeBuf = typeBuf:sub(1, cursorPos - 1) .. char .. typeBuf:sub(cursorPos + 1)
                  cursorPos = cursorPos + 1
                else
                  -- Append mode: add char at end (if under maxLength)
                  if not maxLength or #typeBuf < maxLength then
                    typeBuf = typeBuf .. char
                    cursorPos = cursorPos + 1
                  end
                end
                resetBlink()
                updateDisplay()
              end
            end
```

with:

```lua
            else
              if MODIFIER_KEYS[input.KeyCode.Name] then return end  -- never beep on bare modifiers
              local char = toPrintableChar(input.KeyCode.Name)
              if char then
                if cursorPos <= #typeBuf then
                  -- Overwrite mode: replace char at cursor position
                  typeBuf = typeBuf:sub(1, cursorPos - 1) .. char .. typeBuf:sub(cursorPos + 1)
                  cursorPos = cursorPos + 1
                  resetBlink()
                  updateDisplay()
                else
                  -- Append mode: add char at end (if under maxLength)
                  if not maxLength or #typeBuf < maxLength then
                    typeBuf = typeBuf .. char
                    cursorPos = cursorPos + 1
                    resetBlink()
                    updateDisplay()
                  else
                    beep(promptDef)  -- buffer already at max length
                  end
                end
              else
                beep(promptDef)  -- non-printable key
              end
            end
```

- [ ] **Step 2: Verify the edit**

Re-read the `type` branch (~301–414). Confirm: a printable char inserts/appends silently; an append blocked by max length beeps; a non-printable key (e.g. a function key) beeps; bare modifiers return silently; Left/Right/Backspace cursor editing is unchanged and does not beep. Mobile path untouched.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/KeyInput.luau
git commit -m "$(printf 'Beep on invalid char and max-length in type prompts\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 5: Buy/sell over-limit submit beep

Wire the submit-time over-limit beep (original `CALL 2524`) into `sceneBuySellAmount` via the existing `playSound` callback. Distinct from Layer 1: this fires on Enter after affordable-looking digits fail the affordability / quantity check.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`

**Interfaces:**
- Consumes: the `playSound` callback already threaded into `PromptEngine.processState` (signature at line 1502) and constructed in `Apple2Interface.luau:85`.

- [ ] **Step 1: Add the `playSound` parameter to `sceneBuySellAmount`**

Replace the function signature (currently line 1074):

```lua
local function sceneBuySellAmount(state, actions, localSceneCb, goodIdx, isBuy)
```

with:

```lua
local function sceneBuySellAmount(state, actions, localSceneCb, goodIdx, isBuy, playSound)
```

- [ ] **Step 2: Beep in the buy and sell over-limit branches**

In the `onType` handler, replace the over-limit block (currently lines 1139–1153):

```lua
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
```

with:

```lua
      if isBuy then
        if qty * price > cash then
          -- Exceeds available cash: beep and stay on same scene (input already cleared).
          -- Faithful to the original CALL 2524 submit-time beep.
          if playSound then playSound("beep") end
          if localSceneCb then localSceneCb("buy_good_" .. goodIdx) end
          return nil
        end
        actions.buyGoods(goodIdx, math.floor(qty))
      else
        if qty > cargoAmt then
          -- Exceeds available cargo: beep and stay on same scene.
          if playSound then playSound("beep") end
          if localSceneCb then localSceneCb("sell_good_" .. goodIdx) end
          return nil
        end
        actions.sellGoods(goodIdx, math.floor(qty))
      end
```

- [ ] **Step 3: Pass `playSound` at both dispatch sites**

In `PromptEngine.processState`, replace the two dispatch calls (currently lines 1596 and 1600):

```lua
    return sceneBuySellAmount(state, actions, localSceneCb, idx, true)
```

```lua
    return sceneBuySellAmount(state, actions, localSceneCb, idx, false)
```

with, respectively:

```lua
    return sceneBuySellAmount(state, actions, localSceneCb, idx, true, playSound)
```

```lua
    return sceneBuySellAmount(state, actions, localSceneCb, idx, false, playSound)
```

- [ ] **Step 4: Verify the edit**

Re-read `sceneBuySellAmount` (~1074–1158) and the two dispatch sites (~1594–1600). Confirm the signature, both `playSound("beep")` guards, and both dispatch calls now pass `playSound`. Confirm the existing zero-quantity path (`qty == 0`, ~1135) is unchanged and stays silent.

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "$(printf 'Beep on buy/sell over-limit submit (CALL 2524)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 6: `noBeep` flags on combat main loop and firm name

Suppress Layer-1 beeps for the two excluded scenes.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`

**Interfaces:**
- Consumes: the `beep(promptDef)` gate from Task 1 (reads `promptDef.noBeep`).

- [ ] **Step 1: Add `noBeep` to the combat main-loop promptDef**

In `sceneCombatLayout`, replace the promptDef opening (currently lines 645–647):

```lua
  local promptDef = {
    type = "key",
    keys = { "F", "R", "T" },
```

with:

```lua
  local promptDef = {
    type = "key",
    noBeep = true,  -- combat main loop has its own handling; never beeps
    keys = { "F", "R", "T" },
```

- [ ] **Step 2: Add `noBeep` to the firm-name promptDef**

In `sceneFirmName`, replace the promptDef opening (currently lines 478–481):

```lua
  return { rows = rows }, {
    type            = "type",
    typePlaceholder = "",
    maxLength       = 22,
```

with:

```lua
  return { rows = rows }, {
    type            = "type",
    noBeep          = true,  -- customized dialog; takes no input beeps (spec Decision 2)
    typePlaceholder = "",
    maxLength       = 22,
```

- [ ] **Step 3: Verify the edit**

Re-read both promptDefs. Confirm `noBeep = true` is set on exactly these two and that the firm-name scene's existing empty-name `playSound("badjoss")` (~line 491) is untouched — `noBeep` gates only the new Layer-1 beep, not that submit sound.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "$(printf 'Suppress beep for combat main loop and firm-name dialog\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 7: Correct the stale note in the local-event-sounds spec

The earlier spec stated buy/sell over-limit played `good_joss`; it played the beep (`CALL 2524`), now implemented here.

**Files:**
- Modify: `docs/superpowers/specs/2026-06-25-local-event-sounds-design.md`

- [ ] **Step 1: Fix the parenthetical note (line 21)**

Replace:

```markdown
Per the original, **every local validation rejection played `good_joss`**. (Note: the original also played `good_joss` for the "you have only X in cash" buy/sell over-limit cases and `bad_joss` for an empty firm name, but those are out of scope — see Non-Goals.)
```

with:

```markdown
Per the original, **every local validation rejection played `good_joss`**. (Note: the original played `bad_joss` for an empty firm name, out of scope here — see Non-Goals. The buy/sell over-limit case played the plain system beep `CALL 2524`, not `good_joss`; it is implemented separately — see `docs/superpowers/specs/2026-06-26-input-beeps-design.md`.)
```

- [ ] **Step 2: Fix the Non-Goal bullet (the "Buy/sell over-limit silent-clear" item)**

Replace:

```markdown
- **Buy/sell over-limit silent-clear** (`PromptEngine.luau:1127-1136`): when the player tries to buy more than they can afford or sell more than they hold, our implementation silently clears the input and re-renders the *same* scene — it shows no rejection message. The original played `good_joss` here, but since our implementation presents no distinct rejection scene, wiring it is deferred.
```

with:

```markdown
- **Buy/sell over-limit silent-clear** (`PromptEngine.luau:1127-1136`): when the player tries to buy more than they can afford or sell more than they hold, our implementation silently clears the input and re-renders the *same* scene — it shows no rejection message. The original played the plain system beep (`CALL 2524`) here, not `good_joss`. This was deferred at the time and is now implemented in `docs/superpowers/specs/2026-06-26-input-beeps-design.md`.
```

- [ ] **Step 3: Verify the edit**

Re-read both edited passages. Confirm both now attribute buy/sell over-limit to the `CALL 2524` beep and cross-reference the input-beeps spec, and that no other claim in the file was altered.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-06-25-local-event-sounds-design.md
git commit -m "$(printf 'Correct stale good_joss note for buy/sell over-limit\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 8: Manual playtest verification (user-driven)

No code changes. This task is a checklist the **user** runs in Roblox Studio (Play mode, Apple II interface) to confirm the audio, since screen capture is silent and an agent cannot self-verify sound.

**Files:** none.

- [ ] **Step 1: Confirm local files have synced to Studio**

Confirm Azul has propagated `KeyInput.luau` and `PromptEngine.luau` to Studio (no pending sync). No MCP injection needed — Azul handles local→Studio sync.

- [ ] **Step 2: Beep checklist — each should beep**

Enter Play mode, choose the Apple II interface, and verify a beep on each:

- Port-sail menu (`key`): press an invalid letter and an arrow key.
- Buy/sell good selection (`singlechar`): press an invalid letter.
- Buy/sell **amount** (`numeric`): press a letter; hold a digit past the field width; press Left-arrow and Backspace with the field empty.
- Buy **amount** over budget (`numeric` submit): type an amount you can't afford, press Enter — beep, field re-prompts.
- Sell **amount** over holdings (`numeric` submit): type more than you hold, press Enter — beep, field re-prompts.
- Combat "throw cargo" → which goods (`key`) and how much (`type`): press an invalid key / non-printable key.

- [ ] **Step 3: Silence checklist — each should stay silent**

- Any valid keypress (menu selection, valid digit, valid good) — no beep, even when repeated.
- Bare modifier keys (Shift, Ctrl, Alt, Caps Lock) at any prompt — no beep.
- Combat **main loop** (F / R / T prompt): press an invalid key — **no beep**.
- **Firm-name** entry: press any key, including invalid ones and at max length — **no beep** (but an empty-name submit still plays the existing `badjoss`).

- [ ] **Step 4: Report results**

Report which checklist items passed. If any beep is missing or fires where it should be silent, capture the prompt and key involved and route back to the relevant task.

---

## Self-Review

**Spec coverage:**
- Layer 1 (`KeyInput`) beeps — Tasks 1–4 (one per prompt type). ✓
- Layer 2 (`PromptEngine` over-limit submit) — Task 5. ✓
- `noBeep` on the two excluded scenes — Task 6. ✓
- Modifier-key exclusion — Tasks 1 (key), 2 (singlechar), 3 (numeric), 4 (type). ✓
- Decision 1 (Backspace = Left in numeric) — Task 3. ✓
- Decision 2 (firm name no beeps) — Task 6. ✓
- Desktop-only / mobile untouched — verification steps in Tasks 1–4. ✓
- Stale-note correction — Task 7. ✓
- Manual audio verification by user — Task 8. ✓
- No new assets / `beep` already registered — Global Constraints. ✓

**Placeholder scan:** No TBD/TODO; every code step shows the exact before/after. ✓

**Type consistency:** `beep(promptDef)` and `MODIFIER_KEYS` are defined in Task 1 and consumed by name in Tasks 2–4; `noBeep` is read by `beep` (Task 1) and set in Task 6; `playSound` matches the existing `processState` parameter used in Task 5. ✓
