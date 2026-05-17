local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local Sounds = require(script.Parent.Sounds)

local SoundPlayer = {}

local templates = {}
for name, id in pairs(Sounds) do
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Parent = SoundService
	templates[name] = s
end

task.spawn(function()
	local list = {}
	for _, s in pairs(templates) do
		table.insert(list, s)
	end
	ContentProvider:PreloadAsync(list)
end)

function SoundPlayer.play(name)
	local template = templates[name]
	if not template then
		warn(("SoundPlayer.play: unknown sound %q"):format(tostring(name)))
		return
	end

	local s = template:Clone()
	s.Parent = SoundService
	s:Play()

	local done = false
	s.Ended:Once(function() done = true end)

	local length = s.TimeLength
	if length <= 0 then length = 5 end
	local deadline = os.clock() + length + 0.2

	while not done and os.clock() < deadline do
		task.wait(0.05)
	end

	s:Destroy()
end

return SoundPlayer
