-- Remotes.lua
-- Single source of truth for all RemoteEvents and RemoteFunctions.
-- Required by both server and client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local function getOrCreate(className, name)
  local existing = ReplicatedStorage:FindFirstChild(name)
  if existing then return existing end
  local obj = Instance.new(className)
  obj.Name = name
  obj.Parent = ReplicatedStorage
  return obj
end

-- Client -> Server actions
Remotes.ChooseStart    = getOrCreate("RemoteEvent", "ChooseStart")    -- "cash" or "guns"
Remotes.BuyGoods       = getOrCreate("RemoteEvent", "BuyGoods")       -- goodIndex, quantity
Remotes.SellGoods      = getOrCreate("RemoteEvent", "SellGoods")      -- goodIndex, quantity
Remotes.EndTurn        = getOrCreate("RemoteEvent", "EndTurn")        -- recalculate prices
Remotes.RequestStateUpdate = getOrCreate("RemoteEvent", "RequestStateUpdate")  -- client requests full state refresh
Remotes.TravelTo             = getOrCreate("RemoteEvent", "TravelTo")             -- destination (1-7)
Remotes.TransferToWarehouse   = getOrCreate("RemoteEvent", "TransferToWarehouse")   -- goodIndex, quantity
Remotes.TransferFromWarehouse = getOrCreate("RemoteEvent", "TransferFromWarehouse") -- goodIndex, quantity

-- Phase 3: Financial interactions
Remotes.WuRepay             = getOrCreate("RemoteEvent", "WuRepay")             -- client->server: amount
Remotes.WuBorrow            = getOrCreate("RemoteEvent", "WuBorrow")            -- client->server: amount
Remotes.LeaveWu             = getOrCreate("RemoteEvent", "LeaveWu")             -- client->server: triggers enforcer check
Remotes.BankDeposit         = getOrCreate("RemoteEvent", "BankDeposit")         -- client->server: amount
Remotes.BankWithdraw        = getOrCreate("RemoteEvent", "BankWithdraw")        -- client->server: amount
Remotes.BuyLiYuenProtection   = getOrCreate("RemoteEvent", "BuyLiYuenProtection")   -- client->server: no args
Remotes.DeclineLiYuenTribute  = getOrCreate("RemoteEvent", "DeclineLiYuenTribute")  -- client->server: skip Li Yuen payment
Remotes.ConfirmWu             = getOrCreate("RemoteEvent", "ConfirmWu")             -- client->server: enter Wu session
Remotes.DeclineWu             = getOrCreate("RemoteEvent", "DeclineWu")             -- client->server: skip Wu session
Remotes.AcceptBankruptcyLoan  = getOrCreate("RemoteEvent", "AcceptBankruptcyLoan")  -- client->server: accept Wu emergency loan
Remotes.DeclineBankruptcyLoan = getOrCreate("RemoteEvent", "DeclineBankruptcyLoan") -- client->server: refuse Wu emergency loan (game over)
Remotes.Notify                = getOrCreate("RemoteEvent", "Notify")                -- server->client: message string

-- Phase 4: Game over
Remotes.RestartGame = getOrCreate("RemoteEvent", "RestartGame")  -- client->server: restart after game over

-- Phase 5: Combat
Remotes.CombatFight     = getOrCreate("RemoteEvent", "CombatFight")     -- client->server: fight action
Remotes.CombatRun       = getOrCreate("RemoteEvent", "CombatRun")       -- client->server: run action
Remotes.CombatThrow     = getOrCreate("RemoteEvent", "CombatThrow")     -- client->server: goodIndex, qty
Remotes.CombatNoCommand = getOrCreate("RemoteEvent", "CombatNoCommand") -- client->server: no command queued, enemy fires unopposed

-- Phase 6: Ship progression + retirement
Remotes.ShipRepair     = getOrCreate("RemoteEvent", "ShipRepair")     -- amount (cash to spend)
Remotes.DeclineRepair  = getOrCreate("RemoteEvent", "DeclineRepair")  -- skip repair dialog
Remotes.AcceptUpgrade  = getOrCreate("RemoteEvent", "AcceptUpgrade")  -- no args
Remotes.DeclineUpgrade = getOrCreate("RemoteEvent", "DeclineUpgrade") -- no args
Remotes.AcceptGun      = getOrCreate("RemoteEvent", "AcceptGun")      -- no args
Remotes.DeclineGun     = getOrCreate("RemoteEvent", "DeclineGun")     -- no args
Remotes.ShipPanelDone  = getOrCreate("RemoteEvent", "ShipPanelDone")  -- dismiss ship panel
Remotes.Retire         = getOrCreate("RemoteEvent", "Retire")         -- retire (HK, netWorth>=1M)
Remotes.QuitGame       = getOrCreate("RemoteEvent", "QuitGame")       -- quit game (any time)
Remotes.SetUIMode      = getOrCreate("RemoteEvent", "SetUIMode")      -- client->server: "modern" or "apple2"

-- Server -> Client updates
Remotes.StateUpdate    = getOrCreate("RemoteEvent", "StateUpdate")    -- full state snapshot

return Remotes
