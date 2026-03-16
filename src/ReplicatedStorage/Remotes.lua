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

-- Client → Server actions
Remotes.ChooseStart    = getOrCreate("RemoteEvent", "ChooseStart")    -- "cash" or "guns"
Remotes.BuyGoods       = getOrCreate("RemoteEvent", "BuyGoods")       -- goodIndex, quantity
Remotes.SellGoods      = getOrCreate("RemoteEvent", "SellGoods")      -- goodIndex, quantity
Remotes.EndTurn        = getOrCreate("RemoteEvent", "EndTurn")        -- recalculate prices
Remotes.RequestStateUpdate = getOrCreate("RemoteEvent", "RequestStateUpdate")  -- client requests full state refresh

-- Server → Client updates
Remotes.StateUpdate    = getOrCreate("RemoteEvent", "StateUpdate")    -- full state snapshot

return Remotes
