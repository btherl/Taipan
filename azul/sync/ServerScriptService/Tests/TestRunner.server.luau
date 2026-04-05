-- TestRunner.server.lua
-- Run this in Studio Play mode (not Live) to execute all .spec files.
-- Output appears in the Studio Output window.
local RunService = game:GetService("RunService")
if not RunService:IsRunMode() then return end

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
