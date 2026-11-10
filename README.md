# PbzRemotePickup · 远程拾取

《影之刃零》(Phantom Blade Zero) 的 UE4SS Lua mod：按一个键，就能拾取一定范围内最近的普通道具（材料、消耗品），不用每次都走过去。

[English](#english)

## 功能

- 按拾取键拾取范围内最近的一个可拾取道具；也可以设置成按一次就依次拾取范围内全部道具。
- 拾取键可以绑定到键盘（支持 Alt/Shift 组合键，Ctrl 被游戏占用）、鼠标（包括侧键）或手柄（支持组合键）。
- 拾取走的是游戏自己的拾取逻辑，会正常写入存档。
- 游戏暂停或菜单打开时不会触发。
- 不需要任何设置界面也能调整：快捷键切换拾取范围、开关“跳过装备”，屏幕上方会显示两秒提示。
- 以下物品**不会**被远程拾取：
  - 已拾取的、隐藏的物品（隐藏物品通常要等剧情条件满足才出现）；
  - 任务物品（物品 ID 以 `K_` / `I_` 开头）；
  - 剧情物品：挂了剧情流程标记、拾取时会添加剧情标签或会触发任务的拾取物；
  - 武器、饰品等装备（默认开启，可关闭）。只有已知格式的材料和消耗品会被拾取，例如 `Weapon_Material_*`、`R_*`、`Item_*`、掉落表物品等。

## 为什么要跳过剧情物品和装备

有些武器的拾取本身就是剧情事件。比如溪谷的第一把双刀：在剧情走到那一步之前被远程拾取的话，拾取事件不会触发，后面的教程和楼梯交互会一直卡住，只能改存档修复。另外，梦魇周目里拾取装备会让你已有的同名装备 +1。所以装备请走过去手动拾取。

## 依赖

- 已安装 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)，并且能加载 Lua mod。开发时用的是 UE4SS v3.0.1 Beta。
- 可选：**模组配置菜单**（PbzModConfig，作者 皮一下就很凡@Bilibili）。装好并启用后，设置会出现在游戏的「设置 → 模组 → 远程拾取」页面里。本 mod **不包含**它的任何文件，只在它启用时，从它自己的目录（`ue4ss/Mods/PbzModConfig/Scripts`）加载。没装或停用时也能正常用：用快捷键调整，或者改 `settings.json`。

开发和测试用的游戏版本：Steam 构建 26367565。游戏更新后可能失效。

## 安装

1. 退出游戏，**先备份存档**（`ProjectPBZ/Saved/SaveGames`）。
2. 把本仓库放到 `<游戏目录>/platform/steam/ue4ss/Mods/PbzRemotePickup/`。从 GitHub 下载 ZIP 时，解压出来的文件夹名是 `PbzRemotePickup-main`，要改名为 `PbzRemotePickup`。目录结构如下：
   ```
   Mods/PbzRemotePickup/
     enabled.txt
     Scripts/main.lua
   ```
3. 启动游戏。在 `UE4SS.log` 里看到 `[PbzRemotePickup] loaded v0.10 ...` 就说明加载成功了。

卸载：删除 `Mods/PbzRemotePickup` 文件夹即可。

## 快捷键

| 功能 | 键盘默认 | 手柄 |
|---|---|---|
| 拾取 | `O` | 默认不绑定 |
| 切换拾取范围（25 → 50 → 100 → 150 → 200 米循环） | `P` | 默认不绑定，可设组合键 |
| 开关“跳过装备” | `L` | 默认不绑定，可设组合键 |

手柄组合键写在 `settings.json` 里，用 `+` 连接，例如 `"rangeGamepad":"Gamepad_LeftShoulder+Gamepad_DPad_Up"`（按住 LB 再按十字键上）。前面的键要按住，最后一个键按下时触发。多个绑定同时满足时，键数多的组合优先，所以 LB+R3 不会同时触发只绑了 R3 的拾取。

## 设置

第一次修改设置后，会在 mod 目录下生成 `settings.json`。没装模组配置菜单的话，可以先退出游戏，手动创建或编辑这个文件：

```json
{"equipGamepad":"","equipKey":"L","onePerPress":true,"pickupGamepad":"","pickupKey":"O","radiusM":50,"rangeGamepad":"","rangeKey":"P","showToast":true,"skipEquipment":true,"skipHidden":true}
```

