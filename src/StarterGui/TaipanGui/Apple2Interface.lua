-- Apple2Interface.lua
-- Adapter: orchestrates Terminal, PromptEngine, KeyInput, GlitchLayer.
-- Implements { update(state), notify(message), destroy() }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Terminal     = require(script.Parent.Apple2.Terminal)
local GlitchLayer  = require(script.Parent.Apple2.GlitchLayer)
local KeyInput     = require(script.Parent.Apple2.KeyInput)
local PromptEngine = require(script.Parent.Apple2.PromptEngine)

local AMBER = Color3.fromRGB(200, 180, 80)
local RED   = Color3.fromRGB(220, 80, 80)

-- Server-driven scenes that override any localScene
local SERVER_SCENES = {
  gameOver   = function(s) return s.gameOver == true end,
  combat     = function(s) return s.combat ~= nil end,
  shipOffers = function(s) return s.shipOffer ~= nil end,
  wuSession  = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.inWuSession == true
  end,
}

local Apple2Interface = {}

function Apple2Interface.new(screenGui, actions)
  local term    = Terminal.new(5)         -- displayOrder 5
  local glitch  = GlitchLayer.new(term._gui)
  local ki      = KeyInput.new(screenGui)

  local lastState  = nil
  local localScene = nil  -- nil | "buy" | "sell" | "travel" | "warehouse" | "bank" |
                           --       "buy_good_N" | "sell_good_N" | "bank_deposit" |
                           --       "bank_withdraw" | "wu_repay" | "wu_borrow" |
                           --       "wh_to" | "wh_from" | "wh_to_N" | "wh_from_N" |
                           --       "settings" | "repair"

  local function isServerDriven(state)
    for _, check in pairs(SERVER_SCENES) do
      if check(state) then return true end
    end
    return false
  end

  local function render(state, scene)
    local lines, promptDef = PromptEngine.processState(state or {}, scene, actions,
      function(newScene)
        -- Local scene transition callback: set scene, re-render without StateUpdate
        localScene = newScene
        render(lastState, localScene)
      end
    )

    if lines.rows then
      term.setRows(lines.rows)         -- direct-layout scene (e.g. firm name box)
    else
      term.clear()
      for _, line in ipairs(lines) do
        if type(line) == "table" and line.segments then
          term.print(line)             -- segmented multi-font line
        elseif type(line) == "table" then
          term.print(line.text, line.color)
        else
          term.print(line, nil)
        end
      end
    end

    -- Attach terminal reference to promptDef for KeyInput type mode
    if promptDef then
      promptDef._terminal = term
      promptDef._onError  = function(errMsg)
        term.print(">> " .. errMsg, RED)
        ki.setPrompt(promptDef, state, actions)
      end
    end

    ki.setPrompt(promptDef, state, actions)
  end

  local adapter = {}

  function adapter.update(state)
    lastState = state

    -- Server-driven scenes clear localScene
    if isServerDriven(state) then
      localScene = nil
    end

    render(state, localScene)
  end

  function adapter.notify(message)
    -- Append notification below current display without clearing
    local parts = message:split("\n")
    for _, line in ipairs(parts) do
      term.print(line, AMBER)
    end
  end

  function adapter.destroy()
    ki.destroy()
    term.destroy()
    glitch.destroy()
  end

  return adapter
end

return Apple2Interface
