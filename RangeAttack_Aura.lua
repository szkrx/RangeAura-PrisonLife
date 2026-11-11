local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local MeleeEvent = ReplicatedStorage:WaitForChild("meleeEvent", 20)
local GunRemotes = ReplicatedStorage:FindFirstChild("GunRemotes")
if not GunRemotes then
	GunRemotes = ReplicatedStorage:WaitForChild("GunRemotes", 10)
end
local ShootEvent = GunRemotes and GunRemotes:FindFirstChild("ShootEvent")
local ReloadFn = GunRemotes and GunRemotes:FindFirstChild("FuncReload")

if not MeleeEvent then
	return
end

local old = _G.__RANGE_AURA
if old and type(old.destroy) == "function" then
	pcall(old.destroy)
end

local CFG = {
	radius = 10,
	rate = 10,
	damage = 15,
	mode = "both",
	teamFilter = true,
	occlusion = true,
	showRing = true,
	autoEquip = true,
	anim = true,
	gunArgMode = "part_damage",
}

local FIRE_GAP = 0.05
local FIRE_BURST = 3
local RING_Y = 2.7
local RELOAD_EVERY = 2.5
local TARGET_PANEL_W = 262
local TARGET_PANEL_H = 322

local state = {
	enabled = false,
	targetCount = 0,
	hits = 0,
	damage = 0,
	bestRange = 0,
	tokens = 0,
	lastTick = 0,
	lastReload = 0,
	lastEquip = 0,
	lastAnim = 0,
	lastListSig = "",
	swingLeft = true,
	lastHit = setmetatable({}, { __mode = "k" }),
	hpTrack = setmetatable({}, { __mode = "k" }),
	whitelist = {},
}

