-- HitFlashLayer.lua
-- Full-screen 10-iteration image strobe overlay that replicates the Apple II
-- enemy-fire video-mode flash from BASIC line 5540.
--
-- Per iteration (4 frames @ ~16 ms each, total ~640 ms):
--   1. Show lo-res page 1 image
--   2. Show lo-res page 2 image
--   3. Show hi-res page 2 image
--   4. Hide overlay (terminal visible — "hi-res page 1")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Images = require(ReplicatedStorage.Images)

local ITERATIONS = 10
local FRAME_MS   = 16  -- ~one 60 Hz CRT frame

local HitFlashLayer = {}

function HitFlashLayer.new(terminalGui)
  local img = Instance.new("ImageLabel")
  img.Name                  = "HitFlashLayer"
  img.Size                  = UDim2.fromScale(1, 1)
  img.BackgroundTransparency = 1
  img.BorderSizePixel       = 0
  img.ZIndex                = 50
  img.Visible               = false
  img.ScaleType             = Enum.ScaleType.Stretch
  img.Image                 = ""
  img.Parent                = terminalGui.TextParent

  local playing = false
  local pendingCallbacks = {}

  local function play(onComplete)
    if playing then
      -- Already strobing; queue the callback to fire when the in-flight strobe ends.
      if onComplete then table.insert(pendingCallbacks, onComplete) end
      return
    end
    playing = true
    task.spawn(function()
      local frameTime = FRAME_MS / 1000
      for _ = 1, ITERATIONS do
        img.Image   = Images.hitFlashLoresPage1
        img.Visible = true
        task.wait(frameTime)
        img.Image   = Images.hitFlashLoresPage2
        task.wait(frameTime)
        img.Image   = Images.hitFlashHiresPage2
        task.wait(frameTime)
        img.Visible = false
        task.wait(frameTime)
      end
      img.Visible = false
      playing     = false
      if onComplete then onComplete() end
      while #pendingCallbacks > 0 do
        local cb = table.remove(pendingCallbacks, 1)
        cb()
      end
    end)
  end

  local function destroy()
    img:Destroy()
  end

  return {
    play    = play,
    destroy = destroy,
  }
end

return HitFlashLayer
