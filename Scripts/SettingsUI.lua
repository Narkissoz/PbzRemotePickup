-- SettingsUI.lua : the in-game settings panel of PbzRemotePickup.
--
-- The panel is made of plain UMG widgets (Overlay / SizeBox / Border / VerticalBox / HorizontalBox / TextBlock)
-- that are created from Lua inside a host UserWidget and added to the viewport. No other mod is involved.
-- Everything is polled: keys through the caller's keyDown(pc, name) (PlayerController:IsInputKeyDown) and the
-- mouse through UWidget:IsHovered, so the panel needs no delegates and no hooks.
--
-- Two halves:
--   View      - builds the widgets and writes text / colours into them. Only this half touches UMG.
--   UI.new    - the menu itself: rows, selection, value editing, key capture. It only talks to a view through
--               a handful of methods, so the offline tests can run it against a fake view.
--
-- A menu is described by rows:
--   { kind = "header", label = L }                                              not selectable
--   { kind = "info",   label = L, value = function(menu) return text end }      not selectable, live text
--   { kind = "number", key = k, label = L, desc = L, min = a, max = b, step = s, unit = L }
--   { kind = "toggle", key = k, label = L, desc = L }
--   { kind = "choice", key = k, label = L, desc = L, options = { { value = v, label = L }, ... } }
--   { kind = "key",    key = k, device = "keyboard" | "gamepad", label = L, desc = L, needOne = group }
--   { kind = "action", label = L, desc = L, run = function(menu) end, confirm = true | nil }
-- L is a string, a { zh = ..., en = ... } table, or a function(menu) returning either.

local UEHelpers = require("UEHelpers")

local UI = {}

---------------------------------------------------------------- engine helpers
local function Valid(o)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end

local function Address(o)
    local ok, r = pcall(function() return o:GetAddress() end)
    if ok then return r end
    return nil
end

local function Find(path)
    local ok, o = pcall(StaticFindObject, path)
    if ok and Valid(o) then return o end
    return nil
end

local function FindOrLoad(path)
    local o = Find(path)
    if o then return o end
    if type(LoadAsset) == "function" then
        pcall(LoadAsset, (path:gsub("%.[^./]+$", "")))
        return Find(path)
    end
    return nil
end