local conns = {}
local function track(conn)
	conns[#conns + 1] = conn
	return conn
end

local function rigOf(player)
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return nil end
	if hum.Health <= 0 then return nil end
	return char, hum, hrp
end

local function teamBlocked(player)
	local myTeam = LocalPlayer.Team
	local other = player.Team
	if myTeam == nil or other == nil or myTeam ~= other then
		return false
	end
	if myTeam.Name == "Guards" then
		return true
	end
	return CFG.teamFilter
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasSight(origin, targetChar, part)
	if not CFG.occlusion then return true end
	local dir = part.Position - origin
	local dist = dir.Magnitude
	if dist < 1 then return true end
	rayParams.FilterDescendantsInstances = { LocalPlayer.Character, targetChar }
	local hit = workspace:Raycast(origin, dir.Unit * dist, rayParams)
	return hit == nil
end

local function whitelistHasEntry()
	return next(state.whitelist) ~= nil
end

local function collectTargets(hrpPos, rayOrigin, radius)
	local list = {}
	local filtered = whitelistHasEntry()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and not teamBlocked(plr) and (not filtered or state.whitelist[plr]) then
			local char, hum, hrp = rigOf(plr)
			if char and hum and hrp then
				local dist = (hrp.Position - hrpPos).Magnitude
				if dist <= radius then
					local part = char:FindFirstChild("Head") or hrp
					if hasSight(rayOrigin, char, part) then
						list[#list + 1] = {
							key = plr,
							arg = plr,
							hum = hum,
							part = part,
							dist = dist,
						}
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end

local GUN_RANK = {
	["AK-47"] = 1,
	["M4A1"] = 2,
	["FAL"] = 3,
	["MP5"] = 4,
	["M9"] = 5,
	["M700"] = 6,
	["Remington 870"] = 7,
	["Revolver"] = 8,
}

local function heldGun()
	local char = LocalPlayer.Character
	if not char then return nil end
	local tool = char:FindFirstChildOfClass("Tool")
	if tool and GUN_RANK[tool.Name] then return tool end
	return nil
end

local function bestGun()
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if not backpack then return nil end
	local best, rank
	for _, tool in ipairs(backpack:GetChildren()) do
		local r = GUN_RANK[tool.Name]
		if r and (not rank or r < rank) then
			best, rank = tool, r
		end
	end
	return best
end

local function ensureGun(hum, now)
	if not CFG.autoEquip then return end
	if heldGun() then return end
	if now - state.lastEquip < 0.5 then return end
	state.lastEquip = now
	local gun = bestGun()
	if gun then
		pcall(function() hum:EquipTool(gun) end)
	end
end

local MELEE_NAMES = {
	["Hammer"] = true,
	["Baton"] = true,
	["Nightstick"] = true,
	["Bat"] = true,
	["Pipe"] = true,
	["Crowbar"] = true,
}

local function isMeleeTool(tool)
	if not tool:IsA("Tool") then return false end
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:FindFirstChild("Animation") then return true end
	return MELEE_NAMES[tool.Name] == true
end

local function ensureMelee(char, hum)
	local equipped = char:FindFirstChildOfClass("Tool")
	if equipped and isMeleeTool(equipped) then return end
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if not backpack or not hum then return end
	for _, tool in ipairs(backpack:GetChildren()) do
		if isMeleeTool(tool) then
			pcall(function() hum:EquipTool(tool) end)
			return
		end
	end
end

local animCache = { char = nil, left = nil, right = nil }

local function ensureAnims(char, hum)
	if animCache.char == char then return end
	animCache.char = char
	animCache.left = nil
	animCache.right = nil
	local holder = char:FindFirstChild("ClientInputHandler")
	if not holder then return end
	local left = holder:FindFirstChild("fight_left")
	local right = holder:FindFirstChild("fight_right")
	if not left or not right then return end
	local okL, trackL = pcall(function() return hum:LoadAnimation(left) end)
	local okR, trackR = pcall(function() return hum:LoadAnimation(right) end)
	if okL then animCache.left = trackL end
	if okR then animCache.right = trackR end
end

local function playSwing(char, hum, now)
	if not CFG.anim then return end
	if now - state.lastAnim < 0.45 then return end
	state.lastAnim = now
	ensureAnims(char, hum)
	local swing = state.swingLeft and animCache.left or animCache.right
	state.swingLeft = not state.swingLeft
	if swing then
		pcall(function() swing:Play(0.05) end)
	end
	local head = char:FindFirstChild("Head")
	local sound = head and head:FindFirstChild("punchSound")
	if sound then
		pcall(function()
			sound.Pitch = 1 + math.random(-10, 10) / 100
			sound:Play()
		end)
	end
end

local ring = nil

local function ensureRing()
	if ring and ring.Parent then return ring end
	ring = Instance.new("Part")
	ring.Name = "RangeAuraRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Massless = true
	ring.Material = Enum.Material.ForceField
	ring.Color = Color3.fromRGB(0, 170, 255)
	ring.Transparency = 0.35
	ring.Shape = Enum.PartType.Cylinder
	ring.TopSurface = Enum.SurfaceType.Smooth
	ring.BottomSurface = Enum.SurfaceType.Smooth
	ring.Size = Vector3.new(0.15, 2, 2)
	ring.Parent = workspace
	return ring
end

local function updateRing(hrp)
	if not ring and not CFG.showRing then return end
	if CFG.showRing and state.enabled and hrp then
		local r = ensureRing()
		local d = CFG.radius * 2
		r.Size = Vector3.new(0.15, d, d)
		r.CFrame = CFrame.new(hrp.Position - Vector3.new(0, RING_Y, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		r.Transparency = 0.35
	elseif ring then
		ring.Transparency = 1
	end
end

local function mk(class, props, parent)
	local obj = Instance.new(class)
	if props then
		for k, v in next, props do
			obj[k] = v
		end
	end
	if parent then obj.Parent = parent end
	return obj
end

local gui = mk("ScreenGui", {
	Name = "RangeAuraGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 9999,
}, PlayerGui)

local fab = mk("TextButton", {
	Name = "Fab",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.45, 0),
	Size = UDim2.fromOffset(54, 54),
	BackgroundColor3 = Color3.fromRGB(0, 150, 230),
	BackgroundTransparency = 0.05,
	Text = "范",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	AutoButtonColor = false,
	BorderSizePixel = 0,
	ZIndex = 20,
}, gui)
mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fab)
mk("UIStroke", { Color = Color3.fromRGB(120, 220, 255), Transparency = 0.45, Thickness = 1.5 }, fab)
local fabScale = mk("UIScale", { Scale = 1 }, fab)

local panel = mk("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.fromOffset(300, 416),
	BackgroundColor3 = Color3.fromRGB(16, 18, 24),
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	Visible = true,
	ZIndex = 10,
}, gui)
local panelScale = mk("UIScale", { Scale = 1 }, panel)
mk("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
mk("UIStroke", { Color = Color3.fromRGB(0, 170, 255), Transparency = 0.6, Thickness = 1 }, panel)

local header = mk("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
}, panel)

