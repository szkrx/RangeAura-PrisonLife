-- 极简 Roblox 运行时模拟器：只覆盖 RangeAttack_Aura.lua 用到的 API
local M = {}

local clock = 0
local created = {}

local function newSignal()
	local handlers = {}
	local sig = {}
	function sig:Connect(fn)
		local conn = { connected = true }
		handlers[#handlers + 1] = { fn = fn, conn = conn }
		function conn:Disconnect()
			if not self.connected then return end
			self.connected = false
			for i = #handlers, 1, -1 do
				if handlers[i].conn == self then
					table.remove(handlers, i)
				end
			end
		end
		return conn
	end
	function sig:Fire(...)
		local snapshot = {}
		for i = 1, #handlers do snapshot[i] = handlers[i] end
		for _, h in ipairs(snapshot) do
			if h.conn.connected then
				h.fn(...)
			end
		end
	end
	return sig
end

--============================== 基础类型 ==============================
local Vector3 = {}
local Vector2 = {}
local UDim = {}
local Color3 = {}
local CFrame = {}
local Enum = setmetatable({}, {
	__index = function(t, k)
		local e = setmetatable({}, {
			__index = function(_, k2)
				return tostring(k) .. "." .. tostring(k2)
			end,
		})
		t[k] = e
		return e
	end,
})

local Vector3mt = {}
Vector3mt.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	end
	if k == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then return Vector3.new(0, 0, 0) end
		return Vector3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return nil
end
Vector3mt.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3mt.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3mt.__mul = function(a, b)
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3mt.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
Vector3mt.__tostring = function(v) return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end

function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3mt)
end

local Vector2mt = {}
Vector2mt.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end

function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2mt)
end

function UDim.new(s, o)
	return { Scale = s or 0, Offset = o or 0 }
end

local UDim2mt = {}
UDim2mt.__tostring = function(u)
	return string.format("UDim2(%s,%s,%s,%s)", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end

local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }, UDim2mt)
end
M.UDim2new = udim2

local UDim2 = { new = udim2 }
function UDim2.fromOffset(x, y) return udim2(0, x, 0, y) end
function UDim2.fromScale(x, y) return udim2(x, 0, y, 0) end

local Color3mt = {}
function Color3.fromRGB(r, g, b)
	return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, Color3mt)
end
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3mt)
end

local CFramemt = {}
CFramemt.__mul = function(a, b)
	local p = a.Position
	if b.Position then
		return setmetatable({ Position = Vector3.new(p.X + b.Position.X, p.Y + b.Position.Y, p.Z + b.Position.Z) }, CFramemt)
	end
	return setmetatable({ Position = p }, CFramemt)
end
function CFrame.new(v)
	return setmetatable({ Position = v or Vector3.new(0, 0, 0) }, CFramemt)
end
function CFrame.Angles()
	return setmetatable({ Position = Vector3.new(0, 0, 0) }, CFramemt)
end

--============================== 实例系统 ==============================
local METHODS = {}
local SIGNALS = {
	InputBegan = true, InputChanged = true, InputEnded = true,
	MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
	Activated = true, CharacterAdded = true, ChildAdded = true,
	ChildRemoved = true, Destroying = true, AncestryChanged = true,
}

local INHERITS = {
	Part = { "BasePart", "PVInstance", "Instance" },
	Model = { "PVInstance", "Instance" },
	TextButton = { "GuiButton", "GuiObject", "Instance" },
	TextLabel = { "GuiObject", "Instance" },
	Frame = { "GuiObject", "Instance" },
	ScreenGui = { "LayerCollector", "Instance" },
	UIScale = { "UIComponent", "Instance" },
	UICorner = { "UIComponent", "Instance" },
	UIStroke = { "UIComponent", "Instance" },
	UIPadding = { "UIComponent", "Instance" },
	UIListLayout = { "UIComponent", "Instance" },
	Tool = { "BackpackItem", "Instance" },
	Humanoid = { "Instance" },
	Player = { "Instance" },
}

local instanceMT = {}

