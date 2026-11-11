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

local function firesFor(target)
	local n = 0
	for _, f in ipairs(H.fires) do
		if f.target == target then n = n + 1 end
	end
	return n
end

local function gunFiresFor(part)
	local n = 0
	for _, f in ipairs(H.gunFires) do
		if f.part == part then n = n + 1 end
	end
	return n
end

local function dragTo(obj, sx, sy, ex, ey)
	obj.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(sx, sy, 0) })
	H.uis.InputChanged:Fire({ UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(ex, ey, 0) })
	H.uis.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(ex, ey, 0) })
end

print("== 1. 加载 ==")
local chunk = assert(loadfile("RangeAttack_Aura.lua"))
local ok, err = pcall(chunk)
check(ok, "脚本无报错加载", err)

local gui = H.find(H.playerGui, "RangeAuraGui")
check(gui ~= nil, "ScreenGui 已创建")

local panel = gui and H.find(gui, "Panel")
check(panel ~= nil and panel.Visible == true, "面板默认展开")
check(gui and H.find(gui, "ChipNpc") == nil, "NPC 开关已移除")

local fab = gui and H.find(gui, "Fab")
check(fab ~= nil, "悬浮球已创建")

local authorLabel = gui and H.find(gui, "Author")
check(authorLabel ~= nil and authorLabel.Text == "by kr X", "作者标签 = kr X", authorLabel and authorLabel.Text)

print("== 2. 悬浮球轻点 ==")
local function tap(obj, x, y)
	local pos = Vector3.new(x, y, 0)
	obj.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, Position = pos })
	H.uis.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch, Position = pos })
end

tap(fab, 1230, 330)
check(panel.Visible == false, "轻点收起面板")
tap(fab, 1230, 330)
check(panel.Visible == true, "再点展开面板")

print("== 3. 默认双发 + 10 格范围 ==")
local toggleBtn = H.find(gui, "MainToggle")
toggleBtn.MouseButton1Click:Fire()
H.fires = {}
H.gunFires = {}
step(1.0)