local title = mk("TextLabel", {
	Name = "Title",
	Size = UDim2.new(1, -142, 1, 0),
	Position = UDim2.fromOffset(14, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "范围攻击  RANGE AURA",
	TextColor3 = Color3.fromRGB(238, 244, 255),
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 10,
}, header)

local author = mk("TextLabel", {
	Name = "Author",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -48, 0.5, 0),
	Size = UDim2.fromOffset(92, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "by kr X",
	TextColor3 = Color3.fromRGB(104, 116, 138),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 10,
}, header)

local closeBtn = mk("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(30, 30),
	BackgroundColor3 = Color3.fromRGB(38, 42, 54),
	Text = "×",
	TextColor3 = Color3.fromRGB(200, 210, 225),
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	AutoButtonColor = false,
	BorderSizePixel = 0,
	ZIndex = 12,
}, header)
mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, closeBtn)

local dragArea = mk("TextButton", {
	Name = "DragArea",
	Size = UDim2.new(1, -58, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	ZIndex = 11,
}, header)

local body = mk("Frame", {
	Name = "Body",
	Position = UDim2.new(0, 0, 0, 46),
	Size = UDim2.new(1, 0, 1, -46),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, panel)
mk("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 2),
	PaddingBottom = UDim.new(0, 10),
}, body)
mk("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, body)

local toggle = mk("TextButton", {
	Name = "MainToggle",
	Size = UDim2.new(1, 0, 0, 44),
	LayoutOrder = 1,
	BackgroundColor3 = Color3.fromRGB(44, 48, 60),
	Text = "已关闭 · 点击开启",
	TextColor3 = Color3.fromRGB(235, 240, 250),
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, body)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, toggle)

local modeRow = mk("Frame", {
	Name = "ModeRow",
	Size = UDim2.new(1, 0, 0, 34),
	LayoutOrder = 2,
	BackgroundTransparency = 1,
}, body)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, modeRow)

local modeButtons = {}
local function refreshModes()
	for name, btn in pairs(modeButtons) do
		if CFG.mode == name then
			btn.BackgroundColor3 = Color3.fromRGB(0, 132, 210)
		else
			btn.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
		end
	end
end

local function makeRowButton(parent, name, order, text)
	local btn = mk("TextButton", {
		Name = name,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		LayoutOrder = order,
		BackgroundColor3 = Color3.fromRGB(40, 44, 56),
		Text = text,
		TextColor3 = Color3.fromRGB(232, 238, 250),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
	return btn
end

local gunBtn = makeRowButton(modeRow, "ModeGun", 1, "枪击")
local meleeBtn = makeRowButton(modeRow, "ModeMelee", 2, "近战")
local bothBtn = makeRowButton(modeRow, "ModeBoth", 3, "双发")
modeButtons.gun = gunBtn
modeButtons.melee = meleeBtn
modeButtons.both = bothBtn

local function setMode(name)
	CFG.mode = name
	refreshModes()
end

track(gunBtn.MouseButton1Click:Connect(function() setMode("gun") end))
track(meleeBtn.MouseButton1Click:Connect(function() setMode("melee") end))
track(bothBtn.MouseButton1Click:Connect(function() setMode("both") end))
refreshModes()

local targetBtn = mk("TextButton", {
	Name = "TargetBtn",
	Size = UDim2.new(1, 0, 0, 34),
	LayoutOrder = 3,
	BackgroundColor3 = Color3.fromRGB(34, 38, 50),
	Text = "目标：全部",
	TextColor3 = Color3.fromRGB(210, 220, 236),
	Font = Enum.Font.Gotham,
	TextSize = 12,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, body)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, targetBtn)

local function whitelistCount()
	local n = 0
	for _ in pairs(state.whitelist) do n = n + 1 end
	return n
end

local function refreshTargetBtn()
	local n = whitelistCount()
	if n == 0 then
		targetBtn.Text = "目标：全部"
	else
		targetBtn.Text = string.format("目标：%d 人", n)
	end
end

local function makeSlider(layoutOrder, name, labelText, suffix, minV, maxV, stepV, defaultV, onChanged)
	local holder = mk("Frame", {
		Name = name .. "Holder",
		Size = UDim2.new(1, 0, 0, 46),
		LayoutOrder = layoutOrder,
		BackgroundTransparency = 1,
	}, body)

	mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(146, 156, 176),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
	}, holder)

	local valLabel = mk("TextLabel", {
		Name = name .. "Value",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(0, 200, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	}, holder)

	local hit = mk("TextButton", {
		Name = name .. "Hit",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, holder)

	local trackBar = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 0.5, -3),
		BackgroundColor3 = Color3.fromRGB(42, 46, 58),
		BorderSizePixel = 0,
	}, hit)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, trackBar)

	local fill = mk("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 180, 255),
		BorderSizePixel = 0,
	}, trackBar)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)

	local knob = mk("Frame", {
		Size = UDim2.fromOffset(18, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, hit)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)

	local value = defaultV
	local dragging = false

	local function apply(v, silent)
		v = math.floor((v - minV) / stepV + 0.5) * stepV + minV
		if v < minV then v = minV end
		if v > maxV then v = maxV end
		value = v
		local alpha = (v - minV) / (maxV - minV)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valLabel.Text = tostring(v) .. suffix
		if not silent then onChanged(v) end
	end

	local function fromScreenX(x)
		local abs = hit.AbsolutePosition
		local width = hit.AbsoluteSize.X
		if width <= 0 then return end
		local alpha = (x - abs.X) / width
		if alpha < 0 then alpha = 0 end
		if alpha > 1 then alpha = 1 end
		apply(minV + alpha * (maxV - minV))
	end

	local function beginDrag(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			dragging = true
			fromScreenX(input.Position.X)
		end
	end

	track(hit.InputBegan:Connect(beginDrag))
	track(trackBar.InputBegan:Connect(beginDrag))
	track(knob.InputBegan:Connect(beginDrag))
	track(fill.InputBegan:Connect(beginDrag))

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseMovement then
			fromScreenX(input.Position.X)
		end
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end))

	apply(defaultV, true)
