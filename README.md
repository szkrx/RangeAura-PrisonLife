# RangeAura · Prison Life 范围攻击

作者：**kr X** ｜ 纯客户端 Roblox Lua ｜ 手机 / PC 双端 ｜ 适配 **Prison Life**

不开枪也能自动打人：按设定半径扫描附近玩家，把**近战命中**和**枪械命中**同时发给目标，范围、攻速、伤害全部实时可调。

```
[ 已关闭 · 点击开启 ]
[ 枪击 ][ 近战 ][ 双发 ]
[ 目标：全部 ]
范围（格）            10 格
攻速（次/秒）         10 次
枪伤（AK-47 默认 15） 15
[队友][遮挡][范围圈]
运行中 · 目标 3 · 发包 128
伤害 1280 · 有效 11 格
```

## 功能

- **三种模式**：枪击（`GunRemotes.ShootEvent`）/ 近战（`meleeEvent`）/ 双发（两条包一起走）
- **伤害可调**：1~300，默认 15 与 AK-47 面板值一致
- **范围可调**：4~60 格，默认 10 格
- **攻速可调**：2~20 次/秒，全局令牌桶限流 20 包/秒
- **目标选择**：名单勾选，只打指定玩家，支持全选 / 清空，玩家进出自动刷新
- **遮挡过滤**：射线打不通的目标直接跳过，不发废包
- **自动装备**：按 `AK-47 → M4A1 → FAL → MP5 → M9 → M700 → 870 → Revolver` 优先级装枪
- **自动换弹**：每 2.5 秒 `FuncReload`
- **伤害统计**：累计掉血量 + 实测有效距离，直接看出打没打中
- **手机适配**：悬浮球 + 可拖面板 + 触摸滑条，按视口自动缩放 0.62~1.1
- **纯客户端**：不修改服务端、不写入游戏数据

## 快速开始

1. 注入器整段执行 `RangeAttack_Aura.lua`
2. 右侧圆形悬浮球「范」，轻点展开面板（默认已展开）
3. 点「已关闭 · 点击开启」
4. 拖 `范围` / `攻速` / `枪伤` 调手感
5. 点 `目标：全部` 可以只打指定玩家

悬浮球可拖动，轻点（位移 < 6px）才是开关面板；重复执行脚本会先销毁上一份，不会叠界面。

## 三种模式

| 模式 | 发送内容 | 适用 |
|---|---|---|
| 枪击 | `ShootEvent:FireServer(Head, 伤害)` | 服务端吃客户端伤害值 |
| 近战 | `meleeEvent:FireServer(玩家, 1, 1)` | 与游戏自身调用完全一致 |
| 双发 | 上面两条都发 | 默认，任一条通了就有伤害 |

## 攻击对象

1. 点 `目标：全部` 打开名单
2. 点名字切换：`✓` 打 / 空白 不打
3. `全选` / `清空` 批量操作
4. 选了人按钮变 `目标：2 人`；全部取消就恢复打所有人

## 配置项

脚本顶部 `CFG`：

| 字段 | 默认 | 说明 |
|---|---|---|
| `radius` | 10 | 起始范围（格） |
| `rate` | 10 | 每目标每秒次数 |
| `damage` | 15 | 枪伤 |
| `mode` | `both` | `gun` / `melee` / `both` |
| `teamFilter` | true | 是否过滤同队 |
| `occlusion` | true | 是否跳过被遮挡目标 |
| `showRing` | true | 地面范围圈 |
| `autoEquip` | true | 自动装枪 |
| `anim` | true | 本地出拳动画/音效 |
| `gunArgMode` | `part_damage` | 枪械参数布局 |

`gunArgMode` 可选：

| 值 | 实际发送 |
|---|---|
| `part_damage` | `FireServer(部件, 伤害)` |
| `hum_damage` | `FireServer(Humanoid, 伤害)` |
| `part` | `FireServer(部件)` |
| `part_damage_alt` | `FireServer(伤害, 部件)` |

## 常见问题

**Q：`发包` 一直涨，`伤害` 不动？**
A：服务端没吃你这一路。先确认枪已装上（面板目标数正常），再把 `gunArgMode` 换一个值试；四个都不行说明服务端自己算伤害，此时把 `遮挡` 打开、范围压到 `有效` 值附近，靠攻速堆输出。

**Q：`有效` 是什么？**
A：实测打出过伤害的最大距离。范围贴着它 +2 格，命中率最高。

**Q：为什么默认只有 10 格？**
A：服务端近战/枪械判定通常 8~12 格，范围开大只会稀释命中率。

**Q：会不会和游戏自带出拳冲突？**
A：不会。脚本走 Remote 通道，不占用鼠标/触摸输入。

## 目录

```
RangeAttack_Aura.lua   主脚本（单文件，无依赖）
使用说明.md            面板与参数详解
README.md              本文件
CHANGELOG.md           版本记录
LICENSE                MIT
mock_roblox.lua        本地测试用的 Roblox 运行时模拟器
test.lua               主流程回归（48 条）
test_nogun.lua         缺 GunRemotes 时的退化测试（5 条）
test_missing.lua       缺 meleeEvent 时的退出测试（1 条）
```

## 测试

```bash
npm i fengari-node-cli luaparse
node node_modules/fengari-node-cli/src/lua-cli.js test.lua
node node_modules/fengari-node-cli/src/lua-cli.js test_nogun.lua
node node_modules/fengari-node-cli/src/lua-cli.js test_missing.lua
```

主流程 48 条 + 边缘 6 条，全过。

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 许可

MIT © kr X
