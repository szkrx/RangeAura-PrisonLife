-- 边界测试：ReplicatedStorage 里没有 meleeEvent 时，脚本应安全退出
local M = dofile("mock_roblox.lua")
local H = M.install()

H.melee.Parent = nil

local chunk = assert(loadfile("RangeAttack_Aura.lua"))
local ok, err = pcall(chunk)

local gui = H.find(H.playerGui, "RangeAuraGui")

if ok and gui == nil then
	print("  [PASS] 找不到 meleeEvent 时安全退出，没有残留界面")
	os.exit(0)
else
	print("  [FAIL] ok=" .. tostring(ok) .. " err=" .. tostring(err) .. " gui=" .. tostring(gui))
	os.exit(1)
end
