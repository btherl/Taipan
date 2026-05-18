# Combat Hit Flash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce the Apple II Taipan! enemy-fire video-mode strobe (BASIC line 5540) as a full-screen image overlay in the Roblox Apple II interface.

**Architecture:** Server tags the existing "We've been hit, Taipan!!" `pendingMessages` entry with `hitFlash = true`. The Apple II interface plays a 10-iteration full-screen image strobe (lo-res page 1 → lo-res page 2 → hi-res page 2 → terminal) before rendering the notif's text and starting the `underattack` sound.

**Tech Stack:** Roblox Luau, Azul file sync, existing `pendingMessages`/`notifQueue` pipeline.

**Spec:** `docs/superpowers/specs/2026-05-18-combat-hit-flash-design.md`

---

## Background

### Files involved

| File | Action | Responsibility |
|------|--------|----------------|
| `sync/ReplicatedStorage/Images.luau` | CREATE | Asset-ID registry (mirrors `Sounds.luau` pattern) |
| `sync/StarterGui/TaipanGui/GameController/Apple2/HitFlashLayer.luau` | CREATE | Full-screen image-strobe overlay above the Apple II terminal |
| `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` | MODIFY | Construct the layer, gate `playNextNotif` on `entry.hitFlash`, destroy on teardown |
| `sync/ServerScriptService/GameService.server.luau` | MODIFY | Set `entryHit.hitFlash = true` in `applyEnemyFire` |
| `sourcemap.json` | MODIFY | Register the two new files for Azul sync |

### How sync works

Per project `CLAUDE.md`, local file edits propagate automatically to Roblox Studio via Azul, as long as the file is registered in `sourcemap.json`. Each new file needs a unique `guid` (existing values are in the 9000s).

### Why no automated tests

The spec (section "Testing") explicitly states no TestEZ spec is needed: the server change is a single boolean flag and the client change is presentational. Verification is a manual Studio playtest at the end of the plan. Do not invent tests for these tasks.

### Studio state