end

makeSlider(4, "Range", "范围（格）", " 格", 4, 60, 1, CFG.radius, function(v) CFG.radius = v end)
makeSlider(5, "Rate", "攻速（次/秒）", " 次", 2, 20, 1, CFG.rate, function(v) CFG.rate = v end)
makeSlider(6, "Damage", "枪伤（AK-47 默认 15）", "", 1, 300, 1, CFG.damage, function(v) CFG.damage = v end)

local chips = mk("Frame", {
	Name = "Chips",
	Size = UDim2.new(1, 0, 0, 32),
	LayoutOrder = 7,
	BackgroundTransparency = 1,
}, body)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, chips)

local function makeChip(name, order, text, getter, setter)
	local btn = mk("TextButton", {
		Name = name,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		LayoutOrder = order,
		BackgroundColor3 = Color3.fromRGB(40, 44, 56),
		Text = "",
		TextColor3 = Color3.fromRGB(230, 236, 248),
		Font = Enum.Font.Gotham,
		TextSize = 11,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, chips)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)

	local function refresh()
		local on = getter()
		btn.Text = text .. (on and " 开" or " 关")
		if on then
			btn.BackgroundColor3 = Color3.fromRGB(0, 132, 210)
		else
			btn.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
		end
	end

	track(btn.MouseButton1Click:Connect(function()
		setter(not getter())
		refresh()
	end))

	refresh()
	return btn
