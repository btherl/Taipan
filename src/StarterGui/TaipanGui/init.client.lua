-- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
-- Bootstrapper: shows InterfacePicker immediately, then delegates to the right adapter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- Taipan is pure 2D: hide the 3D world behind a full-screen black backdrop.
-- CharacterAutoLoads=false (set server-side) means no avatar spawns,
-- so key presses are never consumed by character movement scripts.
do
  local backdrop = Instance.new("ScreenGui")
  backdrop.Name            = "Backdrop"
  backdrop.DisplayOrder    = -10
  backdrop.ResetOnSpawn    = false
  backdrop.IgnoreGuiInset  = true
  backdrop.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
  backdrop.Parent          = Players.LocalPlayer.PlayerGui

  local fill = Instance.new("Frame")
  fill.Size                  = UDim2.fromScale(1, 1)
  fill.BackgroundColor3      = Color3.new(0, 0, 0)
  fill.BackgroundTransparency = 0
  fill.BorderSizePixel       = 0
  fill.Parent                = backdrop
end

-- Point camera away from the world so nothing leaks through transparent areas.
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame     = CFrame.new(0, 1e6, 0)

local Remotes           = require(ReplicatedStorage.Remotes)
local GameActions       = require(script.GameActions)
local ModernInterface   = require(script.ModernInterface)
local InterfacePicker   = require(script.InterfacePicker)
local Apple2Interface   = require(script.Apple2Interface)

local screenGui = script.Parent   -- TaipanGui ScreenGui
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function makeAdapter(mode)
  if mode == "modern"  then return ModernInterface.new(screenGui, GameActions) end
  if mode == "apple2"  then return Apple2Interface.new(screenGui, GameActions) end
  return InterfacePicker.new(screenGui, GameActions)
end

-- Show picker immediately — no wait for StateUpdate
local currentMode    = "picker"
local currentAdapter = InterfacePicker.new(screenGui, GameActions)

Remotes.StateUpdate.OnClientEvent:Connect(function(state)
  if type(state) ~= "table" then return end   -- sentinel guard (boolean during DataStore load)

  local targetMode = state.uiMode  -- nil | "modern" | "apple2"

  if currentMode == "picker" then
    if targetMode ~= nil then
      -- Returning player with saved mode, or player just selected interface
      currentAdapter.destroy()
      currentAdapter = makeAdapter(targetMode)
      currentMode    = targetMode
    else
      -- ChooseStart fired; state exists but no interface chosen yet → advance to Phase 2
      currentAdapter.update(state)
      return
    end

  elseif (currentMode == "modern" or currentMode == "apple2")
      and targetMode ~= nil
      and targetMode ~= currentMode then
    -- Live interface switch from settings
    currentAdapter.destroy()
    currentAdapter = makeAdapter(targetMode)
    currentMode    = targetMode
  end

  currentAdapter.update(state)
end)

Remotes.Notify.OnClientEvent:Connect(function(message)
  if currentAdapter then currentAdapter.notify(message) end
end)
