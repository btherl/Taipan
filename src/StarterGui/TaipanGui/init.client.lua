-- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
-- Bootstrapper: reads state.uiMode, delegates to the right adapter.
-- Does not know about any specific panel or interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes           = require(ReplicatedStorage.Remotes)
local GameActions       = require(script.GameActions)
local ModernInterface   = require(script.ModernInterface)
local InterfacePicker   = require(script.InterfacePicker)
local Apple2Interface   = require(script.Apple2Interface)

local screenGui = script.Parent   -- TaipanGui ScreenGui
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local currentMode    = nil   -- nil | "picker" | "modern" | "apple2"
local currentAdapter = nil

local function makeAdapter(mode)
  if mode == "modern"  then return ModernInterface.new(screenGui, GameActions) end
  if mode == "apple2"  then return Apple2Interface.new(screenGui, GameActions) end
  return InterfacePicker.new(screenGui, GameActions)   -- nil → picker
end

Remotes.StateUpdate.OnClientEvent:Connect(function(state)
  if type(state) ~= "table" then return end   -- sentinel guard (boolean during DataStore load)

  local targetMode = state.uiMode  -- nil | "modern" | "apple2"

  if currentMode == nil then
    -- First real state: instantiate the appropriate adapter
    local label = targetMode or "picker"
    currentAdapter = makeAdapter(targetMode)
    currentMode    = label

  elseif currentMode == "picker" and targetMode ~= nil then
    -- Player just picked an interface
    currentAdapter.destroy()
    currentAdapter = makeAdapter(targetMode)
    currentMode    = targetMode

  elseif (currentMode == "modern" or currentMode == "apple2")
      and targetMode ~= nil
      and targetMode ~= currentMode then
    -- Live interface switch
    currentAdapter.destroy()
    currentAdapter = makeAdapter(targetMode)
    currentMode    = targetMode
  end

  currentAdapter.update(state)
end)

Remotes.Notify.OnClientEvent:Connect(function(message)
  if currentAdapter then currentAdapter.notify(message) end
end)
