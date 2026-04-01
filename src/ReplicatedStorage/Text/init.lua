--[[ CONFIG ]]
local SCREEN_RESOLUTION = Vector2.new(1920, 1080)
--[[
	This defines the virtual resolution of the text screen.
	All text will scale relative to this resolution.
	! This is NOT affected by the user's screen size, as this is a virtual resolution !
	The text canvas will scale fit with the user's screen size.
	This is only for defining a easy boundary for text positioning and scaling.
]]


-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Classes
local Sprite = require(script.lib.TextSprite)

-- Modules
local Util = require(script.lib.Util)

-- Variables
local Unicode = require(script.lib.Unicode)

-- Initialization
do
	Util.ScreenSize = SCREEN_RESOLUTION
end

-- Module
local Text = {}
Text.__index = Text

-- Constructor
function Text.new(font_name, automatic_update)
	local font_folder = script.Fonts:FindFirstChild(font_name)

	if (not font_folder) then
		error(font_name.." was not found in font folder.")
	end


	local self = setmetatable({
		Parent = nil;

		Sprites = {};
		Folder = font_folder;
		Text = "";
		OldText = "";

		TextCentered = false;
		Stroke = false;

		TextColor3 = Color3.new(1, 1, 1);
		StrokeColor3 = Color3.new(0, 0, 0);

		Inverted = false;
		BackgroundColor3 = Color3.new(0, 0, 0);

		ZIndex = 1;

		Position = Vector2.new(0, 0);
		TextSize = 1;

		UpdateConnection = nil;

		FontData = require(font_folder.FontData);
		ImageID = font_folder.ImageID.Value;

		CanUpdate = true;
	}, Text)

	if automatic_update then
		self.UpdateConnection = RunService.RenderStepped:Connect(function(DeltaTime)
			self:Update(DeltaTime)
		end)
	end

	return self
end

-- Helper
function Text.GetTextGUI(display_order: number)
	local screen_gui = Instance.new("ScreenGui")
	screen_gui.DisplayOrder = display_order or 0
	screen_gui.ResetOnSpawn = false
	screen_gui.IgnoreGuiInset = true
	screen_gui.Enabled = true

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Parent = screen_gui
	frame.Name = "TextParent"

	local aspect_ratio = Instance.new("UIAspectRatioConstraint")
	aspect_ratio.AspectRatio = (SCREEN_RESOLUTION.X / SCREEN_RESOLUTION.Y)
	aspect_ratio.Parent = frame

	return screen_gui
end

function Text.GetVirtualResolution()
	return SCREEN_RESOLUTION
end

function Text:Update(DeltaTime)
	if not self.CanUpdate then return end

	-- Update text first: adjust sprite count, glyph data, and virtual positions.
	-- This must run before the render loop so UpdateSprite flushes the correct
	-- positions to Instance.Position in the same frame (fixes one-frame flash).
	if self.Text ~= self.OldText then
		local old_length = string.len(self.OldText)
		self.OldText = self.Text

		-- Update sprite count
		local length = string.len(self.Text)
		local text = string.split(self.Text, "")
		local difference = (length - old_length)
		local total_x_length = 0

		if not (difference == 0) then
			if difference > 0 then
				difference = math.abs(difference)
				for i = 1, difference do
					table.insert(self.Sprites, Sprite.new("ImageLabel", false))
				end
			else
				difference = math.abs(difference)

				for i = 1, difference do
					self.Sprites[i]:DestroySprite()
				end

				local new_sprites = {}

				for i = 1, #self.Sprites do
					if not self.Sprites[i].Destroyed then
						table.insert(new_sprites, self.Sprites[i])
					end
				end

				self.Sprites = new_sprites
			end
		end

		-- Update each sprite
		for i = 1, length do
			self.Sprites[i].Stroke = self.Stroke
			self.Sprites[i].StrokeColor3 = self.StrokeColor3

			self.Sprites[i]:LoadImage(self.ImageID)
			self.Sprites[i].SpriteName = text[i]
			self.Sprites[i].Instance.ZIndex = self.ZIndex
			self.Sprites[i].Size = Vector2.new(self.TextSize, self.TextSize)

			local frame = self.FontData[Unicode[text[i]]]
			local animation = {
				Framerate = 24;
				Frames = {
					[1] = {
						ImageRectSize = Vector2.new(
							frame.width,
							frame.height
						);
						ImageRectOffset = Vector2.new(
							frame.x,
							frame.y
						);
						Offset = Vector2.new(frame.xoffset, (frame.yoffset / 2));
						ImageSize = Vector2.new(
							frame.width,
							frame.height
						);
					};
				}
			}

			self.Sprites[i]:AddManual(text[i], animation)
			self.Sprites[i]:Play(text[i], true)

			total_x_length += frame.xadvance * self.TextSize
		end

		-- Position sprites
		local x_start = self.Position.X
		if self.TextCentered then
			-- Offset for centered text
			x_start -= (total_x_length / 2)
		end

		local current_x = x_start
		local current_y = self.Position.Y

		for i = 1, length do
			local letter = text[i + 1] or text[i]
			local x_advance = self.FontData[Unicode[letter]].xadvance

			self.Sprites[i].Position = Vector2.new(current_x, current_y)

			current_x += x_advance * self.TextSize
		end
	end

	-- Render: propagate settings and flush virtual positions to Instance.Position.
	-- Runs after text update so new positions are always written in the same frame.
	for i = 1, #self.Sprites do
		-- Suppress stroke when inverted: opaque background blocks make stroke offsets look wrong.
		self.Sprites[i].Stroke = self.Inverted and false or self.Stroke
		self.Sprites[i].StrokeColor3 = self.StrokeColor3

		self.Sprites[i]:UpdateSprite(DeltaTime)

		if self.Sprites[i].Instance.Parent ~= self.Parent then
			self.Sprites[i].Instance.Parent = self.Parent
		end

		local inst = self.Sprites[i].Instance
		if self.Inverted then
			inst.ImageColor3            = Color3.new(1, 1, 1)  -- white: preserve black glyphs from spritesheet as-is
			inst.BackgroundColor3       = self.BackgroundColor3
			inst.BackgroundTransparency = 0
		else
			inst.ImageColor3            = self.TextColor3
			inst.BackgroundTransparency = 1
		end
	end
end

function Text:Destroy()
	self.CanUpdate = false

	for i = 1, #self.Sprites do
		self.Sprites[i]:DestroySprite()
	end

	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
	end
end

return Text