local function Str(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return nil
end

local function ToText(s)
    s = tostring(s == nil and "" or s)
    local lib = Find("/Script/Engine.Default__KismetTextLibrary")
    if lib then
        local ok, t = pcall(function() return lib:Conv_StringToText(s) end)
        if ok and t ~= nil then return t end
    end
    return FText(s)
end

local function Margin(l, t, r, b) return { Left = l, Top = t, Right = r or l, Bottom = b or t } end
local function SlateColor(c) return { SpecifiedColor = { R = c.R, G = c.G, B = c.B, A = c.A }, ColorUseRule = 0 } end

---------------------------------------------------------------- language
-- "zh" when the game runs in Chinese, else "en". When nothing can be read the panel stays Chinese.
function UI.detectLanguage()
    local culture, sample = nil, nil
    pcall(function()
        local lib = Find("/Script/Engine.Default__KismetInternationalizationLibrary")
        if lib then culture = Str(lib:GetCurrentLanguage()) end
    end)
    pcall(function()          -- the game can run in a language other than the engine culture: look at one of its texts
        local lib = Find("/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary")
        if lib then sample = Str(lib:MakeTextByKey("UI_StartMenu_01")) end
    end)
    local lang = nil
    if sample and sample ~= "" then
        -- CJK ideographs are U+4E00..U+9FFF: UTF-8 lead bytes E4..E9
        lang = sample:find("[\228-\233][\128-\191][\128-\191]") and "zh" or "en"
    elseif culture and culture ~= "" then
        lang = culture:lower():find("^zh") and "zh" or "en"
    end
    return lang or "zh", culture, sample
end

---------------------------------------------------------------- keys
UI.MODIFIERS = { Ctrl = { "LeftControl", "RightControl" }, Alt = { "LeftAlt", "RightAlt" }, Shift = { "LeftShift", "RightShift" } }
UI.MODIFIER_ORDER = { "Ctrl", "Alt", "Shift" }
local MODIFIER_KEYS = { "LeftControl", "RightControl", "LeftAlt", "RightAlt", "LeftShift", "RightShift" }

-- every keyboard key / mouse button a keyboard row can be bound to (UE key names). Escape cancels a capture.
UI.KEYBOARD_KEYS = {}
do
    local k = UI.KEYBOARD_KEYS
    for c = string.byte("A"), string.byte("Z") do k[#k + 1] = string.char(c) end
    for _, n in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do k[#k + 1] = n end
    for i = 1, 12 do k[#k + 1] = "F" .. i end
    for _, n in ipairs({
        "SpaceBar", "Enter", "Tab", "BackSpace", "CapsLock", "Insert", "Delete", "Home", "End", "PageUp", "PageDown",
        "Up", "Down", "Left", "Right",
        "Tilde", "Hyphen", "Equals", "LeftBracket", "RightBracket", "Backslash", "Semicolon", "Apostrophe", "Comma", "Period", "Slash",
        "NumPadZero", "NumPadOne", "NumPadTwo", "NumPadThree", "NumPadFour", "NumPadFive", "NumPadSix", "NumPadSeven",
        "NumPadEight", "NumPadNine", "Multiply", "Add", "Subtract", "Decimal", "Divide",
        "LeftMouseButton", "RightMouseButton", "MiddleMouseButton", "ThumbMouseButton", "ThumbMouseButton2",
    }) do k[#k + 1] = n end
end

-- every gamepad button a gamepad row can be bound to. Stick directions are left out (too easy to hit by accident).
UI.GAMEPAD_KEYS = {
    "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
    "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right",
    "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick", "Gamepad_Special_Left", "Gamepad_Special_Right",
}
UI.MAX_CHORD = 3

local function SetOf(list) local s = {}; for _, n in ipairs(list) do s[n] = true end; return s end
local KEYBOARD_SET, GAMEPAD_SET = SetOf(UI.KEYBOARD_KEYS), SetOf(UI.GAMEPAD_KEYS)

-- what the keys do while the panel is open
UI.NAV = {
    up      = { "Up", "W", "Gamepad_DPad_Up", "Gamepad_LeftStick_Up" },
    down    = { "Down", "S", "Gamepad_DPad_Down", "Gamepad_LeftStick_Down" },
    left    = { "Left", "A", "Gamepad_DPad_Left", "Gamepad_LeftStick_Left" },
    right   = { "Right", "D", "Gamepad_DPad_Right", "Gamepad_LeftStick_Right" },
    confirm = { "Enter", "SpaceBar", "Gamepad_FaceButton_Bottom" },
    back    = { "Escape", "BackSpace", "Gamepad_FaceButton_Right" },
    clear   = { "Delete", "Gamepad_FaceButton_Left" },
    click   = { "LeftMouseButton" },       -- on the row under the cursor: confirm, or step a number up
    rclick  = { "RightMouseButton" },      -- on the row under the cursor: step a number down, clear a binding
}
local NAV_KEYS, NAV_OF = {}, {}
for _, act in ipairs({ "back", "confirm", "clear", "click", "rclick", "up", "down", "left", "right" }) do
    for _, n in ipairs(UI.NAV[act]) do NAV_KEYS[#NAV_KEYS + 1] = n; NAV_OF[n] = act end
end
local NAV_PRIORITY = { back = 9, confirm = 8, clear = 7, click = 6, rclick = 5, up = 4, down = 3, left = 2, right = 1 }
local NAV_REPEATS = { up = true, down = true, left = true, right = true }
local REPEAT_DELAY, REPEAT_EVERY = 0.42, 0.11        -- seconds
local CAPTURE_TIMEOUT = 8                            -- seconds without any key
local DRAIN_SECONDS = 1.5                            -- after closing: longest wait for the keys to be released
local ARMED_SECONDS = 4

local KEY_LABELS = {
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
    SpaceBar = { zh = "空格", en = "Space" }, Enter = { zh = "回车", en = "Enter" }, BackSpace = { zh = "退格", en = "Backspace" },
    Up = { zh = "方向键上", en = "Up" }, Down = { zh = "方向键下", en = "Down" },
    Left = { zh = "方向键左", en = "Left" }, Right = { zh = "方向键右", en = "Right" },
    Tilde = "`", Hyphen = "-", Equals = "=", LeftBracket = "[", RightBracket = "]", Backslash = "\\", Semicolon = ";",
    Apostrophe = "'", Comma = ",", Period = ".", Slash = "/",
    NumPadZero = "Num 0", NumPadOne = "Num 1", NumPadTwo = "Num 2", NumPadThree = "Num 3", NumPadFour = "Num 4",
    NumPadFive = "Num 5", NumPadSix = "Num 6", NumPadSeven = "Num 7", NumPadEight = "Num 8", NumPadNine = "Num 9",
    Multiply = "Num *", Add = "Num +", Subtract = "Num -", Decimal = "Num .", Divide = "Num /",
    LeftMouseButton = { zh = "鼠标左键", en = "Left Mouse" }, RightMouseButton = { zh = "鼠标右键", en = "Right Mouse" },
    MiddleMouseButton = { zh = "鼠标中键", en = "Middle Mouse" },
    ThumbMouseButton = { zh = "鼠标侧键 1", en = "Mouse 4" }, ThumbMouseButton2 = { zh = "鼠标侧键 2", en = "Mouse 5" },
    Gamepad_FaceButton_Bottom = "A", Gamepad_FaceButton_Right = "B", Gamepad_FaceButton_Left = "X", Gamepad_FaceButton_Top = "Y",
    Gamepad_LeftShoulder = "LB", Gamepad_RightShoulder = "RB", Gamepad_LeftTrigger = "LT", Gamepad_RightTrigger = "RT",
    Gamepad_LeftThumbstick = { zh = "L3（按下左摇杆）", en = "L3" }, Gamepad_RightThumbstick = { zh = "R3（按下右摇杆）", en = "R3" },
    Gamepad_DPad_Up = { zh = "十字键上", en = "D-Pad Up" }, Gamepad_DPad_Down = { zh = "十字键下", en = "D-Pad Down" },
    Gamepad_DPad_Left = { zh = "十字键左", en = "D-Pad Left" }, Gamepad_DPad_Right = { zh = "十字键右", en = "D-Pad Right" },
    Gamepad_Special_Left = { zh = "视图键 (View)", en = "View" }, Gamepad_Special_Right = { zh = "菜单键 (Menu)", en = "Menu" },
}

local TXT = {
    on = { zh = "开", en = "On" }, off = { zh = "关", en = "Off" },
    unbound = { zh = "未绑定", en = "Not bound" },
    pressKey = { zh = "请按键 ...", en = "Press a key ..." },
    again = { zh = "再按一次确认", en = "Press again to confirm" },
    captureKey = { zh = "按下要绑定的键盘键或鼠标键；先按住 Alt / Shift 再按可以绑定组合键（Ctrl 已被游戏占用，不建议用）。按 Esc 取消。",
                   en = "Press the keyboard key or mouse button to bind. Hold Alt / Shift first for a combination (Ctrl is used by the game). Esc cancels." },
    capturePad = { zh = "按下要绑定的手柄键再松开。同时按住几个键（最多 3 个）可以绑定组合键，由最后按下的那个键触发。按键盘 Esc 取消，几秒不按也会取消。",
                   en = "Press the gamepad button to bind, then let go. Hold up to 3 buttons together for a chord; the last one pressed triggers it. Esc on the keyboard cancels, and so does waiting a few seconds." },
    cancelled = { zh = "已取消，绑定没有变化。", en = "Cancelled, the binding is unchanged." },
    inUse = { zh = "“%s”已经用来%s，这里不能再绑定。", en = "\"%s\" is already used for %s and cannot be bound here." },
    freed = { zh = "同一个键原来绑定在“%s”，已解除。", en = "The same binding was removed from \"%s\"." },
    keepOne = { zh = "至少要保留一个能打开本界面的键。", en = "Keep at least one binding that opens this panel." },
    footKey = { zh = "方向键 / WASD：选择、调整    Enter / 空格：确认    Delete：清除绑定    Esc / 退格：保存并关闭",
                en = "Arrows / WASD: select, adjust    Enter / Space: confirm    Delete: clear binding    Esc / Backspace: save and close" },
    footMouse = { zh = "    鼠标：左键确认 / 增加，右键减少 / 清除绑定", en = "    Mouse: left click confirms / increases, right click decreases / clears a binding" },
    footPad = { zh = "十字键 / 左摇杆：选择、调整    A：确认    X：清除绑定    B：保存并关闭",
                en = "D-Pad / left stick: select, adjust    A: confirm    X: clear binding    B: save and close" },
}

local function Pick(x, lang)
    if type(x) == "table" then
        if lang == "zh" then return x.zh or x["zh-Hans"] or x.en or "" end
        return x[lang] or x.en or x.zh or x["zh-Hans"] or ""
    end
    if x == nil then return "" end
    return tostring(x)
end

-- "Ctrl+O" -> "Ctrl + O", "Gamepad_LeftShoulder+Gamepad_DPad_Up" -> "LB + D-Pad Up", "" -> "Not bound"
function UI.keyLabel(binding, lang)
    if binding == nil or binding == "" then return Pick(TXT.unbound, lang) end
    local parts = {}
    for part in (binding .. "+"):gmatch("(.-)%+") do
        local known = KEY_LABELS[part]
        parts[#parts + 1] = known and Pick(known, lang) or (part:gsub("^Gamepad_", ""))
    end
    return table.concat(parts, " + ")
end

-- Rows for settings entries in the shape main.lua keeps for the optional ModConfig page:
--   { key, type = "header" | "keybind" | "number" | "toggle" | "choice", label, description,
--     min, max, step, unit, options, allowGamepad, needOne }
-- extras are entries only this panel shows; each one names the key of the entry it follows in `after`.
function UI.rowsFromEntries(entries, extras)
    local list = {}
    for _, e in ipairs(entries) do list[#list + 1] = e end
    for _, x in ipairs(extras or {}) do
        local at = #list
        for i, e in ipairs(list) do if e.key == x.after then at = i end end
        table.insert(list, at + 1, x)
    end
    local rows = {}
    for _, e in ipairs(list) do
        local r = nil
        if e.type == "header" then r = { kind = "header" }
        elseif e.type == "keybind" then r = { kind = "key", key = e.key, device = e.allowGamepad and "gamepad" or "keyboard", needOne = e.needOne }
        elseif e.type == "number" then r = { kind = "number", key = e.key, min = e.min, max = e.max, step = e.step or 1, unit = e.unit }
        elseif e.type == "toggle" then r = { kind = "toggle", key = e.key }
        elseif e.type == "choice" then r = { kind = "choice", key = e.key, options = e.options }
        end
        if r then
            r.label, r.desc = e.label, e.description
            rows[#rows + 1] = r
        end
    end
    return rows
end

---------------------------------------------------------------- view (UMG)
local V_COLLAPSED, V_HIT_INVISIBLE, V_SELF_HIT_INVISIBLE, V_VISIBLE = 1, 3, 4, 0
local H_FILL, H_LEFT, H_CENTER, H_RIGHT = 0, 1, 2, 3
local V_FILL, V_CENTER = 0, 2
local HOST_CLASS = "/Game/PBZContent/UI/FrontEnd/Sense/W_Sense_Quest.W_Sense_Quest_C"
local Z_ORDER = 1200
local PANEL_WIDTH = 920
-- font sizes; about twenty rows have to fit a 1080-unit-high screen together with title, description and footer
local SIZE_TITLE, SIZE_ROW, SIZE_DESC, SIZE_FOOTER = 24, 17, 16, 14

local COLORS = {
    dim     = { R = 0, G = 0, B = 0, A = 0.55 },
    panel   = { R = 0.012, G = 0.012, B = 0.016, A = 0.95 },
    none    = { R = 0, G = 0, B = 0, A = 0 },
    idle    = { R = 1, G = 1, B = 1, A = 0.035 },
    select  = { R = 0.80, G = 0.52, B = 0.14, A = 0.50 },
    capture = { R = 0.16, G = 0.45, B = 0.85, A = 0.60 },
    text    = { R = 0.88, G = 0.88, B = 0.88, A = 1 },
    white   = { R = 1, G = 1, B = 1, A = 1 },
    faint   = { R = 0.50, G = 0.50, B = 0.50, A = 1 },
    accent  = { R = 1, G = 0.74, B = 0.36, A = 1 },
    warn    = { R = 1, G = 0.40, B = 0.28, A = 1 },
}
local ROW_STYLES = {
    idle     = { bg = "idle",    label = "text",   value = "accent" },
    selected = { bg = "select",  label = "white",  value = "white" },
    capture  = { bg = "capture", label = "white",  value = "white" },
    header   = { bg = "none",    label = "accent", value = "faint" },
    info     = { bg = "none",    label = "faint",  value = "faint" },
}

-- Fonts the game is using right now, most used first. The default UMG font may have no Chinese glyphs in a
-- shipping build, so the panel borrows the font object of the game's own text blocks.
local function DiscoverFonts()
    local byName, list = {}, {}
    local ok, blocks = pcall(FindAllOf, "TextBlock")
    if ok and blocks then
        for i, tb in ipairs(blocks) do
            if i > 800 then break end
            pcall(function()
                if not tb:IsValid() then return end
                local font = tb.Font
                local object = font.FontObject
                if object == nil or not object:IsValid() then return end
                local name = tostring(object:GetFullName())
                local entry = byName[name]
                if not entry then
                    entry = { name = name, count = 0, object = object, typeface = Str(font.TypefaceFontName) }
                    byName[name] = entry
                    list[#list + 1] = entry
                end
                entry.count = entry.count + 1
            end)
        end
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

local View = {}
View.__index = View
UI.View = View

-- env: getPC(), log(msg). rows: the menu rows (only their count matters here).
function View.new(env, rows)
    local log = env.log or function() end
    local self = setmetatable({ rows = {}, cache = {}, fonts = {}, warned = {}, log = log }, View)
    local step = "start"
    local ok, err = pcall(function()
        step = "player controller"
        local pc = env.getPC()
        if not Valid(pc) then error("none", 0) end
        self.pcAddress = Address(pc)

        step = "widget library"
        local library = Find("/Script/UMG.Default__WidgetBlueprintLibrary") or error("not found", 0)
        step = "host widget class"
        local hostClass = FindOrLoad(HOST_CLASS) or error("not found", 0)
        step = "host widget"
        local host = library:Create(pc, hostClass, pc)
        if not Valid(host) then error("not created", 0) end
        local tree = host.WidgetTree
        if not Valid(tree) then error("no widget tree", 0) end
        self.host = host

        step = "fonts"
        self.fonts = DiscoverFonts()
        for _, f in ipairs(self.fonts) do
            if not f.name:find("/Engine/", 1, true) then self.font = f; break end
        end
        log(string.format("panel font: %s (%d fonts in use)", self.font and self.font.name or "UMG default", #self.fonts))

        local function new(className)
            step = "create " .. className
            local class = Find("/Script/UMG." .. className) or error("class not found", 0)
            local w = StaticConstructObject(class, tree, 0, 0x40)        -- unnamed, RF_Transient
            if not Valid(w) then error("failed", 0) end
            return w
        end
        local function text(size, color, justify)
            local t = new("TextBlock")
            self:setFont(t, self.font, size)
            self:soft("text colour", function() t:SetColorAndOpacity(SlateColor(COLORS[color])) end)
            self:soft("text visibility", function() t:SetVisibility(V_HIT_INVISIBLE) end)
            if justify then self:soft("text justification", function() t:SetJustification(justify) end) end
            return t
        end
        local function add(parent, child, what, setup)
            step = "add " .. what
            local slot = parent:AddChild(child)
            if setup and Valid(slot) then self:soft("slot of " .. what, function() setup(slot) end) end
            return slot
        end

        -- screen: dim layer + centred panel
        local screen = new("Overlay")
        local dim = new("Border")
        self:soft("dim colour", function() dim:SetBrushColor(COLORS.dim) end)
        self:soft("dim visibility", function() dim:SetVisibility(V_HIT_INVISIBLE) end)
        add(screen, dim, "dim layer", function(s) s:SetHorizontalAlignment(H_FILL); s:SetVerticalAlignment(V_FILL) end)

        local frame = new("SizeBox")
        self:soft("panel width", function() frame:SetWidthOverride(PANEL_WIDTH) end)
        add(screen, frame, "panel frame", function(s) s:SetHorizontalAlignment(H_CENTER); s:SetVerticalAlignment(V_CENTER) end)

        local panel = new("Border")
        self:soft("panel colour", function() panel:SetBrushColor(COLORS.panel) end)
        self:soft("panel padding", function() panel:SetPadding(Margin(30, 22, 30, 18)) end)
        add(frame, panel, "panel")

        local column = new("VerticalBox")
        add(panel, column, "column")

        self.title = text(SIZE_TITLE, "white")
        add(column, self.title, "title", function(s) s:SetPadding(Margin(4, 0, 4, 10)) end)

        for i = 1, #rows do
            local bg = new("Border")
            self:soft("row colour", function() bg:SetBrushColor(COLORS.idle) end)
            self:soft("row padding", function() bg:SetPadding(Margin(14, 4, 14, 4)) end)
            self:soft("row visibility", function() bg:SetVisibility(V_VISIBLE) end)
            add(column, bg, "row", function(s) s:SetPadding(Margin(0, 1, 0, 1)) end)
            local line = new("HorizontalBox")
            add(bg, line, "row line")
            local label = text(SIZE_ROW, "text")
            self:soft("label wrap", function() label:SetAutoWrapText(true) end)
            add(line, label, "row label", function(s) s:SetSize({ Value = 1.0, SizeRule = 1 }); s:SetVerticalAlignment(V_CENTER) end)
            local value = text(SIZE_ROW, "accent", 2)
            add(line, value, "row value", function(s)
                s:SetPadding(Margin(24, 0, 0, 0)); s:SetHorizontalAlignment(H_RIGHT); s:SetVerticalAlignment(V_CENTER)
            end)
            self.rows[i] = { bg = bg, label = label, value = value }
        end

        self.note = text(SIZE_DESC, "warn")
        self:soft("note wrap", function() self.note:SetAutoWrapText(true) end)
        self:soft("note visibility", function() self.note:SetVisibility(V_COLLAPSED) end)
        add(column, self.note, "note", function(s) s:SetPadding(Margin(4, 8, 4, 0)) end)
        self.desc = text(SIZE_DESC, "text")
        self:soft("description wrap", function() self.desc:SetAutoWrapText(true) end)
        add(column, self.desc, "description", function(s) s:SetPadding(Margin(4, 8, 4, 0)) end)
        self.footer = text(SIZE_FOOTER, "faint")
        self:soft("footer wrap", function() self.footer:SetAutoWrapText(true) end)
        add(column, self.footer, "footer", function(s) s:SetPadding(Margin(4, 12, 4, 0)) end)

        -- our screen replaces the host's own content before the host is first drawn
        step = "attach to host"
        tree.RootWidget = screen
        if Address(tree.RootWidget) ~= Address(screen) then
            log("host root could not be replaced, adding the panel to the host's root instead")
            local root = tree.RootWidget
            local slot = root:AddChild(screen)
            self:soft("host slot", function() slot:SetHorizontalAlignment(H_FILL); slot:SetVerticalAlignment(V_FILL) end)
        end
        step = "add to viewport"
        host:SetVisibility(V_COLLAPSED)
        host:AddToViewport(Z_ORDER)
    end)
    if not ok then return nil, step .. ": " .. tostring(err) end
    return self
end

-- a setter that failed is logged once and otherwise ignored: the panel should still come up
function View:soft(what, fn)
    local ok, err = pcall(fn)
    if not ok and not self.warned[what] then
        self.warned[what] = true
        if self.log then self.log("panel: " .. what .. " failed: " .. tostring(err)) end
    end
    return ok
end

function View:setFont(textBlock, font, size)
    self:soft("font", function()
        local info = { Size = size, LetterSpacing = 0 }
        if font and Valid(font.object) then
            info.FontObject = font.object
            if font.typeface and font.typeface ~= "" and font.typeface ~= "None" then
                info.TypefaceFontName = UEHelpers.FindOrAddFName(font.typeface)
            end
        else
            local own = textBlock.Font
            info.FontObject = own.FontObject
            info.TypefaceFontName = own.TypefaceFontName
        end
        textBlock:SetFont(info)
    end)
end

function View:alive(pc)
    return self.host ~= nil and self.pcAddress ~= nil and self.pcAddress == Address(pc) and Valid(self.host)
end

function View:setText(widget, slot, s)
    if self.cache[slot] == s then return end
    self.cache[slot] = s
    self:soft("text", function() widget:SetText(ToText(s)) end)
end

function View:setTitle(s) self:setText(self.title, "title", s) end
function View:setDesc(s) self:setText(self.desc, "desc", s) end
function View:setNote(s)            -- takes no room while there is nothing to say
    if self.cache.note == s then return end
    self:setText(self.note, "note", s)
    self:soft("note visibility", function() self.note:SetVisibility(s == "" and V_COLLAPSED or V_HIT_INVISIBLE) end)
end
function View:setFooter(s) self:setText(self.footer, "footer", s) end

function View:setRow(i, label, value, style)
    local r = self.rows[i]
    if not r then return end
    self:setText(r.label, "label" .. i, label)
    self:setText(r.value, "value" .. i, value)
    if self.cache["style" .. i] ~= style then
        self.cache["style" .. i] = style
        local st = ROW_STYLES[style] or ROW_STYLES.idle
        self:soft("row style", function()
            r.bg:SetBrushColor(COLORS[st.bg])
            r.label:SetColorAndOpacity(SlateColor(COLORS[st.label]))
            r.value:SetColorAndOpacity(SlateColor(COLORS[st.value]))
        end)
    end
end

-- row i drawn with another font (used to compare fonts)
function View:setRowFont(i, font, size)
    local r = self.rows[i]
    if not r then return end
    self:setFont(r.label, font, size or SIZE_ROW)
    self:setFont(r.value, font, size or SIZE_ROW)
end

-- index of the row under the mouse cursor, or nil
function View:hovered()
    for i, r in ipairs(self.rows) do
        local ok, h = pcall(function() return r.bg:IsHovered() end)
        if ok and h == true then return i end
    end
    return nil
end

function View:show() self:soft("show", function() self.host:SetVisibility(V_SELF_HIT_INVISIBLE) end) end
function View:hide() self:soft("hide", function() self.host:SetVisibility(V_COLLAPSED) end) end

---------------------------------------------------------------- keeping the game from reacting to the keys
-- "pause"   : pause the game while the panel is open (the PlayerController still reads keys while paused)
-- "disable" : switch off the input of the player pawn and controller
-- "none"    : leave the game alone
local Block = {}
UI.Block = Block

function Block.apply(mode, pc, log)
    local state = { mode = mode, pcAddress = Address(pc) }
    if mode == "pause" then
        local statics, ctx = UEHelpers.GetGameplayStatics(), UEHelpers.GetWorldContextObject()
        state.wasPaused = statics:IsGamePaused(ctx) == true
        if not state.wasPaused then
            state.result = statics:SetGamePaused(ctx, true)
            state.paused = statics:IsGamePaused(ctx) == true
        end
        log(string.format("input block: pause (was paused %s, SetGamePaused -> %s, paused now %s)",
            tostring(state.wasPaused), tostring(state.result), tostring(state.paused)))
        state.ok = state.wasPaused or state.paused == true
    elseif mode == "disable" then
        local pawn = pc:K2_GetPawn()
        if Valid(pawn) then
            pawn:DisableInput(pc)
            state.pawn, state.pawnAddress = pawn, Address(pawn)
        end
        pc:DisableInput(pc)
        log("input block: input of pawn and controller disabled" .. (state.pawn and "" or " (no pawn)"))
        state.ok = true
    else
        log("input block: none")
        state.ok = true
    end
    return state
end

function Block.release(state, pc, log)
    if not state then return end
    if not Valid(pc) or Address(pc) ~= state.pcAddress then
        log("input block: the world changed, nothing to release")
        return
    end
    if state.mode == "pause" then
        if not state.wasPaused then
            local statics, ctx = UEHelpers.GetGameplayStatics(), UEHelpers.GetWorldContextObject()
            local r = statics:SetGamePaused(ctx, false)
            log("input block: unpaused (SetGamePaused -> " .. tostring(r) .. ")")
        end
    elseif state.mode == "disable" then
        pc:EnableInput(pc)
        local pawn = pc:K2_GetPawn()
        if Valid(pawn) and Address(pawn) == state.pawnAddress then pawn:EnableInput(pc) end
        log("input block: input enabled again")
    end
end

---------------------------------------------------------------- menu
-- env:
--   rows            row descriptions (see the top of this file)
--   title           L
--   load()          -> table of current values (copied)
--   commit(values)  called on close when something changed
--   defaults        table key -> default value (for menu.resetDefaults)
--   keyDown(pc, name) -> boolean
--   getPC()         -> PlayerController
--   log(msg), now() (seconds), lang(values) -> "zh" | "en" (asked again whenever a value changes)
--   block           "pause" | "disable" | "none" (default "pause");  mouse = true shows the cursor and follows it
--   newView(env, rows) -> view   (tests)
--   allKeys = true  sample every bindable key on every tick and keep the last presses in menu.recent (diagnostics)
--   idleClose       seconds without any key press after which the panel closes itself (nil = never)
function UI.new(env)
    local log = env.log or function() end
    local now = env.now or os.clock
    local rows = env.rows
    local M = { isOpen = false, values = {}, sel = 1, lang = "zh", device = "keyboard", note = nil, capture = nil,
                view = nil, dirty = false, recent = {}, block = env.block or "pause", mouse = env.mouse == true,
                failures = 0, lastTick = 0 }
    local prev, hold, armed, blockState, hoverRow, mouseWas, draining = {}, nil, nil, nil, nil, nil, nil
    local serial = 0

    local selectable = {}
    for i, r in ipairs(rows) do
        if r.kind ~= "header" and r.kind ~= "info" then selectable[#selectable + 1] = i end
    end

    local function T(x)
        if type(x) == "function" then x = x(M) end
        return Pick(x, M.lang)
    end
    M.text = T

    local function Number(v)
        if type(v) == "number" and v == math.floor(v) then return string.format("%d", v) end
        return tostring(v)
    end

    local function ValueText(r, selected)
        local v = M.values[r.key]
        if r.kind == "number" then
            local s = Number(v) .. (r.unit and (" " .. T(r.unit)) or "")
            return selected and ("<   " .. s .. "   >") or s
        elseif r.kind == "toggle" then
            return T(v and TXT.on or TXT.off)
        elseif r.kind == "choice" then
            local s = tostring(v)
            for _, o in ipairs(r.options) do if o.value == v then s = T(o.label) end end
            return selected and ("<   " .. s .. "   >") or s
        elseif r.kind == "key" then
            if M.capture and M.capture.row == r then
                if #M.capture.chord > 0 then return UI.keyLabel(table.concat(M.capture.chord, "+"), M.lang) .. " ..." end
                return T(TXT.pressKey)
            end
            return UI.keyLabel(v, M.lang)
        elseif r.kind == "action" then
            return (armed and armed.row == r) and T(TXT.again) or ""
        elseif r.kind == "info" then
            return T(r.value)
        end
        return ""
    end

    local function Render()
        local view = M.view
        if not view then return end
        view:setTitle(T(env.title))
        local current = rows[selectable[M.sel]]
        for i, r in ipairs(rows) do
            local selected = (r == current)
            local style = (r.kind == "header" and "header") or (r.kind == "info" and "info")
                or (selected and ((M.capture and "capture") or "selected")) or "idle"
            view:setRow(i, T(r.label), ValueText(r, selected), style)
        end
        local desc = ""
        if M.capture then desc = T(M.capture.device == "gamepad" and TXT.capturePad or TXT.captureKey)
        elseif current then desc = T(current.desc) end
        view:setNote(M.note or "")
        view:setDesc(desc)
        view:setFooter(M.device == "gamepad" and T(TXT.footPad) or (T(TXT.footKey) .. (M.mouse and T(TXT.footMouse) or "")))
    end
    M.render = Render

    local function SetValue(r, v)
        if M.values[r.key] == v then return end
        M.values[r.key] = v
        M.dirty = true
        if env.lang then M.lang = env.lang(M.values) or M.lang end
        if r.onChange then
            local ok, err = pcall(r.onChange, M, v)
            if not ok then log("onChange " .. tostring(r.key) .. " failed: " .. tostring(err)) end
        end
    end

    -- rows that share needOne = <group> must not all end up unbound
    local function WouldOrphan(r, newValue)
        if not r.needOne or newValue ~= "" then return false end
        for _, o in ipairs(rows) do
            if o ~= r and o.needOne == r.needOne and (M.values[o.key] or "") ~= "" then return false end
        end
        return true
    end

    local function ForgetCaptureKeys()
        for name in pairs(prev) do
            if not NAV_OF[name] then prev[name] = nil end
        end
    end

    local function BeginCapture(r)
        M.capture = { row = r, device = r.device, started = now(), chord = {} }
        M.note = nil
        ForgetCaptureKeys()
    end

    local function FinishCapture(binding)
        local c = M.capture
        M.capture = nil
        ForgetCaptureKeys()
        if not binding then M.note = T(TXT.cancelled); return end
        local r = c.row
        local same = {}
        for _, o in ipairs(rows) do
            if o.kind == "key" and o ~= r and M.values[o.key] == binding then
                if WouldOrphan(o, "") then
                    M.note = string.format(T(TXT.inUse), UI.keyLabel(binding, M.lang), T(o.label))
                    return
                end
                same[#same + 1] = o
            end
        end
        local names = {}
        for _, o in ipairs(same) do SetValue(o, ""); names[#names + 1] = T(o.label) end
        SetValue(r, binding)
        M.note = #names > 0 and string.format(T(TXT.freed), table.concat(names, " / ")) or nil
        log(string.format("bound %s = '%s'", tostring(r.key), binding))
    end

    local function Adjust(r, dir)
        if r.kind == "number" then
            local v = (tonumber(M.values[r.key]) or r.min) + dir * r.step
            SetValue(r, math.max(r.min, math.min(r.max, v)))
        elseif r.kind == "toggle" then
            SetValue(r, not M.values[r.key])
        elseif r.kind == "choice" then
            local at = 1
            for i, o in ipairs(r.options) do if o.value == M.values[r.key] then at = i end end
            SetValue(r, r.options[((at - 1 + dir) % #r.options) + 1].value)
        end
    end

    local function Activate(r)
        if r.kind == "toggle" then SetValue(r, not M.values[r.key])
        elseif r.kind == "choice" then Adjust(r, 1)
        elseif r.kind == "key" then BeginCapture(r)
        elseif r.kind == "action" then
            if r.confirm and not (armed and armed.row == r and now() < armed.expires) then
                armed = { row = r, expires = now() + ARMED_SECONDS }
                return
            end
            armed = nil
            r.run(M)
        end
    end

    local function Clear(r)
        if r.kind ~= "key" then return end
        if WouldOrphan(r, "") then M.note = T(TXT.keepOne); return end
        SetValue(r, "")
    end

    function M.resetDefaults()
        for _, r in ipairs(rows) do
            if r.key ~= nil and env.defaults and env.defaults[r.key] ~= nil then SetValue(r, env.defaults[r.key]) end
        end
    end

    local function Do(act)
        local r = rows[selectable[M.sel]]
        M.note = nil
        if act ~= "confirm" and act ~= "click" then armed = nil end
        if act == "up" or act == "down" then
            if #selectable > 0 then M.sel = ((M.sel - 1 + (act == "up" and -1 or 1)) % #selectable) + 1 end
        elseif act == "left" then if r then Adjust(r, -1) end
        elseif act == "right" then if r then Adjust(r, 1) end
        elseif act == "confirm" then if r then Activate(r) end
        elseif act == "clear" then if r then Clear(r) end
        elseif act == "click" then
            if r and r.kind == "number" then Adjust(r, 1) elseif r then Activate(r) end
        elseif act == "rclick" then
            if r and r.kind == "number" then Adjust(r, -1) elseif r then Clear(r) end
        elseif act == "back" then M.close("back") end
    end

    local function Sample(pc, names, down)
        for _, n in ipairs(names) do
            if down[n] == nil then down[n] = env.keyDown(pc, n) == true end
        end
    end

    -- press / release edges against the previous sample. A key seen for the first time only sets its baseline,
    -- so keys that are already held (the one that opened the panel or started a capture) do nothing until released.
    local function Edges(names, down, pressed, released)
        for _, n in ipairs(names) do
            local d, was = down[n], prev[n]
            if d ~= nil then
                if was ~= nil and d ~= was then
                    if d then pressed[#pressed + 1] = n elseif released then released[#released + 1] = n end
                end
                prev[n] = d
            end
        end
    end

    local function Remember(names)
        for _, n in ipairs(names) do
            table.insert(M.recent, 1, n)
            if #M.recent > 6 then table.remove(M.recent) end
            if env.onKey then pcall(env.onKey, n) end
        end
    end

    local function TickNav(pc, t)
        local down, pressed = {}, {}
        Sample(pc, NAV_KEYS, down)
        Edges(NAV_KEYS, down, pressed)
        if env.allKeys then
            local extra = {}
            for _, list in ipairs({ UI.KEYBOARD_KEYS, UI.GAMEPAD_KEYS, MODIFIER_KEYS }) do
                Sample(pc, list, down)
                Edges(list, down, extra)
            end
            Remember(pressed); Remember(extra)
        end

        local hovered = nil
        if M.mouse and M.view.hovered then
            hovered = M.view:hovered()
            if hovered ~= hoverRow then
                hoverRow = hovered
                for si, ri in ipairs(selectable) do
                    if ri == hovered and M.sel ~= si then M.sel = si; armed = nil; M.note = nil end
                end
            end
        end
        M.hoverRow = hovered

        local act, actKey = nil, nil
        if #pressed > 0 then M.lastInput = t end
        for _, name in ipairs(pressed) do
            M.device = name:find("^Gamepad_") and "gamepad" or "keyboard"
            local a = NAV_OF[name]
            if (a == "click" or a == "rclick") and not (hovered ~= nil and hovered == selectable[M.sel]) then a = nil end
            if a and (not act or NAV_PRIORITY[a] > NAV_PRIORITY[act]) then act, actKey = a, name end
        end
        if act then
            hold = NAV_REPEATS[act] and { act = act, key = actKey, next = t + REPEAT_DELAY } or nil
            Do(act)
        elseif hold then
            if down[hold.key] then
                if t >= hold.next then hold.next = t + REPEAT_EVERY; Do(hold.act) end
            else
                hold = nil
            end
        end
    end

    local function TickCapture(pc, t)
        local c = M.capture
        local keys = c.device == "gamepad" and UI.GAMEPAD_KEYS or UI.KEYBOARD_KEYS
        local down, pressed = {}, {}
        Sample(pc, keys, down); Sample(pc, MODIFIER_KEYS, down); Sample(pc, NAV_KEYS, down)
        Edges(keys, down, pressed); Edges(MODIFIER_KEYS, down, {}); Edges(NAV_KEYS, down, pressed)
        if env.allKeys then Remember(pressed) end
        if #pressed > 0 then M.lastInput = t end
        for _, n in ipairs(pressed) do
            if n == "Escape" then FinishCapture(nil); return end
        end
        if c.device == "gamepad" then
            for _, n in ipairs(pressed) do
                if GAMEPAD_SET[n] and #c.chord < UI.MAX_CHORD then
                    local have = false
                    for _, x in ipairs(c.chord) do if x == n then have = true end end
                    if not have then c.chord[#c.chord + 1] = n end
                end
            end
            if #c.chord > 0 then
                for _, n in ipairs(c.chord) do
                    if not down[n] then FinishCapture(table.concat(c.chord, "+")); return end
                end
            elseif t - c.started > CAPTURE_TIMEOUT then
                FinishCapture(nil)
            end
        else
            for _, n in ipairs(pressed) do
                if KEYBOARD_SET[n] then
                    local parts = {}
                    for _, m in ipairs(UI.MODIFIER_ORDER) do
                        if down[UI.MODIFIERS[m][1]] or down[UI.MODIFIERS[m][2]] then parts[#parts + 1] = m end
                    end
                    parts[#parts + 1] = n
                    FinishCapture(table.concat(parts, "+"))
                    return
                end
            end
            if t - c.started > CAPTURE_TIMEOUT then FinishCapture(nil) end
        end
    end

    local function SetMouse(pc, on)
        pcall(function()
            if on then
                if mouseWas == nil then mouseWas = pc.bShowMouseCursor == true end
                pc.bShowMouseCursor = true
            elseif mouseWas ~= nil then
                pc.bShowMouseCursor = mouseWas
                mouseWas = nil
            end
        end)
    end

    local function ReleaseBlock(pc)
        local state = blockState
        blockState = nil
        if not state then return end
        local ok, err = pcall(Block.release, state, pc, log)
        if not ok then log("input block release failed: " .. tostring(err)) end
    end

    local function ApplyBlock(pc)
        local ok, state = pcall(Block.apply, M.block, pc, log)
        if ok then blockState = state else log("input block '" .. tostring(M.block) .. "' failed: " .. tostring(state)) end
        if not ok or not state.ok then
            if M.block ~= "disable" then          -- pausing not possible: fall back to switching the input off
                ReleaseBlock(pc)
                local ok2, state2 = pcall(Block.apply, "disable", pc, log)
                if ok2 then blockState = state2 end
            end
        end
    end

    -- change the block mode / mouse mode while the panel is open (diagnostics)
    function M.setBlock(mode)
        M.block = mode
        if not M.isOpen then return end
        local pc = env.getPC()
        ReleaseBlock(pc)
        ApplyBlock(pc)
    end
    function M.setMouse(on)
        M.mouse = on == true
        if M.isOpen then SetMouse(env.getPC(), M.mouse) end
    end

    function M.isCapturing() return M.isOpen and M.capture ~= nil end
    -- true while the panel is open, and for the moment after closing in which the game is still held back
    function M.busy() return M.isOpen or draining ~= nil end

    -- Safety net: if the caller's poll loop stops while the game is held back (paused), nothing would ever
    -- give the game back. A timer outside that loop notices and lets go.
    local function Watchdog(mySerial)
        if not M.busy() or mySerial ~= serial then return end
        if now() - M.lastTick > 3 then
            ExecuteInGameThread(function()
                if M.busy() and mySerial == serial then
                    log("the panel stopped receiving ticks, closing it")
                    M.forceClose("watchdog")
                end
            end)
            return
        end
        ExecuteWithDelay(1000, function() Watchdog(mySerial) end)
    end

    local function Drain(pc)
        if not Valid(pc) or not blockState or Address(pc) ~= blockState.pcAddress then
            blockState, draining = nil, nil                 -- the world changed: nothing to give back
            return
        end
        local held = false
        if now() - draining.since < DRAIN_SECONDS then
            for _, list in ipairs({ NAV_KEYS, UI.KEYBOARD_KEYS, UI.GAMEPAD_KEYS }) do
                for _, n in ipairs(list) do
                    if env.keyDown(pc, n) == true then held = true; break end
                end
                if held then break end
            end
        end
        if not held then
            draining = nil
            ReleaseBlock(pc)
        end
    end

    function M.open(pc)
        if M.isOpen then return true end
        if M.failures >= 3 then return false, "disabled after repeated failures" end
        if not (M.view and M.view:alive(pc)) then
            M.view = nil
            local view, err = (env.newView or View.new)(env, rows)
            if not view then
                M.failures = M.failures + 1
                log("settings panel unavailable: " .. tostring(err))
                return false, err
            end
            M.view = view
            if env.onView then pcall(env.onView, M, view) end
        end
        M.failures = 0
        M.values = {}
        for k, v in pairs(env.load()) do M.values[k] = v end
        M.lang = (env.lang and env.lang(M.values)) or UI.detectLanguage()
        M.dirty, M.note, M.capture, armed, hold, hoverRow = false, nil, nil, nil, nil, nil
        prev = {}
        if M.sel > #selectable then M.sel = 1 end
        M.isOpen = true
        M.lastTick = now()
        M.lastInput = M.lastTick
        serial = serial + 1
        draining = nil
        if not blockState then ApplyBlock(pc) end       -- still held when the panel is reopened right after closing
        if M.mouse then SetMouse(pc, true) end
        Render()
        M.view:show()
        if type(ExecuteWithDelay) == "function" and type(ExecuteInGameThread) == "function" and not env.noWatchdog then
            local mySerial = serial
            ExecuteWithDelay(1000, function() Watchdog(mySerial) end)
        end
        log("settings panel opened")
        return true
    end

    local function Finish(reason, touchGame)
        M.isOpen = false
        M.capture, hold, armed = nil, nil, nil
        if touchGame then
            local pc = env.getPC()
            if M.view then M.view:hide() end
            if Valid(pc) then SetMouse(pc, false) end
            -- The key that closed the panel is still down. Released now, the game would act on it (Esc would open
            -- the pause menu, B would dodge), so the block stays until the keys are up: see M.tick.
            if blockState then draining = { since = now() } end
        else
            M.view, blockState, mouseWas, draining = nil, nil, nil, nil
        end
        log("settings panel closed (" .. tostring(reason) .. ")" .. (M.dirty and ", saving" or ""))
        if M.dirty and env.commit then
            local copy = {}
            for k, v in pairs(M.values) do copy[k] = v end
            local ok, err = pcall(env.commit, copy)
            if not ok then log("saving the settings failed: " .. tostring(err)) end
        end
        M.dirty = false
        if env.onClose then pcall(env.onClose, M, reason) end
    end

    function M.close(reason)
        if not M.isOpen then return end
        Finish(reason or "closed", true)
    end

    -- close and give the game back at once, without waiting for the keys to be released
    function M.forceClose(reason)
        if M.isOpen then Finish(reason or "forced", true) end
        if draining then
            draining = nil
            ReleaseBlock(env.getPC())
        end
    end

    -- one poll step while the panel is open
    function M.tick(pc)
        if not M.isOpen then
            if draining then M.lastTick = now(); Drain(pc) end
            return
        end
        if not M.view or not M.view:alive(pc) then
            Finish("the world changed", false)      -- the widgets died with the old world: touch none of them
            return
        end
        local t = now()
        M.lastTick = t
        if armed and t >= armed.expires then armed = nil end
        if M.capture then TickCapture(pc, t) else TickNav(pc, t) end
        if M.isOpen and env.idleClose and t - M.lastInput > env.idleClose then M.close("no input") end
        if M.isOpen then Render() end
    end

    return M
end

return UI