| 键 | 说明 | 默认 |
|---|---|---|
| `pickupKey` | 键盘或鼠标拾取键，填 UE 的按键名，可加 `Alt+` / `Shift+` 前缀，例如 `O`、`Alt+O`、`ThumbMouseButton`（鼠标侧键）。Ctrl 被游戏占用，不建议使用。填 `""` 表示不绑定 | `O` |
| `pickupGamepad` | 手柄拾取键，填 UE 的 `Gamepad_*` 按键名，例如 `Gamepad_LeftShoulder`。填 `""` 表示不绑定 | `""` |
| `radiusM` | 拾取范围（米），5–200 | `50` |
| `onePerPress` | 每按一次只拾取一个 | `true` |
| `skipHidden` | 跳过隐藏道具 | `true` |
| `skipEquipment` | 跳过武器、饰品等装备 | `true` |
| `rangeKey` / `rangeGamepad` | 切换拾取范围的键盘键 / 手柄键（手柄可用组合键） | `P` / `""` |
| `equipKey` / `equipGamepad` | 开关“跳过装备”的键盘键 / 手柄键（手柄可用组合键） | `L` / `""` |
| `showToast` | 用快捷键改设置时在屏幕上显示提示 | `true` |

手柄背键：UE 没有给背键单独的键名。游戏能识别的话可以直接绑定；识别不了，就先在 Steam 输入里把背键映射成一个空闲的手柄键，再绑定那个键。

## 排查问题

所有日志都写在 `UE4SS.log` 里，前缀是 `[PbzRemotePickup]`：
- `skip <物体> ... : <原因>`：这个物品被跳过了，后面写着原因。如果某种材料被误判成 `equipment / unknown item <ID>`，欢迎提 issue 并附上这个 ID。
- `PICKED` / `FAILED`：拾取成功或失败。如果失败后又出现一行 `LATE`，说明其实延迟拾取成功了。
- `toast: ...`：快捷键改了设置。如果后面跟着 `on-screen message unavailable`，说明屏幕提示显示失败，但设置已经改好了；连续失败 3 次后，本次游戏不再尝试显示提示。
- `struct ...: id fields [...]`：读取拾取物结构体时的诊断信息，提 issue 时请一并附上。

## 已知限制

- 只能拾取当前已加载区域内的道具，太远的区域游戏还没加载，范围调到 200 米也捡不到。
- 剧情物品和装备是按规则判断的，不能保证覆盖所有情况。拿不准的物品请走过去手动拾取。
- 少数道具的拾取要过几秒才完成，日志里会先出现 `FAILED`，随后出现 `LATE`，这属于正常现象。
- 屏幕提示借用了游戏自带的一个界面控件来显示，游戏更新后可能失效；失效时设置照样会改好，只是不再显示提示。

## 免责声明

非官方 mod，与游戏开发商无关。使用前请备份存档，后果自负。

## 许可证

[MIT](LICENSE)

---

## English

UE4SS Lua mod for Phantom Blade Zero. Press a key to pick up the nearest regular item (materials, consumables) within range without walking to it.

- Bindable to keyboard (Alt/Shift combos; Ctrl is used by the game), mouse (including side buttons) or gamepad (chords supported). Doesn't fire while paused or in menus.
- Works without any settings UI: `P` cycles the range (25/50/100/150/200 m) and `L` toggles "skip equipment", each with a short on-screen message. Gamepad chords such as `Gamepad_LeftShoulder+Gamepad_DPad_Up` can be set in `settings.json` (`rangeGamepad`, `equipGamepad`).
- Uses the game's own pickup path, so pickups are saved normally.
- Never picks up: items already taken or hidden, quest items (`K_*` / `I_*`), story-scripted pickups, and (by default) equipment. Only known material / consumable IDs are taken. Some weapon pickups are story events: the first dual blades in Xigu, if taken early, block the following tutorial and stairs. In Nightmare runs, picking up equipment also raises the copy you own by +1.
- Requires UE4SS with Lua mods enabled (developed on UE4SS v3.0.1 Beta, Steam build 26367565). The **PbzModConfig** mod is optional: if installed and enabled, settings appear under Settings → Mods. None of its files are bundled; they're loaded from its own folder at runtime, only while it is enabled. Without it, edit `settings.json` (keys in the table above).
- Install: back up your saves, put this repo at `platform/steam/ue4ss/Mods/PbzRemotePickup/` (rename `PbzRemotePickup-main` if you downloaded the ZIP), then start the game and look for `loaded v0.10` in `UE4SS.log`.
- Limits: only items in currently loaded areas; the story / equipment filters are rule-based and may miss cases; some pickups finish a few seconds late (`FAILED` then `LATE` in the log).
- Unofficial, not affiliated with the developer. Back up your saves. MIT licensed.
