# PbzRemotePickup

[English](README.md) | **简体中文**

《影之刃零》(Phantom Blade Zero) 的 UE4SS Lua mod，用于远程拾取附近的道具。每按一次拾取键，即可拾取设定范围内最近的一个符合条件的道具（材料与消耗品），无需移动到道具旁边。

## 功能

- 每次按键拾取范围内最近的一个符合条件的道具；也可设置为一次按键依次拾取范围内全部符合条件的道具。
- 拾取通过游戏自身的交互逻辑完成，并按正常方式记录到存档中。
- 拾取键可绑定到键盘（支持 Alt、Shift 组合键）、鼠标（含侧键）或手柄（支持组合键）。
- 游戏暂停或菜单占用输入时不会触发。
- 自带游戏内设置界面（默认 `F8`），可用键盘、鼠标或手柄修改全部设置，包括所有按键绑定。该界面是本 mod 的一部分，不依赖其他 mod。
- 提供切换拾取范围和开关装备过滤的快捷键，不打开界面也能调整；每次更改都会在屏幕上显示简短提示（中文或英文，默认跟随游戏语言）。
- 以下物品不会被远程拾取：
  - 已拾取或当前处于隐藏状态的物品；
  - 任务物品（物品 ID 以 `K_` 或 `I_` 开头）；
  - 与剧情事件关联的物品，即带有剧情流程标签、拾取时会添加剧情标签或会触发任务的拾取物；
  - 武器、饰品等装备（默认启用，可关闭）。启用该过滤时，仅拾取 ID 符合已知材料与消耗品格式的物品，例如 `Weapon_Material_*`、`R_*`、`Item_*` 以及掉落表物品。

## 依赖

- 已安装并支持 Lua mod 的 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)。本 mod 基于 UE4SS v3.0.1 Beta 开发。
- 可选：**模组配置菜单**（PbzModConfig，作者：皮一下就很凡@Bilibili）。安装并启用后，本 mod 的设置将显示在游戏的「设置 → 模组 → 远程拾取」页面中。本 mod 不包含其任何文件，仅在其启用时从其自身目录（`ue4ss/Mods/PbzModConfig/Scripts`）加载。它不是必需的：无论是否安装，本 mod 自带的设置界面都可使用。

开发与测试所用的游戏版本为 Steam 构建 26367565，游戏更新可能影响兼容性。

## 安装

1. 退出游戏，并**备份存档**（`ProjectPBZ/Saved/SaveGames`）。
2. 将本仓库的内容放入 `<游戏目录>/platform/steam/ue4ss/Mods/PbzRemotePickup/`。从 GitHub 下载的 ZIP 解压后文件夹名为 `PbzRemotePickup-main`，需重命名为 `PbzRemotePickup`。目录结构如下：
   ```
   Mods/PbzRemotePickup/
     enabled.txt
     Scripts/main.lua
     Scripts/SettingsUI.lua
   ```
   `tests` 文件夹仅用于开发，可以不放入。
3. 启动游戏。`UE4SS.log` 中出现 `[PbzRemotePickup] loaded v0.11 ...` 即表示加载成功。

卸载时，删除 `Mods/PbzRemotePickup` 文件夹即可。

## 操作

| 功能 | 键盘（默认） | 手柄 |
|---|---|---|
| 拾取 | `O` | 默认未绑定 |
| 切换拾取范围（25 → 50 → 100 → 150 → 200 米） | `P` | 默认未绑定，支持组合键 |
| 开关"跳过装备" | `L` | 默认未绑定，支持组合键 |
| 打开 / 关闭设置界面 | `F8` | 默认未绑定，支持组合键 |

所有绑定均可在设置界面中修改。手柄组合键可在界面中同时按住几个键来绑定，也可写入 `settings.json`，各键名之间以 `+` 连接，例如 `"rangeGamepad":"Gamepad_LeftShoulder+Gamepad_DPad_Up"`（按住 LB 后按十字键上）。除最后一个键外，其余键均需保持按住，按下最后一个键时触发。多个绑定同时满足时，以按键数量最多的绑定为准，因此按下 LB+R3 时不会同时触发仅绑定 R3 的拾取。

## 设置界面

在游戏过程中按 `F8` 打开界面。界面打开期间游戏暂停，远程拾取和其他快捷键均不会触发；游戏已暂停或游戏菜单占用输入时，界面不会打开。更改在关闭界面时生效，并写入 `settings.json`。

| | 键盘 / 鼠标 | 手柄 |
|---|---|---|
| 选择一行 | 方向键或 `W` / `S`；鼠标移到该行上 | 十字键或左摇杆 |
| 调整数值 | 方向键或 `A` / `D`；左键增加，右键减少 | 十字键或左摇杆 |
| 确认（切换开关、开始绑定按键、执行操作） | `Enter`、空格或鼠标左键 | `A` |
| 清除绑定 | `Delete` 或鼠标右键 | `X` |
| 保存并关闭 | `Esc`、退格键或界面热键 | `B` 或界面热键 |

绑定按键：选中该行并确认，然后按下要绑定的键。

- 键盘 / 鼠标项可绑定任意按键或鼠标键（含侧键）。先按住 `Alt` 或 `Shift` 可绑定组合键（`Ctrl` 已被游戏占用，不建议使用）。按 `Esc` 取消。
- 手柄项可绑定单个键，或最多三个键的组合键：同时按住后松开即可，最后按下的那个键为触发键。按键盘 `Esc` 取消，数秒内不按键也会取消。
- 若某个绑定已被其他项使用，该项的绑定会被解除。界面会始终保留至少一个可打开界面的绑定。

