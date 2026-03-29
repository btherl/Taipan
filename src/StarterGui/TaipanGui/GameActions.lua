-- GameActions.lua
-- Shared Remote wrappers. Both interfaces import this; neither calls Remotes directly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)

local pendingFirmName = ""

return {
  setFirmName    = function(name) pendingFirmName = name or "" end,
  chooseStart    = function(choice) Remotes.ChooseStart:FireServer(choice, pendingFirmName) end,
  buyGoods       = function(g, q)   Remotes.BuyGoods:FireServer(g, q) end,
  sellGoods      = function(g, q)   Remotes.SellGoods:FireServer(g, q) end,
  travelTo       = function(dest)   Remotes.TravelTo:FireServer(dest) end,
  endTurn        = function()       Remotes.EndTurn:FireServer() end,
  wuRepay        = function(amt)    Remotes.WuRepay:FireServer(amt) end,
  wuBorrow       = function(amt)    Remotes.WuBorrow:FireServer(amt) end,
  leaveWu        = function()       Remotes.LeaveWu:FireServer() end,
  buyLiYuen      = function()       Remotes.BuyLiYuenProtection:FireServer() end,
  bankDeposit    = function(amt)    Remotes.BankDeposit:FireServer(amt) end,
  bankWithdraw   = function(amt)    Remotes.BankWithdraw:FireServer(amt) end,
  transferTo     = function(g, q)   Remotes.TransferToWarehouse:FireServer(g, q) end,
  transferFrom   = function(g, q)   Remotes.TransferFromWarehouse:FireServer(g, q) end,
  combatFight    = function()       Remotes.CombatFight:FireServer() end,
  combatRun      = function()       Remotes.CombatRun:FireServer() end,
  combatThrow    = function(g, q)   Remotes.CombatThrow:FireServer(g, q) end,
  shipRepair     = function(amt)    Remotes.ShipRepair:FireServer(amt) end,
  acceptUpgrade  = function()       Remotes.AcceptUpgrade:FireServer() end,
  declineUpgrade = function()       Remotes.DeclineUpgrade:FireServer() end,
  acceptGun      = function()       Remotes.AcceptGun:FireServer() end,
  declineGun     = function()       Remotes.DeclineGun:FireServer() end,
  shipPanelDone  = function()       Remotes.ShipPanelDone:FireServer() end,
  retire         = function()       Remotes.Retire:FireServer() end,
  quitGame       = function()       Remotes.QuitGame:FireServer() end,
  restartGame    = function()       Remotes.RestartGame:FireServer() end,
  setUIMode      = function(mode)   Remotes.SetUIMode:FireServer(mode) end,
  requestState   = function()       Remotes.RequestStateUpdate:FireServer() end,
}
