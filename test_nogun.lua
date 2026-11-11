local M = dofile("mock_roblox.lua")
local H = M.install()

local pass, fail = 0, 0
local function check(cond, msg, extra)
	if cond then
		pass = pass + 1
		print("  [PASS] " .. msg)
	else
		fail = fail + 1
		print("  [FAIL] " .. msg .. (extra and (" -> " .. tostring(extra)) or ""))
	end
end

local function step(seconds, dt)
	dt = dt or 0.05
	for _ = 1, math.floor(seconds / dt + 0.5) do
		H.advance(dt)
		H.heartbeat:Fire(dt)
	end
end

H.gunRemotes.Parent = nil

local chunk = assert(loadfile("RangeAttack_Aura.lua"))
local ok, err = pcall(chunk)
check(ok, "没有 GunRemotes 也不报错", err)

local gui = H.find(H.playerGui, "RangeAuraGui")
check(gui ~= nil, "界面照常创建")

local toggleBtn = H.find(gui, "MainToggle")
toggleBtn.MouseButton1Click:Fire()

H.fires = {}
step(0.6)
check(#H.fires > 0, "双发模式自动退化为近战", #H.fires)

H.find(gui, "ModeGun").MouseButton1Click:Fire()
H.fires = {}
step(0.6)
check(#H.fires == 0, "枪击模式缺 Remote 时不发包", #H.fires)

H.find(gui, "ModeMelee").MouseButton1Click:Fire()
H.fires = {}
step(0.6)
check(#H.fires > 0, "近战模式正常", #H.fires)

print(string.format("\n结果: %d 通过 / %d 失败", pass, fail))
if fail > 0 then
	os.exit(1)
end
