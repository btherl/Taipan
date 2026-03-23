-- @Complexitify
-- @N_ckD

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Asset paths
local Source = script.Parent

-- Libraries
local XMLParser = require(Source.XMLParser)
local Signal = require(Source.Signal)

local Util = require(Source.Util)

-- Variables
local XMLCache = {}

local StrokeOffsets = {
	[1] = Vector2.new(-2, -2);
	[2] = Vector2.new(2, 2);
	[3] = Vector2.new(2, -2);
	[4] = Vector2.new(-2, 2);
}

local Sprite = {}
Sprite.__index = Sprite

function Sprite.new(instance, automatic_update)
	local animation = true
	if instance ~= "ImageLabel" then
		animation = false
	end

	local self = setmetatable({
		Instance = Instance.new(instance);
		Destroyed = false;

		StrokeInstances = {};

		AnimationEnabled = animation;
		AnimationTimer = 0;
		AnimationCompleted = true;
		Animation = nil;
		AnimationName = "";
		Looped = false;
		Frame = 1;
		LastFrame = nil;

		XMLFramePath = 1;

		RectOffsetOffset = Vector2.new(0, 0);
		RectSizeOffset = Vector2.new(0, 0);

		Stroke = false;
		StrokeColor3 = Color3.new(1, 1, 1);


		Position = Vector2.new(0, 0);
		Size = animation and Vector2.new(1, 1) or Vector2.new(100, 100);

		ScreenSize = Util.ScreenSize,

		Parent = nil;

		ImageID = "";
		XML = nil;
		ScaleFactor = 1;

		Animations = {};

		UpdateConnection = nil;

		OnAnimationCompleted = Signal.new();
	}, Sprite)

	self.Instance.BackgroundTransparency = 1
	self.Instance.AnchorPoint = Vector2.new(0.5, 0.5)

	if automatic_update == false then
		self.UpdateConnection = RunService.Heartbeat:Connect(function(DeltaTime)
			self:UpdateSprite(DeltaTime)
		end)
	end

	return self
end

function Sprite:SetScaleFactor(scale_factor)
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	self.ScaleFactor = scale_factor
end

function Sprite:LoadGraphic(image_id, raw_xml)
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	if type(raw_xml) ~= "string" then
		error("Invalid argument #2 to LoadGraphic(). String expected, got ModuleScript. Did you call require() first?")
	end

	-- Check the cache for already parsed XML
	-- It takes a lot of resources to parse XML, so it generates insane lag without a cache.
	if XMLCache[raw_xml] then
		self.XML = XMLCache[raw_xml]
	else
		print("Parsing new XML!")
		self.XML = XMLParser.parse(raw_xml)
		XMLCache[raw_xml] = self.XML
	end

	self.Instance.Image = image_id
	self.ImageID = image_id
end

function Sprite:LoadImage(image_id)
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	self.ImageID = image_id
	self.Instance.Image = image_id
end

function Sprite:AddByPrefix(animation_name, prefix, frame_rate)
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	if not (self.ImageID and self.XML) then
		error("No ImageID and XML loaded. Please use LoadGraphic()")
	end

	local animation = {
		Framerate = frame_rate;
		Frames = {};
	}

	local xml_frames = self.XML.children[self.XMLFramePath].children

	for i = 1, #xml_frames do
		local xml_frame = xml_frames[i].attrs

		if not xml_frame then
			continue
		end
		if not xml_frame.name then
			continue
		end

		local frame_prefix = string.sub(xml_frame.name, 1, string.len(prefix))

		-- Only use frames with the same prefix
		if frame_prefix == prefix then
			local image_rect_size = Vector2.new(
				xml_frame.width * self.ScaleFactor,
				xml_frame.height * self.ScaleFactor
			)

			local image_rect_offset = Vector2.new(
				xml_frame.x * self.ScaleFactor,
				xml_frame.y * self.ScaleFactor
			)

			-- The target size in pixels of the Instance
			local target_size = Vector2.new(
				xml_frame.width,
				xml_frame.height
			)

			local frame = {
				ImageRectSize = image_rect_size;
				ImageRectOffset = image_rect_offset;
				Offset = Vector2.new(0, 0);
				ImageSize = target_size;
			}

			table.insert(animation.Frames, frame)
		end
	end

	self.Animations[animation_name] = animation

	return animation
end

function Sprite:LoadSingleFrameImage(target_size, name)
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	local animation = {
		Framerate = 24;
		Frames = {
			[1] = {
				ImageRectSize = Vector2.new(0, 0);
				ImageRectOffset = Vector2.new(0, 0);
				Offset = Vector2.new(0, 0);
				ImageSize = target_size;
			};
		};
	}

	self.Animations[name] = animation
end

function Sprite:AddManual(animation_name, animation)
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	self.Animations[animation_name] = animation
end

function Sprite:Play(animation_name, stop_all)
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	if self.AnimationCompleted or stop_all then
		self.Animation = self.Animations[animation_name]
		self.AnimationName = animation_name
		self.Looped = false
		self.Frame = 1
		self.AnimationTimer = 0
		self.AnimationCompleted = false
		self:UpdateImage()
	end
