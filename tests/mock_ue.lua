-- A small stand-in for the UE4SS Lua environment, enough to load the mod's scripts outside the game.
-- UObjects are tables that accept any method call and record it; a few methods and properties behave.
local Mock = {
    keys = {},            -- key name -> true while "held"
    paused = false, pauseAllowed = true,
    culture = "zh-Hans", gameText = "新游戏",
    missing = {},         -- object paths StaticFindObject should not find
    all = {},             -- short class name -> list for FindAllOf
    async = {},           -- callbacks queued by ExecuteWithDelay
    timers = {},          -- callbacks queued by ExecuteInGameThreadWithDelay
    constructed = {},     -- everything StaticConstructObject made
    output = {},          -- lines printed by the scripts
}

local nextAddress = 0x1000
local PROPERTIES = { WidgetTree = true, RootWidget = true, Font = true, FontObject = true, TypefaceFontName = true,
                     bShowMouseCursor = true, Slot = true, Pawn = true }
local Methods = {}
local ObjectMT = {}

function Mock.object(name, fields)
    local o = { __name = name, __address = nextAddress, __calls = {}, __valid = true }
    nextAddress = nextAddress + 16
    for k, v in pairs(fields or {}) do o[k] = v end
    return setmetatable(o, ObjectMT)
end

function Mock.fname(name)
    return { name = name, ToString = function() return name end }
end

function Mock.calls(o, method)
    local n = 0
    for _, c in ipairs(o.__calls) do if c.name == method then n = n + 1 end end
    return n
end

ObjectMT.__index = function(self, key)
    if type(key) ~= "string" or key:sub(1, 2) == "__" then return nil end
    if Methods[key] then return Methods[key] end
    if PROPERTIES[key] then return nil end
    return function(obj, ...)
        obj.__calls[#obj.__calls + 1] = { name = key, args = { ... } }
        return nil
    end
end

local function method(name, fn)
    Methods[name] = function(obj, ...)
        obj.__calls[#obj.__calls + 1] = { name = name, args = { ... } }
        return fn(obj, ...)
    end
end

method("IsValid", function(o) return o.__valid end)
method("GetAddress", function(o) return o.__address end)
method("GetFullName", function(o) return o.__name end)
method("GetFName", function(o) return Mock.fname(o.__name) end)
method("GetClass", function(o) return o.__class or Mock.object("Class") end)
method("AddChild", function(o, child)
    o.__children = o.__children or {}
    o.__children[#o.__children + 1] = child
    local slot = Mock.object("slot of " .. tostring(child.__name))
    child.__slot = slot
    return slot
end)
method("Create", function(_, _, class)
    return Mock.object("widget " .. tostring(class.__name), { WidgetTree = Mock.object("WidgetTree", { RootWidget = Mock.object("host root") }) })
end)
method("AddToViewport", function(o, z) o.__viewport = z end)
method("SetVisibility", function(o, v) o.__visibility = v end)
method("SetText", function(o, t) o.__text = t and t.text end)
method("SetBrushColor", function(o, c) o.__brush = c end)
method("SetColorAndOpacity", function(o, c) o.__color = c end)
method("SetFont", function(o, f) o.__font = f end)
method("IsHovered", function(o) return o.__hovered == true end)
method("IsInputKeyDown", function(_, key) return Mock.keys[key.KeyName.name] == true end)
method("K2_GetPawn", function() return Mock.pawn end)
method("DisableInput", function(o) o.__input = false end)
method("EnableInput", function(o) o.__input = true end)
method("IsGamePaused", function() return Mock.paused end)
method("SetGamePaused", function(_, _, p)
    if not Mock.pauseAllowed then return false end
    Mock.paused = p
    return true
end)
method("Conv_StringToText", function(_, s) return { text = s } end)
method("GetCurrentLanguage", function() return Mock.culture end)
method("GetCurrentCulture", function() return Mock.culture end)
method("MakeTextByKey", function() local s = Mock.gameText; return { ToString = function() return s end } end)
method("GetLocalPlayerSubSystemFromPlayerController", function() return Mock.router end)
method("GetActiveInputMode", function() return Mock.inputMode or 1 end)

local found = {}
function StaticFindObject(path)
    if Mock.missing[path] then return Mock.object("missing " .. path, { __valid = false }) end
    if not found[path] then found[path] = Mock.object(path) end
    return found[path]
end

function StaticConstructObject(class, outer)
    local o = Mock.object("new " .. (class.__name:match("([^.]+)$") or class.__name), { __class = class, __outer = outer })
    Mock.constructed[#Mock.constructed + 1] = o
    return o
end

function FindAllOf(short) return Mock.all[short] end
function FindFirstOf(short) return (Mock.all[short] or {})[1] end
function FText(s) return { text = s } end
function LoadAsset() end
function ExecuteWithDelay(ms, fn) Mock.async[#Mock.async + 1] = { ms = ms, fn = fn } end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(ms, fn) Mock.timers[#Mock.timers + 1] = { ms = ms, fn = fn } end
function RegisterKeyBind() end
function RegisterHook() end
Key = setmetatable({}, { __index = function(_, k) return k end })

local realPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    Mock.output[#Mock.output + 1] = (table.concat(parts, "\t"):gsub("\n$", ""))
    if Mock.echo then realPrint(...) end
end
Mock.print = realPrint

-- run the callbacks queued by ExecuteInGameThreadWithDelay once (each may queue the next round)
function Mock.pump()
    local batch = Mock.timers
    Mock.timers = {}
    for _, t in ipairs(batch) do t.fn() end
    return #batch
end

function Mock.reset()
    Mock.keys, Mock.paused, Mock.pauseAllowed = {}, false, true
    Mock.culture, Mock.gameText = "zh-Hans", "新游戏"
    Mock.missing, Mock.async, Mock.timers, Mock.constructed, Mock.output = {}, {}, {}, {}, {}
    Mock.pc = Mock.object("PlayerController", { bShowMouseCursor = false })
    Mock.pawn = Mock.object("Pawn")
    Mock.statics = Mock.object("GameplayStatics")
    Mock.world = Mock.object("World")
    Mock.router = Mock.object("Router")
    Mock.inputMode = 1
    local font = Mock.object("Font /Game/PBZContent/UI/Fonts/GameFont.GameFont")
    local engineFont = Mock.object("Font /Engine/EngineFonts/Roboto.Roboto")
    Mock.all = { TextBlock = {
        Mock.object("TextBlock a", { Font = { FontObject = engineFont, TypefaceFontName = Mock.fname("Bold") } }),
        Mock.object("TextBlock b", { Font = { FontObject = font, TypefaceFontName = Mock.fname("Regular") } }),
        Mock.object("TextBlock c", { Font = { FontObject = font, TypefaceFontName = Mock.fname("Regular") } }),
    } }
end
Mock.reset()

package.preload["UEHelpers"] = function()
    return {
        GetPlayerController = function() return Mock.pc end,
        GetPlayer = function() return Mock.pawn end,
        GetGameplayStatics = function() return Mock.statics end,
        GetWorldContextObject = function() return Mock.world end,
        FindOrAddFName = function(name) return Mock.fname(name) end,
    }
end

return Mock
