-- TestRunner.server.lua
-- Runs all .spec files. Activate via Studio's "Run" button (server-only mode).
-- Does NOT run during normal Play-testing or in live games.
local RunService = game:GetService("RunService")
if not RunService:IsRunMode() then return end   -- only run in Run mode, not Play/Live

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestEZ = require(ReplicatedStorage.TestEZ)

local testsFolder = ServerScriptService:FindFirstChild("Tests")
  or error("Tests folder not found in ServerScriptService")

local results = TestEZ.TestBootstrap:run({ testsFolder })
if results.failureCount > 0 then
  error(string.format("Tests failed: %d failure(s)", results.failureCount))
end
print(string.format("All tests passed (%d)", results.successCount))
