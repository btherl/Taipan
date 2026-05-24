-- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
-- Bootstrapper: boots straight into the Apple II terminal interface.

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

-- Disable camera controls (like zoom via I/O keys), character movement, and Roblox UI
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

UserInputService.ModalEnabled = true

-- Disable Chat and all other CoreGuis for the terminal experience
task.spawn(function()
  local success
  repeat
    success = pcall(function()
      StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
    end)
    task.wait()
  until success
end)

-- Disable zoom
local player = Players.LocalPlayer
player.CameraMinZoomDistance = 0.5
player.CameraMaxZoomDistance = 0.5

local Remotes           = require(ReplicatedStorage.Remotes)
local GameActions       = require(script.GameActions)
local Apple2Interface   = require(script.Apple2Interface)
-- ModernInterface and InterfacePicker are deprecated: the game boots straight into Apple II.

local screenGui = script.Parent   -- TaipanGui ScreenGui
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Boot straight into Apple II — no interface picker.
-- A returning player's saved game arrives as a StateUpdate (pushed by the server after its
-- DataStore load); a new player gets no StateUpdate until ChooseStart. Since the client can't
-- tell them apart up front, we show a brief loading screen, then fall back to the start scene
-- only if no real state arrived within LOAD_GRACE_S. If state arrives first, that wins and the
-- loading screen is replaced directly — no flash of the start scene for returning players.
-- setUIMode("apple2") persists Apple II as the saved interface (Modern is deprecated).
local LOAD_GRACE_S = 1.5

local currentAdapter = Apple2Interface.new(screenGui, GameActions)
currentAdapter.showLoading()

local receivedState = false

Remotes.StateUpdate.OnClientEvent:Connect(function(state)
  if type(state) ~= "table" then return end   -- sentinel guard (boolean during DataStore load)
  receivedState = true
  currentAdapter.update(state)
end)

Remotes.Notify.OnClientEvent:Connect(function(message)
  currentAdapter.notify(message)
end)

-- Persist Apple II (also pushes saved state for an already-loaded returning player).
-- Fired after the StateUpdate listener is connected so that push can't be missed.
GameActions.setUIMode("apple2")

-- New player (no save → no StateUpdate): render the start-choice scene once the grace elapses.
task.delay(LOAD_GRACE_S, function()
  if not receivedState then
    currentAdapter.update({})
  end
end)