“全部恢复默认”需连续确认两次。界面的手柄热键建议绑定为组合键（例如按住 LB 再按下左摇杆），单个键在战斗中容易误触。

## 设置

首次更改设置后，mod 文件夹中会生成 `settings.json`。全部设置均可在设置界面中修改；也可在游戏未运行时手动创建或编辑该文件：

```json
{"equipGamepad":"","equipKey":"L","menuGamepad":"","menuKey":"F8","onePerPress":true,"pickupGamepad":"","pickupKey":"O","radiusM":50,"rangeGamepad":"","rangeKey":"P","showToast":true,"skipEquipment":true,"skipHidden":true,"toastLanguage":"auto"}
```

| 键 | 说明 | 默认值 |
|---|---|---|
| `pickupKey` | 键盘或鼠标拾取键，填写 UE 按键名，可加 `Alt+` 或 `Shift+` 前缀，例如 `O`、`Alt+O`、`ThumbMouseButton`（鼠标侧键）。Ctrl 已被游戏占用，不建议使用。填写 `""` 表示不绑定。 | `O` |
| `pickupGamepad` | 手柄拾取键，填写 UE 的 `Gamepad_*` 按键名，例如 `Gamepad_LeftShoulder`。填写 `""` 表示不绑定。 | `""` |
| `radiusM` | 拾取范围（米），取值 5–200。 | `50` |
| `onePerPress` | 每次按键仅拾取一个道具。 | `true` |
| `skipHidden` | 跳过隐藏道具。 | `true` |
| `skipEquipment` | 跳过武器、饰品等装备。 | `true` |
| `rangeKey` / `rangeGamepad` | 切换拾取范围的键盘键 / 手柄绑定（手柄支持组合键）。 | `P` / `""` |
| `equipKey` / `equipGamepad` | 开关"跳过装备"的键盘键 / 手柄绑定（手柄支持组合键）。 | `L` / `""` |
| `showToast` | 通过快捷键更改设置时显示屏幕提示。 | `true` |
| `toastLanguage` | 屏幕提示和设置界面的语言：`auto`（游戏语言为中文时显示中文，否则显示英文）、`en` 或 `zh-Hans`。 | `auto` |
| `menuKey` / `menuGamepad` | 打开和关闭设置界面的键盘键 / 手柄绑定（手柄支持组合键）。两者均为空时，`menuKey` 恢复为 `F8`。 | `F8` / `""` |

手柄背键：虚幻引擎没有为背键定义专用的键名。若游戏能够识别背键，可直接绑定；否则，请先在 Steam 输入中将背键映射为一个未使用的手柄按键，再绑定该按键。

## 故障排查

所有信息均写入 `UE4SS.log`，前缀为 `[PbzRemotePickup]`：

- `skip <物体> ... : <原因>`：该物品已被跳过，后附原因。若某种材料被判定为 `equipment / unknown item <ID>`，请提交 issue 并附上该 ID。
- `PICKED` / `FAILED`：拾取结果。若随后出现 `LATE`，表示拾取在延迟后完成。
- `toast: ...`：快捷键更改了设置。若随后出现 `on-screen message unavailable`，表示屏幕提示未能显示，但设置已经生效；连续失败三次后，本次游戏中将不再显示屏幕提示。
- `game culture: ...`：`toastLanguage` 为 `auto` 时检测到的游戏语言。若检测失败，提示将以英文显示，此时请手动设置 `toastLanguage`。
- `settings panel opened` / `settings panel closed (...)` / `settings saved from the panel: ...`：设置界面的打开、关闭与保存，最后一行列出保存后的全部设置。
- `settings panel unavailable: <步骤>: <原因>` 或 `settings panel not opened: ...`：界面未能建立，通常发生在游戏更新之后。快捷键和 `settings.json` 仍可使用。连续失败三次后，本次游戏中不再尝试打开界面。
- `input block: ...`：界面打开期间如何让游戏不响应按键（暂停游戏；若游戏拒绝暂停，则改为关闭角色输入），以及何时恢复。
- `struct ...: id fields [...]`：读取拾取物数据中物品 ID 时的诊断信息，提交 issue 时请一并附上。

## 已知限制

- 仅能拾取当前已加载区域内的道具。游戏尚未加载的区域，即使范围设为最大值 200 米也无法拾取。
- 剧情物品与装备依据规则识别，无法保证覆盖所有情况。对于无法确定的物品，请手动拾取。
- 部分道具的拾取会在数秒后才完成，此时日志中会先出现 `FAILED`，随后出现 `LATE`，属于正常现象。
- 屏幕提示和设置界面借助游戏自带的界面控件显示，游戏更新后可能失效。届时设置仍会正常生效，`settings.json` 和快捷键仍可使用。
- 设置界面通过轮询读取按键，极短的一次点按偶尔可能漏掉，再按一次即可。
- 设置界面的文字使用游戏当前正在显示的字体，提供简体中文和英文。

## 开发

`Scripts/SettingsUI.lua` 可脱离游戏测试：`tests/` 中有一个 UE4SS 环境的简易替身，菜单逻辑在其上运行。使用任意 Lua 5.4 解释器，在仓库根目录执行：

```
lua tests/test_settings_ui.lua
lua tests/test_main_panel.lua
```

## 免责声明

本 mod 为非官方作品，与游戏开发商无关。使用前请备份存档，风险由使用者自行承担。

## 许可证

[MIT](LICENSE)