end

makeChip("ChipTeam", 1, "队友", function() return CFG.teamFilter end, function(v) CFG.teamFilter = v end)
makeChip("ChipSight", 2, "遮挡", function() return CFG.occlusion end, function(v) CFG.occlusion = v end)
makeChip("ChipRing", 3, "范围圈", function() return CFG.showRing end, function(v)
	CFG.showRing = v
	updateRing(nil)
end)

local statusBoard = mk("Frame", {
	Name = "StatusBoard",
	Size = UDim2.new(1, 0, 0, 30),
	LayoutOrder = 8,
	BackgroundTransparency = 1,
}, body)

local statusLine1 = mk("TextLabel", {
	Name = "Status1",
	Size = UDim2.new(1, 0, 0, 15),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(128, 138, 158),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "待机",
}, statusBoard)

local statusLine2 = mk("TextLabel", {
	Name = "Status2",
	Size = UDim2.new(1, 0, 0, 15),
	Position = UDim2.fromOffset(0, 15),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(0, 190, 230),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "伤害 0 · 有效 —",
}, statusBoard)

local targetPanel = mk("Frame", {
	Name = "TargetPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.45, 0),
	Size = UDim2.fromOffset(TARGET_PANEL_W, TARGET_PANEL_H),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 30,
}, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 14) }, targetPanel)
mk("UIStroke", { Color = Color3.fromRGB(0, 170, 255), Transparency = 0.5, Thickness = 1 }, targetPanel)
local targetScale = mk("UIScale", { Scale = 1 }, targetPanel)

local targetTitle = mk("TextLabel", {
	Name = "TargetTitle",
	Size = UDim2.new(1, -50, 0, 38),
	Position = UDim2.fromOffset(14, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "选择攻击对象",
	TextSize = 14,
	TextColor3 = Color3.fromRGB(235, 241, 252),
	TextXAlignment = Enum.TextXAlignment.Left,
}, targetPanel)

local targetClose = mk("TextButton", {
	Name = "TargetClose",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0, 19),
	Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = Color3.fromRGB(38, 42, 54),
	Text = "×",
	TextColor3 = Color3.fromRGB(200, 210, 225),
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, targetPanel)
mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, targetClose)

local targetScroll = mk("ScrollingFrame", {
	Name = "TargetScroll",
	Position = UDim2.fromOffset(10, 40),
	Size = UDim2.new(1, -20, 1, -88),
	BackgroundColor3 = Color3.fromRGB(14, 16, 22),
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, targetPanel)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, targetScroll)
mk("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, targetScroll)
mk("UIPadding", {
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 4),
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
}, targetScroll)

local targetAllBtn = mk("TextButton", {
	Name = "TargetAll",
	Position = UDim2.new(0, 10, 1, -40),
	Size = UDim2.new(0.5, -15, 0, 32),
	BackgroundColor3 = Color3.fromRGB(0, 132, 210),
	Text = "全选",
	TextColor3 = Color3.fromRGB(240, 245, 255),
	Font = Enum.Font.Gotham,
	TextSize = 12,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, targetPanel)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, targetAllBtn)