Tasks below assume the Studio simulation is **stopped** when editing files (per the user's global guidance on script injection). After every file write, check that local and Studio copies match (Azul handles this — the agent just needs to wait for the sync to complete and confirm via `inspect_instance` or by re-reading if anything went wrong).

---

## Task 1: Create `Images.luau` asset registry

**Files:**
- Create: `sync/ReplicatedStorage/Images.luau`
- Modify: `sourcemap.json` (add ModuleScript entry under `ReplicatedStorage` children)

- [ ] **Step 1: Create `Images.luau` with 3 placeholder asset IDs**

Write `sync/ReplicatedStorage/Images.luau`:

```lua
return {
  hitFlashHiresPage2 = "rbxassetid://0",
  hitFlashLoresPage1 = "rbxassetid://0",
  hitFlashLoresPage2 = "rbxassetid://0",
}
```

These placeholders render nothing in Roblox. The user will replace them with real asset IDs after uploading captured framebuffer images. The cadence and layout work for testing even with placeholders (overlay just looks transparent during phases 1–3).

- [ ] **Step 2: Register `Images.luau` in `sourcemap.json`**

Open `sourcemap.json`. Find the `ReplicatedStorage` children array (search for `"name": "Sounds"` — the `Images` entry will sit alphabetically before `Remotes`/`SoundPlayer`/`Sounds`).

Locate the existing entry that sits just before where `Images` would go alphabetically (e.g. the entry whose `name` comes immediately before `"Images"`). Insert this new entry directly after it:

```json
        {
          "name": "Images",
          "className": "ModuleScript",
          "guid": "9800",
          "filePaths": [
            "sync/ReplicatedStorage/Images.luau"
          ]
        },
```

GUID `9800` is unused (verified — the 980x range is empty). If for some reason it collides, pick any other unused 4-digit value.

- [ ] **Step 3: Verify Azul sync**

In Roblox Studio (Edit mode, not Play), confirm that `ReplicatedStorage.Images` now exists as a ModuleScript. Use the MCP `inspect_instance` tool with path `ReplicatedStorage.Images` or browse manually.

If the module is missing, check that the JSON is syntactically valid (`python -c "import json; json.load(open('sourcemap.json'))"` or equivalent) and that Azul has finished syncing.

- [ ] **Step 4: Commit**

```bash
git add sync/ReplicatedStorage/Images.luau sourcemap.json
git commit -m "Add Images asset-ID registry with hit-flash placeholders"
```

---

## Task 2: Create `HitFlashLayer.luau` module

**Files:**
- Create: `sync/StarterGui/TaipanGui/GameController/Apple2/HitFlashLayer.luau`
- Modify: `sourcemap.json` (add ModuleScript entry under `Apple2` folder children)

- [ ] **Step 1: Write the full `HitFlashLayer.luau` module**

Create `sync/StarterGui/TaipanGui/GameController/Apple2/HitFlashLayer.luau` with the complete implementation:

```lua
-- HitFlashLayer.lua
-- Full-screen 10-iteration image strobe overlay that replicates the Apple II
-- enemy-fire video-mode flash from BASIC line 5540.
--
-- Per iteration (4 frames @ ~16 ms each, total ~640 ms):
--   1. Show lo-res page 1 image
--   2. Show lo-res page 2 image
--   3. Show hi-res page 2 image
--   4. Hide overlay (terminal visible — "hi-res page 1")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Images = require(ReplicatedStorage.Images)

local ITERATIONS = 10
local FRAME_MS   = 16  -- ~one 60 Hz CRT frame

local HitFlashLayer = {}

function HitFlashLayer.new(terminalGui)
  local img = Instance.new("ImageLabel")
  img.Name                  = "HitFlashLayer"
  img.Size                  = UDim2.fromScale(1, 1)
  img.BackgroundTransparency = 1
  img.BorderSizePixel       = 0
  img.ZIndex                = 50
  img.Visible               = false
  img.ScaleType             = Enum.ScaleType.Stretch
  img.Image                 = ""
  img.Parent                = terminalGui.TextParent

  local playing = false

  local function play(onComplete)
    if playing then
      -- Already strobing; chain the callback so the caller still advances.
      if onComplete then task.spawn(onComplete) end
      return
    end
    playing = true
    task.spawn(function()
      local frameTime = FRAME_MS / 1000
      for _ = 1, ITERATIONS do
        img.Image   = Images.hitFlashLoresPage1
        img.Visible = true
        task.wait(frameTime)
        img.Image   = Images.hitFlashLoresPage2
        task.wait(frameTime)
        img.Image   = Images.hitFlashHiresPage2
        task.wait(frameTime)
        img.Visible = false
        task.wait(frameTime)
      end
      img.Visible = false
      playing     = false
      if onComplete then onComplete() end
    end)
  end

  local function destroy()
    img:Destroy()
  end

  return {
    play    = play,
    destroy = destroy,
  }
end

return HitFlashLayer
```

Design notes baked in:
- `ZIndex = 50` sits above terminal text (ZIndex 1) and below `GlitchLayer` (ZIndex 100), matching the spec's layering decision.
- `Size = UDim2.fromScale(1, 1)` inherits the 16:9 letterboxing from the terminal's `AspectRatioConstraint` on `TextParent`, so the image stays within the virtual canvas.
- The `playing` guard prevents concurrent strobes from a re-entered notif (defensive — shouldn't happen in practice).
- No state reads of `lastState`/`combat` etc. — the layer is purely presentational and safe to play even if combat ends mid-strobe.

- [ ] **Step 2: Register `HitFlashLayer.luau` in `sourcemap.json`**

Find the `Apple2` folder children array in `sourcemap.json` (search for `"name": "Apple2"` followed by `"className": "Folder"`). Existing children in alphabetical order: `GlitchLayer`, `KeyInput`, `PromptEngine`, `ShipGrid`, `ShipSpriteData`, `Terminal`.

Insert `HitFlashLayer` between `GlitchLayer` and `KeyInput`:

```json
                    {
                      "name": "HitFlashLayer",
                      "className": "ModuleScript",
                      "guid": "9801",
                      "filePaths": [
                        "sync/StarterGui/TaipanGui/GameController/Apple2/HitFlashLayer.luau"
                      ]
                    },
```

GUID `9801` is unused. Make sure the comma placement keeps the JSON array valid (the entry just before now needs a trailing comma if it doesn't have one; the entry just after should keep its leading position).

- [ ] **Step 3: Verify Azul sync**

In Studio (Edit mode), confirm `StarterGui.TaipanGui.GameController.Apple2.HitFlashLayer` exists as a ModuleScript. Use `inspect_instance` or browse manually.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/HitFlashLayer.luau sourcemap.json
git commit -m "Add HitFlashLayer module for combat hit strobe overlay"
```

---

## Task 3: Wire `HitFlashLayer` into `Apple2Interface.luau`

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau`

Three changes: add the `require`, construct the layer alongside `GlitchLayer`, wrap the post-pop body of `playNextNotif` in a `runNotif` closure gated by `entry.hitFlash`, and destroy on teardown.

- [ ] **Step 1: Add the `HitFlashLayer` require**

In `Apple2Interface.luau`, near line 11 (alongside the other `Apple2.*` requires), add:

```lua
local HitFlashLayer = require(script.Parent.Apple2.HitFlashLayer)
```

Place it alphabetically — between `GlitchLayer` and `KeyInput`:

```lua
local Terminal     = require(script.Parent.Apple2.Terminal)
local GlitchLayer  = require(script.Parent.Apple2.GlitchLayer)
local HitFlashLayer = require(script.Parent.Apple2.HitFlashLayer)
local KeyInput     = require(script.Parent.Apple2.KeyInput)
local PromptEngine = require(script.Parent.Apple2.PromptEngine)
local ShipGrid     = require(script.Parent.Apple2.ShipGrid)
local SoundPlayer  = require(ReplicatedStorage.SoundPlayer)
```

- [ ] **Step 2: Construct the layer alongside `GlitchLayer`**

Find the constructor block around line 53-54:

```lua
  local glitch  = GlitchLayer.new(term._gui)
  local ki      = KeyInput.new(screenGui)
```

Insert the `hitFlash` line between them:

```lua
  local glitch   = GlitchLayer.new(term._gui)
  local hitFlash = HitFlashLayer.new(term._gui)
  local ki       = KeyInput.new(screenGui)
```

- [ ] **Step 3: Gate `playNextNotif` on `entry.hitFlash`**

Find `playNextNotif` (starts around line 153). The change wraps the existing body — from the `if entry.includeStatusScreen` check (currently line 189) down to the closing `end)` of the `task.spawn` (currently line 258) — inside a local `runNotif` function, then calls either `hitFlash.play(runNotif)` or `runNotif()` based on `entry.hitFlash`.

Locate this region (currently lines 186-259):

```lua
    notifGen += 1
    local myGen = notifGen
    local entry = table.remove(notifQueue, 1)
    if entry.includeStatusScreen and type(lastState) == "table" then
      local statusRows = PromptEngine.buildPortRows(lastState)
      for r, rowDef in pairs(statusRows) do
        local rNum = tonumber(r)
        if rNum then
          term.showInputAt(rNum, rowDef)
        end
      end
    end
    for r, rowDef in pairs(entry.rows) do
      local rNum = tonumber(r)
      if rNum then
        term.showInputAt(rNum, rowDef)
      end
    end
    -- Detect combat-mode notif: state.combat ~= nil AND entry.rows has only row 4 set.
    -- For these, leave the F/R/T prompt active so the user can update the queued command mid-notif.
    local isCombatNotif = false
    if lastState and lastState.combat ~= nil then
      local rowCount = 0
      for _ in pairs(entry.rows) do rowCount += 1 end
      if rowCount == 1 and entry.rows[4] ~= nil then
        isCombatNotif = true
      end
    end
    local soundPlaying = entry.sound ~= nil
    local skipDelayRequested = false

    if not isCombatNotif then
      -- During sound: keypress buffers a "skip post-sound delay" intent.
      -- After sound: keypress advances immediately (current anyKey behaviour).
      ki.setPrompt({
        type   = "key",
        keys   = {},
        anyKey = true,
        onKey  = function()
          if soundPlaying then
            skipDelayRequested = true
          else
            advanceNotif(myGen)
          end
        end,
      }, lastState, actions)
    end

    -- Animations owned by this notif: enqueue and start draining after the
    -- configured delay from row display.
    if entry.animations and #entry.animations > 0 then
      local startDelay = entry.animationStartDelay or 0
      task.delay(startDelay, function()
        if myGen ~= notifGen then return end
        for _, evt in ipairs(entry.animations) do
          table.insert(combatAnimQueue, evt)
        end
        drainCombatEvents()
      end)
    end

    task.spawn(function()
      if entry.sound then
        SoundPlayer.play(entry.sound)  -- blocks until Ended (or fallback deadline)
        soundPlaying = false
        if myGen ~= notifGen then return end
        if skipDelayRequested then
          advanceNotif(myGen)
          return
        end
      end
      task.delay(entry.duration, function() advanceNotif(myGen) end)
    end)
  end
```

Replace it with:

```lua
    notifGen += 1
    local myGen = notifGen
    local entry = table.remove(notifQueue, 1)

    local function runNotif()
      if myGen ~= notifGen then return end  -- stale (e.g. combat exited during flash)
      if entry.includeStatusScreen and type(lastState) == "table" then
        local statusRows = PromptEngine.buildPortRows(lastState)
        for r, rowDef in pairs(statusRows) do
          local rNum = tonumber(r)
          if rNum then
            term.showInputAt(rNum, rowDef)
          end
        end
      end
      for r, rowDef in pairs(entry.rows) do
        local rNum = tonumber(r)
        if rNum then
          term.showInputAt(rNum, rowDef)
        end
      end
      -- Detect combat-mode notif: state.combat ~= nil AND entry.rows has only row 4 set.
      -- For these, leave the F/R/T prompt active so the user can update the queued command mid-notif.
      local isCombatNotif = false
      if lastState and lastState.combat ~= nil then
        local rowCount = 0
        for _ in pairs(entry.rows) do rowCount += 1 end
        if rowCount == 1 and entry.rows[4] ~= nil then
          isCombatNotif = true
        end
      end
      local soundPlaying = entry.sound ~= nil
      local skipDelayRequested = false

      if not isCombatNotif then
        -- During sound: keypress buffers a "skip post-sound delay" intent.
        -- After sound: keypress advances immediately (current anyKey behaviour).
        ki.setPrompt({
          type   = "key",
          keys   = {},
          anyKey = true,
          onKey  = function()
            if soundPlaying then
              skipDelayRequested = true
            else
              advanceNotif(myGen)
            end
          end,
        }, lastState, actions)
      end

      -- Animations owned by this notif: enqueue and start draining after the
      -- configured delay from row display.
      if entry.animations and #entry.animations > 0 then
        local startDelay = entry.animationStartDelay or 0
        task.delay(startDelay, function()
          if myGen ~= notifGen then return end
          for _, evt in ipairs(entry.animations) do
            table.insert(combatAnimQueue, evt)
          end
          drainCombatEvents()
        end)
      end

      task.spawn(function()
        if entry.sound then
          SoundPlayer.play(entry.sound)  -- blocks until Ended (or fallback deadline)
          soundPlaying = false
          if myGen ~= notifGen then return end
          if skipDelayRequested then
            advanceNotif(myGen)
            return
          end
        end
        task.delay(entry.duration, function() advanceNotif(myGen) end)
      end)
    end

    if entry.hitFlash then
      hitFlash.play(runNotif)
    else
      runNotif()
    end
  end
```

Three things to confirm by eye after the edit:
1. Indentation: everything inside `runNotif` is one level deeper than before (matters in Lua only for readability, not semantics).
2. The `myGen ~= notifGen` guard at the top of `runNotif` is new — it discards the post-flash logic if the notif was invalidated while the strobe was playing.
3. The final `if entry.hitFlash then ... else ... end` block replaces nothing — it's appended after the closure definition.

- [ ] **Step 4: Add `hitFlash.destroy()` to `adapter.destroy`**

Find `adapter.destroy` around line 469-474:

```lua
  function adapter.destroy()
    ki.destroy()
    term.destroy()
    glitch.destroy()
    shipGrid.destroy()
  end
```

Add a `hitFlash.destroy()` call (order doesn't matter; keep alphabetical or insertion order — placing it next to `glitch.destroy()` reads well):

```lua
  function adapter.destroy()
    ki.destroy()
    term.destroy()
    glitch.destroy()
    hitFlash.destroy()
    shipGrid.destroy()
  end
```

- [ ] **Step 5: Verify Azul sync**

In Studio (Edit mode), confirm `Apple2Interface` has been updated. Re-reading the file in the local checkout vs. inspecting in Studio should show the same content.

- [ ] **Step 6: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau
git commit -m "Wire HitFlashLayer into Apple2Interface notif lifecycle"
```

---

## Task 4: Server flag — set `hitFlash = true` on the "We've been hit" notif

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau`

- [ ] **Step 1: Add the one-line flag in `applyEnemyFire`**

Find `applyEnemyFire` around line 688. The current code (lines 692-695):

```lua
  Remotes.Notify:FireClient(player, "We've been hit, Taipan!!")
  local entryHit = makeCombatNotif("We've been hit, Taipan!!", 2)
  entryHit.sound = "underattack"
  table.insert(pending, entryHit)
```

Add `entryHit.hitFlash = true` between `entryHit.sound = ...` and `table.insert(...)`:

```lua
  Remotes.Notify:FireClient(player, "We've been hit, Taipan!!")
  local entryHit = makeCombatNotif("We've been hit, Taipan!!", 2)
  entryHit.sound = "underattack"
  entryHit.hitFlash = true
  table.insert(pending, entryHit)
```

Critical: only the primary `entryHit` gets the flag. Do NOT add it to the follow-up entries in this function ("buggers hit a gun", "buggers got us", "Li Yuen's fleet drove them off"). The strobe plays once per enemy fire event, on the impact notif.

- [ ] **Step 2: Verify Azul sync**

Confirm `GameService` updated in Studio.

- [ ] **Step 3: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "Flag combat impact notif for hit-flash strobe"
```

---

## Task 5: Manual verification

**Files:** none (verification only — no commit)

- [ ] **Step 1: Start Studio Play mode**

Use the MCP `start_stop_play` tool with `is_start: true`, or click Play in Studio.

- [ ] **Step 2: Start a game on the Apple II interface**

Pick the Apple II interface from the picker. Press `F` (Firm) at the cash/guns choice to start with cash and 0 guns — guarantees no fighting back, so the enemy will fire on you the first round.

- [ ] **Step 3: Travel until pirates attack**

Travel between ports (e.g. HK → Shanghai → HK → ...) until a pirate encounter triggers. Pirate encounter chance is `1/pirateBase`, default 1/10, so usually within a few voyages.

- [ ] **Step 4: Take enemy fire**

In combat, you have no guns. Press `F` (Fight) — server responds with "We have no guns, Taipan!!" and then enemy fire resolves. Or wait out the 4-second F/R/T prompt with no input — the same applyEnemyFire path runs.

- [ ] **Step 5: Observe the strobe**

Expected sequence (placeholder asset IDs):
1. Strobe overlay flashes for ~640 ms. With placeholder `rbxassetid://0` images, you will see the overlay's `Visible` toggling but no actual image content — the terminal flashes in and out on the phase-4 frame each iteration. The cadence and layering are what matters at this stage.
2. After the strobe ends, row 4 displays "We've been hit, Taipan!!" in amber.
3. The `underattack` sound starts playing.
4. After 2 seconds (or on keypress) the notif advances.

If the strobe is invisible entirely, confirm:
- `ReplicatedStorage.Images` exists and the three keys are accessible.
- `HitFlashLayer` is constructed (check `inspect_instance` on `Players.LocalPlayer.PlayerGui.TaipanTerminal.TextParent.HitFlashLayer`).
- `entry.hitFlash` flag arrives on the client (use `execute_luau` to log incoming `pendingMessages`).

- [ ] **Step 6: Exit Play mode**

`start_stop_play` with `is_start: false`.

- [ ] **Step 7: Report findings to the user**

The user owns audio/visual verification (per project memory `feedback_audio_verification`). Report:
- Whether the strobe cadence felt right (default `FRAME_MS = 16`, `ITERATIONS = 10`, total ~640 ms — tunable in `HitFlashLayer.luau`).
- Whether the strobe correctly precedes the "We've been hit" row and `underattack` sound.
- Any layering issues (text bleeding through, overlay misplaced relative to the terminal canvas).

Once the user uploads real asset IDs for the three images, they will paste them into `sync/ReplicatedStorage/Images.luau`. No further code changes required.

---

## Done

The hit flash is live for the Apple II interface with placeholder images. The user can:
1. Replace `rbxassetid://0` in `Images.luau` with real captured framebuffer IDs.
2. Tune `FRAME_MS` and `ITERATIONS` in `HitFlashLayer.luau` if the cadence needs adjustment.

Future work (deferred, separate features):
- Lo-res page 1 live mirror (derive from current terminal text).
- Per-hit randomisation across a pool of captures.
- Modern interface analogue.
- GlitchLayer coupling.
