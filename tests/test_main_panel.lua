-- Offline test of Scripts/main.lua together with the settings panel: the whole mod is loaded into the stub
-- environment from a temporary mod folder (so settings.json is written there, not into the repository).
-- Run from the repository root with any Lua 5.4:  lua tests/test_main_panel.lua
local root = (arg and arg[0] or ""):gsub("[\\/]?tests[\\/][^\\/]*$", "")
if root == "" then root = "." end
package.path = root .. "/tests/?.lua;" .. package.path

local Mock = require("mock_ue")

local passed, failed = 0, {}
local function eq(got, want, what)
    if got ~= want then error(string.format("%s: expected %s, got %s", what or "value", tostring(want), tostring(got)), 2) end
end

---------------------------------------------------------------- a throw-away mod folder
local windows = package.config:sub(1, 1) == "\\"
local base = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
local modDir = string.format("%s/pbz_remote_pickup_test_%d_%d", base, os.time(), math.random(100000, 999999))
local scripts = modDir .. "/Scripts"
if windows then os.execute('mkdir "' .. scripts:gsub("/", "\\") .. '"') else os.execute('mkdir -p "' .. scripts .. '"') end

local function copy(from, to)
    local f = assert(io.open(from, "rb")); local data = f:read("a"); f:close()
    local t = assert(io.open(to, "wb")); t:write(data); t:close()
end
local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("a"); f:close()
    return data
end
local function writeFile(path, data)
    local f = assert(io.open(path, "wb")); f:write(data); f:close()
end
copy(root .. "/Scripts/main.lua", scripts .. "/main.lua")
copy(root .. "/Scripts/SettingsUI.lua", scripts .. "/SettingsUI.lua")
local settingsPath = modDir .. "/settings.json"

local function cleanup()
    os.remove(settingsPath); os.remove(scripts .. "/main.lua"); os.remove(scripts .. "/SettingsUI.lua")
    if windows then os.execute('rmdir /s /q "' .. modDir:gsub("/", "\\") .. '"') else os.execute('rm -rf "' .. modDir .. '"') end
end

---------------------------------------------------------------- driving the mod
local function output(from) return table.concat(Mock.output, "\n", from or 1) end
local function logged(text, from) return output(from):find(text, 1, true) ~= nil end

-- load the mod afresh with the given settings.json content (nil = no file)
local function Load(settings)
    Mock.reset()
    package.loaded["SettingsUI"] = nil
    package.loaded["UEHelpers"] = nil
    if settings then writeFile(settingsPath, settings) else os.remove(settingsPath) end
    dofile(scripts .. "/main.lua")
    Mock.pump()                      -- the first poll only records which keys are down