local targetNoneBtn = mk("TextButton", {
	Name = "TargetNone",
	Position = UDim2.new(0.5, 5, 1, -40),
	Size = UDim2.new(0.5, -15, 0, 32),
	BackgroundColor3 = Color3.fromRGB(44, 48, 60),
	Text = "清空",
	TextColor3 = Color3.fromRGB(235, 240, 250),
	Font = Enum.Font.Gotham,
	TextSize = 12,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, targetPanel)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, targetNoneBtn)

local function playerListSig()
	local s = ""
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			s = s .. plr.Name .. "|"
		end
	end
	return s
end

local refreshTargetRows

local function buildTargetRows()
	for _, child in ipairs(targetScroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local order = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			order = order + 1
			local row = mk("TextButton", {
				Name = "T_" .. plr.Name,
				Size = UDim2.new(1, 0, 0, 32),
				LayoutOrder = order,
				BackgroundColor3 = Color3.fromRGB(32, 36, 46),
				Text = plr.Name,
				TextColor3 = Color3.fromRGB(226, 233, 244),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				AutoButtonColor = false,
				BorderSizePixel = 0,
			}, targetScroll)
			mk("UICorner", { CornerRadius = UDim.new(0, 7) }, row)
			mk("UIPadding", { PaddingLeft = UDim.new(0, 10) }, row)
			track(row.MouseButton1Click:Connect(function()
				if state.whitelist[plr] then
					state.whitelist[plr] = nil
				else
					state.whitelist[plr] = true
				end
				refreshTargetRows()
				refreshTargetBtn()
			end))
		end
	end
	state.lastListSig = playerListSig()
end

function refreshTargetRows()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local row = targetScroll:FindFirstChild("T_" .. plr.Name)
			if row then
				if state.whitelist[plr] then
					row.Text = "✓  " .. plr.Name
					row.BackgroundColor3 = Color3.fromRGB(0, 120, 190)
				else
					row.Text = "    " .. plr.Name
					row.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
				end
			end
		end
	end
end

track(targetBtn.MouseButton1Click:Connect(function()
	targetPanel.Visible = not targetPanel.Visible
	if targetPanel.Visible then
		buildTargetRows()
		refreshTargetRows()
		refreshTargetBtn()
	end
end))

track(targetClose.MouseButton1Click:Connect(function()
	targetPanel.Visible = false
end))

track(targetAllBtn.MouseButton1Click:Connect(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			state.whitelist[plr] = true
		end
	end
	refreshTargetRows()
	refreshTargetBtn()
end))

track(targetNoneBtn.MouseButton1Click:Connect(function()
	state.whitelist = {}
	refreshTargetRows()
	refreshTargetBtn()
end))

track(Players.PlayerRemoving:Connect(function(plr)
	state.whitelist[plr] = nil
	refreshTargetBtn()
	if targetPanel.Visible then
		buildTargetRows()
		refreshTargetRows()
	end
end))

local lastStatus = -1

local function setStatus(force)
	local now = os.clock()
	if not force and now - lastStatus < 0.2 then return end
	lastStatus = now
	statusLine1.Text = string.format("%s · 目标 %d · 发包 %d",
		state.enabled and "运行中" or "待机", state.targetCount, state.hits)
	if state.bestRange > 0 then
		statusLine2.Text = string.format("伤害 %d · 有效 %.0f 格", state.damage, state.bestRange)
	else
		statusLine2.Text = string.format("伤害 %d · 有效 —", state.damage)
	end
end

local function refreshToggle()
	if state.enabled then
		toggle.Text = "已开启 · 点击关闭"
		toggle.BackgroundColor3 = Color3.fromRGB(0, 150, 110)
	else
		toggle.Text = "已关闭 · 点击开启"
		toggle.BackgroundColor3 = Color3.fromRGB(44, 48, 60)
	end
end

refreshToggle()
refreshTargetBtn()

local function viewportSize()
	local cam = workspace.CurrentCamera
	if cam then return cam.ViewportSize end
	return Vector2.new(1280, 720)
end

local function clampDelta(startX, startY, dx, dy, sizeX, sizeY, keepX, keepY)
	local vp = viewportSize()
	local x = startX + dx
	local y = startY + dy
	local minX = -(sizeX - keepX)
	local maxX = vp.X - keepX
	local minY = 0
	local maxY = vp.Y - keepY
	if x < minX then x = minX end
	if x > maxX then x = maxX end
	if y < minY then y = minY end
	if y > maxY then y = maxY end
	return x - startX, y - startY
end

local function makeDrag(handle, target, scaleObj)
	local drag = { on = false, startPos = nil, base = nil, startTop = nil, size = nil }

	track(handle.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			drag.on = true
			drag.startPos = input.Position
			drag.base = target.Position
			drag.startTop = target.AbsolutePosition
			drag.size = target.AbsoluteSize
		end
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if not drag.on then return end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseMovement then return end
		local s = scaleObj and scaleObj.Scale or 1
		if not s or s <= 0 then s = 1 end
		local dx, dy = clampDelta(
			drag.startTop.X, drag.startTop.Y,
			input.Position.X - drag.startPos.X,
			input.Position.Y - drag.startPos.Y,
			drag.size.X, drag.size.Y,
			80, 46
		)
		target.Position = UDim2.new(
			drag.base.X.Scale, drag.base.X.Offset + dx / s,
			drag.base.Y.Scale, drag.base.Y.Offset + dy / s
		)
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			drag.on = false
		end
	end))

	return drag
