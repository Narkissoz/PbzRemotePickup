-- PbzRemotePickup v0.10
-- Settings (pickup key for keyboard/mouse and gamepad, pickup range, one-per-press, skip hidden, skip
-- equipment) are saved to settings.json in this mod folder. If the separate "PbzModConfig" mod is installed,
-- they also appear in the game's Settings > Mods page; its client files are loaded from that mod's own folder
-- (Mods/PbzModConfig/Scripts) at runtime, nothing of it is bundled here. Without it, edit settings.json.
-- The pickup key is read by polling PlayerController input.
-- v0.10: hotkeys that work without any settings UI - cycle the pickup range (25/50/100/150/200 m) and toggle
-- "skip equipment" - each with a short on-screen message (UMG text added to the viewport; log only if that fails).
--
-- Debug keys, disabled by default (uncomment the RegisterKeyBind lines below "debug keys" to use them):
-- F9 : diagnostic scan (read-only) -> scan_report.txt
--     nearby actors, the player's interact component, BP_Rubbish (world pickups) census,
--     reflection + property values of the nearest BP_Rubbish.
-- F10: toggle the pickup MONITOR. Hooks interaction / backpack / level-actor / BP_Rubbish functions
--     and logs every call -> monitor_log.txt. Turn it on, pick an item up by hand, turn it off.
--
-- Pickup key (default O) : remote pickup. Nearest eligible BP_Rubbish: call its own OnInteract(player),
--     which is exactly what the game runs when you press interact next to it (captured with the monitor:
--     StartInteract -> BP_Rubbish:OnInteract -> AddPropsByMap -> CompleteActorSaveData -> Pickup).
--     Fallback if the item is still there: SetCurrentInteractActor + StartInteract (button-press path).
--     One item per press while PullOnePerPress is true.
--
-- World pickups in this game are BP_Rubbish actors (BP_Rubbish_C, BP_Rubbish_b_C, ...). Quest items (IDs K_* / I_*) are skipped by an ID check.
-- v0.8: also skipped
--   * scripted pickups: the item is wired into a story flow (flow identity tags, tags added on pickup,
--     or a quest it starts). Picking these remotely skips their story event - e.g. the first dual blades
--     in Xigu, whose pickup event unlocks the way forward.
--   * equipment (setting, on by default): weapons / accessories / medicines, and any item whose ID is not a
--     known material or consumable pattern. Equipment pickups also raise the NG+ (+1) level of the copy you own.

local UEHelpers = require("UEHelpers")

---------------------------------------------------------------- config
local Config = {
    ScanRadius       = 1500,  -- cm, P lists actors within 15 m
    ScanMaxRows      = 80,
    DumpMaxLines     = 200,

    PullRadius       = 5000,  -- cm, O considers BP_Rubbish within 50 m
    PullOnePerPress  = true,  -- experimental: one item per O press
    VerifyDelayMs    = 500,   -- wait before checking whether the item was picked up
    BetweenItemsMs   = 900,   -- gap between items when PullOnePerPress is false
    SkipHidden       = true,
    PickupClassPrefixes = { "BP_Rubbish" },          -- world pickup actor classes
    QuestIdPrefixes  = { "K_", "I_" },               -- quest item IDs
    DenyKeywords     = { "quest", "task", "mission", "renwu" },
    SkipEquipment    = true,
    EquipFields      = { GetWeapons = true, ReallyGetWeapons = true, Medicines = true, Accessories = true,
                         ReallyMedicines = true, ReallyAccessories = true },
    -- item IDs known to be materials / consumables (everything else counts as equipment when SkipEquipment)
    ResourceIdPatterns = { "^Weapon_Material_", "^Medi_Material_", "^Ac_Material_", "^R_%d", "^Item_",
                           "^Return_", "^T_%d", "^Page_", "^Dust" },
    LateCheckMs      = 500,   -- after a FAILED pickup, keep checking at this interval ...
    LateCheckTries   = 12,    -- ... this many times (6 s) and log LATE if it went through after all

    MonitorMaxPerFunc = 40,   -- log at most this many calls per hooked function per monitor session
}

local PICKUP_CLASS   = "/Script/ProjectPBZ.PBZPickupActor"
local INTERACT_CLASS = "/Script/ProjectPBZ.PBZInteractComponent"
local ACTOR_CLASS    = "/Script/Engine.Actor"
local TAG = "[PbzRemotePickup] "
local STOP_CLASSES = { Object = true, Actor = true, Pawn = true, Character = true, ActorComponent = true,
                       SceneComponent = true, PrimitiveComponent = true, Info = true,
                       Subsystem = true, WorldSubsystem = true, GameInstanceSubsystem = true }

---------------------------------------------------------------- logging
local ModDir = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[\\/]Scripts[\\/]main%.lua$", ""))
local ReportPath  = ModDir .. "\\scan_report.txt"
local MonitorPath = ModDir .. "\\monitor_log.txt"
local Report, MonitorFile = nil, nil

local function log(msg)
    print(TAG .. msg .. "\n")
    if Report then Report:write(msg, "\n") end
end

local function mlog(msg)
    print(TAG .. "[mon] " .. msg .. "\n")
    if MonitorFile then MonitorFile:write(os.date("%H:%M:%S "), msg, "\n"); MonitorFile:flush() end
end

-- modules next to main.lua first, then the PbzModConfig mod's own Scripts folder (optional, not bundled).
-- Its folder is only used while that mod is enabled in UE4SS (enabled.txt, or "PbzModConfig : 1" in mods.txt).
local ModsDir = ModDir:match("^(.*)[\\/][^\\/]+$") or ModDir
local function Ue4ssModEnabled(name)
    local f = io.open(ModsDir .. "\\" .. name .. "\\enabled.txt", "r")
    if f then f:close(); return true end
    local list = io.open(ModsDir .. "\\mods.txt", "r")
    if not list then return false end
    local on = false
    for line in list:lines() do
        local n, v = line:match("^%s*([^;:%s][^:]-)%s*:%s*(%d)")
        if n == name then on = (v == "1") end
    end
    list:close()
    return on
end
local ModConfigEnabled = Ue4ssModEnabled("PbzModConfig")
package.path = ModDir .. "\\Scripts\\?.lua;"
    .. (ModConfigEnabled and (ModsDir .. "\\PbzModConfig\\Scripts\\?.lua;") or "") .. package.path

---------------------------------------------------------------- settings (settings.json; also shown in PbzModConfig when enabled)
local SettingsPath = ModDir .. "\\settings.json"
local DEFAULTS = { radiusM = 50, onePerPress = true, skipHidden = true, skipEquipment = true, showToast = true,
                   rangeKey = "P", equipKey = "L",               -- keyboard hotkeys: cycle range / toggle skip equipment (Ctrl is taken by the game)
                   rangeGamepad = "", equipGamepad = "",          -- gamepad hotkeys, chords allowed (A+B), "" = unbound
                   pickupKey = "O",        -- keyboard / mouse binding, UE FKey name with optional Ctrl+/Alt+/Shift+
                   pickupGamepad = "" }    -- gamepad binding (any Gamepad_* key the game reports), "" = unbound
