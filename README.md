# PbzRemotePickup

**English** | [简体中文](README.zh-CN.md)

A UE4SS Lua mod for *Phantom Blade Zero* that collects nearby items remotely. Each press of the pickup key collects the nearest eligible item (materials and consumables) within a configurable range, without the need to walk to it.

## Features

- Collects the nearest eligible item within range on each key press, or optionally every eligible item in range in sequence.
- Pickups are carried out through the game's own interaction logic and are recorded in the save file as usual.
- The pickup key can be bound to the keyboard (Alt and Shift combinations are supported), the mouse (including side buttons) or a gamepad (button chords are supported).
- Inactive while the game is paused or a menu has input focus.
- Hotkeys cycle the pickup range and toggle the equipment filter. Each change is confirmed by a brief on-screen message in English or Chinese, following the game language by default, so no settings menu is required.
- The following items are never collected remotely:
  - items that have already been collected or are currently hidden;
  - quest items (item IDs beginning with `K_` or `I_`);
  - items tied to story events, i.e. pickups that carry story flow tags, add story tags when collected, or start a quest;
  - equipment such as weapons and accessories (enabled by default, can be disabled). While this filter is enabled, only items whose IDs match known material and consumable patterns are collected, for example `Weapon_Material_*`, `R_*`, `Item_*` and loot table entries.

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) with Lua mod support. The mod was developed with UE4SS v3.0.1 Beta.
- Optional: **PbzModConfig** (Mod Config Menu) by 皮一下就很凡 (Bilibili). When it is installed and enabled, the settings of this mod appear under Settings → Mods → Remote Pickup. None of its files are bundled with this mod; they are loaded from PbzModConfig's own directory (`ue4ss/Mods/PbzModConfig/Scripts`), and only while PbzModConfig is enabled. Without it, settings can be changed with the hotkeys or in `settings.json`.

Developed and tested on Steam build 26367565. Game updates may affect compatibility.

## Installation

1. Exit the game and **back up your saves** (`ProjectPBZ/Saved/SaveGames`).
2. Place the contents of this repository in `<game directory>/platform/steam/ue4ss/Mods/PbzRemotePickup/`. A ZIP downloaded from GitHub extracts to a folder named `PbzRemotePickup-main`, which must be renamed to `PbzRemotePickup`. The resulting layout is:
   ```
   Mods/PbzRemotePickup/
     enabled.txt
     Scripts/main.lua
   ```
3. Launch the game. The line `[PbzRemotePickup] loaded v0.10.1 ...` in `UE4SS.log` confirms that the mod has loaded.

To uninstall, delete the `Mods/PbzRemotePickup` folder.

## Controls

| Action | Keyboard (default) | Gamepad |
|---|---|---|
| Pick up | `O` | Unbound by default |
| Cycle pickup range (25 → 50 → 100 → 150 → 200 m) | `P` | Unbound by default; chords supported |
| Toggle "skip equipment" | `L` | Unbound by default; chords supported |

Gamepad chords are defined in `settings.json` by joining key names with `+`, for example `"rangeGamepad":"Gamepad_LeftShoulder+Gamepad_DPad_Up"` (hold LB, then press D-pad Up). All keys except the last must be held; the binding triggers when the last key is pressed. When several bindings match at the same time, the one with the most keys takes precedence, so LB+R3 does not also trigger a pickup bound to R3 alone.

## Configuration

`settings.json` is created in the mod folder the first time a setting changes. Without PbzModConfig, the file can also be created or edited by hand while the game is not running:

```json
{"equipGamepad":"","equipKey":"L","onePerPress":true,"pickupGamepad":"","pickupKey":"O","radiusM":50,"rangeGamepad":"","rangeKey":"P","showToast":true,"skipEquipment":true,"skipHidden":true,"toastLanguage":"auto"}
```

| Key | Description | Default |
|---|---|---|
| `pickupKey` | Keyboard or mouse pickup key, given as a UE key name with an optional `Alt+` or `Shift+` prefix, for example `O`, `Alt+O` or `ThumbMouseButton` (mouse side button). Ctrl is used by the game and is not recommended. `""` leaves the key unbound. | `O` |
| `pickupGamepad` | Gamepad pickup button, given as a UE `Gamepad_*` key name, for example `Gamepad_LeftShoulder`. `""` leaves it unbound. | `""` |
| `radiusM` | Pickup range in metres, 5–200. | `50` |
| `onePerPress` | Collect only one item per key press. | `true` |
| `skipHidden` | Skip hidden items. | `true` |
| `skipEquipment` | Skip weapons, accessories and other equipment. | `true` |
| `rangeKey` / `rangeGamepad` | Keyboard key / gamepad binding that cycles the pickup range (gamepad chords supported). | `P` / `""` |
| `equipKey` / `equipGamepad` | Keyboard key / gamepad binding that toggles "skip equipment" (gamepad chords supported). | `L` / `""` |
| `showToast` | Show an on-screen message when a hotkey changes a setting. | `true` |
| `toastLanguage` | Language of on-screen messages: `auto` (Chinese when the game language is Chinese, English otherwise), `en` or `zh-Hans`. | `auto` |

Gamepad back paddles: Unreal Engine defines no dedicated key names for back paddles. If the game recognises a paddle, it can be bound directly. Otherwise, map the paddle to an unused gamepad button in Steam Input and bind that button instead.

## Troubleshooting

All messages are written to `UE4SS.log` with the prefix `[PbzRemotePickup]`:

- `skip <actor> ... : <reason>`: the item was skipped for the stated reason. If a material is reported as `equipment / unknown item <ID>`, please open an issue that includes the ID.
- `PICKED` / `FAILED`: the result of a pickup attempt. A subsequent `LATE` line indicates that the pickup completed after a delay.
- `toast: ...`: a hotkey changed a setting. If it is followed by `on-screen message unavailable`, the message could not be displayed, although the setting was still applied. After three consecutive failures, on-screen messages are disabled for the rest of the session.
- `game culture: ...`: the game language detected for on-screen messages when `toastLanguage` is `auto`. If detection fails, messages are shown in English; set `toastLanguage` explicitly in that case.
- `struct ...: id fields [...]`: diagnostic information about how item IDs are read from pickup data. Please include this line when reporting an issue.

## Known limitations

- Only items in currently loaded areas can be collected. Areas the game has not yet loaded are out of reach even at the maximum range of 200 m.
- Story items and equipment are identified by rules and may not be detected in every case. Items whose status is uncertain should be collected manually.
- Some pickups complete a few seconds after the attempt. The log then shows `FAILED` followed by `LATE`; this is expected behaviour.
- On-screen messages are displayed through a widget provided by the game and may stop working after a game update. Settings continue to be applied in that case; only the message is not shown.

## Disclaimer

This is an unofficial mod and is not affiliated with the developer of the game. Back up your saves before use. Use at your own risk.

## License

[MIT](LICENSE)