end

makeDrag(dragArea, panel, panelScale)

local fabDrag = { on = false, moved = false, startPos = nil, startAbs = nil }

track(fab.InputBegan:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
		fabDrag.on = true
		fabDrag.moved = false
		fabDrag.startPos = input.Position
		fabDrag.startAbs = fab.AbsolutePosition
		fabDrag.size = fab.AbsoluteSize
		fabDrag.base = fab.Position
	end
end))

track(UserInputService.InputChanged:Connect(function(input)
	if not fabDrag.on then return end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseMovement then return end
	local rawX = input.Position.X - fabDrag.startPos.X
	local rawY = input.Position.Y - fabDrag.startPos.Y
	local dx, dy = clampDelta(
		fabDrag.startAbs.X, fabDrag.startAbs.Y,
		rawX, rawY,
		fabDrag.size.X, fabDrag.size.Y,
		fabDrag.size.X, fabDrag.size.Y
	)
	if math.abs(rawX) > 6 or math.abs(rawY) > 6 then
		fabDrag.moved = true
	end
	if fabDrag.moved then
		local s = fabScale.Scale
		if not s or s <= 0 then s = 1 end
		fab.Position = UDim2.new(
			fabDrag.base.X.Scale, fabDrag.base.X.Offset + dx / s,
			fabDrag.base.Y.Scale, fabDrag.base.Y.Offset + dy / s
		)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if not fabDrag.on then return end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
	fabDrag.on = false
	if not fabDrag.moved then
		panel.Visible = not panel.Visible
	end
end))

local function updateScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local s = math.min(vp.X / 1100, vp.Y / 640)
	if s < 0.62 then s = 0.62 end
	if s > 1.1 then s = 1.1 end
	panelScale.Scale = s
	fabScale.Scale = s
	targetScale.Scale = s
end
updateScale()

if workspace.CurrentCamera then
	track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale))
end

local function gunFire(t)
	if not ShootEvent then return end
	local m = CFG.gunArgMode
	if m == "hum_damage" then
		ShootEvent:FireServer(t.hum, CFG.damage)
	elseif m == "part" then
		ShootEvent:FireServer(t.part)
	elseif m == "part_damage_alt" then
		ShootEvent:FireServer(CFG.damage, t.part)
	else
		ShootEvent:FireServer(t.part, CFG.damage)
	end
end

