local SoundService = game:GetService("SoundService")
local Sounds = require(script.Parent.Sounds)

local SoundPlayer = {}

function SoundPlayer.play(name)
	local id = Sounds[name]
	if not id then
		warn(("SoundPlayer.play: unknown sound %q"):format(tostring(name)))
		return
	end

	local s = Instance.new("Sound")
	s.SoundId = id
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