local RADIUS_MIN, RADIUS_MAX, RADIUS_STEP = 5, 200, 5
local RANGE_STEPS = { 25, 50, 100, 150, 200 }      -- cycled by the range hotkey
local KEYBOARD_SLOTS = { "pickupKey", "rangeKey", "equipKey" }
local GAMEPAD_SLOTS  = { "pickupGamepad", "rangeGamepad", "equipGamepad" }
local KEY_SLOTS = { "pickupKey", "pickupGamepad", "rangeKey", "rangeGamepad", "equipKey", "equipGamepad" }
local function GamepadOnly(binding)
    if binding == "" then return true end
    for part in (binding .. "+"):gmatch("(.-)%+") do
        if not part:find("^Gamepad_") then return false end
    end
    return true
end

local Settings = { values = {}, revision = 0, listeners = {} }
for k, v in pairs(DEFAULTS) do Settings.values[k] = v end

-- settings.json is a flat object of strings / numbers / booleans; a tiny reader / writer is enough
local FlatJson = {}
do
    local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
    local function str(s) return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"' end
    function FlatJson.encode(tbl)
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            local v, tv = tbl[k], type(tbl[k])
            local enc = (tv == "string" and str(v)) or (tv == "boolean" and tostring(v))
                or (tv == "number" and v == v and v ~= math.huge and v ~= -math.huge and string.format("%.14g", v)) or nil
            if enc then parts[#parts + 1] = str(k) .. ":" .. enc end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    local UNESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
    function FlatJson.decode(s)
        local i, out = 1, {}
        local function ws() i = s:find("[^ \t\r\n]", i) or (#s + 1) end
        local function expect(c) ws(); if s:sub(i, i) ~= c then error("expected '" .. c .. "' at " .. i) end; i = i + 1 end
        local function readString()
            expect('"')
            local buf = {}
            while true do
                local c = s:sub(i, i)
                if c == "" then error("unterminated string") end
                if c == '"' then i = i + 1; break end
                if c == "\\" then
                    local e = s:sub(i + 1, i + 1)
                    if e == "u" then
                        local cp = tonumber(s:sub(i + 2, i + 5), 16) or 63
                        buf[#buf + 1] = cp < 128 and string.char(cp) or "?"; i = i + 6
                    else buf[#buf + 1] = UNESC[e] or e; i = i + 2 end
                else buf[#buf + 1] = c; i = i + 1 end
            end
            return table.concat(buf)
        end
        expect("{"); ws()
        if s:sub(i, i) == "}" then return out end
        while true do
            local k = readString(); expect(":"); ws()
            local c = s:sub(i, i)
            if c == '"' then out[k] = readString()
            elseif s:sub(i, i + 3) == "true" then out[k] = true; i = i + 4
            elseif s:sub(i, i + 4) == "false" then out[k] = false; i = i + 5
            elseif s:sub(i, i + 3) == "null" then i = i + 4
            else
                local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
                if not num or num == "" then error("bad value at " .. i) end
                out[k] = tonumber(num); i = i + #num
            end
            ws()
            local sep = s:sub(i, i); i = i + 1
            if sep == "}" then break elseif sep ~= "," then error("expected ',' or '}'") end
        end
        return out
    end
end

local function Sanitize(values)
    local out = {}
    for k, v in pairs(DEFAULTS) do out[k] = v end
    if type(values) ~= "table" then return out end
    local r = values.radiusM
    if type(r) == "number" and r == r then
        r = math.max(RADIUS_MIN, math.min(RADIUS_MAX, r))
        out.radiusM = RADIUS_MIN + math.floor((r - RADIUS_MIN) / RADIUS_STEP + 0.5) * RADIUS_STEP
    end
    if type(values.onePerPress) == "boolean" then out.onePerPress = values.onePerPress end
    if type(values.skipHidden) == "boolean" then out.skipHidden = values.skipHidden end
    if type(values.skipEquipment) == "boolean" then out.skipEquipment = values.skipEquipment end
    if type(values.showToast) == "boolean" then out.showToast = values.showToast end
    for _, k in ipairs(KEY_SLOTS) do
        local v = values[k]
        if type(v) == "string" and #v <= 96 and (v == "" or v:match("^[A-Za-z][A-Za-z0-9_+]*$")) then out[k] = v end
    end
    for _, k in ipairs(KEYBOARD_SLOTS) do       -- keyboard / mouse slots: no gamepad keys
        if out[k]:find("Gamepad_") then out[k] = DEFAULTS[k] end
    end
    for _, k in ipairs(GAMEPAD_SLOTS) do        -- gamepad slots: every part of the chord must be a gamepad key
        if not GamepadOnly(out[k]) then out[k] = "" end
    end
    return out
end

local function ApplyToConfig()
    Config.PullRadius = Settings.values.radiusM * 100
    Config.PullOnePerPress = Settings.values.onePerPress
    Config.SkipHidden = Settings.values.skipHidden
    Config.SkipEquipment = Settings.values.skipEquipment
    Config.ShowToast = Settings.values.showToast
end

local function SaveSettings()
    local f, err = io.open(SettingsPath, "w")
    if not f then return false, tostring(err) end
    local copy = {}
    for k in pairs(DEFAULTS) do copy[k] = Settings.values[k] end
    f:write(FlatJson.encode(copy))
    f:close()
    return true
end

local SettingsLoadNote = nil
local function LoadSettings()
    local f = io.open(SettingsPath, "r")
    if not f then return end
    local raw = f:read("a"); f:close()
    if #raw > 65536 then SettingsLoadNote = "settings.json too large, using defaults"; return end
    local ok, decoded = pcall(FlatJson.decode, raw)
    if ok and type(decoded) == "table" then Settings.values = Sanitize(decoded)
    else SettingsLoadNote = "settings.json unreadable (" .. tostring(decoded) .. "), using defaults" end
end

local function SetSettings(newValues)
    Settings.values = Sanitize(newValues)
    Settings.revision = Settings.revision + 1
    ApplyToConfig()
    local saved, err = SaveSettings()
    for _, cb in ipairs(Settings.listeners) do pcall(cb) end
    return saved, err
end

---------------------------------------------------------------- helpers
local function S(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t ~= "userdata" and t ~= "table" then return tostring(v) end
    for _, m in ipairs({ "ToString", "GetFullName" }) do
        local ok, r = pcall(function() return v[m](v) end)
        if ok and r ~= nil then return tostring(r) end
    end
    local ok, r = pcall(function() return v:get() end)
    if ok and r ~= nil and r ~= v then return S(r) end
    return tostring(v)
end

local function Valid(o)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end

local function Unwrap(o)
    if Valid(o) then return o end
    local ok, r = pcall(function() return o:get() end)
    if ok and Valid(r) then return r end
    return nil
end

local function Dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function ClassName(o)
    local ok, r = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and r or "?"
end

local function ObjName(o)
    local ok, r = pcall(function() return o:GetFName():ToString() end)
    return ok and r or "?"
end

local function NameOrString(o)
    local n = ObjName(o)
    if n ~= "?" then return n end
    return S(o)
end

local function IsCDO(o) return ObjName(o):sub(1, 9) == "Default__" end

local function Loc(a)
    local ok, l = pcall(function() return a:K2_GetActorLocation() end)
    if ok and l then return l end
    return nil
end

local function Hidden(a)
    local h = false
    pcall(function() h = a.bHidden == true end)
    return h
end

local function StartsWithAny(s, list)
    for _, p in ipairs(list) do if s:sub(1, #p) == p then return true end end
    return false
end

local function UAID(name) return name:match("(UAID_[0-9A-Fa-f]+_%d+)") end

local function Short(v)
    local s = S(v)
    if #s > 140 then s = s:sub(1, 140) .. "..." end
    return s
end

---------------------------------------------------------------- reflection
local DumpedClasses = {}
local function DumpClass(cls)
    local c, lines = cls, 0
    local function line(s)
        lines = lines + 1
        if lines <= Config.DumpMaxLines then log(s) elseif lines == Config.DumpMaxLines + 1 then log("    ...") end
    end
    while Valid(c) do
        local name = S(c:GetFName())
        if DumpedClasses[name] or STOP_CLASSES[name] then break end
        DumpedClasses[name] = true
        line("  [class " .. name .. "]  " .. S(c:GetFullName()))
        pcall(function()
            c:ForEachFunction(function(f)
                local fname = S(f:GetFName())
                if fname:sub(1, 17) == "ExecuteUbergraph_" then return end
                local params = {}
                pcall(function()
                    f:ForEachProperty(function(p)
                        table.insert(params, S(p:GetFName()) .. ":" .. S(p:GetClass():GetFName()))
                    end)
                end)
                line("    fn  " .. fname .. "(" .. table.concat(params, ", ") .. ")")
            end)
        end)
        pcall(function()
            c:ForEachProperty(function(p)
                line("    var " .. S(p:GetFName()) .. " : " .. S(p:GetClass():GetFName()))
            end)
        end)
        local ok, sup = pcall(function() return c:GetSuperStruct() end)
        if not ok then break end
        c = sup
    end
end

-- property values of one instance (game classes only)
local function DumpValues(obj)
    local c = obj:GetClass()
    local n = 0
    while Valid(c) do
        local cname = S(c:GetFName())
        if STOP_CLASSES[cname] then break end
        pcall(function()
            c:ForEachProperty(function(p)
                local pn = S(p:GetFName())
                local ok, v = pcall(function() return obj[pn] end)
                n = n + 1
                if n <= Config.DumpMaxLines then
                    log(string.format("    %s.%s = %s", cname, pn, ok and Short(v) or "<unreadable>"))
                end
            end)
        end)
        local ok, sup = pcall(function() return c:GetSuperStruct() end)
        if not ok then break end
        c = sup
    end
end

---------------------------------------------------------------- queries
local function ActorsOfClass(cls)
    local res = {}
    if not Valid(cls) then return res, -1 end
    local ok = pcall(function()
        local out = {}
        UEHelpers.GetGameplayStatics():GetAllActorsOfClass(UEHelpers.GetWorldContextObject(), cls, out)
        for _, a in ipairs(out) do
            local o = Unwrap(a)
            if o then table.insert(res, o) end
        end
    end)
    return res, ok and #res or -1
end

local function FindAll(shortName)
    local res = {}
    pcall(function()
        for _, o in ipairs(FindAllOf(shortName) or {}) do
            if Valid(o) and not IsCDO(o) then table.insert(res, o) end
        end
    end)
    return res
end

local function PlayerInteractComp(pawn)
    local icls = StaticFindObject(INTERACT_CLASS)
    if Valid(icls) then
        local ok, c = pcall(function() return pawn:GetComponentByClass(icls) end)
        if ok and Valid(c) then return c end
    end
    for _, comp in ipairs(FindAll("PBZInteractComponent")) do
        local ok, o = pcall(function() return comp:GetOwner() end)
        if ok and o == pawn then return comp end
    end
    return FindAll("PBZInteractComponent")[1]
end

-- item IDs a BP_Rubbish will give (fields found in the v0.4 reflection dump)
local function UsableId(s)
    return s and s ~= "" and s ~= "None" and s ~= "nil" and not s:find("^%u%a+: %x+$") and not s:find("^userdata")
        and not s:find("^%a*Struct ")
end

-- Pickups entries are PickupInfo structs (BP struct, field names carry GUID suffixes): find the struct's
-- name / string fields once via reflection and read those, so the real item ID is checked.
local StructFields = {}
local StructFieldLog = {}
local function StructStringValues(v)
    local desc = S(v)
    local path = desc:match("^%a*Struct (%S+)$")
    if not path then return nil end
    local fields = StructFields[path]
    if fields == nil then
        fields = {}
        pcall(function()
            local st = StaticFindObject(path)
            if Valid(st) then
                st:ForEachProperty(function(prop)
                    local n = prop:GetFName():ToString()
                    local pc = prop:GetClass():GetFName():ToString()
                    if pc == "NameProperty" or pc == "StrProperty" then fields[#fields + 1] = n end
                end)
            end
        end)
        StructFields[path] = fields
    end
    local vals = {}
    for _, n in ipairs(fields) do
        local ok, r = pcall(function() return S(v[n]) end)
        if ok and UsableId(r) then vals[#vals + 1] = r end
    end
    if not StructFieldLog[path] then
        StructFieldLog[path] = true
        print(TAG .. string.format("struct %s: id fields [%s], sample [%s]\n", path, table.concat(fields, ","), table.concat(vals, ",")))
    end
    return vals
end

local function ItemsOf(a)
    local ids, seen, equip = {}, {}, {}
    local function add(v, field)
        local s = S(v)
        if UsableId(s) then
            if not seen[s] then seen[s] = true; table.insert(ids, s) end
            if field and Config.EquipFields[field] then equip[s] = field end
        end
    end
    pcall(function() add(a["Item ID"]) end)
    for _, f in ipairs({ "PickupMap", "GetWeapons", "ReallyGetWeapons" }) do      -- TMap<item, count>
        pcall(function() a[f]:ForEach(function(k, _) add(k:get(), f) end) end)
    end
    for _, f in ipairs({ "Pickups", "Medicines", "Accessories", "ReallyMedicines", "ReallyAccessories" }) do  -- arrays / sets
        pcall(function() a[f]:ForEach(function(_, e)
            local v = e:get()
            local sv = StructStringValues(v)
            if sv then for _, s in ipairs(sv) do add(s, f) end else add(v, f) end
        end) end)
    end
    local loot = nil
    pcall(function() local s = S(a["Loot Item ID"]); if UsableId(s) then loot = s end end)
    return ids, loot, equip
end

local function ItemIdOf(a)
    local ids, loot, equip = ItemsOf(a)
    if #ids > 0 then return table.concat(ids, ","), ids, equip end
    return loot and ("loot:" .. loot) or nil, ids, equip
end

local function IsResourceId(id)
    for _, p in ipairs(Config.ResourceIdPatterns) do if id:find(p) then return true end end
    return false
end

-- names of the tags in an FGameplayTagContainer (empty table if none / unreadable)
local function TagNames(container)
    local names = {}
    pcall(function()
        container.GameplayTags:ForEach(function(_, e)
            local tg = e:get()
            local n = nil
            pcall(function() n = tg.TagName:ToString() end)
            table.insert(names, n or "?")
        end)
    end)
    return names
end

-- the pickup is wired into a story flow: picking it up remotely would skip its story event
local function ScriptedReason(a)
    local flow = nil
    pcall(function() flow = a.BP_PBZFlowComponent end)
    if Valid(flow) then
        local t = TagNames(flow.IdentityTags)
        if #t > 0 then return "story flow item (" .. table.concat(t, ",") .. ")" end
    end
    for _, f in ipairs({ "AddTagWhenSuccess", "AddTagWhenFailed" }) do
        local t = {}
        pcall(function() t = TagNames(a[f]) end)
        if #t > 0 then return "adds story tags on pickup (" .. table.concat(t, ",") .. ")" end
    end
    local q = nil
    pcall(function() q = a.BeginQuest end)
    if Valid(q) then return "starts a quest (" .. ObjName(q) .. ")" end
    return nil
end

local function Destroyed(a)
    local d = false
    pcall(function() d = a.bDestroyed == true end)
    return d
end

local function IsPickupClass(cn) return StartsWithAny(cn, Config.PickupClassPrefixes) end

local function WorldPickups(ploc, radius)
    local all = ActorsOfClass(StaticFindObject(ACTOR_CLASS))
    local list = {}
    for _, a in ipairs(all) do
        local cn = ClassName(a)
        if IsPickupClass(cn) then
            local l = Loc(a)
            if l then
                local dd = Dist(ploc, l)
                if not radius or dd <= radius then
                    table.insert(list, { actor = a, class = cn, name = ObjName(a), dist = dd, hidden = Hidden(a) })
                end
            end
        end
    end
    table.sort(list, function(x, y) return x.dist < y.dist end)
    return list, #all
end

local function DenyReason(d)
    local id, ids, equip = ItemIdOf(d.actor)
    d.item = id
    if Destroyed(d.actor) then return "already picked up" end
    if Config.SkipHidden and d.hidden then return "hidden" end
    for _, it in ipairs(ids or {}) do
        if StartsWithAny(it, Config.QuestIdPrefixes) then return "quest item id " .. it end
    end
    local scripted = ScriptedReason(d.actor)
    if scripted then return scripted end
    if Config.SkipEquipment then
        for _, it in ipairs(ids or {}) do
            if equip and equip[it] then return "equipment " .. it .. " (" .. equip[it] .. ")" end
            if not IsResourceId(it) then return "equipment / unknown item " .. it end
        end
    end
    local hay = (d.class .. " " .. d.name .. " " .. (id or "")):lower()
    for _, kw in ipairs(Config.DenyKeywords) do
        if hay:find(kw, 1, true) then return "keyword '" .. kw .. "'" end
    end
    return nil
end

---------------------------------------------------------------- debug: diagnostic scan (F9, disabled by default)
local function Scan()
    Report = io.open(ReportPath, "w")
    DumpedClasses = {}
    local pawn = UEHelpers.GetPlayer()
    if not Valid(pawn) then log("no player pawn"); if Report then Report:close(); Report = nil end; return end
    local ploc = Loc(pawn)
    local t0 = os.clock()
    log(string.format("v0.10 scan  player X=%.0f Y=%.0f Z=%.0f", ploc.X, ploc.Y, ploc.Z))

    -- player interact component
    local comp = PlayerInteractComp(pawn)
    if comp then
        log("player interact component: " .. ObjName(comp))
        for _, f in ipairs({ "LevelAClasses", "LevelBClasses", "LevelCClasses" }) do
            local items = {}
            pcall(function() comp[f]:ForEach(function(_, e) table.insert(items, NameOrString(e:get())) end) end)
            log(string.format("  %s [%d]: %s", f, #items, table.concat(items, ", ")))
        end
        for _, f in ipairs({ "SearchActors", "InteractActors" }) do
            local rows = {}
            pcall(function()
                comp[f]:ForEach(function(k, v)
                    local a = Unwrap(k:get())
                    local l = a and Loc(a)
                    table.insert(rows, string.format("     %s | %s %.1fm => %s", a and ClassName(a) or "?", a and ObjName(a) or S(k:get()),
                        l and Dist(ploc, l) / 100 or -1, Short(v:get())))
                end)
            end)
            log(string.format("  %s [%d]", f, #rows))
            for _, r in ipairs(rows) do log(r) end
        end
        pcall(function()
            local a = Unwrap(comp.CurrentInteractActor)
            log("  CurrentInteractActor = " .. (a and (ClassName(a) .. " | " .. ObjName(a)) or "none"))
        end)
    else
        log("player interact component: not found")
    end

    -- world pickups (BP_Rubbish*)
    local picks, total = WorldPickups(ploc, nil)
    local byClass = {}
    for _, d in ipairs(picks) do byClass[d.class] = (byClass[d.class] or 0) + 1 end
    log(string.format("world pickups loaded: %d (of %d actors)", #picks, total))
    for cn, n in pairs(byClass) do log(string.format("  %5d  %s", n, cn)) end
    log("nearest pickups:")
    for i, d in ipairs(picks) do
        if i > 25 then break end
        local why = DenyReason(d)
        log(string.format("  %7.1fm  %s | %s  item=%s%s", d.dist / 100, d.class, d.name, d.item or "?", why and ("  <- skip: " .. why) or "  <- eligible"))
    end

    -- nearby actors (context)
    local near = {}
    for _, a in ipairs(ActorsOfClass(StaticFindObject(ACTOR_CLASS))) do
        local l = Loc(a)
        if l and a ~= pawn then
            local dd = Dist(ploc, l)
            if dd <= Config.ScanRadius then table.insert(near, { a = a, d = dd }) end
        end
    end
    table.sort(near, function(x, y) return x.d < y.d end)
    log(string.format("actors within %.0f m: %d", Config.ScanRadius / 100, #near))
    for i, e in ipairs(near) do
        if i > Config.ScanMaxRows then log("  ..."); break end
        log(string.format("  %6.1fm  %s | %s%s", e.d / 100, ClassName(e.a), ObjName(e.a), Hidden(e.a) and " (hidden)" or ""))
    end

    -- reflection + values of the nearest pickup of each class
    log("reflection:")
    local done = {}
    for _, d in ipairs(picks) do
        if not done[d.class] then
            done[d.class] = true
            pcall(function() DumpClass(d.actor:GetClass()) end)
            log("  [values of " .. d.name .. string.format(" %.1fm]", d.dist / 100))
            pcall(function() DumpValues(d.actor) end)
        end
    end
    log(string.format("scan took %.0f ms", (os.clock() - t0) * 1000))
    if Report then log("report written to " .. ReportPath); Report:close(); Report = nil end
end

---------------------------------------------------------------- debug: pickup monitor (F10, disabled by default)
local Monitor = { on = false, hooked = false, counts = {}, hookCount = 0 }

local function DescribeParam(p)
    local ok, v = pcall(function() return p:get() end)
    if not ok then return "?" end
    if Valid(v) then return ClassName(v) .. ":" .. ObjName(v) end
    return Short(v)
end

local SKIP_FN = { "^Get", "^Is", "^Can", "^Should", "^Has", "^Caculate", "^Calculate", "^Check", "^Play",
                  "Tick", "^ExecuteUbergraph", "^Refresh", "Widget", "^Receive.*Tick", "^Find", "^Pause", "^UnPause" }
local function Noisy(fname)
    for _, p in ipairs(SKIP_FN) do if fname:find(p) then return true end end
    return false
end

local HookedPaths = {}
local function HookClassFunctions(cls, filter)
    if not Valid(cls) then return 0 end
    local n = 0
    pcall(function()
        cls:ForEachFunction(function(f)
            local fname = S(f:GetFName())
            if (filter and not filter(fname)) or (not filter and Noisy(fname)) then return end
            local full = S(f:GetFullName()):gsub("^%S+%s+", "")   -- "Function /Script/X.Y:Name" -> "/Script/X.Y:Name"
            if HookedPaths[full] then return end
            HookedPaths[full] = true
            local ok = pcall(function()
                RegisterHook(full, function(ctx, ...)
                    if not Monitor.on then return end
                    local c = (Monitor.counts[full] or 0) + 1
                    Monitor.counts[full] = c
                    if c > Config.MonitorMaxPerFunc then return end
                    local args = {}
                    for _, p in ipairs({ ... }) do table.insert(args, DescribeParam(p)) end
                    local self = "?"
                    pcall(function() local o = ctx:get(); self = ClassName(o) .. ":" .. ObjName(o) end)
                    mlog(string.format("%s  self=%s  args=(%s)%s", full, self, table.concat(args, ", "),
                        c == Config.MonitorMaxPerFunc and "  [further calls suppressed]" or ""))
                end)
            end)
            if ok then n = n + 1 end
        end)
    end)
    return n
end

local function EnsureHooks()
    local pawn = UEHelpers.GetPlayer()
    local total = 0
    local interactFns = { DoInteract = true, StartInteract = true, EndInteract = true, StartFadeInteract = true,
                          EndFadeInteract = true, StartFlowFadeInteract = true, SetCurrentInteractActor = true,
                          AddActorEndInteractBlockTime = true, RemovePotentialInteract = true }
    if not Monitor.hooked then
        total = total + HookClassFunctions(StaticFindObject(INTERACT_CLASS), function(n) return interactFns[n] end)
        total = total + HookClassFunctions(StaticFindObject(PICKUP_CLASS), nil)
        for _, path in ipairs({ "/Script/ProjectPBZ.PBZBackPackSubsystem", "/Script/ProjectPBZ.PBZLevelActorManager",
                                "/Script/ProjectPBZ.EventPipelineManager" }) do
            total = total + HookClassFunctions(StaticFindObject(path), nil)
        end
        Monitor.hooked = true
    end
    -- pickup blueprint classes currently loaded (hooked once per class)
    Monitor.bpHooked = Monitor.bpHooked or {}
    if Valid(pawn) then
        local picks = WorldPickups(Loc(pawn), nil)
        for _, d in ipairs(picks) do
            if not Monitor.bpHooked[d.class] then
                Monitor.bpHooked[d.class] = true
                local c = d.actor:GetClass()
                while Valid(c) and not STOP_CLASSES[S(c:GetFName())] do
                    total = total + HookClassFunctions(c, function(n) return not n:find("^ExecuteUbergraph") and not n:find("Tick") end)
                    local ok, sup = pcall(function() return c:GetSuperStruct() end)
                    if not ok then break end
                    c = sup
                end
            end
        end
    end
    Monitor.hookCount = Monitor.hookCount + total
    return total
end

local function ToggleMonitor()
    if not Monitor.on then
        local added = EnsureHooks()
        Monitor.counts = {}
        MonitorFile = io.open(MonitorPath, "a")
        Monitor.on = true
        mlog(string.format("=== monitor ON (%d new hooks, %d total). Pick an item up by hand, then press F10 again.", added, Monitor.hookCount))
    else
        Monitor.on = false
        mlog("=== monitor OFF")
        if MonitorFile then MonitorFile:close(); MonitorFile = nil end
    end
end

---------------------------------------------------------------- on-screen message
-- A game widget is used only as a host: its root is replaced by our own canvas with one text block, the
-- standard UMG way to put text on screen from Lua. If anything is missing the message only goes to the log.
local TOAST_HOST_CLASS = "/Game/PBZContent/UI/FrontEnd/Sense/W_Sense_Quest.W_Sense_Quest_C"
local TOAST_MS = 2000
local Toast = { widget = nil, text = nil, seq = 0, broken = nil }

local function FindOrLoad(path)
    local o = StaticFindObject(path)
    if Valid(o) then return o end
    if type(LoadAsset) == "function" then
        pcall(LoadAsset, path:gsub("%.[^./]+$", ""))
        o = StaticFindObject(path)
        if Valid(o) then return o end
    end
    return nil
end

local function ToastBuild()
    local pc = UEHelpers.GetPlayerController()
    if not Valid(pc) then return nil, "no player controller" end
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local hostCls = FindOrLoad(TOAST_HOST_CLASS)
    local canvasCls = StaticFindObject("/Script/UMG.CanvasPanel")
    local textCls = StaticFindObject("/Script/UMG.TextBlock")
    if not (Valid(wbl) and Valid(hostCls) and Valid(canvasCls) and Valid(textCls)) then return nil, "UMG classes not found" end
    local w = wbl:Create(pc, hostCls, pc)
    if not Valid(w) then return nil, "widget create failed" end
    local tree = w.WidgetTree
    if not Valid(tree) then return nil, "widget has no tree" end
    local canvas = StaticConstructObject(canvasCls, tree, UEHelpers.FindOrAddFName("PbzRemotePickup_Canvas"))
    local text = StaticConstructObject(textCls, tree, UEHelpers.FindOrAddFName("PbzRemotePickup_Text"))
    if not (Valid(canvas) and Valid(text)) then return nil, "construct failed" end
    tree.RootWidget = canvas
    local slot = canvas:AddChildToCanvas(text)
    pcall(function()
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.18 }, Maximum = { X = 0.5, Y = 0.18 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetAutoSize(true)
    end)
    pcall(function() text:SetJustification(1) end)                 -- ETextJustify::Center
    pcall(function() text:SetShadowOffset({ X = 1.5, Y = 1.5 }) end)
    pcall(function() text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 }) end)
    pcall(function() local f = text.Font; f.Size = 22; text:SetFont(f) end)
    w:AddToViewport(1000)
    return { widget = w, text = text }
end

local function HideToast(seq)
    if seq ~= Toast.seq then return end
    pcall(function() if Valid(Toast.widget) then Toast.widget:SetVisibility(1) end end)   -- Collapsed
end

local function ShowToast(msg)
    log("toast: " .. msg)
    if not Config.ShowToast or Toast.broken then return end
    local ok, err = pcall(function()
        if not (Valid(Toast.widget) and Valid(Toast.text)) then      -- first use, or the level changed
            local built, why = ToastBuild()
            if not built then error(why, 0) end
            Toast.widget, Toast.text = built.widget, built.text
        end
        Toast.text:SetText(FText(msg))
        Toast.widget:SetVisibility(3)                                 -- HitTestInvisible
    end)
    if not ok then
        Toast.failures = (Toast.failures or 0) + 1
        log("on-screen message unavailable: " .. tostring(err))
        if Toast.failures >= 3 then Toast.broken = true; log("on-screen messages turned off for this session") end
        return
    end
    Toast.failures = 0
    Toast.seq = Toast.seq + 1
    local seq = Toast.seq
    ExecuteWithDelay(TOAST_MS, function() ExecuteInGameThread(function() HideToast(seq) end) end)
end

---------------------------------------------------------------- remote pickup
local Busy = false
local function Gone(a) return (not Valid(a)) or Destroyed(a) end

-- calls the item's own pickup entry point; falls back to the interact-button path.
-- done(ok, how) is called once the outcome is known.
local function PickupOne(comp, pawn, d, done)
    local a = d.actor
    local okB, rB = pcall(function() return a:OnInteract(pawn) end)
    log(string.format("OnInteract(player) on %s [%s] -> %s", d.name, d.item or "?", okB and S(rB) or ("error " .. tostring(rB))))
    ExecuteWithDelay(Config.VerifyDelayMs, function()
        ExecuteInGameThread(function()
            if Gone(a) then done(true, "OnInteract"); return end
            local okA, eA = pcall(function()
                comp:SetCurrentInteractActor(a)
                comp:StartInteract()
            end)
            log("fallback SetCurrentInteractActor+StartInteract -> " .. (okA and "called" or ("error " .. tostring(eA))))
            ExecuteWithDelay(Config.VerifyDelayMs, function()
                ExecuteInGameThread(function()
                    if Gone(a) then done(true, "StartInteract") else done(false, "item still there") end
                end)
            end)
        end)
    end)
end

local function Pull()
    if Busy then log("busy"); return end
    local pawn = UEHelpers.GetPlayer()
    if not Valid(pawn) then log("no player pawn"); return end
    local ploc = Loc(pawn)
    local comp = PlayerInteractComp(pawn)
    if not comp then log("player interact component not found"); return end

    local picks = WorldPickups(ploc, Config.PullRadius)
    local queue = {}
    for _, d in ipairs(picks) do
        local why = DenyReason(d)
        if why then log(string.format("skip %s %.1fm item=%s: %s", d.name, d.dist / 100, d.item or "?", why))
        else table.insert(queue, d); if Config.PullOnePerPress then break end end
    end
    log(string.format("remote pickup: %d target(s) of %d pickups within %.0f m", #queue, #picks, Config.PullRadius / 100))
    if #queue == 0 then return end

    Busy = true
    local picked, failed = 0, 0
    local function step(i)
        if i > #queue then Busy = false; log(string.format("done: %d picked up, %d failed", picked, failed)); return end
        local d = queue[i]
        ExecuteInGameThread(function()
            if Gone(d.actor) then step(i + 1); return end
            PickupOne(comp, pawn, d, function(ok, how)
                if ok then picked = picked + 1 else failed = failed + 1 end
                log(string.format("%s %s %.1fm: %s", ok and "PICKED" or "FAILED", d.name, d.dist / 100, how))
                if not ok then                       -- some pickups finish seconds later: keep checking a while
                    local a, tries = d.actor, 0
                    local function lateCheck()
                        ExecuteInGameThread(function()
                            tries = tries + 1
                            if Gone(a) then
                                log(string.format("LATE %s: the pickup went through after all (%.1f s)", d.name,
                                    (Config.VerifyDelayMs * 2 + tries * Config.LateCheckMs) / 1000))
                            elseif tries < Config.LateCheckTries then
                                ExecuteWithDelay(Config.LateCheckMs, lateCheck)
                            end
                        end)
                    end
                    ExecuteWithDelay(Config.LateCheckMs, lateCheck)
                end
                ExecuteWithDelay(Config.BetweenItemsMs, function() step(i + 1) end)
            end)
        end)
    end
    step(1)
end

---------------------------------------------------------------- error guard and debug key bindings
local function Guard(name, fn)
    return function()
        ExecuteInGameThread(function()
            local ok, err = pcall(fn)
            if not ok then
                Busy = false
                log(name .. " error: " .. tostring(err))
                if Report then Report:close(); Report = nil end
            end
        end)
    end
end

-- debug keys (disabled):
-- RegisterKeyBind(Key.F9, Guard("scan", Scan))
-- RegisterKeyBind(Key.F10, Guard("monitor", ToggleMonitor))

---------------------------------------------------------------- hotkeys: polled through the PlayerController
-- UE4SS RegisterKeyBind only sees the keyboard and cannot be rebound, so the pickup key is read the same
-- way other UE4SS mods for this game do: PlayerController:IsInputKeyDown(FKey) every few frames, with our own
-- press-edge detection. This covers keyboard, mouse (incl. side buttons) and any Gamepad_* key UE reports.
local POLL_MS = 33
local MOD_KEYS = { Ctrl = { "LeftControl", "RightControl" }, Alt = { "LeftAlt", "RightAlt" },
                   Shift = { "LeftShift", "RightShift" }, Cmd = { "LeftCommand", "RightCommand" } }
local MOD_ORDER = { "Ctrl", "Alt", "Shift", "Cmd" }

local FKeyCache = {}
local function FKeyOf(name)
    local k = FKeyCache[name]
    if not k then k = { KeyName = UEHelpers.FindOrAddFName(name) }; FKeyCache[name] = k end
    return k
end

local function KeyDown(pc, name)
    return pc:IsInputKeyDown(FKeyOf(name)) == true
end

local function SplitBinding(binding)
    local parts = {}
    for p in (binding .. "+"):gmatch("(.-)%+") do parts[#parts + 1] = p end
    local key = table.remove(parts)
    return key, parts
end

-- Ctrl/Alt/Shift/Cmd are modifiers and must match exactly (O does not fire on Ctrl+O); any other part of
-- the binding (e.g. Gamepad_LeftShoulder in Gamepad_LeftShoulder+Gamepad_DPad_Up) must simply be held.
-- Returns the number of keys in the binding when it is held, else false.
local function BindingHeld(pc, binding)
    if binding == nil or binding == "" then return false end
    local key, mods = SplitBinding(binding)
    if not KeyDown(pc, key) then return false end
    local want = {}
    for _, m in ipairs(mods) do
        if MOD_KEYS[m] then want[m] = true
        elseif not KeyDown(pc, m) then return false end
    end
    if not key:find("^Gamepad_") then
        for _, m in ipairs(MOD_ORDER) do
            local held = KeyDown(pc, MOD_KEYS[m][1]) or KeyDown(pc, MOD_KEYS[m][2])
            if held ~= (want[m] == true) then return false end
        end
    end
    return #mods + 1
end

-- same gating as the map mod: no pickup while paused or while a menu owns input
local function InputBlocked(pc)
    local paused = false
    pcall(function() paused = UEHelpers.GetGameplayStatics():IsGamePaused(UEHelpers.GetWorldContextObject()) == true end)
    if paused then return "paused" end
    local mode = nil
    pcall(function()
        local cls = StaticFindObject("/Script/ProjectPBZ.PBZUIActionRouterBase")
        local lib = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
        if Valid(cls) and Valid(lib) then
            local sub = lib:GetLocalPlayerSubSystemFromPlayerController(pc, cls)
            if Valid(sub) then mode = sub:GetActiveInputMode() end
        end
    end)
    if mode == 0 then return "menu" end          -- ECommonInputMode::Menu
    return nil
end

local Input = { prev = {}, errors = 0, stopped = false }

local function CycleRange()
    local cur, nextR = Settings.values.radiusM, RANGE_STEPS[1]
    for _, r in ipairs(RANGE_STEPS) do if r > cur then nextR = r; break end end
    local v = {}
    for k, x in pairs(Settings.values) do v[k] = x end
    v.radiusM = nextR
    SetSettings(v)
    ShowToast(string.format("远程拾取范围：%d 米", Settings.values.radiusM))
end

local function ToggleEquipment()
    local v = {}
    for k, x in pairs(Settings.values) do v[k] = x end
    v.skipEquipment = not Settings.values.skipEquipment
    SetSettings(v)
    ShowToast(Settings.values.skipEquipment and "远程拾取：跳过装备（开）" or "远程拾取：也拾取装备（跳过装备 关）")
end

local ACTIONS = {
    { slot = "pickupKey", fn = function() return Pull() end, name = "pull" },
    { slot = "pickupGamepad", fn = function() return Pull() end, name = "pull" },
    { slot = "rangeKey", fn = CycleRange, name = "range" },
    { slot = "rangeGamepad", fn = CycleRange, name = "range" },
    { slot = "equipKey", fn = ToggleEquipment, name = "equipment" },
    { slot = "equipGamepad", fn = ToggleEquipment, name = "equipment" },
}

local function PollOnce()
    local pc = UEHelpers.GetPlayerController()
    if not Valid(pc) then Input.prev = {}; return end
    local fired, best = {}, 0
    for _, a in ipairs(ACTIONS) do
        local binding = Settings.values[a.slot]
        local n = BindingHeld(pc, binding)
        local p = Input.prev[a.slot]
        if n and p and p.binding == binding and not p.down then
            fired[#fired + 1] = { a = a, n = n }
            if n > best then best = n end
        end
        Input.prev[a.slot] = { binding = binding, down = n and true or false }
    end
    if #fired == 0 then return end
    if InputBlocked(pc) then return end
    local done = {}
    for _, f in ipairs(fired) do                 -- the most specific chord wins (LB+R3 does not also fire R3)
        if f.n == best and not done[f.a.name] then
            done[f.a.name] = true
            local ok, err = pcall(f.a.fn)
            if not ok then Busy = false; log(f.a.name .. " error: " .. tostring(err)) end
        end
    end
end

local Schedule = ExecuteInGameThreadWithDelay
local function PollLoop()
    if Input.stopped then return end
    local ok, err = pcall(PollOnce)
    if ok then
        Input.errors = 0
    else
        Input.errors = Input.errors + 1
        if Input.errors <= 3 then log("input poll error: " .. tostring(err)) end
        if Input.errors >= 30 then
            Input.stopped = true
            log("input polling disabled after repeated errors; falling back to keyboard O via RegisterKeyBind")
            RegisterKeyBind(Key.O, Guard("pull", Pull))
            return
        end
    end
    Schedule(POLL_MS, PollLoop)
end

if type(Schedule) == "function" then
    Schedule(2000, PollLoop)
else
    log("ExecuteInGameThreadWithDelay unavailable; using keyboard O via RegisterKeyBind")
    RegisterKeyBind(Key.O, Guard("pull", Pull))
end

---------------------------------------------------------------- ModConfig page (Settings > Mods)
local function L10n(zh, en) return { ["zh-Hans"] = zh, en = en } end

local Provider = {
    modId = "PbzRemotePickup",
    modVersion = "0.10",
    schemaVersion = 4,
    displayName = L10n("远程拾取", "Remote Pickup"),
    groups = { { id = "pickup", label = L10n("拾取", "Pickup"), order = 1 } },
    entries = {
        { key = "keyInfo", type = "header", group = "pickup",
          label = L10n("按拾取键拾取范围内最近的普通道具（跳过任务物品和剧情物品）", "Press the pickup key to pick up the nearest regular item in range (quest and story items are skipped)") },
        { key = "pickupKey", type = "keybind", group = "pickup", defaultValue = DEFAULTS.pickupKey,
          allowGamepad = false, allowMouse = true, allowModifiers = true, allowUnbound = true, conflictGroup = "remotepickup",
          label = L10n("拾取键（键盘 / 鼠标）", "Pickup key (keyboard / mouse)"),
          description = L10n("支持 Alt / Shift 组合键和鼠标按键，包括侧键。Ctrl 已被游戏占用。", "Supports Alt / Shift combos and mouse buttons, including side buttons. Ctrl is used by the game.") },
        { key = "pickupGamepad", type = "keybind", group = "pickup", defaultValue = DEFAULTS.pickupGamepad,
          allowGamepad = true, allowMouse = false, allowModifiers = false, allowUnbound = true, conflictGroup = "remotepickup",
          label = L10n("拾取键（手柄）", "Pickup button (gamepad)"),
          description = L10n("按下要绑定的手柄键。背键能被游戏识别就可以直接绑定；识别不了的话，先在 Steam 输入里把背键映射成一个空闲的手柄键，再来这里绑定。",
                             "Press the gamepad button to bind. Back paddles work if the game sees them; otherwise map the paddle to an unused button in Steam Input first, then bind that.") },
        { key = "radiusM", type = "number", group = "pickup", min = RADIUS_MIN, max = RADIUS_MAX, step = RADIUS_STEP,
          format = "F0", defaultValue = DEFAULTS.radiusM,
          label = L10n("拾取范围（米）", "Pickup range (m)"),
          description = L10n("只会拾取当前已加载区域内、这个距离以内的道具。", "Only items within this distance in currently loaded areas are picked up.") },
        { key = "onePerPress", type = "toggle", group = "pickup", defaultValue = DEFAULTS.onePerPress,
          label = L10n("每次只拾取一个", "One item per press"),
          description = L10n("关闭后，按一次拾取键会依次拾取范围内全部合格道具。", "When off, one press picks up every eligible item in range, one after another.") },
        { key = "skipHidden", type = "toggle", group = "pickup", defaultValue = DEFAULTS.skipHidden,
          label = L10n("跳过隐藏道具", "Skip hidden items"),
          description = L10n("隐藏道具通常要等剧情条件满足才会出现。", "Hidden items usually only appear once a story condition is met.") },
        { key = "skipEquipment", type = "toggle", group = "pickup", defaultValue = DEFAULTS.skipEquipment,
          label = L10n("跳过武器、饰品等装备", "Skip weapons, accessories and other equipment"),
          description = L10n("只远程拾取材料和消耗品。装备请走过去手动拾取：有些装备挂着剧情事件，梦魇周目里拾取装备还会让已有的同名装备 +1。",
                             "Only materials and consumables are picked up remotely. Walk over for equipment: some is tied to story events, and in Nightmare runs picking equipment raises the copy you own by +1.") },
        { key = "rangeKey", type = "keybind", group = "pickup", defaultValue = DEFAULTS.rangeKey,
          allowGamepad = false, allowMouse = true, allowModifiers = true, allowUnbound = true, conflictGroup = "remotepickup",
          label = L10n("切换拾取范围（键盘 / 鼠标）", "Cycle pickup range (keyboard / mouse)"),
          description = L10n("按一次在 25 / 50 / 100 / 150 / 200 米之间切换，屏幕上会提示当前范围。", "Each press cycles 25 / 50 / 100 / 150 / 200 m and shows the new range on screen.") },
        { key = "equipKey", type = "keybind", group = "pickup", defaultValue = DEFAULTS.equipKey,
          allowGamepad = false, allowMouse = true, allowModifiers = true, allowUnbound = true, conflictGroup = "remotepickup",
          label = L10n("开关“跳过装备”（键盘 / 鼠标）", "Toggle \"skip equipment\" (keyboard / mouse)"),
          description = L10n("屏幕上会提示当前状态。手柄组合键请在 settings.json 里设置 rangeGamepad / equipGamepad。",
                             "The new state is shown on screen. Gamepad chords go in settings.json (rangeGamepad / equipGamepad).") },
        { key = "showToast", type = "toggle", group = "pickup", defaultValue = DEFAULTS.showToast,
          label = L10n("屏幕提示", "On-screen messages"),
          description = L10n("用快捷键改设置时在屏幕上显示提示。", "Show a short message when a hotkey changes a setting.") },
    },
}

local SCHEMA_KEYS = {}
for _, e in ipairs(Provider.entries) do if e.type ~= "header" then SCHEMA_KEYS[e.key] = true end end

function Provider.read()
    local values = {}            -- gamepad chord hotkeys live in settings.json only (not in the menu schema)
    for k in pairs(DEFAULTS) do if SCHEMA_KEYS[k] then values[k] = Settings.values[k] end end
    return { values = values,
             revision = Settings.revision, persistence = { state = "saved" } }
end

function Provider.apply(patch)
    if type(patch.pickupGamepad) == "string" and patch.pickupGamepad ~= "" and not patch.pickupGamepad:find("^Gamepad_") then
        return { ok = false, error = "GAMEPAD_BUTTON_REQUIRED", fields = { pickupGamepad = "GAMEPAD_BUTTON_REQUIRED" } }
    end
    local merged = {}
    for k, v in pairs(Settings.values) do merged[k] = v end
    for k, v in pairs(patch) do if SCHEMA_KEYS[k] then merged[k] = v end end
    local saved, err = SetSettings(merged)
    log(string.format("settings: range %d m, one-per-press %s, skip hidden %s, skip equipment %s, key '%s', gamepad '%s'%s", Settings.values.radiusM,
        tostring(Settings.values.onePerPress), tostring(Settings.values.skipHidden), tostring(Settings.values.skipEquipment), Settings.values.pickupKey,
        Settings.values.pickupGamepad, saved and "" or (" (save failed: " .. tostring(err) .. ")")))
    return { ok = true, revision = Settings.revision }
end

function Provider.reset()
    SetSettings(DEFAULTS)
    return { ok = true, revision = Settings.revision }
end

function Provider.flush() return { ok = true } end

function Provider.subscribe(cb)
    table.insert(Settings.listeners, cb)
    return function()
        for i, f in ipairs(Settings.listeners) do if f == cb then table.remove(Settings.listeners, i); break end end
    end
end

LoadSettings()
ApplyToConfig()

local ModConfigHandle = nil
do
    local okClient, Client = pcall(require, "PbzModConfigClient")
    if okClient then
        local ok, h = pcall(Client.register, Provider)
        if ok then ModConfigHandle = h else log("ModConfig registration failed: " .. tostring(h)) end
    else
        log("PbzModConfig " .. (ModConfigEnabled and "not installed" or "not enabled") .. ": settings only via settings.json")
    end
end

if SettingsLoadNote then log(SettingsLoadNote) end
log(string.format("loaded v0.10 (pickup key '%s', gamepad '%s'; range key '%s' / '%s', equipment key '%s' / '%s'; range %d m, one-per-press %s, skip equipment %s; ModConfig %s)",
    Settings.values.pickupKey, Settings.values.pickupGamepad, Settings.values.rangeKey, Settings.values.rangeGamepad,
    Settings.values.equipKey, Settings.values.equipGamepad, Settings.values.radiusM,
    tostring(Settings.values.onePerPress), tostring(Settings.values.skipEquipment), ModConfigHandle and "registered" or "not registered"))