track(toggle.MouseButton1Click:Connect(function()
	state.enabled = not state.enabled
	state.tokens = 0
	state.lastTick = os.clock()
	state.lastHit = setmetatable({}, { __mode = "k" })
	state.hpTrack = setmetatable({}, { __mode = "k" })
	refreshToggle()
	setStatus(true)
	if not state.enabled and ring then
		ring.Transparency = 1
	end
end))

track(closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
end))

track(RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local char, hum, hrp = rigOf(LocalPlayer)

	if not (char and hum and hrp) then
		state.targetCount = 0
		state.lastTick = now
		setStatus()
		return
	end

	updateRing(hrp)

	if not state.enabled then
		state.targetCount = 0
		state.lastTick = now
		setStatus()
		return
	end

	if targetPanel.Visible and playerListSig() ~= state.lastListSig then
		buildTargetRows()
		refreshTargetRows()
	end

	local useGun = (CFG.mode == "gun" or CFG.mode == "both") and ShootEvent ~= nil
	local useMelee = CFG.mode == "melee" or CFG.mode == "both"

	if not (useGun or useMelee) then
		state.targetCount = 0
		state.lastTick = now
		setStatus()
		return
	end

	if useGun then
		ensureGun(hum, now)
		if ReloadFn and heldGun() and now - state.lastReload >= RELOAD_EVERY then
			state.lastReload = now
			task.spawn(function()
				pcall(function() ReloadFn:InvokeServer() end)
			end)
		end
	elseif useMelee then
		ensureMelee(char, hum)
	end

	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	local targets = collectTargets(hrp.Position, origin, CFG.radius)
	state.targetCount = #targets

	for _, t in ipairs(targets) do
		local lastHp = state.hpTrack[t.key]
		local hp = t.hum.Health
		if lastHp and hp < lastHp then
			state.damage = state.damage + (lastHp - hp)
			if t.dist > state.bestRange then
				state.bestRange = t.dist
			end
		end
		state.hpTrack[t.key] = hp
	end

	local interval = 1 / math.max(CFG.rate, 1)
	local dt = now - state.lastTick
	if dt < 0 then dt = 0 end
	if dt > 1 then dt = 1 end
	state.lastTick = now
	state.tokens = math.min(FIRE_BURST, state.tokens + dt / FIRE_GAP)

	local budget = math.floor(state.tokens)
	local fired = false

	if budget > 0 then
		local due = {}
		for _, t in ipairs(targets) do
			if now - (state.lastHit[t.key] or 0) >= interval then
				due[#due + 1] = t
			end
		end
		if #due > 1 then
			table.sort(due, function(a, b)
				return (state.lastHit[a.key] or 0) < (state.lastHit[b.key] or 0)
			end)
		end

		local firedCount = 0
		local limit = math.min(budget, #due)
		for i = 1, limit do
			local t = due[i]
			state.lastHit[t.key] = now
			local sent = false
			if useGun then
				if pcall(gunFire, t) then sent = true end
			end
			if useMelee then
				if pcall(function() MeleeEvent:FireServer(t.arg, 1, 1) end) then
					sent = true
				end
			end
			if sent then
				state.hits = state.hits + 1
				firedCount = firedCount + 1
				fired = true
			end
		end
		state.tokens = state.tokens - firedCount
	end

	if fired and useMelee then
		playSwing(char, hum, now)
	end

	setStatus()
end))

track(LocalPlayer.CharacterAdded:Connect(function()
	state.lastHit = setmetatable({}, { __mode = "k" })
	state.hpTrack = setmetatable({}, { __mode = "k" })
end))

local api = {}
function api.destroy()
	state.enabled = false
	for _, conn in ipairs(conns) do
		pcall(function() conn:Disconnect() end)
	end
	conns = {}
	if ring then
		pcall(function() ring:Destroy() end)
		ring = nil
	end
	pcall(function() gui:Destroy() end)
	if _G.__RANGE_AURA == api then
		_G.__RANGE_AURA = nil
	end
end

_G.__RANGE_AURA = api