end

function Sprite:PlayLooped(animation_name, stop_all) -- I didn't want to add 3 arguments for some reason...
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	if self.AnimationCompleted or stop_all then
		self.Animation = self.Animations[animation_name]
		self.AnimationName = animation_name
		self.Looped = true
		self.Frame = 1
		self.AnimationTimer = 0
		self.AnimationCompleted = false
		self:UpdateImage()
	end
end

function Sprite:Stop()
	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	self.AnimationCompleted = true
	self.AnimationLooped = false
	self.CurrentFrame = 1
	self.CurrentAnimationName = ""
	self.CurrentAnimation = nil
	self:UpdateImage(1/60)
end

function Sprite:UpdateImage()
	if self.Stroke then
		-- Create stroke if doesn't exist
		if #self.StrokeInstances < 1 then
			for i = 1, #StrokeOffsets do
				self.StrokeInstances[i] = self.Instance:Clone()
			end
		end
	else
		-- Remove stroke if it is still present.
		if #self.StrokeInstances > 0 then
			for i = 1, #self.StrokeInstances do
				if self.StrokeInstances[i] then
					self.StrokeInstances[i]:Destroy()
				end
			end
		end
	end

	if not self.AnimationEnabled then
		warn("Animation is not enabled for instances of type: "..self.Instance.ClassName)
		return
	end

	if self.LastFrame or not self.AnimationCompleted then
		if self.Animation then
			self.LastFrame = self.Animation.Frames[self.Frame]
		end

		if self.LastFrame then
			-- Display frame
			self.Instance.ImageRectOffset = self.LastFrame.ImageRectOffset + self.RectOffsetOffset
			self.Instance.ImageRectSize = self.LastFrame.ImageRectSize + self.RectSizeOffset

			self.Instance.Size = UDim2.fromScale(
				(self.LastFrame.ImageSize.X / self.ScreenSize.X) * self.Size.X,
				(self.LastFrame.ImageSize.Y / self.ScreenSize.Y) * self.Size.Y
			)

			-- TODO: Actually account for frame offsets PROPERLY.
			self.Instance.Position = UDim2.fromScale(
				(self.Position.X + (self.LastFrame.Offset.X * self.Size.X)) / self.ScreenSize.X,
				(self.Position.Y + (self.LastFrame.Offset.Y * self.Size.Y)) / self.ScreenSize.Y
			)
		end
	end

	-- Update stroke
	if self.Stroke and #self.StrokeInstances > 0 then
		for i = 1, #self.StrokeInstances do
			local instance = self.StrokeInstances[i]

			instance.ImageColor3 = self.StrokeColor3
			instance.Size = self.Instance.Size
			instance.Parent = self.Instance.Parent
			instance.Image = self.Instance.Image
			instance.ImageRectOffset = self.Instance.ImageRectOffset
			instance.ImageRectSize = self.Instance.ImageRectSize
			instance.Position = self.Instance.Position + UDim2.fromScale(
				(StrokeOffsets[i].X * self.Size.X) / self.ScreenSize.X,
				(StrokeOffsets[i].Y * self.Size.Y) / self.ScreenSize.Y
			)
			instance.ZIndex = self.Instance.ZIndex - 1
		end
	end
end

function Sprite:UpdatePosAndSize()
	self.Instance.Size = UDim2.fromScale(
		(self.Size.X / self.ScreenSize.X),
		(self.Size.Y / self.ScreenSize.Y)
	)

	-- TODO: Actually account for frame offsets PROPERLY.
	self.Instance.Position = UDim2.fromScale(
		(self.Position.X) / self.ScreenSize.X,
		(self.Position.Y) / self.ScreenSize.Y
	)
end

function Sprite:UpdateSprite(DeltaTime)
	if self.Destroyed then return end

	if not self.AnimationEnabled then
		self:UpdatePosAndSize()
		return
	end

	self:UpdateImage()

	-- Literally took this from FlxAnimation.hx lol
	if not self.AnimationCompleted and self.Animation then
		local frame_delta = (1 / self.Animation.Framerate)

		self.AnimationTimer += DeltaTime

		while self.AnimationTimer >= frame_delta and not self.AnimationCompleted do
			self.Frame += 1

			if self.Frame > #self.Animation.Frames then
				if self.Looped then
					self.Frame = 1
				else
					self.AnimationCompleted = true
					self.Animation = nil
					self.OnAnimationCompleted:Fire(self.AnimationName)
				end
			else
				self:UpdateImage()
			end

			self.AnimationTimer -= frame_delta
		end
	end
end

function Sprite:DestroySprite()
	self.Destroyed = true

	self.OnAnimationCompleted:DisconnectAll()

	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
	end
	self.Instance:Destroy()

	-- Remove stroke if it is still present.
	if #self.StrokeInstances > 0 then
		for i = 1, #self.StrokeInstances do
			if self.StrokeInstances[i] then
				self.StrokeInstances[i]:Destroy()
			end
		end
	end
end

return Sprite