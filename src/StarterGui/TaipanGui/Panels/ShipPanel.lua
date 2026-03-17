-- ShipPanel.lua
-- Modal overlay shown at HK when state.shipOffer ~= nil.
-- Sections: upgrade offer, gun offer, ship repair. DONE dismisses.
-- ZIndex=12 (above normal panels, below CombatPanel=15 and GameOverPanel=20)

local ShipPanel = {}

local AMBER  = Color3.fromRGB(200, 180, 80)
local GREEN  = Color3.fromRGB(140, 200, 80)
local RED    = Color3.fromRGB(220, 80, 80)
local ORANGE = Color3.fromRGB(220, 120, 60)
local BLUE   = Color3.fromRGB(120, 120, 220)
local DIM    = Color3.fromRGB(80, 80, 80)
local BG     = Color3.fromRGB(15, 20, 10)
local BORDER = Color3.fromRGB(60, 90, 30)

local function label(parent, name, size, pos, text, color, textSize, zIdx)
  local lbl = Instance.new("TextLabel")
  lbl.Name             = name
  lbl.Size             = size
  lbl.Position         = pos
  lbl.BackgroundTransparency = 1
  lbl.TextColor3       = color or AMBER
  lbl.Font             = Enum.Font.RobotoMono
  lbl.TextSize         = textSize or 14
  lbl.TextXAlignment   = Enum.TextXAlignment.Left
  lbl.TextWrapped      = true
  lbl.ZIndex           = zIdx or 12
  lbl.Text             = text or ""
  lbl.Parent           = parent
  return lbl
end

local function button(parent, name, size, pos, text, bgColor, fgColor, zIdx)
  local btn = Instance.new("TextButton")
  btn.Name             = name
  btn.Size             = size
  btn.Position         = pos
  btn.BackgroundColor3 = bgColor
  btn.BorderColor3     = BORDER
  btn.TextColor3       = fgColor
  btn.Font             = Enum.Font.RobotoMono
  btn.TextSize         = 14
  btn.ZIndex           = zIdx or 12
  btn.Text             = text
  btn.Parent           = parent
  return btn
end