local p1head = H.p1.Character.Head
check(#H.gunFires > 0, "枪击包已发出", #H.gunFires)
check(#H.fires > 0, "近战包已发出", #H.fires)
check(gunFiresFor(p1head) == #H.gunFires, "枪击只打 10 格内的 p1", #H.gunFires)
check(firesFor(H.p1) == #H.fires, "近战只打 p1", #H.fires)
check(H.gunFires[1] ~= nil and H.gunFires[1].damage == 15, "默认枪伤 15", H.gunFires[1] and H.gunFires[1].damage)
check(H.fires[1] ~= nil and H.fires[1].b == 1, "近战第三参数与游戏一致（1）", H.fires[1] and H.fires[1].b)
check(H.ak.Parent == H.me.Character, "自动装备 AK-47", H.ak.Parent and H.ak.Parent.Name)

print("== 4. 枪伤滑条 ==")
local dmgHit = H.find(gui, "DamageHit")
dmgHit.AbsolutePosition = Vector2.new(100, 300)
dmgHit.AbsoluteSize = Vector2.new(200, 32)
dragTo(dmgHit, 300, 310, 300, 310)
H.gunFires = {}
step(0.3)
check(H.gunFires[1] and H.gunFires[1].damage == 300, "拉满 = 300", H.gunFires[1] and H.gunFires[1].damage)
dragTo(dmgHit, 100, 310, 100, 310)
H.gunFires = {}
step(0.3)
check(H.gunFires[1] and H.gunFires[1].damage == 1, "拉到底 = 1", H.gunFires[1] and H.gunFires[1].damage)

print("== 5. 自动换弹 ==")
H.reloads = 0
step(2.6)
check(H.reloads >= 1, "定时换弹", H.reloads)

print("== 6. 模式切换 ==")
H.find(gui, "ModeGun").MouseButton1Click:Fire()
H.fires = {}
H.gunFires = {}
step(0.5)
check(#H.fires == 0 and #H.gunFires > 0, "枪击模式只发枪包", #H.fires)

H.find(gui, "ModeMelee").MouseButton1Click:Fire()
H.fires = {}
H.gunFires = {}
step(0.5)
check(#H.gunFires == 0 and #H.fires > 0, "近战模式只发近战包", #H.gunFires)

print("== 7. 遮挡过滤 ==")
H.rayBlocked = true
H.fires = {}
step(0.5)
check(#H.fires == 0, "被墙挡住的目标跳过", #H.fires)

H.find(gui, "ChipSight").MouseButton1Click:Fire()
H.fires = {}
step(0.5)
check(#H.fires > 0, "关掉遮挡后照打", #H.fires)
H.rayBlocked = false
H.find(gui, "ChipSight").MouseButton1Click:Fire()

print("== 8. 目标选择 ==")
local rangeHit = H.find(gui, "RangeHit")
rangeHit.AbsolutePosition = Vector2.new(100, 200)
rangeHit.AbsoluteSize = Vector2.new(200, 32)
dragTo(rangeHit, 300, 210, 300, 210)

H.find(gui, "TargetBtn").MouseButton1Click:Fire()
local targetPanel = H.find(gui, "TargetPanel")
check(targetPanel ~= nil and targetPanel.Visible == true, "目标面板已打开", targetPanel and targetPanel.Visible)

local row1 = targetPanel and H.find(targetPanel, "T_Enemy1")
check(row1 ~= nil, "列表里有 Enemy1")
if row1 then
	row1.MouseButton1Click:Fire()
end

H.fires = {}
step(0.6)
check(firesFor(H.p1) > 0, "只选中的 p1 被打", firesFor(H.p1))
check(firesFor(H.p2) == 0, "没选中的 p2 不打", firesFor(H.p2))

local allBtn = H.find(targetPanel, "TargetAll")
allBtn.MouseButton1Click:Fire()
H.fires = {}
step(0.6)
check(firesFor(H.p2) > 0, "全选后 p2 也打", firesFor(H.p2))

local noneBtn = H.find(targetPanel, "TargetNone")
noneBtn.MouseButton1Click:Fire()
H.fires = {}
step(0.6)
check(firesFor(H.p2) > 0, "清空后恢复全员", firesFor(H.p2))

H.find(targetPanel, "TargetClose").MouseButton1Click:Fire()
check(targetPanel.Visible == false, "目标面板可关闭")

print("== 9. 伤害统计 ==")
H.p1.Character.Humanoid.Health = 40
step(0.2)
local s2 = H.find(gui, "Status2")
check(s2 ~= nil and string.find(s2.Text, "伤害 [1-9]") ~= nil, "血量下降计入伤害", s2 and s2.Text)
check(s2 ~= nil and string.find(s2.Text, "有效") ~= nil, "显示有效距离", s2 and s2.Text)

print("== 10. 范围滑条 ==")
dragTo(rangeHit, 100, 210, 100, 210)
H.fires = {}
step(0.6)
check(#H.fires == 0, "范围 4 时脱靶", #H.fires)
dragTo(rangeHit, 300, 210, 300, 210)
H.fires = {}
step(0.6)
check(#H.fires > 0, "范围拉回后恢复", #H.fires)

print("== 11. 队友与守卫 ==")
local chipTeam = H.find(gui, "ChipTeam")
chipTeam.MouseButton1Click:Fire()
H.fires = {}
step(0.6)
check(firesFor(H.p3) == 0, "守卫之间关过滤也不打", firesFor(H.p3))

chipTeam.MouseButton1Click:Fire()
H.me.Team = H.teams.Inmates
H.fires = {}
step(0.6)
check(firesFor(H.p1) == 0, "同队囚犯被过滤", firesFor(H.p1))
chipTeam.MouseButton1Click:Fire()
H.fires = {}
step(0.6)
check(firesFor(H.p1) > 0, "关过滤后同队能打", firesFor(H.p1))

print("== 12. 拖动 ==")
local dragArea = H.find(gui, "DragArea")
panel.AbsolutePosition = Vector2.new(490, 96)
panel.AbsoluteSize = Vector2.new(330, 458)
local beforeX = panel.Position.X.Offset
dragTo(dragArea, 500, 150, 566, 194)
local scale = 1.1
check(math.abs(panel.Position.X.Offset - (beforeX + 66 / scale)) < 0.01, "面板位移按缩放折算", panel.Position.X.Offset - beforeX)

fab.AbsolutePosition = Vector2.new(1200, 300)
fab.AbsoluteSize = Vector2.new(59.4, 59.4)
local fabBeforeY = fab.Position.Y.Offset
dragTo(fab, 1200, 400, 1170, 440)
check(math.abs(fab.Position.Y.Offset - (fabBeforeY + 40 / scale)) < 0.01, "悬浮球跟随手指", fab.Position.Y.Offset)

print("== 13. 重生 ==")
local newMe = H.makePlayer("Me2", H.teams.Guards, Vector3.new(500, 0, 0))
H.me.Character = newMe.Character
H.me.CharacterAdded:Fire(newMe.Character)
H.fires = {}
step(0.5)
check(#H.fires == 0, "旧位置脱靶", #H.fires)
H.p1.Character.HumanoidRootPart.Position = Vector3.new(500, 0, 8)
H.p1.Character.Head.Position = Vector3.new(500, 1.5, 8)
H.fires = {}
step(0.8)
check(firesFor(H.p1) > 0, "新位置命中", firesFor(H.p1))

print("== 14. 多目标吞吐 ==")
for i = 1, 8 do
	local p = H.makePlayer("Crowd" .. i, H.teams.Inmates, Vector3.new(500 + i, 0, 4))
	H.players[#H.players + 1] = p
	H["crowd" .. i] = p
end
H.fires = {}
step(2.0)
check(#H.fires <= 42, "全局限流", #H.fires)
check(#H.fires >= 24, "持续输出", #H.fires)
local each = 0
for i = 1, 8 do
	if firesFor(H["crowd" .. i]) >= 2 then each = each + 1 end
end
check(each == 8, "8 个目标轮转", each)

print("== 15. 无队伍 ==")
for i = 1, 8 do
	H["crowd" .. i].Character.Humanoid.Health = 0
end
H.me.Team = nil
H.p1.Team = nil
H.fires = {}
step(0.8)
check(firesFor(H.p1) > 0, "无队伍照常攻击", firesFor(H.p1))

print("== 16. 关闭与卸载 ==")
toggleBtn.MouseButton1Click:Fire()
H.fires = {}
H.gunFires = {}
step(0.5)
check(#H.fires == 0 and #H.gunFires == 0, "关闭后停止", #H.fires + #H.gunFires)

local api = _G.__RANGE_AURA
api.destroy()
check(H.find(H.playerGui, "RangeAuraGui") == nil, "GUI 已销毁")
check(H.workspace:FindFirstChild("RangeAuraRing") == nil, "范围圈已销毁")
H.fires = {}
step(0.5)
check(#H.fires == 0, "卸载后不再发包", #H.fires)

print(string.format("\n结果: %d 通过 / %d 失败", pass, fail))
if fail > 0 then
	os.exit(1)
end
