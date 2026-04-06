-- BoxDrawing.lua
-- Helpers for drawing box/table borders using TaipanThickFont glyphs
-- and rows with mixed fonts (thick border + standard content).

local BoxDrawing = {}

-- Box drawing character codes (TaipanThickFont codepoints)
local VERTICAL      = string.char(129)
local DIVIDER_LEFT  = string.char(136)
local DIVIDER_RIGHT = string.char(137)
local TOP_HORIZ     = string.char(141)
local BOT_HORIZ     = string.char(154)
local BOT_LEFT      = string.char(156)
local DIVIDER_MID   = string.char(157)
local BOT_RIGHT     = string.char(158)
local TOP_LEFT      = string.char(187)
local TOP_RIGHT     = string.char(189)
local SPACE         = string.char(32)

------------------------------------------------------------------------
-- String builders (pure, no Roblox services)
------------------------------------------------------------------------

function BoxDrawing.topString(width, opts)
	opts = opts or {}
	local left  = opts.noLeftCorner  and TOP_HORIZ or TOP_LEFT
	local right = opts.noRightCorner and TOP_HORIZ or TOP_RIGHT
	return left .. string.rep(TOP_HORIZ, width - 2) .. right
end

function BoxDrawing.bottomString(width, opts)
	opts = opts or {}
	local left  = opts.noLeftCorner  and BOT_HORIZ or BOT_LEFT
	local right = opts.noRightCorner and BOT_HORIZ or BOT_RIGHT
	return left .. string.rep(BOT_HORIZ, width - 2) .. right
end

function BoxDrawing.dividerString(width)
	return DIVIDER_LEFT .. string.rep(DIVIDER_MID, width - 2) .. DIVIDER_RIGHT
end

function BoxDrawing.rowBorderString(width)
	return VERTICAL .. string.rep(SPACE, width - 2) .. VERTICAL
end

------------------------------------------------------------------------
-- Terminal-compatible segmented line builders (pure, no Roblox services)
-- Return { segments = { {text, color, font}, ... } } for Terminal rows
------------------------------------------------------------------------

local THICK_FONT = "TaipanThickFont"
local DEFAULT_AMBER = Color3.fromRGB(200, 180, 80)

local function padOrTruncate(str, width)
	local len = #str
	if len > width then
		return string.sub(str, 1, width)
	elseif len < width then
		return str .. string.rep(SPACE, width - len)
	end
	return str
end

function BoxDrawing.boxTop(width, color, opts)
	return { segments = {{ text = BoxDrawing.topString(width, opts), color = color or DEFAULT_AMBER, font = THICK_FONT }} }
end

function BoxDrawing.boxBottom(width, color, opts)
	return { segments = {{ text = BoxDrawing.bottomString(width, opts), color = color or DEFAULT_AMBER, font = THICK_FONT }} }
end

function BoxDrawing.boxDivider(width, color)
	return { segments = {{ text = BoxDrawing.dividerString(width), color = color or DEFAULT_AMBER, font = THICK_FONT }} }
end

function BoxDrawing.boxRow(width, content, borderColor, contentColor)
	borderColor = borderColor or DEFAULT_AMBER
	contentColor = contentColor or borderColor
	return { segments = {
		{ text = VERTICAL, color = borderColor, font = THICK_FONT },
		{ text = padOrTruncate(content or "", width - 2), color = contentColor },
		{ text = VERTICAL, color = borderColor, font = THICK_FONT },
	}}
end

------------------------------------------------------------------------
-- Text object factories (require Roblox Text library)
------------------------------------------------------------------------

local function getTextModule()
	return require(script.Parent)
end

local function makeBorderText(str, position, textSize, zIndex)
	local Text = getTextModule()
	textSize = textSize or 1
	zIndex = zIndex or 1

	local obj = Text.new("TaipanThickFont", false)
	obj.Text = str
	obj.Position = position
	obj.TextSize = textSize
	obj.ZIndex = zIndex
	return obj
end

function BoxDrawing.newTop(position, width, opts, textSize, zIndex)
	return makeBorderText(BoxDrawing.topString(width, opts), position, textSize, zIndex)
end

function BoxDrawing.newBottom(position, width, opts, textSize, zIndex)
	return makeBorderText(BoxDrawing.bottomString(width, opts), position, textSize, zIndex)
end

function BoxDrawing.newDivider(position, width, textSize, zIndex)
	return makeBorderText(BoxDrawing.dividerString(width), position, textSize, zIndex)
end

function BoxDrawing.newRow(position, width, textSize, zIndex)
	local Text = getTextModule()
	textSize = textSize or 1
	zIndex = zIndex or 1

	local innerWidth = width - 2
	local XADVANCE = 14

	-- Border: vertical bars with spaces in between (TaipanThickFont)
	local border = Text.new("TaipanThickFont", false)
	border.Text = BoxDrawing.rowBorderString(width)
	border.Position = position
	border.TextSize = textSize
	border.ZIndex = zIndex

	-- Content: inner text (TaipanStandardFont), offset by one character width
	local content = Text.new("TaipanStandardFont", false)
	content.Text = string.rep(SPACE, innerWidth)
	content.Position = Vector2.new(position.X + XADVANCE * textSize, position.Y)
	content.TextSize = textSize
	content.ZIndex = zIndex

	local row = {}
	row.border = border
	row.content = content

	function row.setContent(str)
		local len = string.len(str)
		if len > innerWidth then
			content.Text = string.sub(str, 1, innerWidth)
		elseif len < innerWidth then
			content.Text = str .. string.rep(SPACE, innerWidth - len)
		else
			content.Text = str
		end
	end

	function row.update(dt)
		border:Update(dt)
		content:Update(dt)
	end

	function row.destroy()
		border:Destroy()
		content:Destroy()
	end

	return row
end

return BoxDrawing
