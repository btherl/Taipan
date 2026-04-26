-- Apple2Interface.lua
-- Adapter: orchestrates Terminal, PromptEngine, KeyInput, GlitchLayer.
-- Implements { update(state), notify(message), destroy() }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Terminal     = require(script.Parent.Apple2.Terminal)
local GlitchLayer  = require(script.Parent.Apple2.GlitchLayer)
local KeyInput     = require(script.Parent.Apple2.KeyInput)
local PromptEngine = require(script.Parent.Apple2.PromptEngine)

local RED   = Color3.fromRGB(220, 80, 80)
local AMBER = Color3.fromRGB(200, 180, 80)

-- Server-driven scenes that override any localScene
local SERVER_SCENES = {
  gameOver   = function(s) return s.gameOver == true end,
  combat     = function(s) return s.combat ~= nil end,
  liYuenDemand = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.liYuenPending == true
  end,
  repairPending = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.repairPending == true
  end,
  wuQuestion = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.wuPending == true
  end,
  bankruptcyPending = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.inWuSession and s.bankruptcyPending ~= nil
  end,
  shipUpgrade = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.shipOffer ~= nil and s.shipOffer.upgradeOffer ~= nil and not s.inWuSession
  end,
  shipGun = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.shipOffer ~= nil and s.shipOffer.gunOffer ~= nil and not s.inWuSession
  end,
}

local Apple2Interface = {}

