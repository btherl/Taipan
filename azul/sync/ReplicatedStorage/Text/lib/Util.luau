-- @Complexitify

local HttpService = game:GetService("HttpService")

local Util = {	
	ScreenSize = Vector2.new(1920, 1080);
}

function Util.GetDataFileSize(data)
	local byte_size = #HttpService:JSONEncode(data)
	
	if byte_size >= 1048576 then
		return Util.RoundNumber((byte_size / 1048576), 2).." MB"
	end
	if byte_size >= 1024 then
		return Util.RoundNumber((byte_size / 1024), 2).." KB"
	end
	return byte_size.." Bytes"
end

return Util