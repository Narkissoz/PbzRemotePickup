# PbzRemotePickup

[English](README.md) | **简体中文**

《影之刃零》(Phantom Blade Zero) 的 UE4SS Lua mod，用于远程拾取附近的道具。每按一次拾取键，即可拾取设定范围内最近的一个符合条件的道具（材料与消耗品），无需移动到道具旁边。

## 功能

- 每次按键拾取范围内最近的一个符合条件的道具；也可设置为一次按键依次拾取范围内全部符合条件的道具。
- 拾取通过游戏自身的交互逻辑完成，并按正常方式记录到存档中。
- 拾取键可绑定到键盘（支持 Alt、Shift 组合键）、鼠标（含侧键）或手柄（支持组合键）。
- 游戏暂停或菜单占用输入时不会触发。
- 提供切换拾取范围和开关装备过滤的快捷键，每次更改都会在屏幕上显示简短提示（中文或英文，默认跟随游戏语言），无需设置菜单即可调整。
- 以下物品不会被远程拾取：
  - 已拾取或当前处于隐藏状态的物品；
  - 任务物品（物品 ID 以 `K_` 或 `I_` 开头）；
  - 与剧情事件关联的物品，即带有剧情流程标签、拾取时会添加剧情标签或会触发任务的拾取物；
  - 武器、饰品等装备（默认启用，可关闭）。启用该过滤时，仅拾取 ID 符合已知材料与消耗品格式的物品，例如 `Weapon_Material_*`、`R_*`、`Item_*` 以及掉落表物品。

## 依赖

- 已安装并支持 Lua mod 的 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)。本 mod 基于 UE4SS v3.0.1 Beta 开发。
- 可选：**模组配置菜单**（PbzModConfig，作者：皮一下就很凡@Bilibili）。安装并启用后，本 mod 的设置将显示在游戏的「设置 → 模组 → 远程拾取」页面中。本 mod 不包含其任何文件，仅在其启用时从其自身目录（`ue4ss/Mods/PbzModConfig/Scripts`）加载。未安装时，可通过快捷键或 `settings.json` 调整设置。

开发与测试所用的游戏版本为 Steam 构建 26367565，游戏更新可能影响兼容性。

## 安装

1. 退出游戏，并**备份存档**（`ProjectPBZ/Saved/SaveGames`）。
2. 将本仓库的内容放入 `<游戏目录>/platform/steam/ue4ss/Mods/PbzRemotePickup/`。从 GitHub 下载的 ZIP 解压后文件夹名为 `PbzRemotePickup-main`，需重命名为 `PbzRemotePickup`。目录结构如下：
   ```
   Mods/PbzRemotePickup/
     enabled.txt
     Scripts/main.lua
   ```
3. 启动游戏。`UE4SS.log` 中出现 `[PbzRemotePickup] loaded v0.10 ...` 即表示加载成功。

卸载时，删除 `Mods/PbzRemotePickup` 文件夹即可。

## 操作

| 功能 | 键盘（默认） | 手柄 |
|---|---|---|
| 拾取 | `O` | 默认未绑定 |
| 切换拾取范围（25 → 50 → 100 → 150 → 200 米） | `P` | 默认未绑定，支持组合键 |
| 开关"跳过装备" | `L` | 默认未绑定，支持组合键 |

手柄组合键在 `settings.json` 中设置，各键名之间以 `+` 连接，例如 `"rangeGamepad":"Gamepad_LeftShoulder+Gamepad_DPad_Up"`（按住 LB 后按十字键上）。除最后一个键外，其余键均需保持按住，按下最后一个键时触发。多个绑定同时满足时，以按键数量最多的绑定为准，因此按下 LB+R3 时不会同时触发仅绑定 R3 的拾取。

## 设置

首次更改设置后，mod 文件夹中会生成 `settings.json`。未安装模组配置菜单时，也可在游戏未运行时手动创建或编辑该文件：

```json
{"equipGamepad":"","equipKey":"L","onePerPress":true,"pickupGamepad":"","pickupKey":"O","radiusM":50,"rangeGamepad":"","rangeKey":"P","showToast":true,"skipEquipment":true,"skipHidden":true,"toastLanguage":"auto"}
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
| `toastLanguage` | 屏幕提示的语言：`auto`（游戏语言为中文时显示中文，否则显示英文）、`en` 或 `zh-Hans`。 | `auto` |

手柄背键：虚幻引擎没有为背键定义专用的键名。若游戏能够识别背键，可直接绑定；否则，请先在 Steam 输入中将背键映射为一个未使用的手柄按键，再绑定该按键。

## 故障排查

所有信息均写入 `UE4SS.log`，前缀为 `[PbzRemotePickup]`：

- `skip <物体> ... : <原因>`：该物品已被跳过，后附原因。若某种材料被判定为 `equipment / unknown item <ID>`，请提交 issue 并附上该 ID。
- `PICKED` / `FAILED`：拾取结果。若随后出现 `LATE`，表示拾取在延迟后完成。
- `toast: ...`：快捷键更改了设置。若随后出现 `on-screen message unavailable`，表示屏幕提示未能显示，但设置已经生效；连续失败三次后，本次游戏中将不再显示屏幕提示。
- `game culture: ...`：`toastLanguage` 为 `auto` 时检测到的游戏语言。若检测失败，提示将以英文显示，此时请手动设置 `toastLanguage`。
- `struct ...: id fields [...]`：读取拾取物数据中物品 ID 时的诊断信息，提交 issue 时请一并附上。

## 已知限制

- 仅能拾取当前已加载区域内的道具。游戏尚未加载的区域，即使范围设为最大值 200 米也无法拾取。
- 剧情物品与装备依据规则识别，无法保证覆盖所有情况。对于无法确定的物品，请手动拾取。
- 部分道具的拾取会在数秒后才完成，此时日志中会先出现 `FAILED`，随后出现 `LATE`，属于正常现象。
- 屏幕提示借助游戏自带的界面控件显示，游戏更新后可能失效。届时设置仍会正常生效，仅不再显示提示。

## 免责声明

本 mod 为非官方作品，与游戏开发商无关。使用前请备份存档，风险由使用者自行承担。

## 许可证

[MIT](LICENSE)
