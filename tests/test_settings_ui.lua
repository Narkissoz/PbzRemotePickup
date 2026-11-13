-- Offline tests of Scripts/SettingsUI.lua (menu logic, key capture, the UMG view against stub objects).
-- Run from the repository root with any Lua 5.4:  lua tests/test_settings_ui.lua
local root = (arg and arg[0] or ""):gsub("[\\/]?tests[\\/][^\\/]*$", "")
if root == "" then root = "." end
package.path = root .. "/tests/?.lua;" .. root .. "/Scripts/?.lua;" .. package.path

local Mock = require("mock_ue")
local UI = require("SettingsUI")

local passed, failed = 0, {}
local function test(name, fn)
    Mock.reset()
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed[#failed + 1] = name .. "\n    " .. tostring(err) end
end
local function eq(got, want, what)
    if got ~= want then error(string.format("%s: expected %s, got %s", what or "value", tostring(want), tostring(got)), 2) end
end

---------------------------------------------------------------- helpers
local function L(zh, en) return { zh = zh, en = en } end

local function FakeView()
    local v = { rows = {}, shown = false, fonts = {} }
    function v:alive(pc) return not self.dead and pc == self.pc end
    function v:setTitle(s) self.title = s end
    function v:setDesc(s) self.desc = s end
    function v:setNote(s) self.note = s end
    function v:setFooter(s) self.footer = s end
    function v:setRow(i, label, value, style) self.rows[i] = { label = label, value = value, style = style } end
    function v:hovered() return self.hover end
    function v:show() self.shown = true end
    function v:hide() self.shown = false end
    return v
end

local DEFAULTS = { radiusM = 50, onePerPress = true, pickupKey = "O", pickupGamepad = "", rangeKey = "Ctrl+O",
                   menuKey = "L", menuGamepad = "", mode = "a" }

local function Rows()
    return {
        { kind = "header", label = L("拾取", "Pickup") },
        { kind = "key", key = "pickupKey", device = "keyboard", label = L("拾取键", "Pickup key"), desc = L("说明", "desc") },
        { kind = "key", key = "pickupGamepad", device = "gamepad", label = L("手柄拾取键", "Pickup button") },
        { kind = "number", key = "radiusM", label = L("范围", "Range"), min = 5, max = 200, step = 5, unit = L("米", "m") },
        { kind = "toggle", key = "onePerPress", label = L("每次一个", "One per press") },
        { kind = "choice", key = "mode", label = "Mode", options = { { value = "a", label = "A" }, { value = "b", label = "B" }, { value = "c", label = "C" } } },
        { kind = "key", key = "rangeKey", device = "keyboard", label = L("范围键", "Range key") },
        { kind = "key", key = "menuKey", device = "keyboard", label = L("打开本界面", "open this panel"), needOne = "menu" },
        { kind = "key", key = "menuGamepad", device = "gamepad", label = L("打开本界面（手柄）", "open this panel (gamepad)"), needOne = "menu" },
        { kind = "action", label = L("恢复默认", "Reset"), confirm = true, run = function(m) m.resetDefaults() end },
        { kind = "info", label = "info", value = function() return "live" end },
    }
end

-- a menu on a fake view with a fake clock; returns menu, context
local function NewMenu(opts)
    opts = opts or {}
    local ctx = { time = 100, stored = {}, commits = {}, logs = {} }
    for k, v in pairs(DEFAULTS) do ctx.stored[k] = v end
    for k, v in pairs(opts.values or {}) do ctx.stored[k] = v end
    local env = {
        rows = opts.rows or Rows(),
        title = L("远程拾取", "Remote Pickup"),
        defaults = DEFAULTS,
        load = function() return ctx.stored end,
        commit = function(v) ctx.commits[#ctx.commits + 1] = v; ctx.stored = v end,
        keyDown = function(pc, name) return pc:IsInputKeyDown({ KeyName = Mock.fname(name) }) end,
        getPC = function() return Mock.pc end,
        log = function(m) ctx.logs[#ctx.logs + 1] = m end,
        now = function() return ctx.time end,
        lang = function() return opts.lang or "zh" end,
        block = opts.block,
        mouse = opts.mouse,
        noWatchdog = true,
    }
    if not opts.realView then
        env.newView = function() local v = FakeView(); v.pc = Mock.pc; ctx.view = v; ctx.views = (ctx.views or 0) + 1; return v end
    end
    local menu = UI.new(env)
    ctx.env = env
    function ctx.tick(dt) ctx.time = ctx.time + (dt or 0.033); menu.tick(Mock.pc) end
    function ctx.press(...) for _, k in ipairs({ ... }) do Mock.keys[k] = true end; ctx.tick() end
    function ctx.release(...) for _, k in ipairs({ ... }) do Mock.keys[k] = nil end; ctx.tick() end
    function ctx.tap(k) ctx.press(k); ctx.release(k) end
    function ctx.row(i) return ctx.view.rows[i] end
    function ctx.pick(index)         -- select row by its index in the row list
        for _ = 1, 40 do
            if ctx.view.rows[index].style == "selected" then return end
            ctx.tap("Down")
        end
        error("row " .. index .. " cannot be selected")
    end
    return menu, ctx
end

---------------------------------------------------------------- labels
test("key labels", function()
    eq(UI.keyLabel("", "zh"), "未绑定")
    eq(UI.keyLabel(nil, "en"), "Not bound")
    eq(UI.keyLabel("Ctrl+O", "en"), "Ctrl + O")
    eq(UI.keyLabel("ThumbMouseButton2", "zh"), "鼠标侧键 2")
    eq(UI.keyLabel("Gamepad_LeftShoulder+Gamepad_DPad_Up", "en"), "LB + D-Pad Up")
    eq(UI.keyLabel("Gamepad_RightThumbstick", "en"), "R3")
    eq(UI.keyLabel("Gamepad_Unknown_Thing", "en"), "Unknown_Thing")
    eq(UI.keyLabel("Shift+Five", "zh"), "Shift + 5")
end)

test("language detection", function()
    eq((UI.detectLanguage()), "zh")
    Mock.gameText = "NEW GAME"
    eq((UI.detectLanguage()), "en")
    Mock.gameText = "새 게임"
    eq((UI.detectLanguage()), "en")
    Mock.gameText = "新遊戲"; Mock.culture = "en"
    eq((UI.detectLanguage()), "zh", "game text wins over the engine culture")
    Mock.missing["/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary"] = true
    Mock.culture = "zh-Hans-CN"
    eq((UI.detectLanguage()), "zh")
    Mock.culture = "en-US"
    eq((UI.detectLanguage()), "en")
    Mock.missing["/Script/Engine.Default__KismetInternationalizationLibrary"] = true
    eq((UI.detectLanguage()), "zh", "nothing readable: Chinese")
end)

---------------------------------------------------------------- open / render / close
test("open renders every row and pauses the game", function()
    local menu, ctx = NewMenu()
    eq(menu.open(Mock.pc), true)
    eq(menu.isOpen, true)
    eq(ctx.view.shown, true)
    eq(Mock.paused, true, "paused")
    eq(ctx.view.title, "远程拾取")
    eq(ctx.row(1).style, "header")
    eq(ctx.row(2).style, "selected")
    eq(ctx.row(2).value, "O")
    eq(ctx.row(3).value, "未绑定")
    eq(ctx.row(4).value, "50 米")
    eq(ctx.row(5).value, "开")
    eq(ctx.row(7).value, "Ctrl + O")
    eq(ctx.row(11).style, "info")
    eq(ctx.row(11).value, "live")
    eq(ctx.view.desc, "说明")
    menu.close("test")
    eq(menu.isOpen, false)
    eq(ctx.view.shown, false)
    eq(menu.busy(), true, "the game is held back until the next tick finds every key released")
    ctx.tick()
    eq(menu.busy(), false)
    eq(Mock.paused, false, "unpaused")
    eq(#ctx.commits, 0, "nothing changed, nothing saved")
end)

test("english texts", function()
    local menu, ctx = NewMenu({ lang = "en" })
    menu.open(Mock.pc)
    eq(ctx.view.title, "Remote Pickup")
    eq(ctx.row(3).value, "Not bound")
    eq(ctx.row(4).value, "50 m")
    eq(ctx.row(5).value, "On")
end)

test("a game that was already paused stays paused", function()
    local menu, ctx = NewMenu()
    Mock.paused = true
    menu.open(Mock.pc)
    menu.close("test"); ctx.tick()
    eq(menu.busy(), false)
    eq(Mock.paused, true)
end)

test("pause refused: falls back to disabling input, and restores it", function()
    local menu, ctx = NewMenu()
    Mock.pauseAllowed = false
    menu.open(Mock.pc)
    eq(Mock.paused, false)
    eq(Mock.pc.__input, false, "controller input off")
    eq(Mock.pawn.__input, false, "pawn input off")
    menu.close("test"); ctx.tick()
    eq(Mock.pc.__input, true)
    eq(Mock.pawn.__input, true)
end)

test("block mode none leaves the game alone", function()
    local menu = NewMenu({ block = "none" })
    menu.open(Mock.pc)
    eq(Mock.paused, false)
    eq(Mock.pc.__input, nil)
end)

---------------------------------------------------------------- navigation
test("keys held while opening do nothing until released", function()
    local menu, ctx = NewMenu()
    Mock.keys.Down = true; Mock.keys.Escape = true
    menu.open(Mock.pc)
    ctx.tick(); ctx.tick()
    eq(menu.isOpen, true)
    eq(ctx.row(2).style, "selected")
    ctx.release("Down", "Escape")
    eq(menu.isOpen, true)
    ctx.tap("Down")
    eq(ctx.row(3).style, "selected")
end)

test("up / down skip headers and info rows and wrap around", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.tap("Up")
    eq(ctx.row(10).style, "selected", "wrapped to the last selectable row")
    ctx.tap("Gamepad_DPad_Down")
    eq(ctx.row(2).style, "selected", "wrapped to the first")
    eq(menu.device, "gamepad")
    ctx.tap("S")
    eq(ctx.row(3).style, "selected")
    eq(menu.device, "keyboard")
    ctx.tap("Gamepad_LeftStick_Up")
    eq(ctx.row(2).style, "selected")
end)

test("number: left / right, clamping, auto repeat", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(4)
    eq(ctx.row(4).value, "<   50 米   >")
    ctx.tap("Right"); eq(menu.values.radiusM, 55)
    ctx.tap("Left"); ctx.tap("Gamepad_DPad_Left"); eq(menu.values.radiusM, 45)
    ctx.press("Right")                       -- hold: one step now, more after the delay
    eq(menu.values.radiusM, 50)
    ctx.tick(0.2); eq(menu.values.radiusM, 50, "no repeat yet")
    ctx.tick(0.3); eq(menu.values.radiusM, 55, "first repeat")
    for _ = 1, 100 do ctx.tick(0.12) end
    eq(menu.values.radiusM, 200, "clamped at max")
    ctx.release("Right")
    ctx.tick(1); eq(menu.values.radiusM, 200)
    ctx.press("A")
    for _ = 1, 100 do ctx.tick(0.12) end
    eq(menu.values.radiusM, 5, "clamped at min")
    ctx.release("A")
end)

test("toggle and choice", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(5)
    ctx.tap("Enter"); eq(menu.values.onePerPress, false); eq(ctx.row(5).value, "关")
    ctx.tap("Gamepad_FaceButton_Bottom"); eq(menu.values.onePerPress, true)
    ctx.tap("Left"); eq(menu.values.onePerPress, false)
    ctx.pick(6)
    ctx.tap("Right"); eq(menu.values.mode, "b")
    ctx.tap("Right"); ctx.tap("Right"); eq(menu.values.mode, "a", "wraps")
    ctx.tap("Left"); eq(menu.values.mode, "c")
    eq(ctx.row(6).value, "<   C   >")
end)

test("back saves the changes and closes", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(4); ctx.tap("Right")
    ctx.tap("Gamepad_FaceButton_Right")
    eq(menu.isOpen, false)
    eq(menu.busy(), false)
    eq(#ctx.commits, 1)
    eq(ctx.commits[1].radiusM, 55)
    eq(ctx.commits[1].pickupKey, "O", "untouched values are passed along")
    eq(Mock.paused, false)
    menu.open(Mock.pc); ctx.tick()
    eq(menu.values.radiusM, 55, "reopened with the saved values")
    ctx.tap("Escape")
    eq(#ctx.commits, 1, "no second save without changes")
end)

---------------------------------------------------------------- key capture
test("keyboard capture: plain key, the confirming key is not bound", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.press("Enter")
    eq(menu.isCapturing(), true)
    eq(ctx.row(2).style, "capture")
    eq(ctx.row(2).value, "请按键 ...")
    ctx.tick(); ctx.tick()
    eq(menu.isCapturing(), true, "Enter is still held from the confirm")
    ctx.release("Enter")
    ctx.press("K")
    eq(menu.isCapturing(), false)
    eq(menu.values.pickupKey, "K")
    ctx.release("K")
    eq(ctx.row(2).value, "K")
    eq(ctx.row(2).style, "selected")
end)

test("keyboard capture: modifiers, mouse buttons, navigation keys", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.tap("Enter")
    ctx.press("LeftControl"); eq(menu.isCapturing(), true, "a modifier alone binds nothing")
    ctx.press("LeftShift")
    ctx.press("F6")
    eq(menu.values.pickupKey, "Ctrl+Shift+F6")
    ctx.release("LeftControl", "LeftShift", "F6")
    ctx.tap("Enter"); ctx.tap("ThumbMouseButton2")
    eq(menu.values.pickupKey, "ThumbMouseButton2")
    ctx.tap("Enter")
    ctx.press("Down")                        -- a navigation key can be bound and must not also move the selection
    eq(menu.values.pickupKey, "Down")
    ctx.tick(1); ctx.tick(1)
    eq(ctx.row(2).style, "selected", "the held key does not start repeating")
    ctx.release("Down")
    eq(ctx.row(2).style, "selected")
    ctx.tap("Enter")
    ctx.tap("Gamepad_FaceButton_Top")
    eq(menu.isCapturing(), true, "gamepad buttons are ignored on a keyboard row")
    ctx.tap("Escape")
    eq(menu.isCapturing(), false)
    eq(menu.isOpen, true, "Escape only cancelled the capture")
    eq(menu.values.pickupKey, "Down")
    eq(ctx.view.note, "已取消，绑定没有变化。")
end)

test("keyboard capture times out", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.tap("Enter")
    ctx.tick(5); eq(menu.isCapturing(), true)
    ctx.tick(4); eq(menu.isCapturing(), false)
    eq(menu.values.pickupKey, "O")
end)

test("gamepad capture: single button on release", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(3)
    ctx.press("Gamepad_FaceButton_Bottom")
    eq(menu.isCapturing(), true)
    ctx.tick(); ctx.release("Gamepad_FaceButton_Bottom")
    eq(menu.isCapturing(), true, "releasing the confirm button binds nothing")
    ctx.press("Gamepad_RightThumbstick")
    eq(menu.isCapturing(), true, "bound on release")
    eq(ctx.row(3).value, "R3（按下右摇杆） ...")
    ctx.release("Gamepad_RightThumbstick")
    eq(menu.values.pickupGamepad, "Gamepad_RightThumbstick")
    ctx.tap("Gamepad_FaceButton_Bottom")     -- the confirm button itself can be bound too
    ctx.tap("Gamepad_FaceButton_Bottom")
    eq(menu.values.pickupGamepad, "Gamepad_FaceButton_Bottom")
end)

test("gamepad capture: chord in press order, keyboard keys ignored, Escape cancels", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(3)
    ctx.tap("Enter")
    ctx.tap("K"); eq(menu.isCapturing(), true)
    ctx.press("Gamepad_LeftShoulder")
    ctx.press("Gamepad_DPad_Up")
    ctx.tick(); ctx.tick()
    ctx.release("Gamepad_LeftShoulder")
    eq(menu.values.pickupGamepad, "Gamepad_LeftShoulder+Gamepad_DPad_Up")
    ctx.release("Gamepad_DPad_Up")
    eq(ctx.row(3).style, "selected", "the leftover D-Pad release did not move the selection")
    eq(ctx.row(3).value, "LB + 十字键上")
    ctx.tap("Enter")
    ctx.press("Gamepad_LeftStick_Up"); ctx.release("Gamepad_LeftStick_Up")
    eq(menu.isCapturing(), true, "stick directions are not bindable")
    ctx.tap("Escape")
    eq(menu.isCapturing(), false)
    eq(menu.values.pickupGamepad, "Gamepad_LeftShoulder+Gamepad_DPad_Up")
    ctx.tap("Enter")
    ctx.tick(9)
    eq(menu.isCapturing(), false, "timed out")
end)

test("gamepad chord is limited to three buttons", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(3); ctx.tap("Enter")
    ctx.press("Gamepad_LeftShoulder"); ctx.press("Gamepad_RightShoulder"); ctx.press("Gamepad_LeftTrigger"); ctx.press("Gamepad_RightTrigger")
    ctx.release("Gamepad_RightTrigger")
    eq(menu.isCapturing(), true, "the fourth button is not part of the chord")
    ctx.release("Gamepad_LeftTrigger")
    eq(menu.values.pickupGamepad, "Gamepad_LeftShoulder+Gamepad_RightShoulder+Gamepad_LeftTrigger")
end)

test("binding a key that another row uses frees the other row", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.tap("Enter")
    ctx.press("LeftControl"); ctx.press("O"); ctx.release("LeftControl", "O")
    eq(menu.values.pickupKey, "Ctrl+O")
    eq(menu.values.rangeKey, "", "the range key lost the same binding")
    eq(ctx.view.note, "同一个键原来绑定在“范围键”，已解除。")
    ctx.tap("Down")
    eq(ctx.view.note, "", "the note goes away with the next action")
end)

test("the last way to open the panel cannot be taken or cleared", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.tap("Enter"); ctx.tap("L")
    eq(menu.values.pickupKey, "O", "L stays the menu key")
    eq(menu.values.menuKey, "L")
    eq(ctx.view.note, "“L”已经用来打开本界面，这里不能再绑定。")
    ctx.pick(8)
    ctx.tap("Delete")
    eq(menu.values.menuKey, "L")
    eq(ctx.view.note, "至少要保留一个能打开本界面的键。")
    ctx.pick(9)                               -- with a gamepad binding in place the keyboard one may go
    ctx.tap("Enter"); ctx.tap("Gamepad_Special_Left")
    eq(menu.values.menuGamepad, "Gamepad_Special_Left")
    ctx.pick(8)
    ctx.tap("Delete")
    eq(menu.values.menuKey, "")
    ctx.pick(9)
    ctx.tap("Gamepad_FaceButton_Left")
    eq(menu.values.menuGamepad, "Gamepad_Special_Left", "now this is the last one")
end)

test("clear binding", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.tap("Delete")
    eq(menu.values.pickupKey, "")
    eq(ctx.row(2).value, "未绑定")
    ctx.pick(4); ctx.tap("Delete")
    eq(menu.values.radiusM, 50, "clear does nothing on other rows")
end)

test("reset to defaults needs two confirms", function()
    local menu, ctx = NewMenu({ values = { radiusM = 120, pickupKey = "", pickupGamepad = "Gamepad_RightThumbstick", onePerPress = false } })
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(10)
    ctx.tap("Enter")
    eq(menu.values.radiusM, 120, "armed only")
    eq(ctx.row(10).value, "再按一次确认")
    ctx.tap("Up"); ctx.tap("Down")
    eq(ctx.row(10).value, "", "moving away disarms")
    ctx.tap("Enter"); ctx.tick(5)
    eq(ctx.row(10).value, "", "the arming expires")
    ctx.tap("Enter"); ctx.tap("Enter")
    eq(menu.values.radiusM, 50)
    eq(menu.values.pickupKey, "O")
    eq(menu.values.pickupGamepad, "")
    eq(menu.values.onePerPress, true)
    ctx.tap("BackSpace")
    eq(ctx.commits[1].radiusM, 50)
end)

---------------------------------------------------------------- mouse
test("mouse: hovering selects, clicking confirms", function()
    local menu, ctx = NewMenu({ mouse = true })
    menu.open(Mock.pc); ctx.tick()
    eq(Mock.pc.bShowMouseCursor, true)
    ctx.view.hover = 5; ctx.tick()
    eq(ctx.row(5).style, "selected")
    ctx.tap("LeftMouseButton")
    eq(menu.values.onePerPress, false)
    ctx.tap("Down"); ctx.tick()
    eq(ctx.row(6).style, "selected", "the keyboard still moves while the mouse rests")
    ctx.tap("LeftMouseButton")
    eq(menu.values.mode, "a", "a click outside the selected row does nothing")
    ctx.view.hover = 1; ctx.tick()
    eq(ctx.row(6).style, "selected", "headers cannot be selected")
    menu.close("test")
    eq(Mock.pc.bShowMouseCursor, false, "cursor restored")
end)

test("mouse: clicks step numbers, right click clears a binding", function()
    local menu, ctx = NewMenu({ mouse = true })
    menu.open(Mock.pc); ctx.tick()
    ctx.view.hover = 4; ctx.tick()
    ctx.tap("LeftMouseButton"); eq(menu.values.radiusM, 55)
    ctx.tap("RightMouseButton"); ctx.tap("RightMouseButton"); eq(menu.values.radiusM, 45)
    ctx.view.hover = 2; ctx.tick()
    ctx.tap("RightMouseButton"); eq(menu.values.pickupKey, "")
    ctx.press("LeftMouseButton"); eq(menu.isCapturing(), true)
    ctx.tick(); eq(menu.isCapturing(), true, "the click that started the capture is not bound")
    ctx.release("LeftMouseButton")
    ctx.tap("LeftMouseButton"); eq(menu.values.pickupKey, "LeftMouseButton", "a fresh click is")
    ctx.view.hover = nil; ctx.tick()
    ctx.tap("RightMouseButton"); eq(menu.values.pickupKey, "LeftMouseButton", "no row under the cursor: nothing happens")
    eq(ctx.view.footer:find("鼠标", 1, true) ~= nil, true, "the footer explains the mouse")
end)

---------------------------------------------------------------- giving the game back
test("the game stays held back until the closing key is released", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.press("Escape")
    eq(menu.isOpen, false)
    eq(ctx.view.shown, false)
    eq(Mock.paused, true, "Escape is still down: the game must not see it")
    ctx.tick(); ctx.tick()
    eq(menu.busy(), true)
    eq(Mock.paused, true)
    ctx.release("Escape")
    eq(menu.busy(), false)
    eq(Mock.paused, false)
end)

test("a key that is never released does not hold the game forever", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.press("Gamepad_FaceButton_Right")
    ctx.tick(1); eq(Mock.paused, true)
    ctx.tick(1); eq(Mock.paused, false, "let go after the timeout")
    eq(menu.busy(), false)
end)

test("reopening while the game is still held back keeps one single pause", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.press("Escape")
    eq(menu.busy(), true)
    eq(menu.open(Mock.pc), true)
    eq(Mock.calls(Mock.statics, "SetGamePaused"), 1, "not paused a second time")
    ctx.release("Escape")
    eq(menu.isOpen, true, "the held Escape did not close the reopened panel")
    eq(Mock.paused, true)
    ctx.tap("BackSpace")
    eq(Mock.paused, false)
    eq(Mock.calls(Mock.statics, "SetGamePaused"), 2)
end)

test("forceClose gives the game back at once", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    Mock.keys.Escape = true
    menu.forceClose("test")
    eq(menu.busy(), false)
    eq(Mock.paused, false)
    menu.open(Mock.pc); ctx.tick()          -- also right after a normal close
    Mock.keys.Escape = nil; ctx.tick()
    ctx.press("Escape")
    eq(menu.busy(), true)
    menu.forceClose("test")
    eq(Mock.paused, false)
end)

test("a new world during the wait gives nothing back", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.press("Escape")
    Mock.pc = Mock.object("PlayerController of the next world")
    ctx.tick()
    eq(menu.busy(), false)
    eq(Mock.calls(Mock.statics, "SetGamePaused"), 1, "no unpause call into the new world")
end)

---------------------------------------------------------------- language, rows from the settings schema
test("the language follows the values while the panel is open", function()
    local rows = { { kind = "choice", key = "lang", label = { zh = "语言", en = "Language" },
                     options = { { value = "zh", label = "中文" }, { value = "en", label = "English" } } } }
    local menu, ctx = NewMenu({ rows = rows, values = { lang = "zh" } })
    ctx.env.lang = function(values) return values.lang end
    menu.open(Mock.pc); ctx.tick()
    eq(ctx.row(1).label, "语言")
    ctx.tap("Right")
    eq(ctx.row(1).label, "Language")
    eq(ctx.view.footer:find("Arrows", 1, true) ~= nil, true)
end)

test("rows from settings entries", function()
    local function L10n(zh, en) return { ["zh-Hans"] = zh, en = en } end
    local entries = {
        { key = "info", type = "header", label = L10n("说明", "About") },
        { key = "pickupKey", type = "keybind", allowGamepad = false, label = L10n("拾取键", "Pickup key"), description = L10n("描述", "Description") },
        { key = "pickupGamepad", type = "keybind", allowGamepad = true, label = L10n("手柄", "Gamepad") },
        { key = "radiusM", type = "number", min = 5, max = 200, step = 5, label = L10n("范围（米）", "Range (m)") },
        { key = "onePerPress", type = "toggle", label = L10n("每次一个", "One per press") },
        { key = "mode", type = "choice", label = "Mode", options = { { value = "a", label = L10n("甲", "A") }, { value = "b", label = L10n("乙", "B") } } },
        { key = "ignored", type = "color" },
    }
    local extras = {
        { after = "pickupGamepad", key = "rangeKey", type = "keybind", label = "range" },
        { after = "mode", key = "menuKey", type = "keybind", needOne = "menu", label = "menu" },
        { after = "menuKey", key = "menuGamepad", type = "keybind", allowGamepad = true, needOne = "menu", label = "menu pad" },
        { after = "nowhere", key = "last", type = "toggle", label = "last" },
    }
    local rows = UI.rowsFromEntries(entries, extras)
    local order = {}
    for i, r in ipairs(rows) do order[i] = r.kind .. ":" .. tostring(r.key) end
    eq(table.concat(order, " "), "header:nil key:pickupKey key:pickupGamepad key:rangeKey number:radiusM toggle:onePerPress "
        .. "choice:mode key:menuKey key:menuGamepad toggle:last")
    eq(rows[2].device, "keyboard"); eq(rows[3].device, "gamepad"); eq(rows[9].device, "gamepad")
    eq(rows[8].needOne, "menu")
    eq(rows[5].min, 5); eq(rows[5].max, 200); eq(rows[5].step, 5)
    local menu, ctx = NewMenu({ rows = rows, values = { last = true } })
    menu.open(Mock.pc); ctx.tick()
    eq(ctx.row(1).label, "说明")
    eq(ctx.row(2).label, "拾取键")
    eq(ctx.view.desc, "描述")
    eq(ctx.row(5).value, "50")
    eq(ctx.row(7).value, "甲")
    menu.forceClose("test")
    menu, ctx = NewMenu({ rows = rows, values = { last = true }, lang = "en" })
    menu.open(Mock.pc); ctx.tick()
    eq(ctx.row(2).label, "Pickup key")
    eq(ctx.row(7).value, "A")
end)

---------------------------------------------------------------- world changes
test("a new world drops the old widgets without touching them", function()
    local menu, ctx = NewMenu()
    menu.open(Mock.pc); ctx.tick()
    ctx.pick(4); ctx.tap("Right")
    local oldView = ctx.view
    Mock.pc = Mock.object("PlayerController of the next world")
    Mock.paused = false
    ctx.tick()
    eq(menu.isOpen, false)
    eq(oldView.shown, true, "hide was not called on the dead view")
    eq(#ctx.commits, 1, "the change is still saved")
    eq(menu.open(Mock.pc), true)
    eq(ctx.views, 2, "a new view was built")
end)

test("view build failure is reported and gives up after three tries", function()
    local menu, ctx = NewMenu()
    ctx.env.newView = function() return nil, "boom" end
    for _ = 1, 3 do
        local ok, err = menu.open(Mock.pc)
        eq(ok, false); eq(err, "boom")
    end
    local ok, err = menu.open(Mock.pc)
    eq(ok, false); eq(err, "disabled after repeated failures")
    eq(Mock.paused, false)
end)

test("idle close", function()
    local menu, ctx = NewMenu()
    ctx.env.idleClose = 30
    menu.open(Mock.pc); ctx.tick()
    ctx.tick(20); eq(menu.isOpen, true)
    ctx.tap("Down")
    ctx.tick(20); eq(menu.isOpen, true, "the key press restarted the countdown")
    ctx.tick(11); eq(menu.isOpen, false)
    ctx.tick()
    eq(Mock.paused, false)
end)

---------------------------------------------------------------- the real view on stub objects
test("UMG view builds, borrows the game's font and shows texts", function()
    local menu, ctx = NewMenu({ realView = true })
    eq(menu.open(Mock.pc), true)
    local view = menu.view
    eq(#view.rows, 11)
    eq(view.font.name, "Font /Game/PBZContent/UI/Fonts/GameFont.GameFont", "most used non-engine font")
    eq(view.host.__viewport, 1200)
    eq(view.host.__visibility, 4, "shown")
    eq(view.title.__text, "远程拾取")
    eq(view.rows[4].label.__text, "范围")
    eq(view.rows[4].value.__text, "50 米")
    eq(view.rows[2].value.__font.FontObject, view.font.object)
    eq(view.rows[2].value.__font.Size, 17)
    eq(view.note.__visibility, 1, "an empty note takes no room")
    eq(view.host.WidgetTree.RootWidget.__name, "new Overlay", "our screen is the host's root")
    local before = Mock.calls(view.rows[4].value, "SetText")
    ctx.tick(); ctx.tick()
    eq(Mock.calls(view.rows[4].value, "SetText"), before, "unchanged text is not set again")
    
    ctx.tap("Down"); ctx.tap("Down"); ctx.tap("Right")
    eq(view.rows[4].value.__text, "<   55 米   >")
    view.rows[5].bg.__hovered = true
    eq(view:hovered(), 5)
    menu.close("test")
    eq(view.host.__visibility, 1, "collapsed")
    eq(menu.open(Mock.pc), true)
    eq(menu.view, view, "the same widgets are reused in the same world")
end)

test("UMG view reports what is missing", function()
    Mock.missing["/Script/UMG.Default__WidgetBlueprintLibrary"] = true
    local menu, ctx = NewMenu({ realView = true })
    local ok, err = menu.open(Mock.pc)
    eq(ok, false)
    eq(err, "widget library: not found")
    Mock.reset()
    Mock.missing["/Script/UMG.SizeBox"] = true
    menu, ctx = NewMenu({ realView = true })
    ok, err = menu.open(Mock.pc)
    eq(ok, false)
    eq(err, "create SizeBox: class not found")
    eq(Mock.paused, false, "the game is not paused when the panel cannot be shown")
end)

---------------------------------------------------------------- summary
Mock.print(string.format("SettingsUI: %d passed, %d failed", passed, #failed))
for _, f in ipairs(failed) do Mock.print("FAILED " .. f) end
if #failed > 0 then error(#failed .. " test(s) failed", 0) end