function ShipPanel.new(parent, onRepair, onAcceptUpgrade, onDeclineUpgrade,
                        onAcceptGun, onDeclineGun, onDone)
  local frame = Instance.new("Frame")
  frame.Name               = "ShipPanel"
  frame.Size               = UDim2.new(1, 0, 1, 0)
  frame.Position           = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3   = BG
  frame.BackgroundTransparency = 0.05
  frame.BorderSizePixel    = 0
  frame.ZIndex             = 12
  frame.Visible            = false
  frame.Parent             = parent

  local y = 10  -- current vertical cursor

  -- Title
  label(frame, "Title",
    UDim2.new(1, -10, 0, 30), UDim2.new(0, 5, 0, y),
    "[ HONG KONG — SHIP OFFERS ]", AMBER, 16)
  y = y + 36

  -- ── Upgrade section ──────────────────────────────────────────
  -- Sub-frame: label (40px) + buttons (44px) + 6px padding top/bottom = 100px
  local upgradeFrame = Instance.new("Frame")
  upgradeFrame.Name             = "UpgradeFrame"
  upgradeFrame.Size             = UDim2.new(1, -10, 0, 100)
  upgradeFrame.Position         = UDim2.new(0, 5, 0, y)
  upgradeFrame.BackgroundColor3 = Color3.fromRGB(20, 30, 15)
  upgradeFrame.BorderColor3     = BORDER
  upgradeFrame.ZIndex           = 12
  upgradeFrame.Visible          = false
  upgradeFrame.Parent           = frame

  local upgradeLabel = label(upgradeFrame, "UpgradeLabel",
    UDim2.new(1, -10, 0, 40), UDim2.new(0, 5, 0, 5),
    "A merchant offers a larger ship...", AMBER, 13)

  local acceptUpgradeBtn = button(upgradeFrame, "AcceptUpgrade",
    UDim2.new(0.45, 0, 0, 44), UDim2.new(0, 5, 0, 50),
    "UPGRADE", Color3.fromRGB(20, 50, 15), GREEN)
  local declineUpgradeBtn = button(upgradeFrame, "DeclineUpgrade",
    UDim2.new(0.45, 0, 0, 44), UDim2.new(0.5, 5, 0, 50),
    "DECLINE", Color3.fromRGB(40, 20, 10), ORANGE)

  acceptUpgradeBtn.Activated:Connect(onAcceptUpgrade)
  declineUpgradeBtn.Activated:Connect(onDeclineUpgrade)
  y = y + 108

  -- ── Gun section ───────────────────────────────────────────────
  -- Sub-frame: label (40px) + buttons (44px) + 6px padding top/bottom = 100px
  local gunFrame = Instance.new("Frame")
  gunFrame.Name             = "GunFrame"
  gunFrame.Size             = UDim2.new(1, -10, 0, 100)
  gunFrame.Position         = UDim2.new(0, 5, 0, y)
  gunFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
  gunFrame.BorderColor3     = Color3.fromRGB(60, 60, 110)
  gunFrame.ZIndex           = 12
  gunFrame.Visible          = false
  gunFrame.Parent           = frame

  local gunLabel = label(gunFrame, "GunLabel",
    UDim2.new(1, -10, 0, 40), UDim2.new(0, 5, 0, 5),
    "An arms dealer is selling a gun...", AMBER, 13)

  local acceptGunBtn = button(gunFrame, "AcceptGun",
    UDim2.new(0.45, 0, 0, 44), UDim2.new(0, 5, 0, 50),
    "BUY GUN", Color3.fromRGB(20, 20, 50), BLUE)
  local declineGunBtn = button(gunFrame, "DeclineGun",
    UDim2.new(0.45, 0, 0, 44), UDim2.new(0.5, 5, 0, 50),
    "DECLINE", Color3.fromRGB(40, 20, 10), ORANGE)

  acceptGunBtn.Activated:Connect(onAcceptGun)
  declineGunBtn.Activated:Connect(onDeclineGun)
  y = y + 108

  -- ── Repair section ────────────────────────────────────────────
  -- Sub-frame: label (20px) + TextBox+buttons (44px) + 6px padding top/bottom = 80px
  local repairFrame = Instance.new("Frame")
  repairFrame.Name             = "RepairFrame"
  repairFrame.Size             = UDim2.new(1, -10, 0, 80)
  repairFrame.Position         = UDim2.new(0, 5, 0, y)
  repairFrame.BackgroundColor3 = Color3.fromRGB(25, 15, 10)
  repairFrame.BorderColor3     = Color3.fromRGB(110, 60, 30)
  repairFrame.ZIndex           = 12
  repairFrame.Visible          = false
  repairFrame.Parent           = frame

  local repairLabel = label(repairFrame, "RepairLabel",
    UDim2.new(1, -10, 0, 20), UDim2.new(0, 5, 0, 4),
    "Ship Repair:", ORANGE, 13)

  local amountBox = Instance.new("TextBox")
  amountBox.Name             = "AmountBox"
  amountBox.Size             = UDim2.new(0.35, 0, 0, 44)
  amountBox.Position         = UDim2.new(0, 5, 0, 30)
  amountBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  amountBox.BorderColor3     = Color3.fromRGB(110, 60, 30)
  amountBox.TextColor3       = AMBER
  amountBox.Font             = Enum.Font.RobotoMono
  amountBox.TextSize         = 14
  amountBox.PlaceholderText  = "amount"
  amountBox.ZIndex           = 12
  amountBox.Parent           = repairFrame

  local allBtn = button(repairFrame, "AllBtn",
    UDim2.new(0.2, 0, 0, 44), UDim2.new(0.37, 0, 0, 30),
    "ALL", Color3.fromRGB(40, 25, 10), ORANGE)
  local repairBtn = button(repairFrame, "RepairBtn",
    UDim2.new(0.35, 0, 0, 44), UDim2.new(0.6, 0, 0, 30),
    "REPAIR", Color3.fromRGB(50, 20, 10), ORANGE)

  -- Internal state for "All" cost (updated by update())
  local currentAllCost = 0

  allBtn.Activated:Connect(function()
    amountBox.Text = tostring(currentAllCost)
  end)
  repairBtn.Activated:Connect(function()
    local amt = tonumber(amountBox.Text)
    if amt and amt > 0 then
      onRepair(math.floor(amt))
      amountBox.Text = ""
    end
  end)
  y = y + 88

  -- ── DONE button ───────────────────────────────────────────────
  local doneBtn = button(frame, "DoneBtn",
    UDim2.new(0.4, 0, 0, 44), UDim2.new(0.3, 0, 0, y),
    "DONE", Color3.fromRGB(30, 40, 20), GREEN, 12)
  doneBtn.Activated:Connect(onDone)

  -- ── update() ─────────────────────────────────────────────────
  local panel = {}

  function panel.update(state)
    local offer = state.shipOffer
    frame.Visible = (offer ~= nil and not state.gameOver)

    if not offer then return end

    -- Upgrade section
    if offer.upgradeOffer then
      upgradeFrame.Visible = true
      upgradeLabel.Text = string.format(
        "A merchant offers +50 tons capacity (fully repaired) for $%d!",
        offer.upgradeOffer.cost)
    else
      upgradeFrame.Visible = false
    end

    -- Gun section
    if offer.gunOffer then
      gunFrame.Visible = true
      gunLabel.Text = string.format(
        "An arms dealer offers a cannon for $%d (needs 10 tons hold).",
        offer.gunOffer.cost)
    else
      gunFrame.Visible = false
    end

    -- Repair section
    if offer.repairRate and state.damage > 0 then
      repairFrame.Visible = true
      local br = offer.repairRate
      local sw  = 100 - math.floor(state.damage / state.shipCapacity * 100)
      sw = math.max(0, sw)
      currentAllCost = br * math.ceil(state.damage) + 1
      repairLabel.Text = string.format(
        "Ship Repair: $%d/unit  |  SW: %d%%  |  Damage: %d",
        br, sw, math.floor(state.damage))
    else
      repairFrame.Visible = false
      currentAllCost = 0
    end
  end

  return panel
end

return ShipPanel