end
local function frame(n) for _ = 1, (n or 1) do Mock.pump() end end
local function press(...) for _, k in ipairs({ ... }) do Mock.keys[k] = true end; frame() end
local function release(...) for _, k in ipairs({ ... }) do Mock.keys[k] = nil end; frame() end
local function tap(k) press(k); release(k) end
local function saved() return readFile(settingsPath) or "" end

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed[#failed + 1] = name .. "\n    " .. tostring(err) end
end

local USER = '{"equipGamepad":"","equipKey":"L","onePerPress":true,"pickupGamepad":"Gamepad_RightThumbstick","pickupKey":"O",'
    .. '"radiusM":200,"rangeGamepad":"","rangeKey":"P","showToast":true,"skipEquipment":true,"skipHidden":true,"toastLanguage":"auto"}'

---------------------------------------------------------------- tests
test("loads with an existing settings.json and adds the panel hotkey", function()
    Load(USER)
    eq(logged("[PbzRemotePickup] loaded v0.11 (pickup key 'O', gamepad 'Gamepad_RightThumbstick'"), true, "load line")
    eq(logged("settings panel key 'F8' / ''"), true, "default panel key")
    eq(logged("panel unavailable"), false)
    eq(saved(), USER, "loading alone does not rewrite the file")
end)

test("fresh install: defaults", function()
    Load(nil)
    eq(logged("loaded v0.11 (pickup key 'O', gamepad ''; range key 'P' / '', equipment key 'L' / ''; settings panel key 'F8' / ''; range 50 m"), true)
end)

test("the hotkey opens the panel, the pickup key does nothing while it is open", function()
    Load(USER)
    local mark = #Mock.output + 1
    tap("O")
    eq(logged("player interact component not found", mark), true, "pickup attempted before the panel opens")
    mark = #Mock.output + 1
    press("F8")
    eq(logged("settings panel opened", mark), true)
    eq(Mock.paused, true, "the game is paused")
    release("F8")
    mark = #Mock.output + 1
    tap("O"); tap("Gamepad_RightThumbstick"); tap("P"); tap("L")
    eq(logged("player interact component not found", mark), false, "no pickup while the panel is open")
    eq(logged("toast:", mark), false, "no range / equipment hotkey while the panel is open")
    eq(saved(), USER)
end)

test("values changed in the panel are applied and saved when it closes", function()
    Load(USER)
    press("F8"); release("F8")
    tap("Down"); tap("Down")                 -- pickup key -> pickup button -> range
    tap("Left"); tap("Left")
    tap("Down"); tap("Enter")                -- one item per press: off
    eq(saved(), USER, "nothing is written while the panel is open")
    local mark = #Mock.output + 1
    press("F8")                              -- the hotkey closes the panel
    eq(logged("settings panel closed (hotkey), saving", mark), true)
    eq(logged("settings saved from the panel", mark), true)
    eq(saved():find('"radiusM":190', 1, true) ~= nil, true, "range saved: " .. saved())
    eq(saved():find('"onePerPress":false', 1, true) ~= nil, true)
    eq(saved():find('"menuKey":"F8"', 1, true) ~= nil, true)
    eq(saved():find('"pickupGamepad":"Gamepad_RightThumbstick"', 1, true) ~= nil, true)
    eq(Mock.paused, true, "still paused while F8 is down")
    release("F8")
    eq(Mock.paused, false)
    mark = #Mock.output + 1
    tap("O")
    eq(logged("within 190 m", mark) or logged("player interact component not found", mark), true, "pickup works again")
    press("F8")
    eq(logged("settings panel opened", mark), true, "and the hotkey opens the panel again")
end)

test("Escape closes without the game seeing the key, and nothing fires on the way out", function()
    Load(USER)
    press("F8"); release("F8")
    local mark = #Mock.output + 1
    press("Escape")
    eq(logged("settings panel closed (back)", mark), true)
    eq(Mock.paused, true)
    press("O")                               -- pressed during the wait: must not pick up
    release("Escape")
    eq(Mock.paused, true, "O is still down")
    release("O")
    eq(Mock.paused, false)
    eq(logged("player interact component not found", mark), false)
end)

test("the panel does not open while the game is paused or in a menu", function()
    Load(USER)
    Mock.inputMode = 0
    local mark = #Mock.output + 1
    tap("F8")
    eq(logged("settings panel opened", mark), false, "menu")
    Mock.inputMode = 1; Mock.paused = true
    tap("F8")
    eq(logged("settings panel opened", mark), false, "paused")
    Mock.paused = false
    tap("F8")
    eq(logged("settings panel opened", mark), true)
end)

test("rebinding keys in the panel", function()
    Load(USER)
    press("F8"); release("F8")
    tap("Enter"); tap("K")                   -- pickup key: K
    for _ = 1, 7 do tap("Down") end          -- ... range key (gamepad)
    tap("Enter")
    press("Gamepad_LeftShoulder"); press("Gamepad_DPad_Up"); release("Gamepad_DPad_Up"); release("Gamepad_LeftShoulder")
    for _ = 1, 5 do tap("Down") end          -- ... panel key (keyboard)
    tap("Enter"); tap("F8")                  -- capturing F8 for the panel key itself must not close the panel
    eq(Mock.paused, true, "still open")
    tap("Enter"); tap("F7")
    tap("Down"); tap("Enter")                -- panel key (gamepad): LB + L3
    press("Gamepad_LeftShoulder"); press("Gamepad_LeftThumbstick"); release("Gamepad_LeftThumbstick"); release("Gamepad_LeftShoulder")
    tap("BackSpace")
    local s = saved()
    eq(s:find('"pickupKey":"K"', 1, true) ~= nil, true, s)
    eq(s:find('"rangeGamepad":"Gamepad_LeftShoulder+Gamepad_DPad_Up"', 1, true) ~= nil, true, s)
    eq(s:find('"menuKey":"F7"', 1, true) ~= nil, true, s)
    eq(s:find('"menuGamepad":"Gamepad_LeftShoulder+Gamepad_LeftThumbstick"', 1, true) ~= nil, true, s)
    eq(Mock.paused, false)
    local mark = #Mock.output + 1
    tap("F8")
    eq(logged("settings panel opened", mark), false, "the old hotkey is gone")
    tap("K")
    eq(logged("player interact component not found", mark), true, "the new pickup key works")
    mark = #Mock.output + 1
    press("Gamepad_LeftShoulder"); press("Gamepad_DPad_Up")
    eq(logged("toast:", mark), true, "the new range chord works")
    release("Gamepad_DPad_Up")
    mark = #Mock.output + 1
    press("Gamepad_LeftThumbstick")
    eq(logged("settings panel opened", mark), true, "the gamepad chord opens the panel")
    release("Gamepad_LeftThumbstick", "Gamepad_LeftShoulder")
    press("Gamepad_LeftShoulder"); press("Gamepad_LeftThumbstick")
    eq(logged("settings panel closed (hotkey)", mark), true, "and closes it")
end)

test("reset to defaults from the panel", function()
    Load(USER)
    press("F8"); release("F8")
    tap("Up"); tap("Up")                     -- wraps to "save and close", then "reset"
    tap("Enter"); tap("Enter")
    tap("Escape")
    local s = saved()
    eq(s:find('"radiusM":50', 1, true) ~= nil, true, s)
    eq(s:find('"pickupGamepad":""', 1, true) ~= nil, true, s)
    eq(s:find('"menuKey":"F8"', 1, true) ~= nil, true, s)
end)

test("a settings.json without any panel hotkey gets the default back", function()
    Load('{"menuKey":"","menuGamepad":"","radiusM":100}')
    eq(logged("settings panel key 'F8' / ''"), true)
    Load('{"menuKey":"","menuGamepad":"Gamepad_Special_Left","radiusM":100}')
    eq(logged("settings panel key '' / 'Gamepad_Special_Left'"), true)
    Load('{"menuKey":"Gamepad_Special_Left"}')
    eq(logged("settings panel key 'F8' / ''"), true, "a gamepad key in the keyboard slot is rejected")
end)

test("language of the panel follows the setting", function()
    -- the panel is drawn on stub widgets: look for a text among the constructed text blocks
    local function has(text)
        for _, o in ipairs(Mock.constructed) do if o.__text == text then return true end end
        return false
    end
    Load(USER)                               -- toastLanguage auto, game culture zh-Hans
    press("F8"); release("F8")
    eq(has("远程拾取 · 设置"), true, "Chinese title")
    eq(has("拾取键（键盘 / 鼠标）"), true)
    eq(has("打开本设置界面（手柄）"), true)
    Load(USER)
    Mock.culture = "en"
    press("F8"); release("F8")
    eq(has("Remote Pickup - Settings"), true, "English title when the game is not in Chinese")
    eq(has("Open this settings panel (gamepad)"), true)
    Load((USER:gsub('"toastLanguage":"auto"', '"toastLanguage":"en"')))
    press("F8"); release("F8")
    eq(has("Remote Pickup - Settings"), true, "English when set explicitly")
    for _ = 1, 11 do tap("Down") end         -- the language row: switch to Simplified Chinese on the spot
    tap("Right")
    eq(has("远程拾取 · 设置"), true, "the panel switches language at once")
end)

test("a new world while the panel is open", function()
    Load(USER)
    press("F8"); release("F8")
    tap("Down"); tap("Down"); tap("Left")
    Mock.pc = Mock.object("PlayerController of the next world", { bShowMouseCursor = false })
    Mock.paused = false
    local mark = #Mock.output + 1
    frame()
    eq(logged("settings panel closed (the world changed), saving", mark), true)
    eq(saved():find('"radiusM":195', 1, true) ~= nil, true)
    eq(logged("error", mark), false)
    tap("F8")
    eq(logged("settings panel opened", mark), true, "opens again in the new world")
    eq(Mock.paused, true)
end)

test("without SettingsUI.lua the mod still loads and the hotkey only reports it", function()
    os.rename(scripts .. "/SettingsUI.lua", scripts .. "/SettingsUI.lua.off")
    local ok, err = pcall(function()
        Load(USER)
        eq(logged("settings panel unavailable (Scripts/SettingsUI.lua)"), true)
        eq(logged("loaded v0.11"), true)
        eq(logged("(panel unavailable)"), true)
        local mark = #Mock.output + 1
        tap("F8")
        eq(logged("settings panel not opened: not loaded", mark), true)
        tap("O")
        eq(logged("player interact component not found", mark), true, "pickup still works")
    end)
    os.rename(scripts .. "/SettingsUI.lua.off", scripts .. "/SettingsUI.lua")
    if not ok then error(err, 0) end
end)

---------------------------------------------------------------- summary
cleanup()
Mock.print(string.format("main.lua + panel: %d passed, %d failed", passed, #failed))
for _, f in ipairs(failed) do Mock.print("FAILED " .. f) end
if #failed > 0 then error(#failed .. " test(s) failed", 0) end