local function newInstance(class)
	local obj = {
		_class = class,
		_props = { _class = class },
		_children = {},
		_signals = {},
		_parent = nil,
	}
	if class == "TextButton" or class == "TextLabel" or class == "Frame" or class == "ScreenGui" then
		obj._props.Visible = true
		obj._props.AbsolutePosition = Vector2.new(0, 0)
		obj._props.AbsoluteSize = Vector2.new(0, 0)
		obj._props.Position = udim2(0, 0, 0, 0)
		obj._props.Size = udim2(0, 0, 0, 0)
		obj._props.AnchorPoint = Vector2.new(0, 0)
	end
	if class == "Part" then
		obj._props.Transparency = 0
		obj._props.Anchored = false
		obj._props.Parent = nil
	end
	if class == "Humanoid" then
		obj._props.Health = 100
		obj._props.MaxHealth = 100
	end
	created[#created + 1] = obj
	return setmetatable(obj, instanceMT)
end

local function removeChild(parent, child)
	for i = #parent._children, 1, -1 do
		if parent._children[i] == child then
			table.remove(parent._children, i)
		end
	end
end

instanceMT.__index = function(self, k)
	if k == "_class" or k == "_props" or k == "_children" or k == "_signals" or k == "_parent" then
		return rawget(self, k)
	end
	local props = rawget(self, "_props")
	if props[k] ~= nil then return props[k] end
	if k == "Parent" then return rawget(self, "_parent") end
	if k == "Name" then return props.Name end
	if SIGNALS[k] then
		local sigs = rawget(self, "_signals")
		if not sigs[k] then sigs[k] = newSignal() end
		return sigs[k]
	end
	for _, c in ipairs(rawget(self, "_children")) do
		if rawget(c, "_props").Name == k then return c end
	end
	local method = METHODS[k]
	if method then return method end
	return nil
end

instanceMT.__newindex = function(self, k, v)
	local props = rawget(self, "_props")
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old then removeChild(old, self) end
		rawset(self, "_parent", v)
		props.Parent = v
		if v then
			table.insert(v._children, self)
			local added = rawget(v, "_signals").ChildAdded
			if added then added:Fire(self) end
		end
		return
	end
	props[k] = v
end

function METHODS.IsA(self, class)
	if rawget(self, "_class") == class then return true end
	local list = INHERITS[rawget(self, "_class")]
	if list then
		for _, c in ipairs(list) do
			if c == class then return true end
		end
	end
	return false
end

function METHODS.GetChildren(self)
	local out = {}
	for i, c in ipairs(rawget(self, "_children")) do out[i] = c end
	return out
end

function METHODS.FindFirstChild(self, name)
	for _, c in ipairs(rawget(self, "_children")) do
		if rawget(c, "_props").Name == name then return c end
	end
	return nil
end

function METHODS.FindFirstChildOfClass(self, class)
	for _, c in ipairs(rawget(self, "_children")) do
		if rawget(c, "_class") == class then return c end
	end
	return nil
end

function METHODS.WaitForChild(self, name)
	return METHODS.FindFirstChild(self, name)
end

function METHODS.GetPropertyChangedSignal(self, name)
	local sigs = rawget(self, "_signals")
	local key = "__prop_" .. name
	if not sigs[key] then sigs[key] = newSignal() end
	return sigs[key]
end

function METHODS.Destroy(self)
	if rawget(self, "_destroyed") then return end
	rawset(self, "_destroyed", true)
	for _, c in ipairs(rawget(self, "_children")) do
		METHODS.Destroy(c)
	end
	local parent = rawget(self, "_parent")
	if parent then removeChild(parent, self) end
	rawset(self, "_parent", nil)
	rawget(self, "_props").Parent = nil
end

function METHODS.EquipTool(self, tool)
	if tool then tool.Parent = self.Parent end
end

function METHODS.LoadAnimation(self, anim)
	return { Play = function() end, Stop = function() end }
end

function METHODS.GetTagged(self, tag)
	return M.tagged[tag] or {}
end

function METHODS.GetPlayers(self)
	local out = {}
	for i, p in ipairs(M.players) do out[i] = p end
	return out
end

--============================== 安装 ==============================
function M.install()
	local H = {
		fires = {},
		players = {},
		tagged = {},
		clock = function() return clock end,
		advance = function(dt) clock = clock + dt end,
		newSignal = newSignal,
	}

	M.players = H.players
	M.tagged = H.tagged

	local function make(class, props, children)
		local obj = newInstance(class)
		for k, v in pairs(props or {}) do obj[k] = v end
		for _, child in ipairs(children or {}) do child.Parent = obj end
		return obj
	end

	-- 玩家工厂
	local function makePlayer(name, team, pos, health)
		local char = make("Model", { Name = name .. "Char" })
		local hum = make("Humanoid", { Name = "Humanoid", Health = health or 100 })
		hum.Parent = char
		local hrp = make("Part", { Name = "HumanoidRootPart", Position = pos, Size = Vector3.new(2, 2, 1) })
		hrp.Parent = char
		local head = make("Part", { Name = "Head", Position = pos + Vector3.new(0, 1.5, 0) })
		head.Parent = char
		local p = make("Player", { Name = name, Team = team, Character = char, Health = health or 100 })
		p.Character = char
		return p
	end

	-- 本地玩家
	local guards = { Name = "Guards" }
	local inmates = { Name = "Inmates" }
	H.teams = { Guards = guards, Inmates = inmates }

	local me = makePlayer("Me", guards, Vector3.new(0, 0, 0))
	local playerGui = make("PlayerGui", { Name = "PlayerGui" })
	playerGui.Parent = me
	local backpack = make("Backpack", { Name = "Backpack" })
	backpack.Parent = me
	local ak = make("Tool", { Name = "AK-47" })
	ak.Parent = backpack
	H.ak = ak
	H.me = me
	H.playerGui = playerGui

	-- 目标玩家
	local p1 = makePlayer("Enemy1", inmates, Vector3.new(0, 0, 10))
	local p2 = makePlayer("Enemy2", inmates, Vector3.new(0, 0, 45))
	local p3 = makePlayer("Mate", guards, Vector3.new(0, 0, 4))
	local p4 = makePlayer("Dead", inmates, Vector3.new(0, 0, 3), 0)

	H.p1, H.p2, H.p3, H.p4 = p1, p2, p3, p4

	local players = { me, p1, p2, p3, p4 }
	for _, p in ipairs(players) do H.players[#H.players + 1] = p end

	-- RemoteEvent
	local melee = newInstance("RemoteEvent")
	melee.Name = "meleeEvent"
	melee.FireServer = function(self, target, a, b)
		H.fires[#H.fires + 1] = { target = target, a = a, b = b, t = clock }
	end

	local replicatedStorage = make("ReplicatedStorage", { Name = "ReplicatedStorage" })
	melee.Parent = replicatedStorage

	H.gunFires = {}
	H.reloads = 0
	local gunRemotes = make("Folder", { Name = "GunRemotes" })
	gunRemotes.Parent = replicatedStorage
	local shoot = newInstance("RemoteEvent")
	shoot.Name = "ShootEvent"
	shoot.FireServer = function(self, part, damage)
		H.gunFires[#H.gunFires + 1] = { part = part, damage = damage, t = clock }
	end
	shoot.Parent = gunRemotes
	local reload = newInstance("RemoteFunction")
	reload.Name = "FuncReload"
	reload.InvokeServer = function(self)
		H.reloads = H.reloads + 1
		return true
	end
	reload.Parent = gunRemotes
	H.shoot = shoot
	H.reload = reload

	-- 服务
	local heartbeat = newSignal()
	local uis = {
		InputBegan = newSignal(),
		InputChanged = newSignal(),
		InputEnded = newSignal(),
	}
	local camera = {
		ViewportSize = Vector2.new(1280, 720),
		signals = {},
	}
	function camera:GetPropertyChangedSignal(name)
		if not self.signals[name] then self.signals[name] = newSignal() end
		return self.signals[name]
	end
	local workspace = make("Workspace", { Name = "Workspace" })
	workspace.CurrentCamera = camera
	workspace.Raycast = function(self, origin, direction, params)
		if H.rayBlocked then
			return { Instance = workspace, Position = origin, Normal = Vector3.new(0, 1, 0) }
		end
		return nil
	end

	local services = {
		Players = {
			LocalPlayer = me,
			GetPlayers = function() return H.players end,
			PlayerAdded = newSignal(),
			PlayerRemoving = newSignal(),
		},
		RunService = { Heartbeat = heartbeat, RenderStepped = newSignal() },
		UserInputService = uis,
		ReplicatedStorage = replicatedStorage,
		CollectionService = { GetTagged = function(_, tag) return H.tagged[tag] or {} end },
		Workspace = workspace,
		Teams = {},
	}

	local game = {}
	function game:GetService(name)
		return services[name]
	end
	game.Workspace = workspace

	-- 注入全局
	local env = {
		game = game,
		workspace = workspace,
		Instance = { new = function(class, parent)
			local obj = newInstance(class)
			if parent then obj.Parent = parent end
			return obj
		end },
		Enum = Enum,
		RaycastParams = { new = function()
			return { FilterType = nil, FilterDescendantsInstances = {} }
		end },
		Vector3 = Vector3,
		Vector2 = Vector2,
		UDim = { new = UDim.new },
		UDim2 = UDim2,
		Color3 = Color3,
		CFrame = CFrame,
		task = {
			wait = function() end,
			spawn = function(fn) fn() end,
			defer = function(fn) fn() end,
		},
		warn = function(...) print("[warn]", ...) end,
	}
	math.clamp = function(v, lo, hi)
		if v < lo then return lo end
		if v > hi then return hi end
		return v
	end
	os.clock = function() return clock end

	H.game = game
	H.workspace = workspace
	H.uis = uis
	H.heartbeat = heartbeat
	H.camera = camera
	H.services = services
	H.makePlayer = makePlayer
	H.make = make
	H.melee = melee
	H.replicatedStorage = replicatedStorage
	H.gunRemotes = gunRemotes

	H.find = function(root, name)
		for _, c in ipairs(METHODS.GetChildren(root)) do
			if rawget(c, "_props").Name == name then return c end
			local found = H.find(c, name)
			if found then return found end
		end
		return nil
	end

	for k, v in pairs(env) do
		_G[k] = v
	end

	setmetatable(_G, nil)
	return H
end

return M
