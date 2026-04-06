-- Apple2Interface.lua
-- Adapter: orchestrates Terminal, PromptEngine, KeyInput, GlitchLayer.
-- Implements { update(state), notify(message), destroy() }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Terminal     = require(script.Parent.Apple2.Terminal)
local GlitchLayer  = require(script.Parent.Apple2.GlitchLayer)
local KeyInput     = require(script.Parent.Apple2.KeyInput)
local PromptEngine = require(script.Parent.Apple2.PromptEngine)

local RED   = Color3.fromRGB(220, 80, 80)

-- Server-driven scenes that override any localScene
local SERVER_SCENES = {
  gameOver   = function(s) return s.gameOver == true end,
  combat     = function(s) return s.combat ~= nil end,
  shipOffers = function(s) return s.shipOffer ~= nil end,
  liYuenDemand = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.liYuenPending == true
  end,
  wuQuestion = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.wuPending == true
  end,
}

local Apple2Interface = {}

function Apple2Interface.new(screenGui, actions)
  local term    = Terminal.new(5)  -- displayOrder 5
  local glitch  = GlitchLayer.new(term._gui)
  local ki      = KeyInput.new(screenGui)

  local lastState  = nil
  local localScene = nil  -- nil | "buy" | "sell" | "buy_good_N" | "sell_good_N" |
                          --       "travel" | "warehouse" | "wh_to" | "wh_from" |
                          --       "wh_to_N" | "wh_from_N" | "bank" | "bank_withdraw" |
                          --       "wu_repay" | "wu_borrow" | "settings" | "repair" |
                          --       "quit_confirm" | "combat_throw_good" | "combat_throw_amt_N" |
                          --       "final_status"
  local notifQueue = {}
  local notifGen   = 0
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

  local function advanceNotif(gen)
    if gen ~= notifGen then return end  -- stale callback, discard
    if #notifQueue > 0 then
      playNextNotif()
    else
      -- Notifications only fire on state transitions (travel/combat); old local scenes are invalid.
      localScene = nil
      render(lastState, localScene)
    end
  end

  playNextNotif = function()
    notifGen += 1
    local myGen = notifGen
    local entry = table.remove(notifQueue, 1)
    -- Write rows 17–24 from entry; blank any unspecified rows
    for r = 17, 24 do
      local rows_r = entry.rows[r] or entry.rows[tostring(r)]
      term.showInputAt(r, rows_r or { text = "", color = GREEN })
    end
    -- Any keypress skips; task.delay auto-advances after duration
    ki.setPrompt({
      type   = "key",
      keys   = {},
      anyKey = true,
      onKey  = function() advanceNotif(myGen) end,
    }, lastState, actions)
    task.delay(entry.duration, function() advanceNotif(myGen) end)
  end

  render = function(state, scene)
    local lines, promptDef = PromptEngine.processState(state or {}, scene, actions,
      function(newScene)
        -- Local scene transition: set scene, re-render without waiting for StateUpdate
        localScene = newScene
        render(lastState, localScene)
      end
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
  end

  local adapter = {}

  function adapter.update(state)
    lastState = state

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

    -- Play notifications first, then render main scene
    if #notifQueue > 0 then
      playNextNotif()
    else
      render(state, localScene)
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