function Apple2Interface.new(screenGui, actions)
  local term    = Terminal.new(5)  -- displayOrder 5
  local glitch  = GlitchLayer.new(term._gui)
  local ki      = KeyInput.new(screenGui)

  local PHASE_WAIT_S = 2

  local lastState  = nil
  local queuedCommand = nil  -- "Fight" | "Run" | "Throw cargo" | nil; persists during combat, cleared when combat ends
  local roundGen   = 0
  local roundPhase = nil
  -- "wait_a"    -- silent 2s wait at round start; F/R/T sets queue for this round
  -- "wait_b"    -- 2s wait with "Taipan, what shall we do??" prompt on row 4
  -- "executing" -- phase C dispatched; awaiting server notifs to drain
  -- nil         -- between rounds (or combat inactive)
  local localScene = nil  -- nil | "buy" | "sell" | "buy_good_N" | "sell_good_N" |
                          --       "travel" | "warehouse" | "wh_to" | "wh_from" |
                          --       "wh_to_N" | "wh_from_N" | "bank" | "bank_withdraw" |
                          --       "wu_repay" | "wu_borrow" | "settings" |
                          --       "repair_amount" | "repair_amount_err" |
                          --       "quit_confirm" | "combat_throw_good" | "combat_throw_amt_N" |
                          --       "final_status"
  local notifQueue = {}
  local notifGen   = 0
  local renderGen  = 0   -- incremented each render; used to discard stale _autoAdvance callbacks
  local GREEN      = Color3.fromRGB(140, 200, 80)

  local function isServerDriven(state)
    for _, check in pairs(SERVER_SCENES) do
      if check(state) then return true end
    end
    return false
  end

  -- Forward declarations for mutual recursion between advanceNotif and playNextNotif
  local render
  local playNextNotif
  local startRoundIfCombat
  local executePhaseC

  local function advanceNotif(gen)
    if gen ~= notifGen then return end  -- stale callback, discard
    notifGen += 1                       -- consume this gen; invalidate the twin callback
    if #notifQueue > 0 then
      playNextNotif()
    else
      -- Notifications only fire on state transitions (travel/combat); old local scenes are invalid.
      localScene = nil
      roundPhase = nil
      render(lastState, localScene)
      startRoundIfCombat()
    end
  end

  playNextNotif = function()
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
    if not isCombatNotif then
      -- Any keypress skips; task.delay auto-advances after duration
      ki.setPrompt({
        type   = "key",
        keys   = {},
        anyKey = true,
        onKey  = function() advanceNotif(myGen) end,
      }, lastState, actions)
    end
    task.delay(entry.duration, function() advanceNotif(myGen) end)
  end

  render = function(state, scene)
    renderGen += 1
    local myRenderGen = renderGen

    local lines, promptDef = PromptEngine.processState(state or {}, scene, actions,
      function(newScene)
        -- Local scene transition: set scene, re-render without waiting for StateUpdate
        localScene = newScene
        render(lastState, localScene)
      end,
      {
        current = queuedCommand,
        set = function(newAction)
          queuedCommand = newAction
          render(lastState, localScene)
        end,
      }
    )

    if lines.rows then
      term.setRows(lines.rows)
    else
      term.clear()
      for _, line in ipairs(lines) do
        if type(line) == "table" and line.segments then
          term.print(line)
        elseif type(line) == "table" then
          term.print(line.text, line.color)
        else
          term.print(line, nil)
        end
      end
    end

    if promptDef then
      promptDef._terminal = term
      promptDef._onError  = function(errMsg)
        term.print(">> " .. errMsg, RED)
        ki.setPrompt(promptDef, state, actions)
      end
    end

    -- Attach terminal reference so KeyInput can display input cursor
    ki.setPrompt(promptDef, state, actions)

    -- _autoAdvance = {duration, nextScene}: auto-transition after timeout unless superseded
    if promptDef and promptDef._autoAdvance then
      local duration  = promptDef._autoAdvance[1]
      local nextScene = promptDef._autoAdvance[2]
      task.delay(duration, function()
        if renderGen == myRenderGen then
          localScene = nextScene
          render(lastState, localScene)
        end
      end)
    end
  end

  startRoundIfCombat = function()
    if not (lastState and lastState.combat) then return end
    if roundPhase ~= nil then return end
    if #notifQueue > 0 then return end
    roundGen += 1
    local myGen = roundGen
    roundPhase = "wait_a"
    task.delay(PHASE_WAIT_S, function()
      if myGen ~= roundGen then return end
      if not (lastState and lastState.combat) then roundPhase = nil; return end
      if queuedCommand == nil then
        roundPhase = "wait_b"
        term.showInputAt(4, { text = "Taipan, what shall we do??", color = AMBER })
        task.delay(PHASE_WAIT_S, function()
          if myGen ~= roundGen then return end
          if not (lastState and lastState.combat) then roundPhase = nil; return end
          executePhaseC()
        end)
      else
        executePhaseC()
      end
    end)
  end

  executePhaseC = function()
    roundPhase = "executing"
    local cmd = queuedCommand
    if cmd == "Throw cargo" then
      roundPhase = nil  -- transitioning to throw subscene; no async round work in flight
      localScene = "combat_throw_good"
      render(lastState, localScene)
      return
    end
    -- non-throw branches: restore row 4 to seaworthiness via re-render, then fire action
    render(lastState, localScene)
    if cmd == nil then
      actions.combatNoCommand()
    elseif cmd == "Fight" then
      actions.combatFight()
    elseif cmd == "Run" then
      actions.combatRun()
    end
  end

  local adapter = {}

  function adapter.update(state)
    lastState = state

    if state.combat == nil then
      queuedCommand = nil
      roundPhase = nil
      roundGen += 1  -- invalidate any in-flight phase callbacks
    end

    -- Drain any pendingMessages from the state update into the queue
    if type(state.pendingMessages) == "table" then
      for _, entry in ipairs(state.pendingMessages) do
        table.insert(notifQueue, entry)
      end
    end

    -- Server-driven scenes reset local navigation
    if isServerDriven(state) then
      localScene = nil
    elseif state.startChoice == nil then
      localScene = nil
    end

    -- Warehouse wait: StateUpdate has arrived with fresh cargo; advance to next step.
    if type(localScene) == "string" and localScene:match("^wh_wait_%d+$") then
      local n = tonumber(localScene:match("(%d+)"))
      localScene = "wh_step_" .. (n + 1)
    end

    -- Play notifications first, then render main scene
    if #notifQueue > 0 then
      playNextNotif()
    else
      render(state, localScene)
      if state.combat ~= nil and #notifQueue == 0 and roundPhase == nil then
        startRoundIfCombat()
      end
    end
  end

  function adapter.notify(_message)
    -- Apple2 receives all event info via pendingMessages; ignore text notifications
  end

  function adapter.destroy()
    ki.destroy()
    term.destroy()
    glitch.destroy()
  end

  return adapter
end

return Apple2Interface
